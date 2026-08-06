require_relative "client"
require_relative "payload"
require_relative "../tokko/client"

module Woo
  # Rebuilds the product catalogue from Tokko. Destructive by design:
  # Tokko is the source of truth, anything else is removed.
  class Sync
    Aborted = Class.new(StandardError)

    # A run that sees implausibly few listings is far more likely to be an API
    # fault than a genuinely emptied catalogue, and it would wipe the site.
    MINIMUM_PROPERTIES = 5

    # Categories the sync is allowed to manage. Anything else the site has is
    # reported as obsolete rather than deleted silently.
    KEEP_CATEGORIES = Payload::CATEGORIES.values.flatten.uniq.freeze

    def initialize(dry_run: true, canary: false, out: $stdout)
      @dry_run = dry_run
      @canary = canary
      @out = out
      @woo = Client.new
      @tokko = Tokko::Client.new
    end

    def call
      properties = fetch_properties
      payloads = properties.map { |property| Payload.new(property).call }

      return run_canary(payloads) if @canary

      report_plan(payloads)
      return :dry_run if dry_run?

      remove_existing_products
      created = payloads.map { |payload| create_product(payload) }
      log "\nCreated #{created.compact.size}/#{payloads.size} products."
      :done
    end

    private

    attr_reader :woo, :tokko, :out

    def dry_run? = @dry_run

    def log(message) = out.puts(message)

    # Proves the whole write path, including the slowest possible image import,
    # without deleting anything.
    def run_canary(payloads)
      payload = payloads.max_by { |candidate| candidate[:image_urls].size }
      log "Canary: #{payload[:sku]} #{payload[:name][0, 60]}"
      log "Images: #{payload[:image_urls].size} (the largest set in the catalogue)"

      if dry_run?
        log "\nDRY RUN. Nothing was changed."
        return :dry_run
      end

      started = Time.now
      product = create_product(payload)
      return :failed unless product

      log "\nTook #{(Time.now - started).round(1)}s"
      log "Review it: #{product["permalink"]}"
      log "Imported images: #{Array(product["images"]).size}/#{payload[:image_urls].size}"
      :done
    end

    def fetch_properties
      properties = tokko.all
      if properties.size < MINIMUM_PROPERTIES
        raise Aborted, "Tokko returned only #{properties.size} properties (minimum #{MINIMUM_PROPERTIES}). " \
                       "Refusing to rebuild the catalogue from a suspect response."
      end

      properties
    end

    def existing_products
      @existing_products ||= woo.all("products", status: "any")
    end

    def categories
      @categories ||= woo.all("products/categories")
    end

    def attributes
      @attributes ||= Array(woo.get("products/attributes"))
    end

    def category_id(name)
      found = categories.find { |category| category["name"].casecmp?(name) }
      raise Aborted, "site has no category named #{name.inspect}" unless found

      found["id"]
    end

    def attribute_id(name)
      found = attributes.find { |attribute| attribute["name"].casecmp?(name) }
      raise Aborted, "site has no attribute named #{name.inspect}" unless found

      found["id"]
    end

    def report_plan(payloads)
      log "Tokko listings: #{payloads.size}"
      log "Existing products to remove: #{existing_products.size}"
      log "Images to import: #{payloads.sum { |p| p[:image_urls].size }}"

      log "\nWill create:"
      payloads.each do |payload|
        log format("  %-12s %-9s %s", payload[:sku], payload[:regular_price], payload[:name][0, 62])
      end

      log "\nWill remove (moved to trash, recoverable in WP admin):"
      existing_products.each { |product| log "  ##{product["id"]}  #{product["name"][0, 68]}" }

      obsolete = categories.reject { |c| KEEP_CATEGORIES.any? { |k| k.casecmp?(c["name"]) } }
      log "\nCategories no longer fed by Tokko (#{obsolete.size}, NOT deleted by this script):"
      obsolete.each { |c| log "  #{c["name"]} (id #{c["id"]}, #{c["count"]} products)" }

      log "\n#{dry_run? ? "DRY RUN. Nothing was changed." : "APPLYING CHANGES."}"
    end

    # WooCommerce enforces SKU uniqueness against trashed products too, so a
    # trashed product still holding a Tokko reference would block recreating it.
    # Releasing the SKU first keeps the trash recoverable without that conflict.
    def remove_existing_products
      existing_products.each do |product|
        woo.put("products/#{product["id"]}", sku: "") unless product["sku"].to_s.empty?
        woo.delete("products/#{product["id"]}", force: false)
        log "  trashed ##{product["id"]}"
      end
    end

    def create_product(payload)
      body = {
        name: payload[:name],
        type: "simple",
        status: payload[:status],
        sku: payload[:sku],
        description: payload[:description],
        regular_price: payload[:regular_price],
        catalog_visibility: "visible",
        categories: payload[:category_names].map { |name| { id: category_id(name) } },
        attributes: payload[:attributes].map.with_index do |(name, value), position|
          { id: attribute_id(name), position:, visible: true, variation: false, options: [value] }
        end,
        images: payload[:image_urls].map { |src| { src: } },
        meta_data: [{ key: "_tokko_id", value: payload[:tokko_id].to_s }]
      }

      product = woo.post("products", body)
      log "  created ##{product["id"]} #{payload[:sku]} (#{payload[:image_urls].size} images)"
      product
    rescue HttpJson::Error => e
      log "  FAILED #{payload[:sku]}: #{e.message[0, 200]}"
      nil
    end
  end
end
