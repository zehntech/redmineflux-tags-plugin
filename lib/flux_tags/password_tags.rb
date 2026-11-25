# frozen_string_literal: true

module FluxTags
  # rtg-010: tags of the Redmineflux Password Manager's entries. Since its
  # rfpm-026 they live in the shared tags/taggings tables, with the taggable
  # type PasswordManager::Entry and the context "tags".
  #
  # Everything here is decided at request time: plugins load alphabetically,
  # so the Password Manager registers after flux_tags' init.rb has run. Its
  # classes are reached by name through safe_constantize, so flux_tags runs
  # unchanged when it is not installed (and on Redmine 4).
  module PasswordTags
    PLUGIN_ID = :redmineflux_password_manager
    TAGGABLE_TYPE = 'PasswordManager::Entry'
    CONTEXT = 'tags'
    API_TYPE = 'password_entries'
    TAB = 'password_entry'
    # The Password Manager's own tag join table, dropped once its tags are moved.
    LEGACY_TABLE = 'redmineflux_password_manager_entry_tags'
    # The vault's Tag::NAME_MAX, for a vault that does not define it.
    NAME_MAX_DEFAULT = 60
    EVENT = 'password_tags_changed.flux_tags'

    # The registered plugin id, never a folder name (checkouts are often
    # named redmineflux-password-manager).
    def self.installed?
      Redmine::Plugin.installed?(PLUGIN_ID)
    end

    # nil when the Password Manager shares the tag tables, otherwise why not:
    # :not_installed, :legacy_tags (it keeps its own tag tables) or
    # :schema_incomplete. Only nil is kept: installing or migrating a plugin
    # needs a restart anyway.
    def self.problem
      return nil if @compatible

      result = if !installed?
                 :not_installed
               elsif legacy_tags?
                 :legacy_tags
               elsif SharedTagsSchema.problem
                 :schema_incomplete
               end
      @compatible = result.nil?
      result
    end

    def self.available?
      problem.nil?
    end

    # Forgets the kept answer (tests).
    def self.reset!
      @compatible = nil
    end

    # A vault older than rfpm-026 has no Tagging model; one that has not run
    # rfpm-026's migrations still has its own join table.
    def self.legacy_tags?
      tagging_class.nil? || ActiveRecord::Base.connection.data_source_exists?(LEGACY_TABLE)
    end

    def self.entry_class
      TAGGABLE_TYPE.safe_constantize
    end

    def self.tagging_class
      'PasswordManager::Tagging'.safe_constantize
    end

    # Tags used on password entries, the way Issue.available_tags lists issue tags.
    def self.available_tags
      ActsAsTaggableOn::Tag.joins(:taggings)
                           .select('tags.id, tags.name, tags.taggings_count, COUNT(taggings.id) as count')
                           .group('tags.id, tags.name, tags.taggings_count')
                           .where(taggings: { taggable_type: TAGGABLE_TYPE, context: CONTEXT })
                           .order('tags.name')
    end

    # The ids of the password entries the vault shows the user, or nil when
    # the vault's visibility rule is not available.
    def self.visible_entry_ids(user)
      entries = entry_class
      entries.visible_across_projects(user).select(:id) if entries.respond_to?(:visible_across_projects)
    end

    # Password taggings the user may not see. Admins see all. Without the
    # vault's visibility rule (its code removed, or an older version) every
    # password tagging is hidden: the check fails closed.
    def self.hidden_taggings(user)
      scope = ActsAsTaggableOn::Tagging.where(taggable_type: TAGGABLE_TYPE)
      return scope.none if user.admin?

      ids = visible_entry_ids(user)
      ids ? scope.where.not(taggable_id: ids) : scope
    end

    # Password taggings the user may see.
    def self.visible_password_taggings(user)
      scope = ActsAsTaggableOn::Tagging.where(taggable_type: TAGGABLE_TYPE)
      return scope if user.admin?

      ids = visible_entry_ids(user)
      ids ? scope.where(taggable_id: ids) : scope.none
    end

    # Every tagging the user may see: all other types, plus visible password taggings.
    def self.shown_taggings(user)
      others = ActsAsTaggableOn::Tagging.where.not(taggable_type: TAGGABLE_TYPE)
      ids = visible_entry_ids(user)
      ids ? others.or(ActsAsTaggableOn::Tagging.where(taggable_type: TAGGABLE_TYPE, taggable_id: ids)) : others
    end

    # The tags of scope the user may see (SEC-002): all but those whose every
    # tagging is a hidden password tagging. A tag with other taggings, or with
    # none, stays. NULL tag ids are left out of both sub-queries, because
    # NOT IN over a NULL matches nothing.
    def self.visible_tags(scope, user)
      return scope if user.admin?

      shown = shown_taggings(user).where.not(tag_id: nil).select(:tag_id)
      hidden_only = hidden_taggings(user).where.not(tag_id: nil).where.not(tag_id: shown).select(:tag_id)
      scope.where.not(id: hidden_only)
    end

    # {tag_id => number of password taggings on it the user may not see}, with
    # every requested id, in one query.
    def self.hidden_counts(tag_ids, user)
      counts = Hash[tag_ids.map { |id| [id, 0] }]
      return counts if user.admin? || tag_ids.empty?

      counts.merge(hidden_taggings(user).where(tag_id: tag_ids).group(:tag_id).count)
    end

    # True when a tag in tag_ids has password taggings the user may not see.
    def self.touches_hidden?(tag_ids, user)
      !user.admin? && hidden_taggings(user).where(tag_id: tag_ids).exists?
    end

    def self.password_entry_ids_for(tag_ids)
      ActsAsTaggableOn::Tagging.where(tag_id: tag_ids, taggable_type: TAGGABLE_TYPE).distinct.pluck(:taggable_id)
    end

    def self.name_max
      tag_class = 'PasswordManager::Tag'.safe_constantize
      tag_class&.const_defined?(:NAME_MAX, false) ? tag_class::NAME_MAX : NAME_MAX_DEFAULT
    end

    # A longer name would make every tagged vault entry fail validation on its
    # next save, so tags used on password entries keep the vault's limit.
    def self.name_too_long?(tag_ids, name)
      name.to_s.strip.length > name_max &&
        ActsAsTaggableOn::Tagging.where(tag_id: tag_ids, taggable_type: TAGGABLE_TYPE).exists?
    end

    # What an event about these tags needs, read before they change.
    def self.snapshot(tag_ids)
      ids = Array(tag_ids).map(&:to_i)
      { tag_ids: ids,
        names: Hash[ActsAsTaggableOn::Tag.where(id: ids).pluck(:id, :name)],
        entry_ids: password_entry_ids_for(ids) }
    end

    # Tells subscribers (the Password Manager's audit) that a change made in
    # flux_tags touched password taggings. Call after the change has committed.
    def self.instrument(action, tag_ids:, names:, entry_ids:, new_name: nil)
      return if entry_ids.blank?

      ActiveSupport::Notifications.instrument(EVENT, action: action, tag_ids: tag_ids, names: names,
                                                     new_name: new_name, password_entry_ids: entry_ids,
                                                     user_id: User.current.id)
    end
  end
end
