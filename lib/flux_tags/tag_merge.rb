# frozen_string_literal: true

module FluxTags
  # rtg-010: merging tags, shared by the admin page and the REST API.
  module TagMerge
    DUPLICATE_KEY = %i[taggable_type taggable_id context tagger_type tagger_id].freeze

    # Moves every tagging of tags to target without tagging a record twice
    # (the unique index does not catch it while tagger_id and tagger_type are
    # NULL), destroys the merged tags and recounts the target. Call it inside
    # a transaction.
    def self.merge!(tags, target)
      merged_ids = tags.map(&:id) - [target.id]
      if merged_ids.any?
        delete_duplicates(merged_ids, target.id)
        ActsAsTaggableOn::Tagging.where(tag_id: merged_ids).update_all(tag_id: target.id)
        tags.reject { |tag| tag.id == target.id }.each(&:destroy)
      end
      target.update_column(:taggings_count, ActsAsTaggableOn::Tagging.where(tag_id: target.id).count)
      target
    end

    # Keeps the target's own tagging of a record, else the oldest merged one.
    def self.delete_duplicates(merged_ids, target_id)
      seen = ActsAsTaggableOn::Tagging.where(tag_id: target_id).pluck(*DUPLICATE_KEY).to_set
      duplicates = ActsAsTaggableOn::Tagging.where(tag_id: merged_ids).order(:id)
                                            .pluck(:id, *DUPLICATE_KEY)
                                            .reject { |_id, *key| seen.add?(key) }
                                            .map(&:first)
      ActsAsTaggableOn::Tagging.where(id: duplicates).delete_all if duplicates.any?
    end
  end
end
