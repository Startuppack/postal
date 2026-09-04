# frozen_string_literal: true

require "rails_helper"

RSpec.describe Postal::MessageDB::Message do
  describe "#encode_utf8" do
    it "accepts a frozen empty non-UTF-8 Subject value" do
      message = described_class.allocate

      expect(message.send(:encode_utf8, "".b.freeze)).to eq("")
    end
  end
end
