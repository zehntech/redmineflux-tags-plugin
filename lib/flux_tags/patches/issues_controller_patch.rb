module FluxTags
    module Patches
        module IssuesControllerPatch
        extend ActiveSupport::Concern

            included do
                helper :issues_tags
                helper :tags
                include TagsHelper
                # A bulk update that carries only tag fields has no issue[...] parameter at all. Core copes, but
                # other plugins that extend parse_params_for_bulk_update read from it and fail (500), so it is
                # always present, if empty (#124189).
                before_action :rf_flux_tags_ensure_issue_params, only: :bulk_update
            end

            private

            def rf_flux_tags_ensure_issue_params
                params[:issue] = {} unless params[:issue].respond_to?(:key?)
            end
        end 
    end
end

base = IssuesController
patch = FluxTags::Patches::IssuesControllerPatch
base.send(:include, patch) unless base.included_modules.include?(patch)



