require "wp/empty_menu_items"

RSpec.describe Wp::EmptyMenuItems do
  def item(id:, url:, title: "Item", parent: 0)
    {
      "id" => id,
      "title" => { "rendered" => title },
      "url" => url,
      "parent" => parent,
      "menus" => 175
    }
  end

  def category(slug:, count:, parent: 0, id: slug.hash.abs)
    { "id" => id, "slug" => slug, "count" => count, "parent" => parent }
  end

  describe "#call" do
    context "when a menu item points at a category with no listings" do
      it "returns it for removal" do
        items = [item(id: 1, url: "https://x.test/categoria-producto/locales/venta-locales/", title: "Locales")]
        categories = [category(slug: "venta-locales", count: 0)]

        removable = described_class.new(items: items, categories: categories).call

        expect(removable.map { |i| i["id"] }).to eq([1])
      end
    end

    context "when a menu item points at a category with listings" do
      it "leaves it alone" do
        items = [item(id: 1, url: "https://x.test/categoria-producto/casas/venta-casas/", title: "Casas")]
        categories = [category(slug: "venta-casas", count: 10)]

        removable = described_class.new(items: items, categories: categories).call

        expect(removable).to be_empty
      end
    end

    context "when a menu item is not a category link" do
      it "leaves it alone, even with no listings anywhere" do
        items = [
          item(id: 1, url: "https://x.test/", title: "INICIO"),
          item(id: 2, url: "https://x.test/propiedades/", title: "EN VENTA"),
          item(id: 3, url: "https://x.test/home/#contacto", title: "CONTACTO")
        ]

        removable = described_class.new(items: items, categories: []).call

        expect(removable).to be_empty
      end
    end

    context "when a parent category is empty but a child under it is not" do
      it "keeps the parent, since removing it would orphan the child" do
        items = [
          item(id: 1, url: "https://x.test/categoria-producto/casas/", title: "Casas"),
          item(id: 2, url: "https://x.test/categoria-producto/casas/venta-casas/", title: "Venta Casas", parent: 1)
        ]
        categories = [category(slug: "casas", count: 0), category(slug: "venta-casas", count: 10)]

        removable = described_class.new(items: items, categories: categories).call

        expect(removable).to be_empty
      end
    end

    context "when every child under an empty parent is also empty" do
      it "returns the parent and the children" do
        items = [
          item(id: 1, url: "https://x.test/categoria-producto/campos/", title: "Campos"),
          item(id: 2, url: "https://x.test/categoria-producto/campos/venta-campos/", title: "Venta", parent: 1),
          item(id: 3, url: "https://x.test/categoria-producto/campos/alquiler-campo/", title: "Alquiler", parent: 1)
        ]
        categories = [
          category(slug: "campos", count: 0),
          category(slug: "venta-campos", count: 0),
          category(slug: "alquiler-campo", count: 0)
        ]

        removable = described_class.new(items: items, categories: categories).call

        expect(removable.map { |i| i["id"] }).to contain_exactly(1, 2, 3)
      end
    end

    context "when a menu item points at a slug WooCommerce does not know" do
      it "leaves it alone rather than guessing it is empty" do
        items = [item(id: 1, url: "https://x.test/categoria-producto/quintas/", title: "Quintas")]

        removable = described_class.new(items: items, categories: []).call

        expect(removable).to be_empty
      end
    end
  end
end
