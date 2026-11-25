# frozen_string_literal: true

module RfFluxTagsHelper
  # Texts the browser side (rf_flux_tags.js and rf_flux_tags_admin.js) needs,
  # taken from the locale files so the pages follow the user's language.
  I18N_KEYS = %w[
    rf_flux_tags_input_hint rf_flux_tags_input_create rf_flux_tags_input_uses rf_flux_tags_input_remove
    rf_flux_tags_input_limit rf_flux_tags_input_no_match rf_flux_tags_saving rf_flux_tags_saved
    rf_flux_tags_error_generic rf_flux_tags_edit_tags rf_flux_tags_no_tags
    rf_flux_tags_search_placeholder rf_flux_tags_filter_all rf_flux_tags_filter_unused
    rf_flux_tags_new_tag rf_flux_tags_delete_unused rf_flux_tags_col_tag rf_flux_tags_col_uses
    rf_flux_tags_col_status rf_flux_tags_status_unused rf_flux_tags_status_in_use rf_flux_tags_selected
    rf_flux_tags_clear_selection rf_flux_tags_select_all_page
    rf_flux_tags_select_all_matching rf_flux_tags_all_selected rf_flux_tags_empty_title
    rf_flux_tags_empty_hint rf_flux_tags_range rf_flux_tags_per_page rf_flux_tags_modal_new_title
    rf_flux_tags_modal_new_sub rf_flux_tags_modal_edit_title rf_flux_tags_modal_edit_sub
    rf_flux_tags_field_name rf_flux_tags_field_name_hint rf_flux_tags_field_color rf_flux_tags_color_auto
    rf_flux_tags_field_color_hint rf_flux_tags_field_description rf_flux_tags_field_description_hint
    rf_flux_tags_create rf_flux_tags_update rf_flux_tags_delete_title_one rf_flux_tags_delete_title_many
    rf_flux_tags_delete_body_used rf_flux_tags_delete_body_unused rf_flux_tags_delete_unused_title
    rf_flux_tags_delete_unused_body
    rf_flux_tags_detail_title rf_flux_tags_detail_rename
    rf_flux_tags_detail_unused rf_flux_tags_detail_visible_only rf_flux_tags_detail_issues
    rf_flux_tags_detail_time_entries rf_flux_tags_detail_projects rf_flux_tags_detail_password_entries
    rf_flux_tags_deleting rf_flux_tags_delete_confirm_one rf_flux_tags_delete_confirm_many
    rf_flux_tags_view rf_flux_tags_close rf_flux_tags_previous rf_flux_tags_next rf_flux_tags_sort_by
    rf_flux_tags_toast_created rf_flux_tags_toast_updated rf_flux_tags_toast_deleted
    rf_flux_tags_toast_unused_deleted rf_flux_tags_loading
    rf_flux_tags_select_row rf_flux_tags_select_page rf_flux_tags_stat_total rf_flux_tags_stat_unused
    rf_flux_tags_stat_issues rf_flux_tags_stat_time_entries rf_flux_tags_stat_projects
    rf_flux_tags_stat_password_entries rf_flux_tags_view_unused
    button_save button_cancel button_delete button_edit
  ].freeze

  def rf_flux_tags_i18n
    I18N_KEYS.each_with_object({}) { |key, memo| memo[key] = l(key) }
  end

  # Columns of the list a tag link opens: the user's usual columns plus Tags,
  # so the tags of the filtered records are visible.
  def rf_flux_tags_list_columns
    base = case controller_name
           when 'projects' then Setting.project_list_defaults['column_names']
           when 'timelog' then Setting.time_entry_list_defaults['column_names']
           else Setting.issue_list_default_columns
           end
    (Array(base).map(&:to_s) | ['tags'])
  rescue StandardError
    ['tags']
  end

  # Where a tag chip leads: the list of records with that tag (Tags column shown).
  # names may be one name, a list of names, or :any for "has any tag".
  def rf_flux_tags_filter_url(names)
    filter = { set_filter: 1, f: ['tags'], c: rf_flux_tags_list_columns }
    if names == :any
      filter[:op] = { 'tags' => '*' }
    else
      filter[:op] = { 'tags' => '=' }
      filter[:v] = { 'tags' => Array(names) }
    end
    project = @project || @issue&.project
    case controller_name
    when 'projects'
      projects_path(filter)
    when 'timelog'
      project&.persisted? ? project_time_entries_path(project, filter) : time_entries_path(filter)
    else
      project&.persisted? ? project_issues_path(project, filter) : issues_path(filter)
    end
  end

  # One tag as a small coloured chip. Pass a Tag record (colour and
  # description are used) or just a name. color: overrides the colour;
  # force_color: shows the colour even when "colored tags" is switched off.
  def rf_flux_tags_chip(tag, link: true, count: nil, removable: false, color: nil, force_color: false)
    name = tag.respond_to?(:name) ? tag.name : tag.to_s
    classes = ['rf-flux-tags-chip']
    classes << 'rf-flux-tags-chip--plain' unless force_color || RfFluxTags.use_colors?
    options = { class: classes.join(' '),
                style: "--rf-flux-tags-color: #{color || RfFluxTags::Colors.for(tag)}",
                title: rf_flux_tags_description(tag).presence }
    label = content_tag(:span, name, class: 'rf-flux-tags-chip__name')
    label << content_tag(:span, count.to_s, class: 'rf-flux-tags-chip__count') unless count.nil?
    return content_tag(:span, label, options) unless link

    link_to(label, rf_flux_tags_filter_url(name), options)
  end

  def rf_flux_tags_description(tag)
    return '' unless tag.respond_to?(:rf_flux_tags_description)

    tag.rf_flux_tags_description.to_s
  end

  # The chips of one record, or a muted "No tags".
  def rf_flux_tags_chips(tags, **options)
    tags = tags.to_a
    return content_tag(:span, l(:rf_flux_tags_no_tags), class: 'rf-flux-tags-empty') if tags.empty?

    safe_join(tags.map { |tag| rf_flux_tags_chip(tag, **options) }, ' ')
  end

  # The tag input: a normal text field (so forms keep posting a comma
  # separated list) that rf_flux_tags.js turns into chips with autocomplete.
  def rf_flux_tags_input_data(context, record = nil, extra = {})
    data = { rf_flux_tags_input: true,
             suggest_url: rf_flux_tags_suggest_path(context: context),
             limit: RfFluxTags::TAG_LIST_LIMIT,
             placeholder: l(:add_tags_placeholder) }
    data[:colors] = RfFluxTags::Colors.map_for(record.tag_list.to_a).to_json if record.respond_to?(:tag_list)
    data.merge(extra)
  end

  # Tags for the issue sidebar, most used first.
  def rf_flux_tags_sidebar_tags
    open_only = RfFluxTags.setting('rf_flux_tags_sidebar_open_only').to_s == '1'
    scope = Issue.available_tags(project: @project, open_only: open_only)
    scope.reorder(Arel.sql('COUNT(taggings.id) DESC, LOWER(tags.name) ASC')).limit(500).to_a
  end

  def rf_flux_tags_active_filter_names
    return [] unless @query.respond_to?(:filters) && @query.filters['tags']

    Array(@query.filters['tags'][:values])
  end
end
