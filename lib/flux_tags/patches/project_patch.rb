module FluxTags
  module Patches
    module ProjectPatch
      def self.included(base)
        base.extend(ClassMethods)
        base.send(:include, InstanceMethods)
        base.class_eval do
          acts_as_ordered_taggable
          include RfFluxTags::TagListLimits unless include?(RfFluxTags::TagListLimits)
          before_save :prepare_tag_change
          # BUG-FT-014: Removed after_save :remove_unused_tags —
          # auto-deleting zero-usage tags silently destroys tag data.
          # For an existing project the right has to be held on that project; only when a project is being
          # created (no project yet) is the right looked for in any role of the person.
          safe_attributes 'tag_list',
                          if: lambda { |project, user|
                            user.admin? ||
                              (project.new_record? ? user.allowed_to?(:manage_project_tags, nil, global: true)
                                                   : user.allowed_to?(:manage_project_tags, project))
                          }
      

          # searchable_options[:columns] ||= []
          # searchable_options[:columns] << "tags.name"
          
          # searchable_options[:preload] ||= []
          # searchable_options[:preload] << :tags
          # old_scope = searchable_options[:scope]
          # searchable_options[:scope] = lambda do |options|
          #   new_scope = old_scope.is_a?(Proc) ? old_scope.call(options) : old_scope
          #   new_scope
          #     .joins("LEFT JOIN taggings ON taggings.taggable_id = projects.id AND taggings.context = 'tags' AND taggings.taggable_type = 'Project'")
          #     .joins('LEFT JOIN tags ON tags.id = taggings.tag_id')
          # end
        end
      end

      module ClassMethods
        def available_tags(options = {})
          projects_scope = Project.visible.select(:id)

          result_scope = ActsAsTaggableOn::Tag.joins(:taggings)
            .select('tags.id, tags.name, tags.taggings_count, COUNT(taggings.id) as count')
            .group('tags.id, tags.name, tags.taggings_count')
            .where(taggings: { taggable_type: 'Project', taggable_id: projects_scope })
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

        def get_common_tag_list_from_multiple_projects(ids)
          common_tags = ActsAsTaggableOn::Tag.joins(:tagging)
            .select('tags.id', 'tags.name')
            .where(:tagging => {:taggable_type => 'Project', :taggable_id => ids})
            .group('tags.id', 'tags.name')
            .having("count(*) = #{ids.count}").to_a

          TagList.new(common_tags)
        end
      end
      
      module InstanceMethods
        def copy_from(arg, options = {})
        project = arg.is_a?(Project) ? arg : Project.find(arg)
        self.tag_list = project.tag_list
        Rails.logger.debug "Tag list after copying from issue: #{self.tag_list.inspect}"
        self
      end
      
        def remove_unused_tags
          unused_tags = ActsAsTaggableOn::Tag.where(taggings_count: 0)
          unused_tags.destroy_all
        end
        def prepare_tag_change
          if tag_list_changed?
          end
        end 
      end
    end
  end 
end

base = Project
patch = FluxTags::Patches::ProjectPatch
base.send(:include, patch) unless base.included_modules.include?(patch) 
