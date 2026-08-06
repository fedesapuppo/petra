require "woo/incremental"

RSpec.describe Woo::Incremental do
  describe "MANAGED_SKU" do
    it "matches Tokko reference codes" do
      expect(%w[PAP7751873 PHO7752396 PLA8583396]).to all(match(described_class::MANAGED_SKU))
    end

    it "ignores products added by hand, so the sync never trashes them" do
      expect(%w[casa-01 ABC 12345 PAP-775 pap7751873]).to all(satisfy { |sku| !described_class::MANAGED_SKU.match?(sku) })
    end

    it "ignores a blank SKU" do
      expect(described_class::MANAGED_SKU.match?("")).to be(false)
    end
  end
end
