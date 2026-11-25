# frozen_string_literal: true

# JSON behind the tag administration page (Administration > Plugins > Tags).
# Administrators only. The page sends the CSRF token with every request, so
# forgery protection stays on.
class RfFluxTagsAdminController < ApplicationController
  before_action :require_admin
  before_action :rf_flux_tags_find_tag, only: %i[update records]

  RECORDS_PER_PAGE = 10

  # GET /rf_flux_tags/tags
  def index
    catalog = RfFluxTags::TagCatalog.new(params)
    render json: {
      tags: catalog.rows.map { |tag| rf_flux_tags_tag_json(tag) },
      pagination: { page: catalog.current_page, per_page: catalog.per_page,
                    total: catalog.total, pages: catalog.pages },
      stats: RfFluxTags::TagCatalog.stats
    }
  end

  # GET /rf_flux_tags/tags/ids : every id matching the current search and filter,
  # for "select all N tags" across pages.
  def ids
    pairs = RfFluxTags::TagCatalog.new(params).id_name_pairs
    render json: { ids: pairs.map(&:first), tags: pairs.map { |id, name| { id: id, name: name } } }
  end

  # POST /rf_flux_tags/tags
  def create
    result = RfFluxTags::TagOperations.create(name: params[:name], color: params[:color],
                                              description: params[:description])
    rf_flux_tags_render_result(result, status: :created) { |res| { tag: rf_flux_tags_tag_json(res.tag) } }
  end

  # PATCH /rf_flux_tags/tags/:id
  def update
    options = { name: params[:name] }
    options[:color] = params[:color] if params.key?(:color)
    options[:description] = params[:description] if params.key?(:description)
    result = RfFluxTags::TagOperations.update(@tag, **options)
    rf_flux_tags_render_result(result) { |res| { tag: rf_flux_tags_tag_json(res.tag) } }
  end

  # DELETE /rf_flux_tags/tags  (tag_ids[])
  def destroy
    result = RfFluxTags::TagOperations.destroy(rf_flux_tags_find_tags)
    # Redmine's own "Successful deletion." notice, shown when the page reloads.
    flash[:notice] = l(:notice_successful_delete) if result.ok?
    rf_flux_tags_render_result(result) { |res| { deleted: res.count } }
  end

  # DELETE /rf_flux_tags/tags/unused
  def destroy_unused
    result = RfFluxTags::TagOperations.destroy_unused
    flash[:notice] = l(:notice_successful_delete) if result.ok?
    rf_flux_tags_render_result(result) { |res| { deleted: res.count } }
  end

  # GET /rf_flux_tags/tags/:id/records : where a tag is used, for the detail drawer.
  def records
    type = params[:type].to_s
    per_page = RECORDS_PER_PAGE
    page = [params[:page].to_i, 1].max
    scope = rf_flux_tags_record_scope(type)
    return rf_flux_tags_render_error(:rf_flux_tags_error_not_found, :not_found) unless scope

    total = scope.count
    items = scope.limit(per_page).offset((page - 1) * per_page).to_a.map { |record| rf_flux_tags_record_json(type, record) }
    render json: { type: type, records: items,
                   pagination: { page: page, per_page: per_page, total: total,
                                 pages: [(total.to_f / per_page).ceil, 1].max } }
  end

  private

  def rf_flux_tags_find_tag
    @tag = ActsAsTaggableOn::Tag.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    rf_flux_tags_render_error(:rf_flux_tags_error_not_found, :not_found)
  end

  def rf_flux_tags_find_tags
    ids = Array(params[:tag_ids]).map(&:to_i).uniq
    ActsAsTaggableOn::Tag.where(id: ids).to_a
  end

  def rf_flux_tags_tag_json(tag)
    uses = tag.has_attribute?(:rf_flux_tags_count) ? tag[:rf_flux_tags_count].to_i : nil
    total = tag.has_attribute?(:rf_flux_tags_total) ? tag[:rf_flux_tags_total].to_i : nil
    {
      id: tag.id,
      name: tag.name,
      count: uses,
      total: total,
      color: RfFluxTags::Colors.for(tag),
      custom_color: rf_flux_tags_custom_color(tag),
      description: rf_flux_tags_description(tag)
    }
  end

  def rf_flux_tags_custom_color(tag)
    return nil unless RfFluxTags::Schema.extras?

    RfFluxTags::Colors.normalize(tag.rf_flux_tags_color)
  end

  def rf_flux_tags_description(tag)
    RfFluxTags::Schema.extras? ? tag.rf_flux_tags_description.to_s : ''
  end

  def rf_flux_tags_tagging_ids(type, tag)
    ActsAsTaggableOn::Tagging.where(tag_id: tag.id, taggable_type: type).select(:taggable_id)
  end

  # The records of one kind carrying the tag, limited to what the user may see.
  def rf_flux_tags_record_scope(type)
    case type
    when 'issue'
      Issue.visible.where(id: rf_flux_tags_tagging_ids('Issue', @tag)).includes(:project).order(id: :desc)
    when 'project'
      Project.visible.where(id: rf_flux_tags_tagging_ids('Project', @tag)).order(:name)
    when 'time_entry'
      TimeEntry.visible.where(id: rf_flux_tags_tagging_ids('TimeEntry', @tag)).includes(:project, :issue, :user).order(id: :desc)
    end
  end

  def rf_flux_tags_record_json(type, record)
    case type
    when 'issue'
      { id: record.id, label: "##{record.id} #{record.subject}", sub: record.project.name,
        url: issue_path(record) }
    when 'project'
      { id: record.id, label: record.name, sub: record.identifier, url: project_path(record) }
    else
      { id: record.id, label: "#{rf_flux_tags_format_hours_label(record)} #{record.comments.to_s.truncate(60)}".strip,
        sub: [record.project&.name, record.user&.name].compact.join(' / '),
        url: record.issue ? issue_path(record.issue) : project_path(record.project) }
    end
  end

  def rf_flux_tags_format_hours_label(entry)
    "#{entry.hours.to_f.round(2)}h"
  end

  def rf_flux_tags_render_result(result, status: :ok)
    if result.ok?
      render json: yield(result), status: status
    else
      rf_flux_tags_render_error(result.error, :unprocessable_entity, result.message)
    end
  end

  def rf_flux_tags_render_error(key, status, detail = nil)
    message = if key == :error_flux_tags_name_too_long_for_password_tags
                "#{l(:rf_flux_tags_field_name)} #{l(key, count: FluxTags::PasswordTags.name_max)}"
              else
                l(key, count: RfFluxTags::TAG_NAME_MAX)
              end
    message = "#{message} #{detail}" if detail.present?
    render json: { error: message }, status: status
  end
end
