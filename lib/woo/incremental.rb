require_relative "client"
require_relative "payload"
require_relative "diff"
require_relative "../tokko/client"

module Woo
  # The steady-state sync. Applies only what changed, so product URLs stay put
  # and photos are imported once rather than on every run.
  class Incremental
    Aborted = Class.new(StandardError)

    MINIMUM_PROPERTIES = 5

    # Tokko reference codes (PAP/PHO/PLA + digits). Products whose SKU does not
    # match were added by hand and are outside this sync's control.
    MANAGED_SKU = /\A[A-Z]{3}\d+\z/

    def initialize(dry_run: true, out: $stdout)
      @dry_run = dry_run
      @out = out
      @woo = Client.new
      @tokko = Tokko::Client.new
    end

    def call
      payloads = fetch_properties.map { |property| Payload.new(property).call }
      plan = Diff.new(payloads:, products: managed_products).call

      report(plan)
      return :dry_run if dry_run?

      plan[:create].each { |payload| create(payload) }
      plan[:update].each { |update| update!(update) }
      plan[:trash].each { |product| trash(product) }

      log "\nDone."
      :done
    end

    private

    attr_reader :woo, :tokko, :out

    def dry_run? = @dry_run

    def log(message) = out.puts(message)

    def fetch_properties
      properties = tokko.all
      if properties.size < MINIMUM_PROPERTIES
        raise Aborted, "Tokko returned only #{properties.size} properties (minimum #{MINIMUM_PROPERTIES}). " \
                       "Refusing to sync from a suspect response."
      end

      properties
    end

    # Only products this sync owns. Anything added by hand in WP admin has no
    # Tokko SKU and is left completely alone.
    def managed_products
      woo.all("products", status: "any").select { |product| product["sku"].to_s.match?(MANAGED_SKU) }
    end

    def categories = @categories ||= woo.all("products/categories")

    def attribute_definitions = @attribute_definitions ||= Array(woo.get("products/attributes"))

    def category_id(name)
      found = categories.find { |category| category["name"].casecmp?(name) }
      raise Aborted, "site has no category named #{name.inspect}" unless found

      found["id"]
    end

    def attribute_id(name)
      found = attribute_definitions.find { |attribute| attribute["name"].casecmp?(name) }
      raise Aborted, "site has no attribute named #{name.inspect}" unless found

      found["id"]
    end

    def wc_categories(names) = names.map { |name| { id: category_id(name) } }

    def wc_attributes(values)
      values.map.with_index do |(name, value), position|
        { id: attribute_id(name), position:, visible: true, variation: false, options: [value] }
      end
    end

    def report(plan)
      log "Tokko listings: #{plan.values_at(:create, :update, :unchanged).sum(&:size)}"
      log "Unchanged: #{plan[:unchanged].size}"

      log "\nCreate (#{plan[:create].size}):"
      plan[:create].each { |p| log "  #{p[:sku]}  #{p[:name][0, 60]}  (#{p[:image_urls].size} images)" }

      log "\nUpdate (#{plan[:update].size}):"
      plan[:update].each { |u| log "  ##{u[:id]} #{u[:sku]}  changed: #{u[:changes].join(", ")}" }

      log "\nTrash (#{plan[:trash].size}):"
      plan[:trash].each { |p| log "  ##{p["id"]} #{p["sku"]}  #{p["name"][0, 55]}" }

      log "\n#{dry_run? ? "DRY RUN. Nothing was changed." : "APPLYING CHANGES."}"
    end

    def create(payload)
      product = woo.post("products", {
        name: payload[:name],
        type: "simple",
        status: payload[:status],
        sku: payload[:sku],
        description: payload[:description],
        regular_price: payload[:regular_price],
        catalog_visibility: "visible",
        categories: wc_categories(payload[:category_names]),
        attributes: wc_attributes(payload[:attributes]),
        images: payload[:image_urls].map { |src| { src: } },
        meta_data: [{ key: "_tokko_id", value: payload[:tokko_id].to_s }]
      })
      log "  created ##{product["id"]} #{payload[:sku]}"
    rescue HttpJson::Error => e
      log "  FAILED create #{payload[:sku]}: #{e.message[0, 200]}"
    end

    def update!(update)
      body = update[:body].dup
      body[:categories] = wc_categories(body.delete(:category_names)) if body.key?(:category_names)
      body[:attributes] = wc_attributes(body[:attributes]) if body.key?(:attributes)

      woo.put("products/#{update[:id]}", body)
      log "  updated ##{update[:id]} #{update[:sku]} (#{update[:changes].join(", ")})"
    rescue HttpJson::Error => e
      log "  FAILED update #{update[:sku]}: #{e.message[0, 200]}"
    end

    def trash(product)
      woo.put("products/#{product["id"]}", sku: "")
      woo.delete("products/#{product["id"]}", force: false)
      log "  trashed ##{product["id"]} #{product["sku"]}"
    end
  end
end
