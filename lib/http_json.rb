require "net/http"
require "json"
require "uri"

module HttpJson
  Error = Class.new(StandardError)

  # Deliberately not an Error: a host that never answers is not a rejected
  # request, and the callers that log-and-continue on Error must not swallow
  # it and spend the rest of the run retrying into a wall.
  Unreachable = Class.new(StandardError)

  # The host drops packets from a datacenter IP now and then. Ten seconds is
  # already forever for a TCP handshake, and failing fast buys more retries
  # inside the same wall clock than one 60s default ever does.
  OPEN_TIMEOUT = 10

  RETRIABLE = [429, 500, 502, 503, 504].freeze

  # Failures raised before a response object exists. A 502 from the host's
  # proxy arrives this way, not as a status code, so without these a throttled
  # shared host takes the whole run down on the first hiccup.
  RETRIABLE_ERRORS = [
    Net::HTTPFatalError,
    Net::HTTPServerException,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    Errno::EPIPE,
    SocketError,
    IOError,
    OpenSSL::SSL::SSLError
  ].freeze

  def self.get(url, basic_auth: nil, attempts: 8, backoff: 2)
    request(Net::HTTP::Get.new(URI(url)), URI(url), basic_auth:, attempts:, backoff:)
  end

  def self.post(url, body, basic_auth: nil, attempts: 4)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body)
    request(req, uri, basic_auth:, attempts:)
  end

  def self.put(url, body, basic_auth: nil, attempts: 4)
    uri = URI(url)
    req = Net::HTTP::Put.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body)
    request(req, uri, basic_auth:, attempts:)
  end

  def self.delete(url, basic_auth: nil, attempts: 4)
    uri = URI(url)
    request(Net::HTTP::Delete.new(uri), uri, basic_auth:, attempts:)
  end

  def self.request(req, uri, basic_auth:, attempts:, backoff: 2)
    req.basic_auth(*basic_auth) if basic_auth
    req["Accept"] = "application/json"

    last_error = nil
    unreachable = false
    attempts.times do |attempt|
      sleep(backoff**attempt) if attempt.positive? && backoff.positive?

      # Creating a product makes WooCommerce sideload every photo from Tokko's
      # CDN before responding, which measured ~2.7s per image on this host.
      begin
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                   open_timeout: OPEN_TIMEOUT, read_timeout: 300) do |http|
          http.request(req)
        end
      rescue *RETRIABLE_ERRORS => e
        unreachable = true
        last_error = "#{e.class} for #{redact(uri)}: #{e.message[0, 200]}"
        next
      end

      unreachable = false
      code = response.code.to_i
      return parse(response.body) if code.between?(200, 299)

      last_error = "HTTP #{code} for #{redact(uri)}: #{response.body.to_s[0, 500]}"
      raise Error, last_error unless RETRIABLE.include?(code)
    end

    raise Unreachable, "gave up after #{attempts} attempts. #{last_error}" if unreachable

    raise Error, "gave up after #{attempts} attempts. #{last_error}"
  end

  def self.parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body)
  rescue JSON::ParserError
    raise Error, "expected JSON, got: #{body[0, 300]}"
  end

  def self.redact(uri)
    uri.to_s.gsub(/key=[^&]+/, "key=[REDACTED]")
  end

  private_class_method :request, :parse, :redact
end
