# frozen_string_literal: true

module RfFluxTags
  # What a person may learn about tags. A tag name, how often it is used and where it is used are information
  # about records: a tag that sits only on issues, projects or time entries of a private project must not be
  # listed (or counted) for someone who cannot open those records. Administrators see everything.
  #
  # Tags that are used nowhere are still listed (they are part of the shared library, created on the
  # administration page for later use), and taggings of record types this plugin does not know (other plugins
  # share the tables) are left alone: whether those are visible is for the plugin that owns them to decide.
  module TagVisibility
    RECORD_TYPES = %w[Issue Project TimeEntry].freeze

    # SQL condition on the taggings table: taggings of records of the three kinds the user may see, and taggings
    # of kinds nobody here knows about. Built from Redmine's own visibility scopes, no request data in it.
    def self.record_condition(user)
      issues = Issue.visible(user).select(:id).to_sql
      projects = Project.visible(user).select(:id).to_sql
      entries = TimeEntry.visible(user).select(:id).to_sql
      known = (RECORD_TYPES + [FluxTags::PasswordTags::TAGGABLE_TYPE]).map { |type| ActiveRecord::Base.connection.quote(type) }.join(', ')
      "((taggings.taggable_type = 'Issue' AND taggings.taggable_id IN (#{issues})) " \
        "OR (taggings.taggable_type = 'Project' AND taggings.taggable_id IN (#{projects})) " \
        "OR (taggings.taggable_type = 'TimeEntry' AND taggings.taggable_id IN (#{entries})) " \
        "OR taggings.taggable_type NOT IN (#{known}))"
    end

    # The taggings the user may see, password entries included only when the Password Manager shows them.
    def self.taggings(user)
      return ActsAsTaggableOn::Tagging.all if user.admin?

      visible_password = FluxTags::PasswordTags.visible_password_taggings(user).select(:id)
      ActsAsTaggableOn::Tagging.where(record_condition(user))
                               .or(ActsAsTaggableOn::Tagging.where(id: visible_password))
    end

    # scope (of tags) without the tags that exist only on records the user cannot see.
    def self.visible_tags(scope, user)
      return scope if user.admin?

      seen = taggings(user).where.not(tag_id: nil).select(:tag_id).to_sql
      scope.where("tags.id IN (#{seen}) OR NOT EXISTS (SELECT 1 FROM taggings t0 WHERE t0.tag_id = tags.id)")
    end

    # {tag_id => [number of visible taggings, [kinds of record it is used on]]} for the given tags, in one query.
    def self.usage(tag_ids, user)
      result = Hash[tag_ids.map { |id| [id, [0, []]] }]
      return result if tag_ids.empty?

      taggings(user).where(tag_id: tag_ids).group(:tag_id, :taggable_type).count.each do |(tag_id, type), count|
        entry = result[tag_id]
        next if entry.nil?

        entry[0] += count
        entry[1] << type
      end
      result
    end
  end
end
