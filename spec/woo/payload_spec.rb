require "woo/payload"

RSpec.describe Woo::Payload do
  describe "#call" do
    context "with a house for sale" do
      it "assigns the parent and sale subcategory" do
        property = {
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 170_000 }] }]
        }

        payload = described_class.new(property).call

        expect(payload[:category_names]).to eq(["Casas", "Venta Casas"])
      end
    end

    context "with an apartment for rent" do
      it "assigns the parent and rental subcategory" do
        property = {
          "type" => { "name" => "Departamento" },
          "operations" => [{ "operation_type" => "Alquiler", "prices" => [{ "currency" => "ARS", "price" => 950_000 }] }]
        }

        payload = described_class.new(property).call

        expect(payload[:category_names]).to eq(["Departamentos", "Alquiler Departamentos"])
      end
    end

    context "with a plot of land" do
      it "assigns Terrenos regardless of the title wording" do
        property = {
          "type" => { "name" => "Terreno" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 27_000 }] }],
          "publication_title" => "Lote Esquina Con Vista A Las Sierras"
        }

        payload = described_class.new(property).call

        expect(payload[:category_names]).to eq(["Terrenos", "Venta terrenos"])
      end
    end

    context "pricing" do
      it "uses the numeric price and labels USD in the Precio attribute" do
        property = {
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 170_000 }] }]
        }

        payload = described_class.new(property).call

        expect(payload[:regular_price]).to eq("170000")
        expect(payload[:attributes].fetch("Precio")).to eq("USD 170000")
      end

      it "labels the pesos amount so a rental is not read as dollars" do
        property = {
          "type" => { "name" => "Departamento" },
          "operations" => [{ "operation_type" => "Alquiler", "prices" => [{ "currency" => "ARS", "price" => 950_000 }] }]
        }

        payload = described_class.new(property).call

        expect(payload[:regular_price]).to eq("950000")
        expect(payload[:attributes].fetch("Precio")).to eq("ARS 950000")
      end

      it "leaves the price blank when Tokko has no price yet" do
        property = {
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [] }]
        }

        payload = described_class.new(property).call

        expect(payload[:regular_price]).to eq("")
        expect(payload[:attributes]).not_to have_key("Precio")
      end
    end

    context "detail attributes" do
      it "maps counts, surfaces and tag-derived features" do
        property = {
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 1 }] }],
          "room_amount" => 3,
          "bathroom_amount" => 2,
          "parking_lot_amount" => 1,
          "roofed_surface" => "150.00",
          "surface" => "200.00",
          "tags" => [{ "name" => "Parrilla" }, { "name" => "Cloaca" }]
        }

        payload = described_class.new(property).call

        expect(payload[:attributes]).to include(
          "Habitaciones" => "3",
          "Baños" => "2",
          "Garages" => "1",
          "Superficie Cubierta" => "150m2",
          "Superficie Terreno" => "200m2",
          "Asador" => "Si",
          "Cloacas" => "Si",
          "Piscina" => "No"
        )
      end

      it "omits surfaces and counts Tokko reports as zero rather than writing 0m2" do
        property = {
          "type" => { "name" => "Terreno" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 1 }] }],
          "room_amount" => 0,
          "bathroom_amount" => 0,
          "parking_lot_amount" => 0,
          "roofed_surface" => "0.00",
          "surface" => "1000.00",
          "tags" => []
        }

        payload = described_class.new(property).call

        expect(payload[:attributes]).to include("Superficie Terreno" => "1000m2")
        expect(payload[:attributes]).not_to have_key("Superficie Cubierta")
        expect(payload[:attributes]).not_to have_key("Habitaciones")
        expect(payload[:attributes]).not_to have_key("Baños")
      end

      it "falls back to total_surface when Tokko leaves surface empty" do
        property = {
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 1 }] }],
          "roofed_surface" => "48.50",
          "surface" => "0.00",
          "total_surface" => "48.50"
        }

        payload = described_class.new(property).call

        expect(payload[:attributes]).to include("Superficie Terreno" => "48.5m2", "Superficie Cubierta" => "48.5m2")
      end
    end

    context "identity and content" do
      it "carries the Tokko reference and id so later runs can match without guessing titles" do
        property = {
          "id" => 7_751_873,
          "reference_code" => "PAP7751873",
          "publication_title" => "Departamento con cochera",
          "rich_description" => "<p>Amplio con vista</p>",
          "type" => { "name" => "Departamento" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 50_000 }] }]
        }

        payload = described_class.new(property).call

        expect(payload[:sku]).to eq("PAP7751873")
        expect(payload[:tokko_id]).to eq(7_751_873)
        expect(payload[:name]).to eq("Departamento con cochera")
        expect(payload[:description]).to eq("<p>Amplio con vista</p>")
        expect(payload[:status]).to eq("publish")
      end

      it "falls back to the plain description when Tokko has no rich text" do
        property = {
          "id" => 1,
          "description" => "Casa en Los Aromos",
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [] }]
        }

        payload = described_class.new(property).call

        expect(payload[:description]).to eq("Casa en Los Aromos")
      end

      it "orders photos and skips blueprints" do
        property = {
          "id" => 1,
          "type" => { "name" => "Casa" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [] }],
          "photos" => [
            { "image" => "b.jpg", "order" => 2, "is_blueprint" => false },
            { "image" => "plan.jpg", "order" => 1, "is_blueprint" => true },
            { "image" => "a.jpg", "order" => 0, "is_blueprint" => false }
          ]
        }

        payload = described_class.new(property).call

        expect(payload[:image_urls]).to eq(["a.jpg", "b.jpg"])
      end
    end

    context "with a property type Tokko can return but the site has no category for" do
      it "raises rather than silently miscategorising" do
        property = {
          "type" => { "name" => "Quinta" },
          "operations" => [{ "operation_type" => "Venta", "prices" => [{ "currency" => "USD", "price" => 1 }] }]
        }

        expect { described_class.new(property).call }
          .to raise_error(Woo::Payload::UnmappedCategory, /Quinta.*Venta/)
      end
    end
  end
end
