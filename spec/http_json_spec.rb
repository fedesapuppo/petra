require "http_json"

RSpec.describe HttpJson do
  describe ".get" do
    context "when the connection fails transiently" do
      it "retries instead of giving up, since shared hosting throttles under load" do
        attempts = 0
        allow(Net::HTTP).to receive(:start) do
          attempts += 1
          raise Net::HTTPFatalError.new("502 Bad Gateway", nil) if attempts < 3

          instance_double(Net::HTTPResponse, code: "200", body: '{"ok":true}')
        end

        result = described_class.get("https://example.com/x", attempts: 4, backoff: 0)

        expect(result).to eq({ "ok" => true })
        expect(attempts).to eq(3)
      end
    end

    context "when the connection keeps failing" do
      it "raises a redacted error rather than leaking the API key" do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNRESET)

        expect { described_class.get("https://example.com/x?key=SECRET123", attempts: 2, backoff: 0) }
          .to raise_error(HttpJson::Unreachable) { |e| expect(e.message).not_to include("SECRET123") }
      end
    end

    context "when the host never accepts a connection" do
      it "raises Unreachable, so callers can tell a dead host from a rejected request" do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

        expect { described_class.get("https://example.com/x", attempts: 2, backoff: 0) }
          .to raise_error(HttpJson::Unreachable)
      end

      it "keeps Unreachable outside Error, so per-product rescues cannot swallow an outage" do
        expect(HttpJson::Unreachable.ancestors).not_to include(HttpJson::Error)
      end

      it "gives the host minutes rather than seconds to come back" do
        attempts = 0
        allow(Net::HTTP).to receive(:start) do
          attempts += 1
          raise Net::OpenTimeout
        end

        expect { described_class.get("https://example.com/x", backoff: 0) }.to raise_error(HttpJson::Unreachable)
        expect(attempts).to be >= 8
      end

      it "waits seconds, not a minute, before writing off an attempt" do
        options = nil
        allow(Net::HTTP).to receive(:start) do |_host, _port, **opts|
          options = opts
          instance_double(Net::HTTPResponse, code: "200", body: "{}")
        end

        described_class.get("https://example.com/x")

        expect(options[:open_timeout]).to be <= 15
      end
    end

    context "when the host answers but keeps failing" do
      it "raises Error rather than Unreachable, since the site is plainly up" do
        allow(Net::HTTP).to receive(:start)
          .and_return(instance_double(Net::HTTPResponse, code: "503", body: "busy"))

        expect { described_class.get("https://example.com/x", attempts: 2, backoff: 0) }
          .to raise_error(HttpJson::Error)
      end
    end
  end
end
