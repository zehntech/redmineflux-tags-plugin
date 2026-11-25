# frozen_string_literal: true

module Api
  module V1
    class FluxTagsController < ApplicationController
      # Why the forgery check is skipped here: every request has to carry an API key in the X-Redmine-API-Key
      # header (require_api_authentication below refuses everything else, a browser session alone is never
      # enough), so there is no ambient credential for another site to ride on.
      skip_before_action :verify_authenticity_token

      # Tell Redmine's ApplicationController that these actions accept API key
      # authentication. Without this, user_setup does not recognise the request
      # as an API call, User.current stays anonymous, and require_login blocks
      # even valid admin API keys before our custom before_action can run.
      accept_api_auth :index, :show, :create, :update, :destroy,
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
      MAX_PAGE = 100_000
      TYPES = { 'issues' => 'Issue', 'projects' => 'Project', 'time_entries' => 'TimeEntry' }.freeze

      # GET /api/v1/flux_tags/tags
      def index
        # Tags that exist only on records (or password entries) the user cannot see are left out (rtg-010, FT-A4).
        scope = visible_tags(ActsAsTaggableOn::Tag.order(:name))
        scope = scope.where('LOWER(tags.name) LIKE LOWER(?)', "%#{sanitize_like(params[:q])}%") if params[:q].present?
        scope = filter_tags_by_context(scope, params[:context]) if params[:context].present?

        tags = scope.limit(per_page).offset(offset).to_a
        preload_usage(tags)
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
        return unless valid_tag_name?(name)

        # One request at a time per name: "bug" and "BUG" sent together must end up as one tag.
        tag = RfFluxTags::NameLock.with(name) do
          existing = ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', name).first
          if existing && !visible_tags(ActsAsTaggableOn::Tag.where(id: existing.id)).exists?
            render_error('A tag with this name already exists', :unprocessable_entity)
            next nil
          end
          existing || create_or_find_tag(name)
        end
        return unless tag

        render_success({ tag: tag_json(tag) }, :created)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        render_error('Tag name is not valid or is already taken', :unprocessable_entity)
      end

      # PATCH/PUT /api/v1/flux_tags/tags/:id
      def update
        return unless require_admin_api

        tag = find_tag
        return unless authorize_password_taggings([tag.id])

        name = tag_name_param
        return unless valid_tag_name?(name)
        return render_name_too_long_error if FluxTags::PasswordTags.name_too_long?([tag.id], name)

        # Same rule as create and as the pages: another tag with the same name, ignoring capital letters,
        # makes the name taken (renaming a tag to a different spelling of its OWN name is fine).
        RfFluxTags::NameLock.with(name) do
          if ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', name).where.not(id: tag.id).exists?
            next render_error('A tag with this name already exists', :unprocessable_entity)
          end

          before = FluxTags::PasswordTags.snapshot([tag.id])
          if tag.update(name: name)
            FluxTags::PasswordTags.instrument('rename', **before, new_name: tag.name) if tag.saved_change_to_name?
            render_success(tag: tag_json(tag))
          else
            render_model_errors(tag)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        render_error('A tag with this name already exists', :unprocessable_entity)
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
        ActsAsTaggableOn::Tag.where(id: tag.id).update_all(taggings_count: 0)
        tag.destroy
        FluxTags::PasswordTags.instrument('delete', **before)
        render_success(message: 'Tag deleted successfully')
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
        # The same rule as the editor on the issue page: the tag right AND the right to edit THIS issue.
        unless RfFluxTags::IssueTags.allowed?(issue, User.current)
          return render_error('You do not have permission to change the tags of this issue', :forbidden)
        end

        names = tag_names_param
        return unless names

        old_tag_ids = issue.tags.pluck(:id)
        return render_model_errors(issue) unless RfFluxTags::IssueTags.replace(issue, names, user: User.current)

        render_taggable_result(issue, old_tag_ids)
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
        # The right has to be held on THIS project; a role in some other project proves nothing here.
        return unless authorize_project_permission(:manage_project_tags, project)

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
        unless User.current.admin? || time_entry.editable_by?(User.current)
          return render_error('You do not have permission to edit this time entry', :forbidden)
        end

        update_taggable_tags(time_entry)
      end

      # GET /api/v1/flux_tags/tags/:id/records
      def tagged_records
        tag = find_tag
        if params[:type] == FluxTags::PasswordTags::API_TYPE
          return render_error(PASSWORD_RECORDS_MESSAGE, :unprocessable_entity)
        end

        taggable_type = TYPES[params[:type].to_s]
        return render_error('type must be one of: issues, projects, time_entries', :unprocessable_entity) if taggable_type.blank?

        tagged_ids = ActsAsTaggableOn::Tagging.where(tag_id: tag.id, taggable_type: taggable_type).select(:taggable_id)
        # Visibility and paging are done by the database, not by loading every tagged record into memory.
        scope = case taggable_type
                when 'Issue' then Issue.visible(User.current).where(id: tagged_ids)
                when 'Project' then Project.visible(User.current).where(id: tagged_ids)
                when 'TimeEntry' then TimeEntry.visible(User.current).where(id: tagged_ids)
                end

        total = scope.count
        page_records = scope.reorder(:id).limit(per_page).offset(offset).to_a

        render_success(
          tag: tag_json(tag),
          type: params[:type],
          records: page_records.map { |r| taggable_json(r) },
          pagination: pagination(total)
        )
      end

      private

      # Two requests that create the same name at the same moment: the one that loses the race gets the tag the
      # other one made (the API promises the existing tag when the name exists), not an error (#124190).
      def create_or_find_tag(name)
        ActsAsTaggableOn::Tag.create!(name: name)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        existing = ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', name).first
        raise unless existing
        raise if !visible_tags(ActsAsTaggableOn::Tag.where(id: existing.id)).exists?

        existing
      end

      # The key has to come in the X-Redmine-API-Key header: a key in the address ends up in logs and in the
      # Referer header of the next request. The REST API switch of Redmine applies here as it does to the
      # core API.
      def require_api_authentication
        return render_error('The REST API is disabled', :forbidden) unless Setting.rest_api_enabled?

        key = request.headers['X-Redmine-API-Key'].to_s.presence
        return render_error('API key is required in the X-Redmine-API-Key header', :unauthorized) if key.blank?

        user = User.find_by_api_key(key)
        return render_error('Invalid or inactive API key', :unauthorized) unless user&.active?

        User.current = user
      end

      # Changing the shared tag library (create, rename, delete) is for administrators, the same as the
      # administration page. A role that holds "Manage tags" in one project is not a right over the tags of every
      # project (those operations act on all taggings of the whole instance). The "Manage tags" permission is
      # kept in the role form for other plugins but does not open these actions (#123871).
      def require_admin_api
        return true if User.current.admin?

        render_error('Only an administrator can create, rename or delete tags.', :forbidden)
        false
      end

      # rtg-010 (SEC-002): a non-admin may not rename or delete a tag
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
        names = tag_names_param
        return unless names

        # Capture affected tag IDs before the change so we can recalculate counts.
        old_tag_ids = record.tags.pluck(:id)
        record.tag_list = names

        if record.save
          render_taggable_result(record, old_tag_ids)
        else
          render_model_errors(record)
        end
      end

      def render_taggable_result(record, old_tag_ids)
        # BUG-FT-003: Recalculate taggings_count from actual DB rows for all
        # affected tags. Counter cache can drift negative after earlier changes
        # that use update_all (bypassing callbacks). Using COUNT(*) is the only
        # reliable source of truth.
        new_tag_ids = record.reload.tags.pluck(:id)
        affected_ids = (old_tag_ids + new_tag_ids).uniq
        ActsAsTaggableOn::Tag.where(id: affected_ids).each do |tag|
          actual_count = ActsAsTaggableOn::Tagging.where(tag_id: tag.id).count
          ActsAsTaggableOn::Tag.where(id: tag.id).update_all(taggings_count: actual_count)
        end
        # BUG-FT-014: Do NOT call remove_unused_tags! — tags must only be
        # deleted explicitly via DELETE /tags/:id, not auto-deleted when
        # usage count drops to zero.
        render_success(taggable: taggable_json(record), tags: tag_list_json(record))
      end

      # A tag the user may see (rtg-010 for password entries, FT-A4 for records of other projects).
      def visible_tags(scope)
        scope = FluxTags::PasswordTags.visible_tags(scope, User.current)
        RfFluxTags::TagVisibility.visible_tags(scope, User.current)
      end

      def find_tag
        visible_tags(ActsAsTaggableOn::Tag.all).find(params[:id])
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

      # The name of the tag from tag[name] or name, cleaned the same way as on the administration page.
      # '' when it is missing or is not plain text.
      def tag_name_param
        nested = params[:tag]
        value = nested.respond_to?(:key?) ? nested[:name] : nil
        value = params[:name] if value.blank?
        value.is_a?(String) ? RfFluxTags.clean_name(value) : ''
      end

      def valid_tag_name?(name)
        if name.blank?
          render_error('Tag name is required', :unprocessable_entity)
          return false
        end
        if name.length > RfFluxTags::TAG_NAME_MAX
          render_error("Tag name is too long (maximum is #{RfFluxTags::TAG_NAME_MAX} characters)", :unprocessable_entity)
          return false
        end

        true
      end

      # The tag names of a tagging request, cleaned and checked. nil (and an answer is sent) when the request
      # has no tag list at all, when it is not a list of names, or when the names are not acceptable. An EMPTY
      # list sent on purpose removes the tags, a request that forgot the list does not wipe them.
      def tag_names_param
        key = params.key?(:tag_list) ? :tag_list : (params.key?(:tags) ? :tags : nil)
        if key.nil?
          render_error('tag_list is required (send an empty list to remove all tags)', :unprocessable_entity)
          return nil
        end

        value = params[key]
        unless value.nil? || value.is_a?(String) || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
          render_error('tag_list must be a list of names or a comma separated text', :unprocessable_entity)
          return nil
        end

        names = RfFluxTags.parse_names(value)
        if names.size > RfFluxTags::TAG_LIST_LIMIT
          render_error("At most #{RfFluxTags::TAG_LIST_LIMIT} tags can be set at once", :unprocessable_entity)
          return nil
        end
        if names.any? { |name| name.length > RfFluxTags::TAG_NAME_MAX }
          render_error("A tag name is too long (maximum is #{RfFluxTags::TAG_NAME_MAX} characters)", :unprocessable_entity)
          return nil
        end

        names
      end

      def filter_tags_by_context(scope, context)
        if context == FluxTags::PasswordTags::API_TYPE
          return scope.where(id: FluxTags::PasswordTags.visible_password_taggings(User.current).select(:tag_id))
        end

        taggable_type = TYPES[context.to_s]
        seen = RfFluxTags::TagVisibility.taggings(User.current)
        if taggable_type
          scope.where(id: seen.where(taggable_type: taggable_type).select(:tag_id))
        else
          scope.where(id: seen.where(context: context.to_s).select(:tag_id))
        end
      end

      def tag_list_json(record)
        tags = record.tag_counts.to_a
        preload_usage(tags)
        tags.map { |tag| tag_json(tag) }
      end

      # How often the tags of a response are used and on what kind of record, counting only what the user may
      # see (FT-A4), for all of them in one query.
      def preload_usage(tags)
        @usage = (@usage || {}).merge(RfFluxTags::TagVisibility.usage(tags.map(&:id), User.current))
      end

      def tag_json(tag)
        preload_usage([tag]) unless @usage&.key?(tag.id)
        count, types = @usage[tag.id]
        {
          id: tag.id,
          name: tag.name,
          taggings_count: count,
          contexts: tag_contexts(types)
        }
      end

      # BUG-FT-004: ActsAsTaggableOn always stores context="tags" (the default
      # context), so plucking :context returns ["tags"] which the MCP filters out.
      # Return the taggable_types instead, mapped to human-readable context names.
      def tag_contexts(types)
        type_map = { 'Issue' => 'issues', 'Project' => 'projects', 'TimeEntry' => 'time_entries',
                     FluxTags::PasswordTags::TAGGABLE_TYPE => FluxTags::PasswordTags::API_TYPE }
        types.map { |type| type_map[type] }.compact.uniq
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
          hours: time_entry.hours.to_f
        }
      end

      def per_page
        value = params[:per_page].to_s.to_i
        value = 25 if value <= 0
        [value, 100].min
      end

      def page
        [[params[:page].to_s.to_i, 1].max, MAX_PAGE].min
      end

      def offset
        (page - 1) * per_page
      end

      def pagination(total)
        { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip.first(100))
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
