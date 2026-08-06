module Wp
  # Picks out the nav menu entries that point at a product category with
  # nothing in it. Those links render a bare "No se encontraron Propiedades."
  # page, which reads as a broken site rather than an empty section.
  #
  # Pure: no network. Takes menu items from wp/v2/menu-items and categories
  # from wc/v3/products/categories.
  class EmptyMenuItems
    CATEGORY_URL = %r{/categoria-producto/(?<path>[^?#]+)}

    def initialize(items:, categories:)
      @items = items
      @counts = categories.to_h { |c| [c["slug"], c["count"]] }
    end

    def call
      empty = @items.select { |item| empty_category?(item) }

      empty.reject { |item| keeps_a_child_alive?(item, empty) }
    end

    private

    def empty_category?(item)
      count = @counts[slug(item)]

      !count.nil? && count.zero?
    end

    # Deleting a parent promotes its children to the top level, so an empty
    # parent stays if anything under it is still worth showing.
    def keeps_a_child_alive?(item, empty)
      children = @items.select { |other| other["parent"] == item["id"] }

      children.any? && !children.all? { |child| empty.include?(child) }
    end

    def slug(item)
      match = CATEGORY_URL.match(item["url"].to_s)
      return nil unless match

      match[:path].split("/").last
    end
  end
end
