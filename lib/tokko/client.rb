require_relative "../http_json"

module Tokko
  class Client
    BASE = "https://www.tokkobroker.com/api/v1".freeze
    PAGE_SIZE = 20

    def initialize(key: ENV.fetch("TOKKO_API_KEY"), lang: "es_ar")
      @key = key
      @lang = lang
    end

    def page(resource: "property", offset: 0, limit: PAGE_SIZE, **params)
      HttpJson.get(url(resource, limit:, offset:, **params))
    end

    def all(resource: "property", **params)
      offset = 0
      results = []

      loop do
        body = page(resource:, offset:, **params)
        objects = body.fetch("objects", [])
        results.concat(objects)

        total = body.dig("meta", "total_count")
        offset += PAGE_SIZE
        break if objects.empty? || (total && offset >= total)
      end

      results
    end

    private

    def url(resource, **params)
      query = { format: "json", key: @key, lang: @lang }.merge(params)
      "#{BASE}/#{resource}/?#{URI.encode_www_form(query)}"
    end
  end
end
