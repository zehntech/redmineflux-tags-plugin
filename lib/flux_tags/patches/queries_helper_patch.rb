module FluxTags
  module Patches
      module QueriesHelperPatch
          def self.included(base)
              base.send :include, InstanceMethods
              base.class_eval do
                  alias_method :column_content_without_flux_tags, :column_content
                  alias_method :column_content, :column_content_with_flux_tags

                  alias_method :csv_value_without_tags, :csv_value
                  alias_method :csv_value, :csv_value_with_tags
              end 
          end 
      end 

      module InstanceMethods
          include TagsHelper 

          def column_content_with_flux_tags(column, issue)
              if column.name == :tags
                  column.value(issue).collect{ |t| render_tag_link(t) }
                  .join(FluxTags.settings[:issues_use_colors].to_i > 0 ? ' ' : ' ').html_safe
              else 
                  column_content_without_flux_tags(column, issue)
              end 
          end 
          # Only the Tags column is handled here; every other column goes to Redmine's own csv_value.
          def csv_value_with_tags(column, object, value)
            if column.name == :tags
              # A cell that starts with = + - @ (or a tab / return) is a formula to a spreadsheet: made text.
              text = value.collect(&:name).join(', ')
              text.match?(/\A[=+\-@\t\r]/) ? "'" + text : text
            else
              csv_value_without_tags(column, object, value)
            end
          end
      end 
  end 
end

base = QueriesHelper
patch = FluxTags::Patches::QueriesHelperPatch
base.send(:include, patch) unless base.included_modules.include?(patch)