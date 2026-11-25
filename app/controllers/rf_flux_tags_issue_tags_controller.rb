# frozen_string_literal: true

# Saves the tags typed into the inline editor of the issue page. It runs with
# the signed-in user's session and CSRF token (no API key in the page) and
# writes a History entry, the same as editing the tags in the issue form.
class RfFluxTagsIssueTagsController < ApplicationController
  helper :rf_flux_tags

  before_action :require_login
  before_action :rf_flux_tags_find_issue

  # PATCH /rf_flux_tags/issues/:id/tags
  def update
    unless RfFluxTags::IssueTags.allowed?(@issue)
      return render json: { error: l(:notice_not_authorized) }, status: :forbidden
    end

    names = RfFluxTags.parse_names(params[:tag_list])
    if names.size > RfFluxTags::TAG_LIST_LIMIT
      return render json: { error: l(:rf_flux_tags_error_too_many, count: RfFluxTags::TAG_LIST_LIMIT) },
                    status: :unprocessable_entity
    end
    if names.any? { |name| name.length > RfFluxTags::TAG_NAME_MAX }
      return render json: { error: l(:rf_flux_tags_error_name_too_long, count: RfFluxTags::TAG_NAME_MAX) },
                    status: :unprocessable_entity
    end

    if RfFluxTags::IssueTags.replace(@issue, names, notes: params[:notes])
      tags = @issue.reload.tag_list.to_a
      render json: { tags: tags, chips_html: render_to_string(partial: 'rf_flux_tags/chips', formats: [:html],
                                                              locals: { issue: @issue }) }
    else
      render json: { error: @issue.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def rf_flux_tags_find_issue
    @issue = Issue.visible.find(params[:id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render json: { error: l(:rf_flux_tags_error_not_found) }, status: :not_found
  end
end
