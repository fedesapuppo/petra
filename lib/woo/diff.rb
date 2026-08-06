module Woo
  # Works out the minimum set of changes to bring the catalogue in line with
  # Tokko. Pure: takes mapped payloads and current products, returns a plan.
  #
  # Photos are the expensive part of a sync, so they are only ever sent for
  # new listings or when the photo count actually changed. Everything else is
  # compared field by field, which keeps product URLs and media stable.
  class Diff
    def initialize(payloads:, products:)
      @payloads = payloads
      @products = products
    end

    def call
      plan = { create: [], update: [], trash: [], unchanged: [] }

      payloads.each do |payload|
        existing = by_sku[payload[:sku]]

        if existing.nil?
          plan[:create] << payload
        elsif (changes = changes_for(payload, existing)).empty?
          plan[:unchanged] << payload
        else
          plan[:update] << { id: existing["id"], sku: payload[:sku], changes:, body: body_for(payload, changes) }
        end
      end

      plan[:trash] = products.reject { |product| synced_skus.include?(product["sku"]) }
      plan
    end

    private

    attr_reader :payloads, :products

    def by_sku
      @by_sku ||= products.to_h { |product| [product["sku"], product] }
    end

    def synced_skus
      @synced_skus ||= payloads.map { |payload| payload[:sku] }.to_set
    end

    def changes_for(payload, existing)
      changes = []
      changes << "name" if payload[:name] != existing["name"]
      changes << "description" if text_of(payload[:description]) != text_of(existing["description"])
      changes << "regular_price" if payload[:regular_price] != existing["regular_price"].to_s
      changes << "categories" if payload[:category_names].sort != category_names(existing).sort
      changes << "attributes" if payload_attributes(payload) != attributes(existing)
      changes << "images" if payload[:image_urls].size != Array(existing["images"]).size
      changes
    end

    def category_names(existing)
      Array(existing["categories"]).map { |category| category["name"] }
    end

    # WooCommerce reuses an existing taxonomy term when one matches
    # case-insensitively, so "Si" can come back as "si".
    def payload_attributes(payload)
      payload[:attributes].transform_values { |value| value.to_s.downcase }
    end

    def attributes(existing)
      Array(existing["attributes"]).to_h { |attribute| [attribute["name"], Array(attribute["options"]).first.to_s.downcase] }
    end

    # WordPress runs descriptions through wpautop, so what comes back is never
    # byte-identical to what was sent. Compare the text, not the markup.
    def text_of(html)
      html.to_s.gsub(/<[^>]+>/, " ").gsub(/&nbsp;/, " ").split.join(" ")
    end

    def body_for(payload, changes)
      body = {}
      body[:name] = payload[:name] if changes.include?("name")
      body[:description] = payload[:description] if changes.include?("description")
      body[:regular_price] = payload[:regular_price] if changes.include?("regular_price")
      body[:images] = payload[:image_urls].map { |src| { src: } } if changes.include?("images")
      # Left as names/values: resolving these to WooCommerce term IDs needs the
      # live taxonomy, which is the executor's job, not this object's.
      body[:attributes] = payload[:attributes] if changes.include?("attributes")
      body[:category_names] = payload[:category_names] if changes.include?("categories")
      body
    end
  end
end
