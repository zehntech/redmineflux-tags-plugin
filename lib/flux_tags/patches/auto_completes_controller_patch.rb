module FluxTags
  module Patches
      module AutoCompletesControllerPatch
        def self.included(base)
          base.send :include, InstanceMethods
        end

        module InstanceMethods
          def issue_tags
            disable_autocomplete_caching
            @name = params[:q].to_s
            @tags = Issue.available_tags(name_like: @name)
            render json: Array(@tags.pluck(:name).sort), content_type: "application/json"
          end

          def project_tags
            disable_autocomplete_caching
            @name = params[:q].to_s
            @tags = Project.available_tags(name_like: @name)
            render json: Array(@tags.pluck(:name).sort), content_type: "application/json"
          end

          def time_entry_tags
            disable_autocomplete_caching
            @name = params[:q].to_s
            @tags = TimeEntry.available_tags project: @project, name_like: @name
            render json: Array(@tags.pluck(:name).sort), content_type: "application/json"
          end

          private

          # The suggestions must always reflect the live tag list (rtg-001).
          def disable_autocomplete_caching
            response.headers['Cache-Control'] = 'no-store'
          end
        end
      end
  end
end

base = AutoCompletesController
patch = FluxTags::Patches::AutoCompletesControllerPatch
base.send(:include, patch) unless base.included_modules.include?(patch)
