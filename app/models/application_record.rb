# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base

  self.abstract_class = true
  self.inheritance_column = "sti_type"
  nilify_blanks

  connects_to database: { writing: :primary, reading: :primary_replica }

end
