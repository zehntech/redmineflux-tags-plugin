# frozen_string_literal: true

module RfFluxTags
  # Changing the tags of issues, with a History entry. One place for the three
  # ways tags change: the inline editor, the issue form and bulk edit.
  module IssueTags
    DETAIL_KEY = 'tag_list'

    # May the user change the tags of this issue?
    def self.allowed?(issue, user = User.current)
      return false unless issue.visible?(user)
      return true if user.admin?

      # The tag right in the project AND the right to edit THIS issue (edit_own_issues only covers issues the
      # person created; attributes_editable? is Redmine's own answer, workflow and closed projects included).
      user.allowed_to?(:manage_issues_tags, issue.project) && issue.attributes_editable?(user)
    end

    # Sets the tags of the issue to names and saves, leaving a History entry
    # when they changed. Returns false (errors on the issue) when saving fails.
    def self.replace(issue, names, user: User.current, notes: nil)
      old_names = issue.tag_list.to_a
      return true if same?(old_names, names) && notes.blank?

      issue.init_journal(user, notes)
      issue.tag_list = names
      add_history(issue, old_names, names)
      issue.save
    end

    # Adds and removes tags on an issue that is about to be saved by bulk edit.
    def self.change(issue, add: [], remove: [])
      old_names = issue.tag_list.to_a
      removed = remove.map(&:downcase)
      kept = old_names.reject { |name| removed.include?(name.downcase) }
      known = kept.map(&:downcase)
      added = add.reject { |name| known.include?(name.downcase) }
      new_names = kept + added
      return false if same?(old_names, new_names)

      reason = limit_problem(old_names, new_names, added)
      if reason
        issue.rf_flux_tags_refusal = reason if issue.respond_to?(:rf_flux_tags_refusal=)
        return false
      end

      issue.tag_list = new_names
      add_history(issue, old_names, new_names)
      true
    end

    # Why a bulk change must be refused, or nil. Only what the change adds counts (a record that already holds
    # more than the limit stays editable).
    def self.limit_problem(old_names, new_names, added)
      if new_names.size > RfFluxTags::TAG_LIST_LIMIT && new_names.size > old_names.size
        "can hold at most #{RfFluxTags::TAG_LIST_LIMIT} tags"
      elsif added.any? { |name| name.length > RfFluxTags::TAG_NAME_MAX }
        "has a tag name longer than #{RfFluxTags::TAG_NAME_MAX} characters"
      end
    end

    def self.same?(old_names, new_names)
      old_names.map(&:downcase).sort == new_names.map(&:downcase).sort
    end

    # The "Tags changed from ... to ..." line of the issue History.
    def self.add_history(issue, old_names, new_names)
      journal = issue.current_journal
      return if journal.nil? || same?(old_names, new_names)

      journal.details << JournalDetail.new(property: 'attr', prop_key: DETAIL_KEY,
                                           old_value: old_names.join(', ').presence,
                                           value: new_names.join(', ').presence)
    end
  end
end
