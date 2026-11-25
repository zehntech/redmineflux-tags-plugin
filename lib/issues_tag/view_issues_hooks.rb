module IssuesTag
  # Where the tag pieces appear in Redmine's own pages. The partials live in
  # app/views/rf_flux_tags (and tags/header_assets for the page head).
  class ViewIssuesHooks < Redmine::Hook::ViewListener
    render_on :view_issues_show_details_bottom, partial: 'rf_flux_tags/issue_row'
    render_on :view_issues_form_details_bottom, partial: 'rf_flux_tags/issue_form'
    render_on :view_issues_sidebar_planning_bottom, partial: 'rf_flux_tags/sidebar'
    render_on :view_issues_bulk_edit_details_bottom, partial: 'rf_flux_tags/bulk_edit'
    render_on :view_layouts_base_html_head, partial: 'tags/header_assets'
    render_on :view_timelog_edit_form_bottom, partial: 'rf_flux_tags/time_entry_form'
    render_on :view_projects_form, partial: 'rf_flux_tags/project_form'
  end
end
