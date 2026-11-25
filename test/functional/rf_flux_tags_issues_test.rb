require File.expand_path('../../test_helper', __FILE__)

# What the tag pieces do on Redmine's own issue pages: the Tags row, the issue
# form, bulk edit, the sidebar, the filter links and the CSV export.
# (Replaces the old issues_controller_test.rb, which tested the previous
# redmine_tags plugin: fixtures, markup and settings that no longer exist.)
class RfFluxTagsIssuesTest < Redmine::ControllerTest
  tests IssuesController
  include FluxTagsTestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enabled_modules, :enumerations,
           :workflows, :versions, :issue_categories, :journals, :journal_details, :custom_fields,
           :custom_values, :custom_fields_projects, :custom_fields_trackers, :queries

  PERMISSIONS = %i[manage_issues_tags].freeze

  def setup
    User.current = nil
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all
    Role.find(1).add_permission!(*PERMISSIONS)       # manager of project 1
    @request.session[:user_id] = 2                   # jsmith: manager of project 1
    @issue = Issue.find(1)
    @issue.tag_list = %w[bug backend]
    @issue.save!
  end

  def teardown
    Setting.plugin_flux_tags = {}
  end

  # ---- show ----

  def test_show_lists_the_tags_as_chips_that_link_to_the_filtered_list
    get :show, params: { id: 1 }
    assert_response :success
    assert_select '#rf-flux-tags-issue-row a.rf-flux-tags-chip', 2
    # the link also asks for the Tags column
    assert_select '#rf-flux-tags-issue-row a.rf-flux-tags-chip[href*=?]', 'c%5B%5D=tags'
    assert_select '#rf-flux-tags-issue-row a.rf-flux-tags-chip[href*=?]', 'v%5Btags%5D%5B%5D=bug'
  end

  def test_show_has_the_edit_button_for_someone_who_may_manage_tags
    get :show, params: { id: 1 }
    assert_select '#rf-flux-tags-issue-row [data-rf-flux-tags-edit]', 1
    assert_select '#rf-flux-tags-issue-row[data-url=?]', '/rf_flux_tags/issues/1/tags'
  end

  def test_show_has_no_edit_button_without_the_permission
    Role.find(1).remove_permission!(*PERMISSIONS)
    get :show, params: { id: 1 }
    assert_response :success
    assert_select '#rf-flux-tags-issue-row a.rf-flux-tags-chip', 2
    assert_select '#rf-flux-tags-issue-row [data-rf-flux-tags-edit]', 0
  end

  def test_show_never_puts_an_api_key_in_the_page
    get :show, params: { id: 1 }
    assert_not_includes response.body, User.find(2).api_key.to_s if User.find(2).api_key.present?
    assert_not_includes response.body, 'update_issue_tags.json?key='
  end

  # ---- issue form ----

  def test_edit_form_has_the_tag_input_with_the_current_tags
    get :show, params: { id: 1 }
    assert_select 'input#issue_tag_list[name=?][data-rf-flux-tags-input][value=?]', 'issue[tag_list]', 'bug, backend'
  end

  def test_new_form_has_the_tag_input
    get :new, params: { project_id: 1 }
    assert_response :success
    assert_select 'input#issue_tag_list[name=?]', 'issue[tag_list]'
  end

  def test_new_form_has_no_tag_input_without_the_permission
    Role.find(1).remove_permission!(*PERMISSIONS)
    get :new, params: { project_id: 1 }
    assert_response :success
    assert_select 'input#issue_tag_list', 0
  end

  def test_update_writes_a_history_entry_for_changed_tags
    put :update, params: { id: 1, issue: { tag_list: 'bug, urgent' } }
    assert_redirected_to '/issues/1'

    assert_equal %w[bug urgent], Issue.find(1).tag_list.to_a
    detail = Issue.find(1).journals.order(:id).last.details.detect { |d| d.prop_key == 'tag_list' }
    assert_equal 'bug, backend', detail.old_value
    assert_equal 'bug, urgent', detail.value
  end

  def test_update_keeps_tags_that_end_up_on_no_issue
    put :update, params: { id: 1, issue: { tag_list: '' } }
    assert_equal [], Issue.find(1).tag_list.to_a
    assert ActsAsTaggableOn::Tag.exists?(name: 'bug'), 'a tag nobody uses any more must not be deleted'
  end

  def test_update_ignores_tags_from_someone_without_the_permission
    Role.find(1).remove_permission!(*PERMISSIONS)
    put :update, params: { id: 1, issue: { tag_list: 'hacked' } }
    assert_equal %w[bug backend], Issue.find(1).tag_list.to_a
  end

  def test_create_saves_the_tags
    assert_difference 'Issue.count' do
      post :create, params: { project_id: 1, issue: { tracker_id: 1, subject: 'With tags', tag_list: 'one, two' } }
    end
    assert_equal %w[one two], Issue.order(:id).last.tag_list.to_a
  end

  # ---- bulk edit ----

  def test_bulk_edit_has_separate_add_and_remove_inputs
    get :bulk_edit, params: { ids: [1, 3] }
    assert_response :success
    assert_select 'input#rf_flux_tags_add[data-rf-flux-tags-input]'
    assert_select 'input#rf_flux_tags_remove[data-rf-flux-tags-input]'
  end

  def test_bulk_update_adds_and_removes_tags_with_a_history_entry_per_issue
    other = Issue.find(3)
    other.tag_list = %w[bug ui]
    other.save!

    post :bulk_update, params: { ids: [1, 3], rf_flux_tags_add: 'release, bug', rf_flux_tags_remove: 'backend, ui' }

    assert_response :redirect
    assert_equal %w[bug release], Issue.find(1).tag_list.to_a
    assert_equal %w[bug release], Issue.find(3).tag_list.to_a
    [1, 3].each do |id|
      details = Issue.find(id).journals.order(:id).last.details.select { |d| d.prop_key == 'tag_list' }
      assert_equal 1, details.size, "issue #{id} needs one tag history line"
    end
  end

  def test_bulk_update_without_tag_changes_writes_no_tag_history
    before = JournalDetail.where(prop_key: 'tag_list').count
    post :bulk_update, params: { ids: [1, 3], issue: { priority_id: 5 } }
    assert_equal before, JournalDetail.where(prop_key: 'tag_list').count
  end

  def test_bulk_update_ignores_tags_from_someone_without_the_permission
    Role.find(1).remove_permission!(*PERMISSIONS)
    post :bulk_update, params: { ids: [1], rf_flux_tags_add: 'hacked' }
    assert_equal %w[bug backend], Issue.find(1).tag_list.to_a
  end

  # ---- list: sidebar, filter, columns, export ----

  def test_sidebar_shows_the_most_used_tags_and_a_view_all_link
    Setting.plugin_flux_tags = { 'rf_flux_tags_sidebar' => 'list', 'rf_flux_tags_sidebar_limit' => '5' }
    %w[a b c d e f g].each_with_index do |name, i|
      issue = Issue.find(i % 3 + 1)
      issue.tag_list = issue.tag_list.to_a | [name]
      issue.save!
    end

    get :index, params: { project_id: 1, set_filter: 1, f: ['status_id'], op: { status_id: '*' } }

    assert_response :success
    assert_select '#rf-flux-tags-sidebar'
    assert_select '#rf-flux-tags-sidebar ul.rf-flux-tags-sidebar__list li', 5
    assert_select '#rf-flux-tags-sidebar .rf-flux-tags-sidebar__all a[href*=?]', 'op%5Btags%5D=%2A'
  end

  def test_sidebar_can_show_colored_tags
    Setting.plugin_flux_tags = { 'rf_flux_tags_sidebar' => 'colored' }
    get :index, params: { project_id: 1, set_filter: 1, f: ['status_id'], op: { status_id: '*' } }
    assert_select '#rf-flux-tags-sidebar .rf-flux-tags-sidebar__chips .rf-flux-tags-chip'
    assert_select '#rf-flux-tags-sidebar ul', 0
  end

  def test_the_old_cloud_setting_shows_colored_tags
    Setting.plugin_flux_tags = { 'rf_flux_tags_sidebar' => 'cloud' }
    get :index, params: { project_id: 1, set_filter: 1, f: ['status_id'], op: { status_id: '*' } }
    assert_select '#rf-flux-tags-sidebar .rf-flux-tags-sidebar__chips'
  end

  def test_sidebar_can_be_switched_off
    Setting.plugin_flux_tags = { 'rf_flux_tags_sidebar' => 'none' }
    get :index, params: { project_id: 1, set_filter: 1, f: ['status_id'], op: { status_id: '*' } }
    assert_select '#rf-flux-tags-sidebar', 0
  end

  def test_the_tags_filter_and_column_work
    get :index, params: { project_id: 1, set_filter: 1, f: ['tags'], op: { tags: '=' }, v: { tags: ['bug'] }, c: %w[subject tags] }
    assert_response :success
    assert_select 'table.issues td.tags a.rf-flux-tags-chip', text: 'bug'
    assert_select 'table.issues tr.issue', 1
  end

  def test_csv_export_has_the_tags_and_keeps_the_other_columns
    # Watchers exists from Redmine 6 on; Author everywhere.
    columns = %w[subject tags author]
    columns << 'watcher_users' if IssueQuery.new(name: '_').available_columns.map(&:name).include?(:watcher_users)
    get :index, params: { c: columns, set_filter: 1, sort: 'id', format: 'csv' }
    assert_response :success
    rows = CSV.parse(response.body)
    header = rows.first
    assert_includes header, 'Tags'
    assert_includes header, 'Author'
    assert_includes header, 'Watchers' if columns.include?('watcher_users')
    assert_equal 'bug, backend', rows.detect { |r| r.first == '1' }[header.index('Tags')]
    assert_equal User.find(Issue.find(1).author_id).name, rows.detect { |r| r.first == '1' }[header.index('Author')]
  end

  def test_colors_can_be_switched_off
    Setting.plugin_flux_tags = { 'issues_use_colors' => '0' }
    get :show, params: { id: 1 }
    assert_select '#rf-flux-tags-issue-row a.rf-flux-tags-chip.rf-flux-tags-chip--plain', 2
  end

  def test_a_chosen_tag_color_is_used
    skip 'plugin migrations not run' unless RfFluxTags::Schema.extras?

    ActsAsTaggableOn::Tag.find_by(name: 'bug').update!(rf_flux_tags_color: '#c0392b', rf_flux_tags_description: 'A defect')
    get :show, params: { id: 1 }
    assert_select '#rf-flux-tags-issue-row a.rf-flux-tags-chip[style*=?][title=?]', '#c0392b', 'A defect'
  end
end
