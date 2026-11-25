  
module FluxTags
  module Patches
    module TimeEntriesControllerPatch
      extend ActiveSupport::Concern

      included do
        helper :tags
        include TagsHelper
      end
    end
  end
end

base = TimelogController
patch = FluxTags::Patches::TimeEntriesControllerPatch
base.send(:include, patch) unless base.included_modules.include?(patch)