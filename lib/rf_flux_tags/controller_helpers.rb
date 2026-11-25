# frozen_string_literal: true

module RfFluxTags
  # Gives the Redmine controllers that show tags the RfFluxTagsHelper
  # (the helper methods of the chips and the tag input).
  module ControllerHelpers
    extend ActiveSupport::Concern

    TARGETS = %w[IssuesController ProjectsController TimelogController SettingsController].freeze

    included do
      helper :rf_flux_tags
    end

    def self.apply!
      TARGETS.each do |name|
        controller = name.safe_constantize
        next unless controller

        controller.send(:include, self) unless controller.included_modules.include?(self)
      end
    end
  end
end
