require "woo/sync"
require "stringio"

RSpec.describe Woo::Sync do
  # A stand-in for Tokko that returns whatever the example needs. The system
  # under test (the guard) is not stubbed, only the network edge is.
  class FakeTokko
    def initialize(properties) = @properties = properties
    def all(**) = @properties
  end

  describe "#call" do
    context "when Tokko returns implausibly few properties" do
      it "aborts instead of rebuilding the catalogue from a suspect response" do
        sync = described_class.allocate
        sync.instance_variable_set(:@tokko, FakeTokko.new([{ "id" => 1 }]))
        sync.instance_variable_set(:@dry_run, true)
        sync.instance_variable_set(:@out, StringIO.new)

        expect { sync.send(:fetch_properties) }
          .to raise_error(Woo::Sync::Aborted, /only 1 propert/i)
      end
    end

    context "when Tokko returns a full catalogue" do
      it "proceeds" do
        properties = Array.new(24) { |i| { "id" => i } }
        sync = described_class.allocate
        sync.instance_variable_set(:@tokko, FakeTokko.new(properties))

        expect(sync.send(:fetch_properties).size).to eq(24)
      end
    end
  end

  describe "KEEP_CATEGORIES" do
    it "covers every category the mapping can assign" do
      assignable = Woo::Payload::CATEGORIES.values.flatten.uniq

      expect(described_class::KEEP_CATEGORIES).to match_array(assignable)
    end
  end
end
