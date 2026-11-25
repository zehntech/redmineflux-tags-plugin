require File.expand_path('../../test_helper', __FILE__)

# rtg-010 (SEC-002): the REST API never shows a tag used only on password
# entries the caller cannot see. The vault's rule is stubbed: user 2 may see
# password entry 1, not entry 2.
class FluxTagsApiPasswordTagsTest < Redmine::ControllerTest
  tests Api::V1::FluxTagsController
  include FluxTagsTestHelper

  fixtures :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :projects

  def setup
    FluxTags::PasswordTags.stubs(:visible_entry_ids).returns([1])
    @hidden_only = flux_tag('hidden-only')
    flux_tagging(@hidden_only, PASSWORD_ENTRY, 2)
    @visible = flux_tag('visible')
    flux_tagging(@visible, PASSWORD_ENTRY, 1)
    @shared = flux_tag('shared')
    flux_tagging(@shared, 'Issue', 1)
    flux_tagging(@shared, PASSWORD_ENTRY, 2)
  end

  def test_index_hides_tags_used_only_on_hidden_password_entries
    tags = api(:get, :index, 2)['data']['tags'].index_by { |tag| tag['name'] }

    assert_equal %w[shared visible], tags.keys.sort
    assert_equal 1, tags['shared']['taggings_count']
    assert_equal %w[issues], tags['shared']['contexts']
    assert_equal %w[password_entries], tags['visible']['contexts']
  end

  def test_index_shows_everything_to_an_admin
    tags = api(:get, :index, 1)['data']['tags'].index_by { |tag| tag['name'] }

    assert_equal %w[hidden-only shared visible], tags.keys.sort
    assert_equal 2, tags['shared']['taggings_count']
    assert_equal %w[issues password_entries], tags['shared']['contexts'].sort
  end

  def test_show_of_a_hidden_tag_is_not_found
    api(:get, :show, 2, id: @hidden_only.id)
    assert_response :not_found
  end

  def test_password_entries_context
    assert_equal %w[visible], names(api(:get, :index, 2, context: 'password_entries'))
    assert_equal %w[hidden-only shared visible], names(api(:get, :index, 1, context: 'password_entries'))
  end

  def test_tagged_records_of_password_entries_point_to_the_vault_api
    body = api(:get, :tagged_records, 1, id: @visible.id, type: 'password_entries')

    assert_response :unprocessable_entity
    assert_match %r{password_entries\.json}, body['error']['message']
  end

  def test_manage_tags_user_cannot_change_tags_on_hidden_entries
    Role.find(1).add_permission!(:manage_tags)
    issue_only = flux_tag('issue-only')
    flux_tagging(issue_only, 'Issue', 1)

    api(:delete, :destroy, 2, id: @hidden_only.id)
    assert_response :not_found
    api(:delete, :destroy, 2, id: @shared.id)
    assert_response :forbidden
    assert ActsAsTaggableOn::Tag.exists?(@shared.id)
    api(:delete, :destroy, 2, id: issue_only.id)
    assert_response :success
  end

  def test_update_refuses_a_name_too_long_for_password_entries
    api(:patch, :update, 1, id: @visible.id, tag: { name: 'x' * 61 })

    assert_response :unprocessable_entity
    assert_equal 'visible', @visible.reload.name
  end

  private

  def api(method, action, user_id, params = {})
    @request.headers['X-Redmine-API-Key'] = User.find(user_id).api_key
    send(method, action, params: params)
    JSON.parse(response.body)
  end

  def names(body)
    body['data']['tags'].map { |tag| tag['name'] }.sort
  end
end
