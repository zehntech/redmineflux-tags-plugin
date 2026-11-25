# frozen_string_literal: true

module RfFluxTags
  # Create, rename and delete tags for the administration page. The
  # rules are the ones the REST API and the old edit page already follow:
  # names are unique ignoring case, tags used on password entries keep the
  # Password Manager's length limit, and the Password Manager hears about
  # every change that touches its entries.
  module TagOperations
    # ok? tells whether it worked; error is an i18n key (message carries a
    # ready-made detail); tag / count carry the outcome.
    Result = Struct.new(:tag, :count, :error, :message, keyword_init: true) do
      def ok?
        error.nil?
      end
    end

    def self.failure(error, message = nil)
      Result.new(error: error, message: message)
    end

    def self.tag_class
      ActsAsTaggableOn::Tag
    end

    def self.find_by_name(name, except_id: nil)
      scope = tag_class.where('LOWER(name) = LOWER(?)', name.to_s)
      scope = scope.where.not(id: except_id) if except_id
      scope.first
    end

    # nil when the name is acceptable, otherwise the i18n key of the problem.
    def self.name_problem(name)
      return :rf_flux_tags_error_name_blank if name.blank?
      return :rf_flux_tags_error_name_too_long if name.length > TAG_NAME_MAX

      nil
    end

    def self.clean_name(value)
      RfFluxTags.clean_name(value)
    end

    def self.clean_description(value)
      value.to_s.gsub(/[[:cntrl:]]/, ' ').squish.first(DESCRIPTION_MAX).presence
    end

    def self.create(name:, color: nil, description: nil)
      name = clean_name(name)
      problem = name_problem(name)
      return failure(problem) if problem

      RfFluxTags::NameLock.with(name) do
        next failure(:rf_flux_tags_error_name_taken) if find_by_name(name)

        tag = tag_class.new(name: name)
        assign_extras(tag, color, description)
        tag.save ? Result.new(tag: tag) : failure(:rf_flux_tags_error_save, tag.errors.full_messages.to_sentence)
      end
    rescue ActiveRecord::RecordNotUnique
      failure(:rf_flux_tags_error_name_taken)
    end

    def self.update(tag, name:, color: :keep, description: :keep)
      name = clean_name(name)
      problem = name_problem(name)
      return failure(problem) if problem
      return password_name_failure if FluxTags::PasswordTags.name_too_long?([tag.id], name)

      RfFluxTags::NameLock.with(name) do
        next failure(:rf_flux_tags_error_name_taken) if find_by_name(name, except_id: tag.id)

        before = FluxTags::PasswordTags.snapshot([tag.id])
        tag.name = name
        assign_extras(tag, color, description)
        next failure(:rf_flux_tags_error_save, tag.errors.full_messages.to_sentence) unless tag.save

        FluxTags::PasswordTags.instrument('rename', **before, new_name: tag.name) if tag.saved_change_to_name?
        Result.new(tag: tag)
      end
    rescue ActiveRecord::RecordNotUnique
      failure(:rf_flux_tags_error_name_taken)
    end

    def self.destroy(tags)
      tags = Array(tags)
      return failure(:rf_flux_tags_error_not_found) if tags.empty?

      ids = tags.map(&:id)
      before = FluxTags::PasswordTags.snapshot(ids)
      tag_class.transaction do
        # Same approach as the REST API (BUG-FT-007): drop the taggings in one
        # statement so a stale taggings_count cannot make the delete time out.
        ActsAsTaggableOn::Tagging.where(tag_id: ids).delete_all
        tag_class.where(id: ids).update_all(taggings_count: 0)
        tag_class.where(id: ids).destroy_all
      end
      FluxTags::PasswordTags.instrument('delete', **before)
      Result.new(count: ids.size)
    end

    # Deletes every tag that is on no record at all.
    def self.destroy_unused
      unused = tag_class.where(TagCatalog.unused_sql).to_a
      return Result.new(count: 0) if unused.empty?

      tag_class.where(id: unused.map(&:id)).destroy_all
      Result.new(count: unused.size)
    end

    def self.password_name_failure
      failure(:error_flux_tags_name_too_long_for_password_tags)
    end
    private_class_method :password_name_failure

    # color / description :keep leaves the stored value alone.
    def self.assign_extras(tag, color, description)
      return unless Schema.extras?

      tag.rf_flux_tags_color = Colors.normalize(color) unless color == :keep
      tag.rf_flux_tags_description = clean_description(description) unless description == :keep
    end
    private_class_method :assign_extras
  end
end
