require File.expand_path('../../test_helper', __FILE__)

# rtg-010: the admin tag actions with tags used on password entries.
class FluxTagsTagsControllerTest < Redmine::ControllerTest
  tests TagsController
  include FluxTagsTestHelper

  fixtures :users, :email_addresses, :user_preferences

  def setup
    @request.session[:user_id] = 1
  end

  def test_update_refuses_a_name_too_long_for_password_entries
    tag = flux_tag('vault')
    flux_tagging(tag, PASSWORD_ENTRY, 1)

    put :update, params: { id: tag.id, tag: { name: 'x' * 61 }, tab: FluxTags::PasswordTags::TAB }

    assert_response :success
    assert_select '#errorExplanation', text: /too long for a tag used on password entries/
    assert_equal 'vault', tag.reload.name
  end

  def test_update_renames_and_publishes_the_event
    tag = flux_tag('vault')
    flux_tagging(tag, PASSWORD_ENTRY, 5)

    events = capture_password_tag_events do
      put :update, params: { id: tag.id, tag: { name: 'vault-2' }, tab: FluxTags::PasswordTags::TAB }
    end

    assert_redirected_to controller: 'settings', action: 'plugin', id: 'flux_tags', tab: FluxTags::PasswordTags::TAB
    assert_equal 'vault-2', tag.reload.name
    assert_equal [['rename', 'vault-2', [5]]], events.map { |e| [e[:action], e[:new_name], e[:password_entry_ids]] }
  end

  def test_destroy_returns_to_the_password_tab_and_publishes_the_event
    tag = flux_tag('vault')
    flux_tagging(tag, PASSWORD_ENTRY, 5)

    events = capture_password_tag_events do
      delete :destroy, params: { tag_ids: [tag.id], tab: FluxTags::PasswordTags::TAB }, xhr: true
    end

    assert_response :success
    assert_include 'tab=password_entry', response.body
    assert_not ActsAsTaggableOn::Tag.exists?(tag.id)
    assert_equal [[5]], events.map { |e| e[:password_entry_ids] }
  end

  def test_destroy_requires_the_authenticity_token
    tag = flux_tag('vault')
    ActionController::Base.allow_forgery_protection = true

    delete :destroy, params: { tag_ids: [tag.id], tab: 'issue' }, xhr: true

    assert_response 422
    assert ActsAsTaggableOn::Tag.exists?(tag.id)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def test_merge_does_not_tag_a_record_twice
    alpha = flux_tag('alpha')
    beta = flux_tag('beta')
    flux_tagging(alpha, PASSWORD_ENTRY, 1)
    flux_tagging(beta, PASSWORD_ENTRY, 1)

    post :merge, params: { tag_ids: [alpha.id, beta.id], tag: { name: 'alpha' } }

    assert_response :redirect
    assert_equal 1, ActsAsTaggableOn::Tagging.where(tag_id: alpha.id).count
    assert_equal 1, alpha.reload.taggings_count
    assert_not ActsAsTaggableOn::Tag.exists?(beta.id)
  end
end

# rtg-010: the Password Tags tab of Administration » Plugins » Tags.
class FluxTagsPasswordTabTest < Redmine::ControllerTest
  tests SettingsController
  include FluxTagsTestHelper

  fixtures :users, :email_addresses, :user_preferences, :projects, :trackers, :issue_statuses, :issues,
           :enumerations

  def setup
    @request.session[:user_id] = 1
    FluxTags::PasswordTags.reset!
  end

  def teardown
    FluxTags::PasswordTags.reset!
  end

  def test_no_password_tab_without_the_password_manager
    FluxTags::PasswordTags.stubs(:installed?).returns(false)

    get :plugin, params: { id: 'flux_tags', tab: FluxTags::PasswordTags::TAB }

    assert_response :success
    assert_select 'a#tab-issue'
    assert_select 'a#tab-password_entry', 0
  end

  def test_password_tab_lists_the_password_tags
    FluxTags::PasswordTags.stubs(:installed?).returns(true)
    FluxTags::PasswordTags.stubs(:legacy_tags?).returns(false)
    flux_tagging(flux_tag('vault-only'), PASSWORD_ENTRY, 1)
    flux_tagging(flux_tag('issue-only'), 'Issue', 1)

    get :plugin, params: { id: 'flux_tags', tab: FluxTags::PasswordTags::TAB }

    assert_response :success
    assert_select 'a#tab-password_entry'
    assert_select '#tab-content-password_entry', text: /vault-only/
    assert_select '#tab-content-password_entry', text: /issue-only/, count: 0
  end

  def test_password_tab_warns_while_the_vault_keeps_its_own_tags
    FluxTags::PasswordTags.stubs(:installed?).returns(true)
    FluxTags::PasswordTags.stubs(:legacy_tags?).returns(true)

    get :plugin, params: { id: 'flux_tags', tab: FluxTags::PasswordTags::TAB }

    assert_response :success
    assert_select '#tab-content-password_entry p.warning', text: /keeps its tags in its own tables/
    assert_select '#tab-content-password_entry table', 0
  end
end
