module Woo
  # Pure translation of a Tokko property into the fields WooCommerce needs.
  # No network, no IDs: category names are resolved to IDs by the caller.
  class Payload
    UnmappedCategory = Class.new(StandardError)

    # [Tokko type, Tokko operation] => [parent category, subcategory].
    # Names must match the site's existing terms exactly, including its
    # inconsistent casing ("Venta terrenos").
    CATEGORIES = {
      ["Casa", "Venta"] => ["Casas", "Venta Casas"],
      ["Casa", "Alquiler"] => ["Casas", "Alquiler Casas"],
      ["Departamento", "Venta"] => ["Departamentos", "Venta Departamentos"],
      ["Departamento", "Alquiler"] => ["Departamentos", "Alquiler Departamentos"],
      ["Terreno", "Venta"] => ["Terrenos", "Venta terrenos"]
    }.freeze

    def initialize(property)
      @property = property
    end

    def call
      {
        tokko_id: property["id"],
        sku: property["reference_code"].to_s,
        name: property["publication_title"].to_s.strip,
        description: description,
        status: "publish",
        category_names: category_names,
        regular_price: regular_price,
        attributes: attributes,
        image_urls: image_urls
      }
    end

    private

    attr_reader :property

    def category_names
      key = [property.dig("type", "name"), operation["operation_type"]]

      CATEGORIES.fetch(key) do
        raise UnmappedCategory, "no site category for type #{key[0].inspect} / operation #{key[1].inspect}"
      end
    end

    def operation
      Array(property["operations"]).first || {}
    end

    def price
      Array(operation["prices"]).first
    end

    def description
      rich = property["rich_description"].to_s.strip
      rich.empty? ? property["description"].to_s.strip : rich
    end

    def image_urls
      Array(property["photos"])
        .reject { |photo| photo["is_blueprint"] }
        .sort_by { |photo| photo["order"].to_i }
        .map { |photo| photo["image"] || photo["original"] }
        .compact
    end

    def regular_price
      return "" unless price

      format_amount(price["price"])
    end

    # Tokko tag names that mean a feature is present.
    FEATURE_TAGS = {
      "Asador" => ["Parrilla", "Asador", "Quincho"],
      "Piscina" => ["Piscina", "Pileta"],
      "Cloacas" => ["Cloaca", "Cloacas"]
    }.freeze

    # The store renders every price with one currency symbol, so the currency
    # lives in the Precio attribute, which the site already displays.
    def attributes
      values = {}
      values["Precio"] = "#{price["currency"]} #{format_amount(price["price"])}" if price
      values["Habitaciones"] = property["room_amount"].to_i.to_s if property["room_amount"].to_i.positive?
      values["Baños"] = property["bathroom_amount"].to_i.to_s if property["bathroom_amount"].to_i.positive?
      values["Garages"] = property["parking_lot_amount"].to_i.to_s if property["parking_lot_amount"].to_i.positive?
      values["Superficie Cubierta"] = surface_label(property["roofed_surface"]) if positive?(property["roofed_surface"])
      values["Superficie Terreno"] = surface_label(land_surface) if positive?(land_surface)

      FEATURE_TAGS.each_key { |name| values[name] = feature_present?(name) ? "Si" : "No" }
      values
    end

    def land_surface
      positive?(property["surface"]) ? property["surface"] : property["total_surface"]
    end

    def positive?(value)
      value.to_f.positive?
    end

    def surface_label(value)
      "#{format_amount(value.to_f)}m2"
    end

    def feature_present?(name)
      wanted = FEATURE_TAGS.fetch(name).map(&:downcase)
      tag_names.any? { |tag| wanted.include?(tag) }
    end

    def tag_names
      Array(property["tags"]).map { |tag| (tag.is_a?(Hash) ? tag["name"] : tag).to_s.downcase }
    end

    def format_amount(amount)
      amount.to_i == amount ? amount.to_i.to_s : amount.to_s
    end
  end
end
