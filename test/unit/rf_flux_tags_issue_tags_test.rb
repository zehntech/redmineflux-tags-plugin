require File.expand_path('../../test_helper', __FILE__)

# Changing the tags of an issue, with a History entry.
class RfFluxTagsIssueTagsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enabled_modules, :enumerations, :journals, :journal_details,
           :workflows

  def setup
    User.current = nil
    @admin = User.find(1)
    @issue = Issue.find(1)
    @issue.tag_list = %w[bug backend]
    @issue.save!
  end

  def test_replace_saves_the_tags_and_writes_a_history_entry
    assert RfFluxTags::IssueTags.replace(@issue, %w[bug urgent], user: @admin)

    @issue.reload
    assert_equal %w[bug urgent], @issue.tag_list.to_a
    detail = @issue.journals.order(:id).last.details.detect { |d| d.prop_key == 'tag_list' }
    assert_equal 'bug, backend', detail.old_value
    assert_equal 'bug, urgent', detail.value
  end

  def test_replace_with_the_same_tags_writes_nothing
    before = Journal.count
    RfFluxTags::IssueTags.replace(@issue, %w[BACKEND bug], user: @admin)
    assert_equal before, Journal.count
  end

  def test_change_adds_and_removes_for_bulk_edit
    @issue.init_journal(@admin)
    changed = RfFluxTags::IssueTags.change(@issue, add: %w[urgent Bug], remove: %w[BACKEND])
    assert changed
    assert_equal %w[bug urgent], @issue.tag_list.to_a
  end

  def test_change_reports_when_nothing_changes
    @issue.init_journal(@admin)
    assert_not RfFluxTags::IssueTags.change(@issue, add: ['bug'], remove: ['nothing'])
  end

  def test_parse_names_cleans_and_deduplicates
    assert_equal %w[a B], RfFluxTags.parse_names(" a ,B,, b ,A\n")
    assert_equal ['x y'], RfFluxTags.parse_names("x\u0000   y")
  end

  def test_a_user_without_the_permission_cannot_edit_tags
    user = User.find(3) # a plain member of project 1 in the fixtures
    Role.all.each { |r| r.remove_permission!(:manage_issues_tags) }
    assert_not RfFluxTags::IssueTags.allowed?(@issue, user)
  end

  def test_an_administrator_can
    assert RfFluxTags::IssueTags.allowed?(@issue, @admin)
  end
end
