# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# Security tests for the Flux Tags plugin.
# Each test states the SECURE behaviour; the ones marked "red" failed before the fixes. Not to be relaxed to make a
# build pass. "still works" tests prove that ordinary tagging keeps working.
class TgSecurityTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :enabled_modules,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :workflows, :issues, :issue_categories

  include FluxTagsTestHelper

  PASSWORD = '12345678'
  JSON_HEADERS = { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }.freeze

  def setup
    Setting.rest_api_enabled = '1'
    Setting.default_language = 'en'
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all

    @public_project = Project.generate!(is_public: true)
    @secret_project = Project.generate!(is_public: false)
    [@public_project, @secret_project].each do |project|
      project.enable_module!(:issue_tracking)
      project.enable_module!(:time_tracking)
      project.trackers = Tracker.all
      project.save!
    end

    tagging = %i[view_issues add_issues edit_issues manage_issues_tags manage_project_tags manage_time_entries_tags
                 view_time_entries edit_time_entries log_time]
    @member_role = Role.generate!(name: 'TG member', permissions: tagging, issues_visibility: 'all')
    @manager_role = Role.generate!(name: 'TG tag manager', permissions: tagging + %i[manage_tags], issues_visibility: 'all')
    @own_role = Role.generate!(name: 'TG own', permissions: %i[view_issues edit_own_issues manage_issues_tags], issues_visibility: 'all')
    @view_role = Role.generate!(name: 'TG view', permissions: %i[view_issues manage_issues_tags], issues_visibility: 'all')

    @admin = User.find(1)
    @admin.update!(password: PASSWORD, password_confirmation: PASSWORD, must_change_passwd: false)
    @member = make_user('tg-member')
    @manager = make_user('tg-manager')
    @own_user = make_user('tg-own')
    @viewer = make_user('tg-viewer')
    @outsider = make_user('tg-outsider')
    User.add_to_project(@member, @public_project, @member_role)
    User.add_to_project(@manager, @secret_project, @manager_role)   # tag manager of the SECRET project only
    User.add_to_project(@own_user, @public_project, @own_role)
    User.add_to_project(@viewer, @public_project, @view_role)

    @public_issue = Issue.generate!(project: @public_project, author: @member, subject: 'TG public issue')
    @own_issue = Issue.generate!(project: @public_project, author: @own_user, subject: 'TG issue of the own-user')
    @secret_issue = Issue.generate!(project: @secret_project, author: @manager, subject: 'TG SECRET issue')
    @secret_entry = TimeEntry.generate!(project: @secret_project, issue: @secret_issue, user: @manager, hours: 2, spent_on: Date.today)

    @public_tag = flux_tag('public-tag')
    flux_tagging(@public_tag, 'Issue', @public_issue.id)
    @secret_tag = flux_tag('secret-tag')
    flux_tagging(@secret_tag, 'Issue', @secret_issue.id)
    @secret_time_tag = flux_tag('secret-time-tag')
    flux_tagging(@secret_time_tag, 'TimeEntry', @secret_entry.id)
    @secret_project_tag = flux_tag('secret-project-tag')
    flux_tagging(@secret_project_tag, 'Project', @secret_project.id)
    @public_project_tag = flux_tag('public-project-tag')
    flux_tagging(@public_project_tag, 'Project', @public_project.id)
    @unused_tag = flux_tag('unused-tag')
  end

  def make_user(login)
    User.generate!(login: login, password: PASSWORD, password_confirmation: PASSWORD)
  end

  def key(user, extra = {})
    JSON_HEADERS.merge('X-Redmine-API-Key' => User.find(user.id).api_key).merge(extra)
  end

  def api(method, path, user, body = nil, headers: nil)
    send(method, path, params: (body ? body.to_json : nil), headers: headers || key(user))
    response.body.present? ? (JSON.parse(response.body) rescue {}) : {}
  end

  # The tag list of a record read fresh from the database (an issue object caches its list).
  def tags_of(record)
    record.class.find(record.id).tag_list.to_a
  end

  def names_in(data)
    data.dig('data', 'tags').to_a.map { |t| t['name'] }.sort
  end

  def web_login(user)
    get '/login'
    token = css_select('input[name=authenticity_token]').first&.[]('value')
    post '/login', params: { username: user.login, password: PASSWORD, authenticity_token: token }.compact
    follow_redirect!
  end

  API = '/api/v1/flux_tags'

  # --- FT-A1: changing the shared tag library is for administrators ------------------------------------

  test 'a role that manages tags in one project cannot create, rename or delete global tags (red)' do
    data = api(:post, "#{API}/tags", @manager, { name: 'planted' })
    assert_response :forbidden, data.to_s
    assert_not ActsAsTaggableOn::Tag.exists?(name: 'planted')

    api(:patch, "#{API}/tags/#{@public_tag.id}", @manager, { name: 'renamed' })
    assert_response :forbidden
    assert_equal 'public-tag', @public_tag.reload.name

    api(:delete, "#{API}/tags/#{@public_tag.id}", @manager)
    assert_response :forbidden
    assert ActsAsTaggableOn::Tag.exists?(@public_tag.id)
    assert ActsAsTaggableOn::Tagging.exists?(tag_id: @public_tag.id)
  end

  test 'an administrator can still create, rename and delete tags through the API (still works)' do
    api(:post, "#{API}/tags", @admin, { name: 'made by admin' })
    assert_response :created
    tag = ActsAsTaggableOn::Tag.find_by(name: 'made by admin')
    api(:patch, "#{API}/tags/#{tag.id}", @admin, { name: 'renamed by admin' })
    assert_response :success
    api(:delete, "#{API}/tags/#{tag.reload.id}", @admin)
    assert_response :success
  end

  # --- #123870 / #123871 -------------------------------------------------------------------------------------

  test 'renaming a tag to another spelling of an existing tag name is refused (#123870)' do
    ActsAsTaggableOn::Tag.create!(name: 'shared-tag')
    other = ActsAsTaggableOn::Tag.create!(name: 'dupcheck')
    third = ActsAsTaggableOn::Tag.create!(name: 'third')
    ['Shared-Tag', ' SHARED-TAG ', 'shared-tag', 'SHARED-tag'].each do |name|
      patch_target = name == 'shared-tag' ? third : other
      api(:put, "#{API}/tags/#{patch_target.id}", @admin, { name: name })
      assert_response :unprocessable_entity, name.inspect
    end
    assert_equal %w[dupcheck], [other.reload.name]
    assert_equal 'third', third.reload.name
    assert_equal 1, ActsAsTaggableOn::Tag.where('LOWER(name) = ?', 'shared-tag').count
  end

  test 'a tag can still be renamed to a new name or to another spelling of its own name (#123870)' do
    tag = ActsAsTaggableOn::Tag.create!(name: 'my-tag')
    api(:put, "#{API}/tags/#{tag.id}", @admin, { name: 'My-Tag' })
    assert_response :success
    assert_equal 'My-Tag', tag.reload.name
    api(:put, "#{API}/tags/#{tag.id}", @admin, { name: 'brand-new' })
    assert_response :success
    assert_equal 'brand-new', tag.reload.name
  end

  test 'a clash found only by the database index is answered as 422, not a server error (#123870)' do
    tag = ActsAsTaggableOn::Tag.create!(name: 'race-tag')
    ActsAsTaggableOn::Tag.any_instance.stubs(:update).raises(ActiveRecord::RecordNotUnique)
    api(:put, "#{API}/tags/#{tag.id}", @admin, { name: 'race-two' })
    assert_response :unprocessable_entity
  end

  test 'the API description and the role form say that only administrators change the tag library (#123871)' do
    yaml = File.read(File.expand_path('../../lib/flux_tags/tag_swagger.yaml', __dir__))
    assert_no_match(/administrator or (the )?"Manage tags"/, yaml)
    assert_no_match(/\?key=/, yaml)
    assert_match(/needs an administrator/i, yaml)
    api(:post, "#{API}/tags", @manager, { name: 'by-manager' })
    assert_response :forbidden
    assert_match(/administrator/, JSON.parse(response.body).dig('error', 'message'))
    assert_match(/administrators/, I18n.t(:permission_manage_tags))
  end

  # --- #124188 / #124189 / #124190 ---------------------------------------------------------------------------

  test 'the 30-tag and 60-character limits also hold on the issue form, the new issue form and bulk edit (#124188)' do
    web_login(@member)
    many = (1..31).map { |i| "limit-tag-#{i}" }.join(', ')
    long = 'x' * 80

    patch "/issues/#{@public_issue.id}", params: { issue: { tag_list: many } }
    assert_not_equal 31, tags_of(@public_issue).size, 'the issue form must not store 31 tags'
    assert_operator tags_of(@public_issue).size, :<=, 30

    patch "/issues/#{@public_issue.id}", params: { issue: { tag_list: long } }
    assert_not_includes tags_of(@public_issue), long

    assert_no_difference 'Issue.count' do
      post "/projects/#{@public_project.id}/issues", params: { issue: { subject: 'too many tags', tracker_id: Tracker.first.id, tag_list: many } }
    end
    assert_no_difference 'Issue.count' do
      post "/projects/#{@public_project.id}/issues", params: { issue: { subject: 'long tag', tracker_id: Tracker.first.id, tag_list: long } }
    end

    post '/issues/bulk_update', params: { ids: [@public_issue.id], rf_flux_tags_add: many }
    assert_operator tags_of(@public_issue).size, :<=, 30
    post '/issues/bulk_update', params: { ids: [@public_issue.id], rf_flux_tags_add: long }
    assert_not_includes tags_of(@public_issue), long
  end

  test 'normal tag lists still save on the issue form, the new issue form and bulk edit (#124188)' do
    web_login(@member)
    thirty = (1..30).map { |i| "ok-tag-#{i}" }.join(', ')
    patch "/issues/#{@public_issue.id}", params: { issue: { tag_list: thirty } }
    assert_equal 30, tags_of(@public_issue).size
    patch "/issues/#{@public_issue.id}", params: { issue: { tag_list: 'a' * 60 } }
    assert_equal ['a' * 60], tags_of(@public_issue)
    assert_difference 'Issue.count', 1 do
      post "/projects/#{@public_project.id}/issues", params: { issue: { subject: 'fine tags', tracker_id: Tracker.first.id, tag_list: 'one, two' } }
    end
    post '/issues/bulk_update', params: { ids: [@public_issue.id], rf_flux_tags_add: 'extra', rf_flux_tags_remove: 'a' * 60 }
    assert_equal ['extra'], tags_of(@public_issue)
  end

  test 'an issue that already holds more than 30 tags can still be edited and shrunk (#124188)' do
    names = (1..35).map { |i| "legacy-#{i}" }
    issue = Issue.find(@public_issue.id)
    issue.tag_list = names
    issue.save!(validate: false)
    web_login(@member)
    patch "/issues/#{issue.id}", params: { issue: { subject: 'edited subject', tag_list: names.join(', ') } }
    assert_equal 'edited subject', issue.reload.subject
    patch "/issues/#{issue.id}", params: { issue: { tag_list: names.first(34).join(', ') } }
    assert_equal 34, tags_of(issue).size
  end

  test 'bulk edit with only tag fields is handled and never a server error (#124189)' do
    web_login(@member)
    [{ rf_flux_tags_add: 'only-tags-x' }, { rf_flux_tags_remove: 'public-tag' }, { rf_flux_tags_add: '' },
     { rf_flux_tags_add: (1..31).map { |i| "t#{i}" }.join(',') }, { rf_flux_tags_add: 'same', rf_flux_tags_remove: 'same' }].each do |fields|
      post '/issues/bulk_update', params: { ids: [@public_issue.id] }.merge(fields)
      assert_operator response.status, :<, 500, fields.inspect
    end
    post '/issues/bulk_update', params: { ids: [@public_issue.id], rf_flux_tags_add: 'applied-tag' }
    assert_response :redirect
    assert_includes tags_of(@public_issue), 'applied-tag'
  end

  test 'creating the same tag at the same moment returns the existing tag, not an error (#124190)' do
    [ActiveRecord::RecordNotUnique.new('dup'), ActiveRecord::RecordInvalid.new(ActsAsTaggableOn::Tag.new)].each_with_index do |error, i|
      name = "race-x-#{i}"
      ActsAsTaggableOn::Tag.stubs(:create!).with { |*| ActsAsTaggableOn::Tag.new(name: name).save!(validate: false); true }.raises(error)
      api(:post, "#{API}/tags", @admin, { name: name })
      assert_response :created, "#{error.class}: #{response.body}"
      assert_equal name, JSON.parse(response.body).dig('data', 'tag', 'name')
      assert_equal 1, ActsAsTaggableOn::Tag.where(name: name).count
      ActsAsTaggableOn::Tag.unstub(:create!)
    end
  end

  test 'a bad tag name on create is still refused (#124190)' do
    api(:post, "#{API}/tags", @admin, { name: 'x' * 80 })
    assert_response :unprocessable_entity
    api(:post, "#{API}/tags", @admin, { name: '' })
    assert_response :unprocessable_entity
  end

  # --- FT-A2: retagging a project needs the right on THAT project -----------------------------------------

  test 'tag rights in one project do not let someone retag another project they can only see (red)' do
    api(:patch, "#{API}/projects/#{@public_project.id}/tags", @manager, { tag_list: ['planted'] })
    assert_response :forbidden
    assert_equal ['public-project-tag'], tags_of(@public_project)

    api(:patch, "#{API}/projects/#{@secret_project.id}/tags", @manager, { tag_list: ['own project tag'] })
    assert_response :success, 'a tag manager of the project itself still can'
    assert_equal ['own project tag'], tags_of(@secret_project)
  end

  test 'the project form and bulk edit apply the same rule (red)' do
    project = Project.find(@public_project.id)
    project.send(:safe_attributes=, { 'tag_list' => 'planted' }, @manager)
    assert_not project.tag_list.include?('planted'), 'safe_attributes must not accept tag_list for a project the user has no tag right on'
    project.send(:safe_attributes=, { 'tag_list' => 'ok' }, @member)
    assert project.tag_list.include?('ok')
  end

  # --- FT-A3 / FT-02: editing tags needs the right to edit THAT issue --------------------------------------

  test 'someone who cannot edit the issue cannot retag it, through the API, the old endpoint or the editor (red)' do
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @viewer, { tag_list: ['planted'] })
    assert_response :forbidden
    assert_not tags_of(@public_issue).include?('planted')

    api(:post, '/update_issue_tags', @viewer, { id: @public_issue.id, tag_list: 'planted' })
    assert_includes [401, 403], response.status
    assert_not tags_of(@public_issue).include?('planted')

    web_login(@viewer)
    patch "/rf_flux_tags/issues/#{@public_issue.id}/tags", params: { tag_list: 'planted' }.to_json, headers: JSON_HEADERS
    assert_response :forbidden
    assert_not tags_of(@public_issue).include?('planted')
  end

  test 'a role that may only edit its own issues can retag its own issues and not those of others (red)' do
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @own_user, { tag_list: ['planted'] })
    assert_response :forbidden, "someone else's issue"
    api(:patch, "#{API}/issues/#{@own_issue.id}/tags", @own_user, { tag_list: ['mine'] })
    assert_response :success, 'the own issue'
    assert_equal ['mine'], tags_of(@own_issue)

    issue = Issue.find(@public_issue.id)
    issue.send(:safe_attributes=, { 'tag_list' => 'form-planted' }, @own_user)
    assert_not issue.tag_list.include?('form-planted'), 'the issue form must not accept tags for an issue the user may not edit'
    assert_not RfFluxTags::IssueTags.allowed?(Issue.find(@public_issue.id), @own_user)
    assert RfFluxTags::IssueTags.allowed?(Issue.find(@own_issue.id), @own_user)
  end

  test 'a member can still retag through the editor, the API and the old endpoint (still works)' do
    web_login(@member)
    patch "/rf_flux_tags/issues/#{@public_issue.id}/tags", params: { tag_list: 'one, two' }.to_json, headers: JSON_HEADERS
    assert_response :success
    assert_equal %w[one two], tags_of(@public_issue).sort
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @member, { tag_list: ['three'] })
    assert_response :success
    api(:post, '/update_issue_tags', @member, { id: @public_issue.id, tag_list: 'four' })
    assert_response :success
    assert_equal ['four'], tags_of(@public_issue)
  end

  test 'the old endpoint keeps the limits of the editor and does not dump the whole issue (red)' do
    api(:post, '/update_issue_tags', @member, { id: @public_issue.id, tag_list: (1..31).map { |n| "t#{n}" }.join(',') })
    assert_response :unprocessable_entity
    api(:post, '/update_issue_tags', @member, { id: @public_issue.id, tag_list: 'x' * 61 })
    assert_response :unprocessable_entity
    api(:post, '/update_issue_tags', @member, { id: @public_issue.id, tag_list: 'fine' })
    assert_response :success
    body = JSON.parse(response.body)
    assert_not body.key?('description'), 'only a short summary is returned, not every column of the issue'
  end

  test 'someone who is not signed in cannot retag an issue of a public project' do
    patch "/rf_flux_tags/issues/#{@public_issue.id}/tags", params: { tag_list: 'planted' }.to_json, headers: JSON_HEADERS
    assert_includes [302, 401, 403], response.status
    assert_not tags_of(@public_issue).include?('planted')
  end

  # --- FT-A4: lists, counts and contexts only describe what the reader may see -------------------------------

  test 'the tag list of a non-member contains no tag, count or context that comes from a private project (red)' do
    data = api(:get, "#{API}/tags?per_page=100", @outsider)
    assert_response :success
    names = names_in(data)
    assert_not_includes names, 'secret-tag'
    assert_not_includes names, 'secret-time-tag'
    assert_not_includes names, 'secret-project-tag'
    assert_includes names, 'public-tag'
    assert_includes names, 'public-project-tag'

    api(:get, "#{API}/tags/#{@secret_tag.id}", @outsider)
    assert_response :not_found
    api(:get, "#{API}/tags?context=time_entries&per_page=100", @outsider)
    assert_not_includes names_in(JSON.parse(response.body)), 'secret-time-tag'
  end

  test 'counts only count the records the reader may see (red)' do
    flux_tagging(@public_tag, 'Issue', @secret_issue.id) # the same tag is also on a private issue
    ActsAsTaggableOn::Tag.where(id: @public_tag.id).update_all(taggings_count: 2)
    data = api(:get, "#{API}/tags?per_page=100", @outsider)
    tag = data['data']['tags'].find { |t| t['name'] == 'public-tag' }
    assert_equal 1, tag['taggings_count'], 'the private issue must not be counted'
    data = api(:get, "#{API}/tags?per_page=100", @admin)
    assert_equal 2, data['data']['tags'].find { |t| t['name'] == 'public-tag' }['taggings_count']
  end

  test 'a member of the project still sees the tags of its records and an admin sees every tag (still works)' do
    assert_includes names_in(api(:get, "#{API}/tags?per_page=100", @member)), 'public-tag'
    assert_includes names_in(api(:get, "#{API}/tags?per_page=100", @manager)), 'secret-tag'
    all = names_in(api(:get, "#{API}/tags?per_page=100", @admin))
    %w[public-tag secret-tag secret-time-tag secret-project-tag unused-tag].each { |name| assert_includes all, name }
  end

  # --- FT-S01: project tag lists respect project visibility -------------------------------------------------

  test 'tag suggestions for projects do not reveal tags of projects the user cannot see (red)' do
    web_login(@outsider)
    get '/rf_flux_tags/suggest', params: { context: 'project', q: 'project' }, headers: { 'ACCEPT' => 'application/json' }
    assert_response :success
    names = JSON.parse(response.body).map { |t| t['name'] }
    assert_not_includes names, 'secret-project-tag'
    assert_includes names, 'public-project-tag'

    get '/project_tags/auto_complete_v2', params: { q: 'project' }, headers: { 'ACCEPT' => 'application/json' }
    assert_not_includes JSON.parse(response.body), 'secret-project-tag'
    assert_equal ['secret-project-tag'], Project.available_tags(name_like: 'secret').pluck(:name).select { |n| n == 'secret-project-tag' } if User.current.admin?
    User.current = @outsider
    assert_not_includes Project.available_tags.map(&:name), 'secret-project-tag'
  ensure
    User.current = nil
  end

  test 'autocomplete does not treat percent or underscore as wildcards (red)' do
    web_login(@member)
    get '/issue_tags/auto_complete/' + @public_project.id.to_s, params: { q: '%' }, headers: { 'ACCEPT' => 'application/json' }
    assert_response :success
    assert_equal [], JSON.parse(response.body), '"%" is a character to look for, not "everything"'
    get '/issue_tags/auto_complete/' + @public_project.id.to_s, params: { q: 'public' }, headers: { 'ACCEPT' => 'application/json' }
    assert_equal ['public-tag'], JSON.parse(response.body)
  end

  # --- FT-A5: the API honours the REST switch and takes the key in the header only ----------------------------

  test 'the API answers nothing while the REST API is switched off and ignores a key in the address (red)' do
    Setting.rest_api_enabled = '0'
    api(:get, "#{API}/tags", @admin)
    assert_includes [401, 403], response.status
    Setting.rest_api_enabled = '1'
    get "#{API}/tags", params: { key: User.find(@admin.id).api_key }, headers: JSON_HEADERS.merge('X-Redmine-API-Key' => '')
    assert_includes [400, 401, 403], response.status
    api(:get, "#{API}/tags", @admin)
    assert_response :success
  end

  # --- FT-06: the API description needs a login and the OPTIONS catch-all is gone --------------------------

  test 'the API description needs a login and is not a public file (red)' do
    get '/flux_tags/api_doc'
    assert_includes [302, 401, 403], response.status
    get '/tag-api.yaml'
    assert_includes [302, 401, 403], response.status
    get '/plugin_assets/flux_tags/swagger/tag_swagger.yaml'
    assert_includes [302, 401, 403, 404], response.status
    assert_not File.exist?(File.expand_path('../../assets/swagger/tag_swagger.yaml', __dir__)), 'the spec must not sit in the public assets folder'

    web_login(@member)
    get '/flux_tags/api_doc'
    assert_response :success
    get '/tag-api.yaml'
    assert_response :success
    assert_match(/openapi|swagger/i, response.body)
  end

  test 'the plugin does not answer every OPTIONS request of the site (red)' do
    routed = begin
      Rails.application.routes.recognize_path('/anything/at/all', method: :options)
    rescue ActionController::RoutingError
      nil
    end
    assert_nil routed
  end

  # --- FT-04 spreadsheet export ---------------------------------------------------------------------------------

  test 'a tag that starts with a formula character is neutralised in the CSV export (red)' do
    flux_tagging(flux_tag('=HYPERLINK("http://evil.example","x")'), 'Issue', @own_issue.id)
    second = Issue.generate!(project: @public_project, author: @member, subject: 'TG second')
    flux_tagging(flux_tag('@SUM(1+1)'), 'Issue', second.id)
    web_login(@member)
    get "/projects/#{@public_project.identifier}/issues.csv", params: { set_filter: 1, c: %w[subject tags] }
    assert_response :success
    assert_no_match(/,"=HYPERLINK/, response.body)
    assert_no_match(/,"?@SUM/, response.body)
    assert_match(/'=HYPERLINK/, response.body)
    assert_match(/'@SUM/, response.body)
  end

  # --- FT-10 / FT-11 old admin controller -----------------------------------------------------------------------

  test 'the delete answer does not put request text into script and a missing name is not a crash (red)' do
    web_login(@admin)
    delete '/tags', params: { tag_ids: [@unused_tag.id], tab: "');alert(1)//" }, xhr: true
    assert_no_match(/alert\(1\)/, response.body)

    patch "/tags/#{@public_tag.id}", params: {}, headers: JSON_HEADERS
    assert_includes [400, 422], response.status
    assert_equal 'public-tag', @public_tag.reload.name

    delete '/tags', params: { tag_ids: [0] }, headers: { 'ACCEPT' => 'application/json' }
    assert_response :not_found
    assert_no_match(/Couldn't find/, response.body)
  end

  # --- FT-A9 / FT-A10 names and odd values in the API ---------------------------------------------------------

  test 'tag names are cleaned: invisible characters go, too long and too many are refused (red)' do
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @member, { tag_list: ["dup​", "‮evil", 'plain'] })
    assert_response :success
    assert_equal %w[dup evil plain], tags_of(@public_issue).sort

    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @member, { tag_list: ['x' * 61] })
    assert_response :unprocessable_entity
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @member, { tag_list: (1..31).map { |n| "t#{n}" } })
    assert_response :unprocessable_entity
    api(:post, "#{API}/tags", @admin, { name: 'x' * 300 })
    assert_response :unprocessable_entity
    assert_equal %w[dup evil plain], tags_of(@public_issue).sort, 'a refused request changes nothing'
  end

  test 'a request without a tag list does not wipe the tags of the record (red)' do
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @member, {})
    assert_response :unprocessable_entity
    assert_equal ['public-tag'], tags_of(@public_issue)
    api(:patch, "#{API}/issues/#{@public_issue.id}/tags", @member, { tag_list: [] })
    assert_response :success, 'sending an empty list on purpose still removes the tags'
    assert_equal [], tags_of(@public_issue)
  end

  test 'odd parameter shapes give a clean 4xx and never a server error (red)' do
    [
      [:post, "#{API}/tags", { tag: 'x' }],
      [:patch, "#{API}/tags/#{@public_tag.id}", { tag: 'x' }],
      [:patch, "#{API}/issues/#{@public_issue.id}/tags", { tag_list: { a: 'b' } }]
    ].each do |method, path, body|
      api(method, path, @admin, body)
      assert_operator response.status, :<, 500, "#{method} #{path} #{body.inspect}"
      assert_no_match(/NoMethodError|TypeError|undefined method/, response.body)
    end
    get "#{API}/tags", params: { page: '99999999999999999999', per_page: '-5' }, headers: key(@admin)
    assert_operator response.status, :<, 500
    get "#{API}/tags/#{@public_tag.id}/records", params: { type: 'issues', page: '99999999999999999999' }, headers: key(@admin)
    assert_operator response.status, :<, 500
  end

  test 'the record list of a tag only holds visible records and is paged in the database (still works)' do
    flux_tagging(@public_tag, 'Issue', @secret_issue.id)
    data = api(:get, "#{API}/tags/#{@public_tag.id}/records?type=issues", @outsider)
    assert_response :success
    subjects = data['data']['records'].map { |r| r['subject'] }
    assert_includes subjects, 'TG public issue'
    assert_not_includes subjects, 'TG SECRET issue'
    assert_equal 1, data['data']['pagination']['total']
  end

  # --- copying an issue ------------------------------------------------------------------------------------------

  test 'copying an issue copies its tags only for someone who may set tags there (red)' do
    User.current = @outsider
    source = Issue.find(@public_issue.id)
    copy = Issue.new
    copy.project = @public_project
    copy.copy_from(source)
    assert_equal [], copy.tag_list.to_a, 'a user without the tag right gets no tags from the copy'
    User.current = @member
    copy = Issue.new
    copy.project = @public_project
    copy.copy_from(source)
    assert_equal ['public-tag'], copy.tag_list.to_a
  ensure
    User.current = nil
  end

  # --- fonts / external requests ----------------------------------------------------------------------------------

  test 'the stylesheet loads nothing from another site (red)' do
    css = File.read(File.expand_path('../../assets/stylesheets/rf_flux_tags.css', __dir__))
    assert_no_match(/googleapis/, css)
    assert_no_match(/@import/, css)
    assert_no_match(/url\(\s*['"]?https?:/, css)
  end

  test 'normal tagging through the issue form still works (still works)' do
    web_login(@member)
    put "/issues/#{@public_issue.id}", params: { issue: { subject: @public_issue.subject, tag_list: 'form tag' } }
    assert_includes [200, 302], response.status
    assert_includes tags_of(@public_issue), 'form tag'
  end

  # --- #124188 reopened: bulk edit must not say "Successful update" when the tag limit refused the change -------

  test 'bulk edit that the tag limit refuses answers with a failure message, never Successful update (#124188)' do
    web_login(@member)
    @public_issue.tag_list = (1..29).map { |i| "have-#{i}" }
    @public_issue.save!
    other = Issue.generate!(project: @public_project, tracker: @public_issue.tracker)
    [[[@public_issue.id], 'new-a, new-b'], [[@public_issue.id, other.id], 'new-a, new-b'],
     [[@public_issue.id], (1..40).map { |i| "n#{i}" }.join(', ')], [[@public_issue.id], 'y' * 90]].each do |ids, add|
      post '/issues/bulk_update', params: { ids: ids, rf_flux_tags_add: add }
      assert_response :success, 'a refused bulk edit shows the form again with the failure'
      assert_select '#errorExplanation', /Failed to save/
      assert_empty flash.to_h.slice('notice').values
      assert_equal 29, tags_of(@public_issue).size
    end
  end

  test 'bulk edit within the limit still answers Successful update (#124188)' do
    web_login(@member)
    @public_issue.tag_list = (1..29).map { |i| "have-#{i}" }
    @public_issue.save!
    post '/issues/bulk_update', params: { ids: [@public_issue.id], rf_flux_tags_add: 'one-more' }
    assert_response :redirect
    assert_equal 30, tags_of(@public_issue).size
    assert flash[:notice].present?
  end
end
