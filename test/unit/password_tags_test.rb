require File.expand_path('../../test_helper', __FILE__)

# rtg-010: detection of the Redmineflux Password Manager and the visibility of
# its tags. The vault's visibility rule is stubbed (visible_entry_ids), so these
# tests run without the Password Manager installed.
class FluxTagsPasswordTagsTest < ActiveSupport::TestCase
  include FluxTagsTestHelper

  fixtures :users, :email_addresses

  def setup
    FluxTags::PasswordTags.reset!
    @admin = User.find(1)
    @user = User.find(2)
  end

  def teardown
    FluxTags::PasswordTags.reset!
  end

  def test_problem_without_the_plugin
    FluxTags::PasswordTags.stubs(:installed?).returns(false)

    assert_equal :not_installed, FluxTags::PasswordTags.problem
    assert_not FluxTags::PasswordTags.available?
  end

  def test_problem_with_a_vault_without_the_tagging_model
    FluxTags::PasswordTags.stubs(:installed?).returns(true)
    FluxTags::PasswordTags.stubs(:tagging_class).returns(nil)

    assert_equal :legacy_tags, FluxTags::PasswordTags.problem
  end

  def test_problem_while_the_vault_has_its_own_tag_table
    FluxTags::PasswordTags.stubs(:installed?).returns(true)
    FluxTags::PasswordTags.stubs(:tagging_class).returns(Class.new)
    ActiveRecord::Base.connection.stubs(:data_source_exists?)
                      .with(FluxTags::PasswordTags::LEGACY_TABLE).returns(true)

    assert_equal :legacy_tags, FluxTags::PasswordTags.problem
  end

  def test_problem_with_an_incomplete_schema
    FluxTags::PasswordTags.stubs(:installed?).returns(true)
    FluxTags::PasswordTags.stubs(:legacy_tags?).returns(false)
    FluxTags::SharedTagsSchema.stubs(:problem).returns('taggings.context')

    assert_equal :schema_incomplete, FluxTags::PasswordTags.problem
  end

  def test_compatible_answer_is_kept_until_reset
    FluxTags::PasswordTags.stubs(:installed?).returns(true)
    FluxTags::PasswordTags.stubs(:legacy_tags?).returns(false)
    assert_nil FluxTags::PasswordTags.problem

    FluxTags::PasswordTags.stubs(:installed?).returns(false)
    assert_nil FluxTags::PasswordTags.problem
    FluxTags::PasswordTags.reset!
    assert_equal :not_installed, FluxTags::PasswordTags.problem
  end

  def test_available_tags_lists_tags_used_on_password_entries
    flux_tagging(flux_tag('issue-only'), 'Issue', 1)
    flux_tagging(flux_tag('password-only'), PASSWORD_ENTRY, 1)
    both = flux_tag('both')
    flux_tagging(both, 'Issue', 2)
    flux_tagging(both, PASSWORD_ENTRY, 2)

    tags = FluxTags::PasswordTags.available_tags.to_a
    assert_equal %w[both password-only], tags.map(&:name)
    assert_equal 1, tags.first.count.to_i
  end

  def test_admin_sees_every_password_tagging
    flux_tagging(flux_tag('secret'), PASSWORD_ENTRY, 1)

    assert_empty FluxTags::PasswordTags.hidden_taggings(@admin)
  end

  def test_every_password_tagging_is_hidden_without_the_vault_rule
    FluxTags::PasswordTags.stubs(:entry_class).returns(nil)
    tagging = flux_tagging(flux_tag('secret'), PASSWORD_ENTRY, 1)

    assert_equal [tagging.id], FluxTags::PasswordTags.hidden_taggings(@user).pluck(:id)
    assert_empty FluxTags::PasswordTags.visible_password_taggings(@user)
  end

  def test_hidden_taggings_follow_the_vault_rule
    FluxTags::PasswordTags.stubs(:visible_entry_ids).returns([1])
    visible = flux_tagging(flux_tag('mine'), PASSWORD_ENTRY, 1)
    hidden = flux_tagging(flux_tag('peer'), PASSWORD_ENTRY, 2)

    assert_equal [hidden.id], FluxTags::PasswordTags.hidden_taggings(@user).pluck(:id)
    assert_equal [visible.id], FluxTags::PasswordTags.visible_password_taggings(@user).pluck(:id)
  end

  def test_visible_entry_ids_use_the_vault_rule_when_installed
    unless FluxTags::PasswordTags.entry_class.respond_to?(:visible_across_projects)
      skip 'Redmineflux Password Manager not installed'
    end

    assert_kind_of ActiveRecord::Relation, FluxTags::PasswordTags.visible_entry_ids(@user)
  end

  def test_visible_tags_hide_only_tags_whose_every_tagging_is_hidden
    FluxTags::PasswordTags.stubs(:visible_entry_ids).returns([1])
    flux_tagging(flux_tag('hidden-only'), PASSWORD_ENTRY, 2)
    shared = flux_tag('shared')
    flux_tagging(shared, PASSWORD_ENTRY, 2)
    flux_tagging(shared, 'Issue', 1)
    flux_tagging(flux_tag('visible'), PASSWORD_ENTRY, 1)
    flux_tag('orphan')

    scope = FluxTags::PasswordTags.visible_tags(ActsAsTaggableOn::Tag.all, @user)
    assert_equal %w[orphan shared visible], scope.where('LOWER(tags.name) LIKE ?', '%').order(:name).limit(10).pluck(:name)
    assert_includes FluxTags::PasswordTags.visible_tags(ActsAsTaggableOn::Tag.all, @admin).pluck(:name), 'hidden-only'
  end

  def test_visible_tags_fail_closed_but_keep_tags_used_elsewhere
    FluxTags::PasswordTags.stubs(:entry_class).returns(nil)
    flux_tagging(flux_tag('password-only'), PASSWORD_ENTRY, 1)
    shared = flux_tag('shared')
    flux_tagging(shared, PASSWORD_ENTRY, 1)
    flux_tagging(shared, 'Issue', 1)

    assert_equal %w[shared], FluxTags::PasswordTags.visible_tags(ActsAsTaggableOn::Tag.all, @user).pluck(:name)
  end

  def test_hidden_counts_for_every_requested_tag
    FluxTags::PasswordTags.stubs(:visible_entry_ids).returns([1])
    shared = flux_tag('shared')
    [1, 2, 3].each { |entry_id| flux_tagging(shared, PASSWORD_ENTRY, entry_id) }
    other = flux_tag('other')
    flux_tagging(other, 'Issue', 1)

    assert_equal({ shared.id => 2, other.id => 0 },
                 FluxTags::PasswordTags.hidden_counts([shared.id, other.id], @user))
    assert_equal({ shared.id => 0, other.id => 0 },
                 FluxTags::PasswordTags.hidden_counts([shared.id, other.id], @admin))
  end

  def test_touches_hidden
    FluxTags::PasswordTags.stubs(:visible_entry_ids).returns([1])
    peer = flux_tag('peer')
    flux_tagging(peer, PASSWORD_ENTRY, 2)
    mine = flux_tag('mine')
    flux_tagging(mine, PASSWORD_ENTRY, 1)

    assert FluxTags::PasswordTags.touches_hidden?([peer.id], @user)
    assert_not FluxTags::PasswordTags.touches_hidden?([mine.id], @user)
    assert_not FluxTags::PasswordTags.touches_hidden?([peer.id], @admin)
  end

  def test_name_too_long_only_for_tags_on_password_entries
    password = flux_tag('password')
    flux_tagging(password, PASSWORD_ENTRY, 1)
    issue = flux_tag('issue')
    flux_tagging(issue, 'Issue', 1)

    assert FluxTags::PasswordTags.name_too_long?([password.id], 'x' * 61)
    assert_not FluxTags::PasswordTags.name_too_long?([password.id], 'x' * 60)
    assert_not FluxTags::PasswordTags.name_too_long?([issue.id], 'x' * 61)
  end

  def test_event_only_when_password_entries_are_affected
    User.current = @admin
    password = flux_tag('password')
    flux_tagging(password, PASSWORD_ENTRY, 7)
    issue = flux_tag('issue')
    flux_tagging(issue, 'Issue', 1)

    events = capture_password_tag_events do
      FluxTags::PasswordTags.instrument('delete', **FluxTags::PasswordTags.snapshot([issue.id]))
      FluxTags::PasswordTags.instrument('rename', **FluxTags::PasswordTags.snapshot([password.id]), new_name: 'renamed')
    end

    assert_equal [{ action: 'rename', tag_ids: [password.id], names: { password.id => 'password' },
                    new_name: 'renamed', password_entry_ids: [7], user_id: @admin.id }], events
  ensure
    User.current = nil
  end
end
