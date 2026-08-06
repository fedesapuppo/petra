require_relative "../http_json"

module Woo
  class Client
    PER_PAGE = 100

    def initialize(
      site: ENV.fetch("WOO_SITE_URL"),
      consumer_key: ENV.fetch("WOO_CONSUMER_KEY"),
      consumer_secret: ENV.fetch("WOO_CONSUMER_SECRET")
    )
      @base = "#{site.chomp("/")}/wp-json/wc/v3"
      @auth = [consumer_key, consumer_secret]
    end

    def get(path, **params)
      HttpJson.get(url(path, **params), basic_auth: @auth)
    end

    def post(path, body)
      HttpJson.post(url(path), body, basic_auth: @auth)
    end

    def put(path, body)
      HttpJson.put(url(path), body, basic_auth: @auth)
    end

    def delete(path, **params)
      HttpJson.delete(url(path, **params), basic_auth: @auth)
    end

    def all(path, **params)
      page = 1
      results = []

      loop do
        batch = get(path, page:, per_page: PER_PAGE, **params)
        break unless batch.is_a?(Array) && !batch.empty?

        results.concat(batch)
        break if batch.size < PER_PAGE

        page += 1
      end

      results
    end

    private

    def url(path, **params)
      query = params.empty? ? "" : "?#{URI.encode_www_form(params)}"
      "#{@base}/#{path}#{query}"
    end
  end
end
