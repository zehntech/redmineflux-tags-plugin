# frozen_string_literal: true

module Api
  module V1
    class FluxTagsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # Tell Redmine's ApplicationController that these actions accept API key
      # authentication. Without this, user_setup does not recognise the request
      # as an API call, User.current stays anonymous, and require_login blocks
      # even valid admin API keys before our custom before_action can run.
      accept_api_auth :index, :show, :create, :update, :destroy, :merge,
                      :issue_tags, :update_issue_tags,
                      :project_tags, :update_project_tags,
                      :time_entry_tags, :update_time_entry_tags,
                      :tagged_records

      before_action :require_api_authentication

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      # rtg-010: the record list of password entries is the Password Manager's
      # own API, which applies its API switch, permissions and audit.
      PASSWORD_RECORDS_MESSAGE = "Password entries are listed by the Password Manager's own API " \
                                 '(GET /projects/:id/password_entries.json?tag=...), which applies its API switch, ' \
                                 'permissions and audit.'
      HIDDEN_PASSWORD_TAGGINGS_MESSAGE = 'This tag is used on password entries you cannot access.'

      # GET /api/v1/flux_tags/tags
      def index
        # rtg-010 (SEC-002): tags used only on password entries the user cannot see are left out.
        scope = FluxTags::PasswordTags.visible_tags(ActsAsTaggableOn::Tag.order(:name), User.current)
        scope = scope.where('LOWER(tags.name) LIKE LOWER(?)', "%#{sanitize_like(params[:q])}%") if params[:q].present?
        scope = filter_tags_by_context(scope, params[:context]) if params[:context].present?

        tags = scope.limit(per_page).offset(offset).to_a
        preload_hidden_counts(tags)
        render_success(tags: tags.map { |tag| tag_json(tag) },
                       pagination: pagination(scope.count))
      end

      # GET /api/v1/flux_tags/tags/:id
      def show
        render_success(tag: tag_json(find_tag))
      end

      # POST /api/v1/flux_tags/tags
      def create
        return unless require_admin_api

        name = tag_name_param
        return render_error('Tag name is required', :unprocessable_entity) if name.blank?

        tag = ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', name).first
        tag ||= ActsAsTaggableOn::Tag.create!(name: name)

        render_success({ tag: tag_json(tag) }, :created)
      end

      # PATCH/PUT /api/v1/flux_tags/tags/:id
      def update
        return unless require_admin_api

        tag = find_tag
        return unless authorize_password_taggings([tag.id])

        name = tag_name_param
        return render_name_too_long_error if FluxTags::PasswordTags.name_too_long?([tag.id], name)

        before = FluxTags::PasswordTags.snapshot([tag.id])
        if tag.update(name: name)
          FluxTags::PasswordTags.instrument('rename', **before, new_name: tag.name) if tag.saved_change_to_name?
          render_success(tag: tag_json(tag))
        else
          render_model_errors(tag)
        end
      end

      # DELETE /api/v1/flux_tags/tags/:id
      def destroy
        return unless require_admin_api

        tag = find_tag
        return unless authorize_password_taggings([tag.id])

        before = FluxTags::PasswordTags.snapshot([tag.id])
        # BUG-FT-007/FT-003: bypass counter-cache callbacks to avoid timeouts
        # caused by negative or corrupted taggings_count values. Manually
        # delete all taggings first, reset the counter, then destroy the tag.
        ActsAsTaggableOn::Tagging.where(tag_id: tag.id).delete_all
        tag.update_column(:taggings_count, 0)
        tag.destroy
        FluxTags::PasswordTags.instrument('delete', **before)
        render_success(message: 'Tag deleted successfully')
      end

      # POST /api/v1/flux_tags/tags/merge
      def merge
        return unless require_admin_api

        requested_ids = Array(params[:tag_ids]).map(&:to_i).uniq
        tags = FluxTags::PasswordTags.visible_tags(ActsAsTaggableOn::Tag.where(id: requested_ids), User.current).to_a

        # BUG-FT-001: provide actionable error when no IDs match existing tags
        if tags.empty?
          return render_error(
            "No tags found with the provided IDs #{requested_ids.inspect}. " \
            'Verify the IDs with list_tags — tags may have been deleted or already merged.',
            :unprocessable_entity
          )
        end

        # Require at least 2 distinct tags to perform a merge
        if tags.length < 2
          return render_error(
            'Merge requires at least 2 tag IDs. ' \
            "Only found 1 tag matching the provided IDs: #{tags.map(&:id).inspect}.",
            :unprocessable_entity
          )
        end

        name = tag_name_param
        return render_error('Target tag name is required', :unprocessable_entity) if name.blank?
        return unless authorize_password_taggings(tags.map(&:id))

        existing = ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', name).first
        if FluxTags::PasswordTags.name_too_long?(tags.map(&:id) + [existing&.id].compact, name)
          return render_name_too_long_error
        end

        before = FluxTags::PasswordTags.snapshot(tags.map(&:id))
        target = nil
        ActsAsTaggableOn::Tagging.transaction do
          target = existing || ActsAsTaggableOn::Tag.create!(name: name)
          # BUG-FT-006 (taggings_count recalculated) and rtg-010 (no record tagged twice).
          FluxTags::TagMerge.merge!(tags, target)
        end
        FluxTags::PasswordTags.instrument('merge', **before, new_name: target.name)

        render_success(tag: tag_json(target), merged_tag_ids: tags.map(&:id))
      end

      # GET /api/v1/flux_tags/issues/:issue_id/tags
      def issue_tags
        issue = find_issue
        return unless authorize_issue_view(issue)

        render_success(taggable: issue_json(issue), tags: tag_list_json(issue))
      end

      # PATCH/PUT /api/v1/flux_tags/issues/:issue_id/tags
      def update_issue_tags
        issue = find_issue
        return unless authorize_issue_view(issue)
        return unless authorize_project_permission(:manage_issues_tags, issue.project)

        update_taggable_tags(issue)
      end

      # GET /api/v1/flux_tags/projects/:project_id/tags
      def project_tags
        project = find_project
        return unless authorize_project_view(project)

        render_success(taggable: project_json(project), tags: tag_list_json(project))
      end

      # PATCH/PUT /api/v1/flux_tags/projects/:project_id/tags
      def update_project_tags
        project = find_project
        return unless authorize_project_view(project)
        return unless authorize_global_permission(:manage_project_tags)

        update_taggable_tags(project)
      end

      # GET /api/v1/flux_tags/time_entries/:time_entry_id/tags
      def time_entry_tags
        time_entry = find_time_entry
        return unless authorize_time_entry_view(time_entry)

        render_success(taggable: time_entry_json(time_entry), tags: tag_list_json(time_entry))
      end

      # PATCH/PUT /api/v1/flux_tags/time_entries/:time_entry_id/tags
      def update_time_entry_tags
        time_entry = find_time_entry
        return unless authorize_time_entry_view(time_entry)
        return unless authorize_project_permission(:manage_time_entries_tags, time_entry.project)

        update_taggable_tags(time_entry)
      end

      # GET /api/v1/flux_tags/tags/:id/records
      def tagged_records
        tag = find_tag
        if params[:type] == FluxTags::PasswordTags::API_TYPE
          return render_error(PASSWORD_RECORDS_MESSAGE, :unprocessable_entity)
        end

        taggable_type = { 'issues' => 'Issue', 'projects' => 'Project', 'time_entries' => 'TimeEntry' }[params[:type]]
        return render_error("type must be one of: issues, projects, time_entries", :unprocessable_entity) if taggable_type.blank?

        taggable_ids = ActsAsTaggableOn::Tagging
                        .where(tag_id: tag.id, taggable_type: taggable_type)
                        .pluck(:taggable_id)

        records = case taggable_type
                  when 'Issue' then Issue.where(id: taggable_ids).select { |i| i.visible?(User.current) }
                  when 'Project' then Project.where(id: taggable_ids).select { |p| p.visible?(User.current) }
                  when 'TimeEntry' then TimeEntry.where(id: taggable_ids).select { |t| t.visible?(User.current) }
                  end

        total = records.size
        page_records = records.slice(offset, per_page) || []

        render_success(
          tag: tag_json(tag),
          type: params[:type],
          records: page_records.map { |r| taggable_json(r) },
          pagination: pagination(total)
        )
      end

      private

      def require_api_authentication
        key = request.headers['X-Redmine-API-Key'].presence || params[:key].to_s.presence
        return render_error('API key is required', :unauthorized) if key.blank?

        user = User.find_by_api_key(key)
        return render_error('Invalid or inactive API key', :unauthorized) unless user&.active?

        User.current = user
      end

      def require_admin_api
        return true if User.current.admin?
        return true if User.current.allowed_to?(:manage_tags, nil, global: true)

        render_error(
          'You do not have permission to manage tags. ' \
          'Ask your administrator to grant you the "Manage Tags" permission ' \
          'under Administration → Roles and Permissions.',
          :forbidden
        )
        false
      end

      # rtg-010 (SEC-002): a non-admin may not rename, merge or delete a tag
      # that is also on password entries the user cannot see.
      def authorize_password_taggings(tag_ids)
        return true unless FluxTags::PasswordTags.touches_hidden?(tag_ids, User.current)

        render_error(HIDDEN_PASSWORD_TAGGINGS_MESSAGE, :forbidden)
        false
      end

      def render_name_too_long_error
        render_error("Tag name is too long for a tag used on password entries (maximum is " \
                     "#{FluxTags::PasswordTags.name_max} characters)", :unprocessable_entity)
      end

      def authorize_project_permission(permission, project)
        return true if User.current.admin? || User.current.allowed_to?(permission, project)

        render_error("You do not have permission to #{permission}", :forbidden)
        false
      end

      def authorize_global_permission(permission)
        return true if User.current.admin? || User.current.allowed_to?(permission, nil, global: true)

        render_error("You do not have permission to #{permission}", :forbidden)
        false
      end

      def authorize_issue_view(issue)
        return true if issue.visible?(User.current)

        render_error('You do not have permission to view this issue', :forbidden)
        false
      end

      def authorize_project_view(project)
        return true if project.visible?(User.current)

        render_error('You do not have permission to view this project', :forbidden)
        false
      end

      def authorize_time_entry_view(time_entry)
        return true if time_entry.visible?(User.current)

        render_error('You do not have permission to view this time entry', :forbidden)
        false
      end

      def update_taggable_tags(record)
        # Capture affected tag IDs before the change so we can recalculate counts.
        old_tag_ids = record.tags.pluck(:id)
        record.tag_list = tag_names_param

        if record.save
          # BUG-FT-003: Recalculate taggings_count from actual DB rows for all
          # affected tags. Counter cache can drift negative after merge operations
          # that use update_all (bypassing callbacks). Using COUNT(*) is the only
          # reliable source of truth.
          new_tag_ids = record.tags.pluck(:id)
          affected_ids = (old_tag_ids + new_tag_ids).uniq
          ActsAsTaggableOn::Tag.where(id: affected_ids).each do |tag|
            actual_count = ActsAsTaggableOn::Tagging.where(tag_id: tag.id).count
            tag.update_column(:taggings_count, actual_count)
          end
          # BUG-FT-014: Do NOT call remove_unused_tags! — tags must only be
          # deleted explicitly via DELETE /tags/:id, not auto-deleted when
          # usage count drops to zero.
          render_success(taggable: taggable_json(record), tags: tag_list_json(record))
        else
          render_model_errors(record)
        end
      end

      # rtg-010 (SEC-002): a tag hidden from the user is not found.
      def find_tag
        FluxTags::PasswordTags.visible_tags(ActsAsTaggableOn::Tag.all, User.current).find(params[:id])
      end

      def find_issue
        Issue.find(params[:issue_id])
      end

      def find_project
        Project.find(params[:project_id])
      end

      def find_time_entry
        TimeEntry.find(params[:time_entry_id])
      end

      def tag_name_param
        value = params.dig(:tag, :name).presence || params[:name].presence
        value.to_s.strip
      end

      def tag_names_param
        value = params[:tag_list].presence || params[:tags].presence
        Array(value).flat_map { |item| item.to_s.split(',') }
                    .map(&:strip)
                    .reject(&:blank?)
                    .uniq { |name| name.downcase }
      end

      def filter_tags_by_context(scope, context)
        if context == FluxTags::PasswordTags::API_TYPE
          return scope.where(id: FluxTags::PasswordTags.visible_password_taggings(User.current).select(:tag_id))
        end

        taggable_type = { 'issues' => 'Issue', 'projects' => 'Project', 'time_entries' => 'TimeEntry' }[context]
        if taggable_type
          scope.joins(:taggings).where(taggings: { taggable_type: taggable_type }).distinct
        else
          scope.joins(:taggings).where(taggings: { context: context }).distinct
        end
      end

      def tag_list_json(record)
        tags = record.tag_counts.to_a
        preload_hidden_counts(tags)
        tags.map { |tag| tag_json(tag) }
      end

      def tag_json(tag)
        {
          id: tag.id,
          name: tag.name,
          # rtg-010 (SEC-002): password taggings the user cannot see are not counted.
          taggings_count: [tag.try(:taggings_count).to_i - hidden_count(tag), 0].max,
          contexts: tag_contexts(tag)
        }
      end

      # Hidden password taggings of the tags of a response, in one query.
      def preload_hidden_counts(tags)
        @hidden_counts = (@hidden_counts || {}).merge(
          FluxTags::PasswordTags.hidden_counts(tags.map(&:id), User.current)
        )
      end

      def hidden_count(tag)
        preload_hidden_counts([tag]) unless @hidden_counts&.key?(tag.id)
        @hidden_counts[tag.id]
      end

      def tag_contexts(tag)
        # BUG-FT-004: ActsAsTaggableOn always stores context="tags" (the default
        # context), so plucking :context returns ["tags"] which the MCP filters out.
        # Return the taggable_types instead, mapped to human-readable context names.
        type_map = { 'Issue' => 'issues', 'Project' => 'projects', 'TimeEntry' => 'time_entries' }
        taggable_types = ActsAsTaggableOn::Tagging.where(tag_id: tag.id).distinct.pluck(:taggable_type)
        contexts = taggable_types.map { |t| type_map[t] }.compact.uniq
        # rtg-010: password entries count only when the user can see one of them.
        if taggable_types.include?(FluxTags::PasswordTags::TAGGABLE_TYPE) &&
           FluxTags::PasswordTags.visible_password_taggings(User.current).where(tag_id: tag.id).exists?
          contexts << FluxTags::PasswordTags::API_TYPE
        end
        contexts
      end

      def taggable_json(record)
        case record
        when Issue then issue_json(record)
        when Project then project_json(record)
        when TimeEntry then time_entry_json(record)
        end
      end

      def issue_json(issue)
        { type: 'issue', id: issue.id, subject: issue.subject, project_id: issue.project_id }
      end

      def project_json(project)
        { type: 'project', id: project.id, name: project.name, identifier: project.identifier }
      end

      def time_entry_json(time_entry)
        {
          type: 'time_entry',
          id: time_entry.id,
          issue_id: time_entry.issue_id,
          project_id: time_entry.project_id,
          hours: time_entry.hours
        }
      end

      def per_page
        value = params[:per_page].to_i
        value = 25 if value <= 0
        [value, 100].min
      end

      def page
        [params[:page].to_i, 1].max
      end

      def offset
        (page - 1) * per_page
      end

      def pagination(total)
        { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end

      def render_success(data = {}, status = :ok)
        render json: { success: true, data: data }, status: status
      end

      def render_error(message, status = :bad_request)
        render json: { success: false, error: { message: message } }, status: status
      end

      def render_model_errors(model)
        render json: {
          success: false,
          error: {
            message: 'Validation failed',
            details: model.errors.full_messages
          }
        }, status: :unprocessable_entity
      end

      def render_not_found(_exception = nil)
        render_error('Resource not found', :not_found)
      end
    end
  end
end
