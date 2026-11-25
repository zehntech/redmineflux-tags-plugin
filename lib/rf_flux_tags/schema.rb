# frozen_string_literal: true

module RfFluxTags
  # Whether the optional rf_flux_tags_* columns exist yet. The code keeps
  # working (with generated colours and no descriptions) until the plugin
  # migrations have been run.
  module Schema
    COLOR_COLUMN = 'rf_flux_tags_color'
    DESCRIPTION_COLUMN = 'rf_flux_tags_description'

    def self.extras?
      names = ActsAsTaggableOn::Tag.column_names
      names.include?(COLOR_COLUMN) && names.include?(DESCRIPTION_COLUMN)
    rescue StandardError
      false
    end
  end
end
