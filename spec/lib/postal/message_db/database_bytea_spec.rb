# frozen_string_literal: true

require "rails_helper"

describe Postal::MessageDB::Database do
  subject(:db) { described_class.allocate }

  describe "#bytea_hex_literal" do
    it "builds a decode() expression over the hex representation" do
      expect(db.bytea_hex_literal("a\\x")).to eq "decode('615c78', 'hex')"
    end

    it "round-trips backslashes, CRLF and binary bytes unchanged" do
      data = "Subject: a\\b\r\n\r\nC:\\new \\x zz \\\\ \xFF\xFE".b
      hex = db.bytea_hex_literal(data)[/'(\h*)'/, 1]
      expect([hex].pack("H*")).to eq data
    end
  end
end
