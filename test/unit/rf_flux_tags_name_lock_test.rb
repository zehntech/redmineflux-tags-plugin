require File.expand_path('../../test_helper', __FILE__)

# The lock that stops "bug" and "BUG" being created together.
class RfFluxTagsNameLockTest < ActiveSupport::TestCase
  def setup
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all
  end

  def test_the_block_runs_and_gives_its_result_back
    assert_equal :done, RfFluxTags::NameLock.with('Bug', 'bug', 'other') { :done }
  end

  def test_no_names_means_no_lock_and_the_block_still_runs
    assert_equal 1, RfFluxTags::NameLock.with { 1 }
    assert_equal 2, RfFluxTags::NameLock.with(nil, []) { 2 }
  end

  def test_an_error_inside_the_block_is_passed_on
    assert_raises(ArgumentError) { RfFluxTags::NameLock.with('bug') { raise ArgumentError, 'boom' } }
  end

  def test_creating_a_tag_twice_with_different_capitals_gives_one_tag
    first  = RfFluxTags::TagOperations.create(name: 'bug')
    second = RfFluxTags::TagOperations.create(name: 'BUG')
    assert first.ok?
    assert_not second.ok?
    assert_equal 1, ActsAsTaggableOn::Tag.where('LOWER(name) = ?', 'bug').count
  end

  def test_looking_up_tags_for_a_list_still_finds_the_existing_ones_ignoring_case
    existing = ActsAsTaggableOn::Tag.create!(name: 'bug')
    found = ActsAsTaggableOn::Tag.find_or_create_all_with_like_by_name('BUG', 'new-one')
    assert_includes found.map(&:id), existing.id
    assert_equal 2, ActsAsTaggableOn::Tag.count
  end
end
