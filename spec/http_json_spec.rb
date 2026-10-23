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

    context "when the edge serves a browser-check page" do
      let(:challenge) do
        "<!DOCTYPE html><html lang=\"en\"><head>" \
          "<meta charset=\"UTF-8\">" \
          "<meta name=\"robots\" content=\"noindex,nofollow\">" \
          "<meta http-equiv=\"refresh\" content=\"30\">" \
          "<script src=\"/hcdn-cgi/jschallenge\"></script>" \
          "<title>Checking your browser before accessing. Just a moment...</title>" \
          "</head><body><p>Please wait for up to 5 seconds...</p></body></html>"
      end

      it "raises Unreachable, so a blocked hourly run is skipped like a dead host" do
        allow(Net::HTTP).to receive(:start)
          .and_return(instance_double(Net::HTTPResponse, code: "403", body: challenge))

        expect { described_class.get("https://example.com/x?key=SECRET123", attempts: 4, backoff: 0) }
          .to raise_error(HttpJson::Unreachable) { |error|
            expect(error.message).to include("bot challenge")
            expect(error.message).not_to include("SECRET123")
          }
      end

      it "does not retry, because the challenge needs a browser and this process cannot pass it" do
        attempts = 0
        allow(Net::HTTP).to receive(:start) do
          attempts += 1
          instance_double(Net::HTTPResponse, code: "403", body: challenge)
        end

        expect { described_class.get("https://example.com/x", attempts: 4, backoff: 0) }
          .to raise_error(HttpJson::Unreachable)
        expect(attempts).to eq(1)
      end
    end

    context "when the API itself rejects the request" do
      it "raises Error for a JSON 403, which is WooCommerce refusing the call" do
        body = '{"code":"woocommerce_rest_cannot_view","message":"Sorry, you cannot list resources.","data":{"status":403}}'
        attempts = 0
        allow(Net::HTTP).to receive(:start) do
          attempts += 1
          instance_double(Net::HTTPResponse, code: "403", body:)
        end

        expect { described_class.get("https://example.com/x", attempts: 4, backoff: 0) }
          .to raise_error(HttpJson::Error, /HTTP 403/)
        expect(attempts).to eq(1)
      end

      it "raises Error for a JSON 401" do
        body = '{"code":"woocommerce_rest_authentication_error","message":"Consumer key is invalid.","data":{"status":401}}'
        allow(Net::HTTP).to receive(:start)
          .and_return(instance_double(Net::HTTPResponse, code: "401", body:))

        expect { described_class.get("https://example.com/x", attempts: 2, backoff: 0) }
          .to raise_error(HttpJson::Error, /HTTP 401/)
      end

      it "raises Error for another 4xx" do
        body = '{"code":"rest_no_route","message":"No route was found matching the URL and request method.","data":{"status":404}}'
        allow(Net::HTTP).to receive(:start)
          .and_return(instance_double(Net::HTTPResponse, code: "404", body:))

        expect { described_class.get("https://example.com/x", attempts: 2, backoff: 0) }
          .to raise_error(HttpJson::Error, /HTTP 404/)
      end

      it "raises Error for an HTML 403 that is a plain forbidden page" do
        body = "<!DOCTYPE html><html><head><title>403 Forbidden</title></head><body>Forbidden</body></html>"
        allow(Net::HTTP).to receive(:start)
          .and_return(instance_double(Net::HTTPResponse, code: "403", body:))

        expect { described_class.get("https://example.com/x", attempts: 2, backoff: 0) }
          .to raise_error(HttpJson::Error)
      end
    end
  end
end
