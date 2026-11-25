class TagsController < ApplicationController
  # rtg-010 (SEC-001): no skip_before_action :verify_authenticity_token. These
  # admin actions also change the tags of password entries; the forms carry
  # the token and tags.js sends it with the delete request.
  before_action :require_admin
  before_action :find_tag, only: [:edit, :update]
  before_action :bulk_find_tags, only: [:context_menu, :merge, :destroy]

  helper :tags
  include TagsHelper

  def show
    render json: @tag, status: :ok
  end

  def edit; end

  def show
    @tag = ActsAsTaggableOn::Tag.find_by(id: params[:id])
    
    if @tag
      render json: @tag, status: :ok
    else
      render json: { error: "Tag not found" }, status: :not_found
    end
  end
   
  def destroy
    begin
      tags = bulk_find_tags
      before = FluxTags::PasswordTags.snapshot(tags.map(&:id))
      tags.each(&:destroy)
      FluxTags::PasswordTags.instrument('delete', **before)

      respond_to do |format|
        if request.xhr? # AJAX request handling
          flash[:notice] = I18n.t('tags.delete_success')
          format.js { render js: "window.location = '/settings/plugin/flux_tags?tab=#{params[:tab] || 'manage_tags'}'" }
        else
          format.html do
            flash[:notice] = I18n.t('tags.delete_success')
            redirect_to controller: 'settings', action: 'plugin', id: 'flux_tags', tab: params[:tab] || 'manage_tags'
          end
          format.json { render json: { message: "Tags deleted successfully" }, status: :ok }
        end
      end
    rescue ActiveRecord::RecordNotFound => e
      respond_to do |format|
        if request.xhr? # AJAX request handling
          format.js { render js: "alert(#{I18n.t('tags.delete_failure').to_json});", status: :not_found }
        else
          format.html do
            flash[:error] = I18n.t('tags.delete_failure')
            redirect_to controller: 'settings', action: 'plugin', id: 'flux_tags', tab: 'manage_tags'
          end
          format.json { render json: { success: false, error: e.message }, status: :not_found }
        end
      end
    end
  end
  
  
  

  def update
    new_name = params[:tag][:name]
    duplicate = ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', new_name).where.not(id: @tag.id).first

    if duplicate
      render_tag_name_error(new_name, :taken)
      return
    end

    if FluxTags::PasswordTags.name_too_long?([@tag.id], new_name)
      render_tag_name_error(new_name, name_too_long_message)
      return
    end

    before = FluxTags::PasswordTags.snapshot([@tag.id])
    begin
      if @tag.update(name: new_name)
        FluxTags::PasswordTags.instrument('rename', **before, new_name: @tag.name) if @tag.saved_change_to_name?
        flash[:notice] = l :notice_successful_update

        respond_to do |format|
          format.html do
            redirect_to controller: 'settings', action: 'plugin', id: 'flux_tags', tab: params[:tab]
          end
          format.json { render json: { message: "Tag updated successfully", tag: @tag }, status: :ok }
        end
      else
        respond_to do |format|
          format.html { render action: 'edit' }
          format.json { render json: { error: "Failed to update tag", details: @tag.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::RecordNotUnique
      render_tag_name_error(new_name, :taken)
    end
  end

  def context_menu
    @tag = @tags.first if @tags.size == 1
    @back = back_url
    render layout: false
  end

  def merge
    if request.post? && params[:tag] && params[:tag][:name]
      name = params[:tag][:name].to_s.strip
      existing = ActsAsTaggableOn::Tag.where('LOWER(name) = LOWER(?)', name).first
      if FluxTags::PasswordTags.name_too_long?(@tags.map(&:id) + [existing&.id].compact, name)
        render json: { error: name_too_long_message }, status: :unprocessable_entity
        return
      end

      before = FluxTags::PasswordTags.snapshot(@tags.map(&:id))
      tag = nil
      ActsAsTaggableOn::Tagging.transaction do
        tag = existing || ActsAsTaggableOn::Tag.create!(name: name)
        FluxTags::TagMerge.merge!(@tags, tag)
      end
      FluxTags::PasswordTags.instrument('merge', **before, new_name: tag.name)

      respond_to do |format|
        format.html do
          redirect_to controller: 'settings', action: 'plugin', id: 'flux_tags', tab: 'manage_tags'
        end
        format.json { render json: { message: "Tags merged successfully", tag: tag }, status: :ok }
      end
    else
      render json: { error: "Invalid merge request" }, status: :unprocessable_entity
    end
  end

  private

  def name_too_long_message
    l(:error_flux_tags_name_too_long_for_password_tags, count: FluxTags::PasswordTags.name_max)
  end

  def render_tag_name_error(attempted_name, message)
    @tag.name = attempted_name
    @tag.errors.add(:name, message)
    respond_to do |format|
      format.html { render action: 'edit' }
      format.json { render json: { error: "Failed to update tag", details: @tag.errors.full_messages }, status: :unprocessable_entity }
    end
  end

  def bulk_find_tags
    @tags = ActsAsTaggableOn::Tag.where(id: params[:id] || params[:tag_ids])
    raise ActiveRecord::RecordNotFound if @tags.empty?
    @tags
  end

  def find_tag
    @tag = ActsAsTaggableOn::Tag.where(id: params[:id]).first or render_404
  end
end
