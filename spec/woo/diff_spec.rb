require "woo/diff"

RSpec.describe Woo::Diff do
  def payload(sku:, name: "A house", price: "100000", categories: ["Casas", "Venta Casas"], attributes: { "Precio" => "USD 100000" }, images: ["a.jpg"])
    {
      tokko_id: 1,
      sku: sku,
      name: name,
      description: "Description",
      status: "publish",
      category_names: categories,
      regular_price: price,
      attributes: attributes,
      image_urls: images
    }
  end

  def product(id:, sku:, name: "A house", price: "100000", categories: ["Casas", "Venta Casas"], attributes: { "Precio" => "USD 100000" }, images: 1)
    {
      "id" => id,
      "sku" => sku,
      "name" => name,
      "description" => "Description",
      "regular_price" => price,
      "categories" => categories.map { |c| { "name" => c } },
      "attributes" => attributes.map { |name, value| { "name" => name, "options" => [value] } },
      "images" => Array.new(images) { |i| { "src" => "#{i}.jpg" } }
    }
  end

  describe "#call" do
    context "when Tokko has a listing the site does not" do
      it "plans a create" do
        plan = described_class.new(payloads: [payload(sku: "PAP1")], products: []).call

        expect(plan[:create].map { |p| p[:sku] }).to eq(["PAP1"])
        expect(plan[:update]).to be_empty
        expect(plan[:trash]).to be_empty
      end
    end

    context "when the listing already exists unchanged" do
      it "plans nothing, so photos are never re-imported" do
        plan = described_class.new(
          payloads: [payload(sku: "PAP1")],
          products: [product(id: 10, sku: "PAP1")]
        ).call

        expect(plan[:create]).to be_empty
        expect(plan[:update]).to be_empty
        expect(plan[:unchanged].size).to eq(1)
      end
    end

    context "when a price changed in Tokko" do
      it "plans an update naming the changed field and leaves images alone" do
        plan = described_class.new(
          payloads: [payload(sku: "PAP1", price: "95000", attributes: { "Precio" => "USD 95000" })],
          products: [product(id: 10, sku: "PAP1")]
        ).call

        expect(plan[:update].size).to eq(1)
        update = plan[:update].first
        expect(update[:id]).to eq(10)
        expect(update[:changes]).to include("regular_price", "attributes")
        expect(update[:body]).not_to have_key(:images)
      end
    end

    context "when WordPress has reformatted what we sent" do
      it "ignores the paragraph tags wpautop adds to descriptions" do
        payloads = [payload(sku: "PAP1")]
        products = [product(id: 10, sku: "PAP1")]
        products.first["description"] = "<p>Description</p>\n"

        plan = described_class.new(payloads:, products:).call

        expect(plan[:unchanged].size).to eq(1)
        expect(plan[:update]).to be_empty
      end

      it "ignores casing WooCommerce inherits from an existing attribute term" do
        plan = described_class.new(
          payloads: [payload(sku: "PAP1", attributes: { "Precio" => "USD 100000", "Piscina" => "Si" })],
          products: [product(id: 10, sku: "PAP1", attributes: { "Precio" => "USD 100000", "Piscina" => "si" })]
        ).call

        expect(plan[:unchanged].size).to eq(1)
      end

      it "still notices a genuine description change" do
        payloads = [payload(sku: "PAP1")]
        payloads.first[:description] = "A different description"
        products = [product(id: 10, sku: "PAP1")]
        products.first["description"] = "<p>Description</p>\n"

        plan = described_class.new(payloads:, products:).call

        expect(plan[:update].first[:changes]).to include("description")
      end
    end

    context "when attributes or categories drifted" do
      it "sends them in the body, otherwise the same drift is detected forever" do
        plan = described_class.new(
          payloads: [payload(sku: "PAP1", price: "95000", attributes: { "Precio" => "USD 95000", "Baños" => "2" }, categories: ["Terrenos", "Venta terrenos"])],
          products: [product(id: 10, sku: "PAP1")]
        ).call

        body = plan[:update].first[:body]

        expect(body[:attributes]).to eq({ "Precio" => "USD 95000", "Baños" => "2" })
        expect(body[:category_names]).to eq(["Terrenos", "Venta terrenos"])
      end
    end

    context "when the site has a product Tokko no longer lists" do
      it "plans a trash" do
        plan = described_class.new(
          payloads: [],
          products: [product(id: 10, sku: "PAP1")]
        ).call

        expect(plan[:trash].map { |p| p["id"] }).to eq([10])
      end
    end

    context "when Tokko added photos to an existing listing" do
      it "includes images in the update so the gallery catches up" do
        plan = described_class.new(
          payloads: [payload(sku: "PAP1", images: ["a.jpg", "b.jpg"])],
          products: [product(id: 10, sku: "PAP1", images: 1)]
        ).call

        expect(plan[:update].first[:changes]).to include("images")
        expect(plan[:update].first[:body][:images].size).to eq(2)
      end
    end
  end
end
