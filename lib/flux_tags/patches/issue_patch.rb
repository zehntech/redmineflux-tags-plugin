module FluxTags
  module Patches
    module IssuePatch
      def self.included(base)
        base.extend(ClassMethods)
        base.send(:include, InstanceMethods)
        base.class_eval do
          acts_as_ordered_taggable
          include RfFluxTags::TagListLimits unless include?(RfFluxTags::TagListLimits)
          # BUG-FT-014: Removed after_save :remove_unused_tags_custom —
          # auto-deleting zero-usage tags silently destroys tag data.
          # Tags must only be deleted via explicit delete_tag.
          before_save :prepare_tag_change
          # Only people who may manage issue tags can set them, through the form,
          # bulk edit or the REST API.
          safe_attributes 'tag_list',
                          if: lambda { |issue, user|
                            user.admin? ||
                              (user.allowed_to?(:manage_issues_tags, issue.project) &&
                               (issue.new_record? || issue.attributes_editable?(user)))
                          }
          alias_method :copy_from_without_flux_tags, :copy_from
          alias_method :copy_from, :copy_from_with_flux_tags

          searchable_options[:columns] << "tags.name"
          searchable_options[:preload] << :tags
          old_scope = searchable_options[:scope]
          searchable_options[:scope] = lambda do |options|
            new_scope = old_scope.is_a?(Proc) ? old_scope.call(options) : old_scope
            new_scope
              .joins("LEFT JOIN taggings ON taggings.taggable_id = issues.id AND taggings.context = 'tags' AND taggings.taggable_type = 'Issue'")
              .joins('LEFT JOIN tags ON tags.id = taggings.tag_id')
          end

          scope :on_project, lambda { |project|
            project = Project.find(project) unless project.is_a? Project
            where("#{project.project_condition(Setting.display_subprojects_issues?)}")
          }
        end
      end

      module ClassMethods
        def available_tags(options = {})
          issues_scope = Issue.visible.select('issues.id').joins(:project)
          issues_scope = issues_scope.on_project(options[:project]) if options[:project]
          issues_scope = issues_scope.joins(:status).open if options[:open_only]

          result_scope = ActsAsTaggableOn::Tag.joins(:taggings)
            .select('tags.id, tags.name, tags.taggings_count, COUNT(taggings.id) as count')
            .group('tags.id, tags.name, tags.taggings_count')
            .where(taggings: { taggable_type: 'Issue', taggable_id: issues_scope})
            .order('tags.name')

          if options[:name_like]
            pattern = "%#{ActiveRecord::Base.sanitize_sql_like(options[:name_like].to_s.strip.first(100))}%"
            result_scope = result_scope.where('LOWER(tags.name) LIKE LOWER(:p)', :p => pattern)
          end

          result_scope
        end

        def allowed_tags?(tags)
          allowed_tags = all_tags.map(&:name)
          tags.all? { |tag| allowed_tags.include?(tag) }
        end

        def remove_unused_tags!
          unused = ActsAsTaggableOn::Tag.find_by_sql(<<-SQL)
            SELECT * FROM tags WHERE id NOT IN (
              SELECT DISTINCT tag_id FROM taggings
            )
          SQL
          unused.each(&:destroy)
        end

        def get_common_tag_list_from_multiple_issues(ids)
          common_tags = ActsAsTaggableOn::Tag.joins(:tagging)
            .select('tags.id', 'tags.name')
            .where(:tagging => {:taggable_type => 'Issue', :taggable_id => ids})
            .group('tags.id', 'tags.name')
            .having("count(*) = #{ids.count}").to_a

          TagList.new(common_tags)
        end
      end

      module InstanceMethods
        def copy_from_with_flux_tags(arg, options = {})
          copy_from_without_flux_tags(arg, options)
          issue = arg.is_a?(Issue) ? arg : Issue.visible.find(arg)
          # The tags are copied only when the person may set tags on the new issue (the copy skipped that rule).
          allowed = User.current.admin? || (project && User.current.allowed_to?(:manage_issues_tags, project))
          self.tag_list = issue.tag_list if allowed
          self
        end
        def remove_unused_tags_custom
          unused_tags = ActsAsTaggableOn::Tag.where(taggings_count: 0)
          unused_tags.destroy_all
        end
        def prepare_tag_change
          return unless defined?(tag_list) && defined?(tag_list_was) && !tag_list_was.nil?
          @prepare_save_tag_change ||= tag_list != tag_list_was 
        end 
      end
    end
  end
end
base = Issue
patch = FluxTags::Patches::IssuePatch
base.send(:include, patch) unless base.included_modules.include?(patch)