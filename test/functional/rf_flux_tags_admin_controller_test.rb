require File.expand_path('../../test_helper', __FILE__)

# The JSON behind the tag administration page.
class RfFluxTagsAdminControllerTest < Redmine::ControllerTest
  tests RfFluxTagsAdminController
  include FluxTagsTestHelper

  fixtures :users, :email_addresses, :user_preferences, :projects, :issues, :issue_statuses, :trackers,
           :projects_trackers, :enabled_modules, :enumerations, :roles, :members, :member_roles

  def setup
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all
    @request.session[:user_id] = 1
  end

  def test_only_administrators_get_in
    @request.session[:user_id] = 2
    get :index
    assert_response :forbidden
  end

  def test_index_returns_tags_pagination_and_stats
    flux_tagging(flux_tag('bug'), 'Issue', 1)
    flux_tag('idle')

    get :index, params: { context: 'issue' }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal ['bug'], body['tags'].map { |t| t['name'] }
    assert_equal 1, body['tags'].first['count']
    assert_equal 1, body['pagination']['total']
    assert_equal 1, body['stats']['unused']
  end

  def test_password_tab_lists_only_tags_used_on_password_entries
    flux_tagging(flux_tag('vault-only'), PASSWORD_ENTRY, 1)
    flux_tagging(flux_tag('issue-only'), 'Issue', 1)

    get :index, params: { context: FluxTags::PasswordTags::TAB }

    assert_equal ['vault-only'], JSON.parse(response.body)['tags'].map { |t| t['name'] }
  end

  def test_ids_returns_everything_matching
    %w[a b c].each { |n| flux_tagging(flux_tag(n), 'Issue', 1) }
    get :ids, params: { context: 'issue', q: 'b' }
    assert_equal ['b'], JSON.parse(response.body)['tags'].map { |t| t['name'] }
  end

  def test_create
    post :create, params: { name: 'customer-request' }
    assert_response :created
    assert ActsAsTaggableOn::Tag.exists?(name: 'customer-request')
  end

  def test_create_duplicate_is_refused
    flux_tag('bug')
    post :create, params: { name: 'BUG' }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)['error'].present?
  end

  def test_update_renames
    tag = flux_tag('old')
    patch :update, params: { id: tag.id, name: 'new' }
    assert_response :success
    assert_equal 'new', tag.reload.name
  end

  def test_destroy_several
    a = flux_tag('a')
    b = flux_tag('b')
    delete :destroy, params: { tag_ids: [a.id, b.id] }
    assert_response :success
    assert_equal 2, JSON.parse(response.body)['deleted']
    assert_equal 0, ActsAsTaggableOn::Tag.count
  end

  def test_destroy_unused
    flux_tagging(flux_tag('used'), 'Issue', 1)
    flux_tag('idle')
    delete :destroy_unused
    assert_equal 1, JSON.parse(response.body)['deleted']
    assert_equal ['used'], ActsAsTaggableOn::Tag.pluck(:name)
  end

  def test_records_lists_issues_carrying_the_tag
    tag = flux_tag('bug')
    flux_tagging(tag, 'Issue', 1)
    get :records, params: { id: tag.id, type: 'issue' }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body['pagination']['total']
    assert_match %r{/issues/1}, body['records'].first['url']
  end

  def test_records_with_an_unknown_type_is_not_found
    tag = flux_tag('bug')
    get :records, params: { id: tag.id, type: 'nonsense' }
    assert_response :not_found
  end
end
