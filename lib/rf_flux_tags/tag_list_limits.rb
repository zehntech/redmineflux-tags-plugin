# frozen_string_literal: true

module RfFluxTags
  # The limits every way of setting tags has to respect: at most TAG_LIST_LIMIT tags on a record and at most
  # TAG_NAME_MAX characters in a name. The REST API and the inline editor check them in their controllers; this
  # validation makes the issue form, the new issue form and bulk edit (and the project and time entry forms)
  # obey the same rules (#124188).
  #
  # Only a list that is being changed is checked, and only for what it adds: a record that already holds more
  # than the limit (saved before the limit existed) stays editable, and tags can still be removed from it.
  module TagListLimits
    def self.included(base)
      base.validate :rf_flux_tags_within_limits
    end

    # A reason set by bulk edit when it refused the tag change itself: the save then fails with it, so the
    # screen never reports a success for a change that was not made (#124188).
    attr_accessor :rf_flux_tags_refusal

    private

    def rf_flux_tags_within_limits
      return unless respond_to?(:tag_list)

      errors.add(:tag_list, rf_flux_tags_refusal) if rf_flux_tags_refusal.present?

      names = tag_list.to_a
      stored = new_record? || !respond_to?(:tag_list_was) || tag_list_was.nil? ? [] : tag_list_was.to_a
      return if !new_record? && names.map(&:downcase).sort == stored.map(&:downcase).sort

      if names.size > RfFluxTags::TAG_LIST_LIMIT && names.size > stored.size
        errors.add(:tag_list, "can hold at most #{RfFluxTags::TAG_LIST_LIMIT} tags")
      end
      known = stored.map(&:downcase)
      if names.any? { |name| name.length > RfFluxTags::TAG_NAME_MAX && !known.include?(name.downcase) }
        errors.add(:tag_list, "has a tag name longer than #{RfFluxTags::TAG_NAME_MAX} characters")
      end
    end
  end
end
