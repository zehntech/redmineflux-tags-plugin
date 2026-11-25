# Older endpoint that saves the tags of one issue (POST /update_issue_tags,
# API key or session). The issue page now uses RfFluxTagsIssueTagsController;
# this stays so existing scripts keep working, with the same permission rules.
class IssueTagsZtController < ApplicationController
  accept_api_auth :update
  before_action :require_login

  def update
    issue = Issue.visible.find(params[:id])
    return render(json: { error: 'Forbidden' }, status: :forbidden) unless RfFluxTags::IssueTags.allowed?(issue)

    value = params[:tag_list]
    unless value.nil? || value.is_a?(String) || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
      return render(json: { error: 'tag_list must be text or a list of names' }, status: :unprocessable_entity)
    end

    # The same limits as the editor on the issue page.
    names = RfFluxTags.parse_names(value)
    if names.size > RfFluxTags::TAG_LIST_LIMIT || names.any? { |name| name.length > RfFluxTags::TAG_NAME_MAX }
      return render(json: { error: 'Too many tags, or a tag name that is too long' }, status: :unprocessable_entity)
    end

    if RfFluxTags::IssueTags.replace(issue, names)
      render json: { id: issue.id, subject: issue.subject, project_id: issue.project_id,
                     tag_list: issue.reload.tag_list.to_a }
    else
      render json: { error: 'Failed to add tags' }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  rescue StandardError => e
    Rails.logger.warn "Failed to add Tags: #{e.inspect}"
    render json: { error: 'Failed to add tags' }, status: :unprocessable_entity
  end
end
