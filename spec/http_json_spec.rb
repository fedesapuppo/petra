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
          .to raise_error(HttpJson::Error) { |e| expect(e.message).not_to include("SECRET123") }
      end
    end
  end
end
