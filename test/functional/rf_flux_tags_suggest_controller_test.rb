require File.expand_path('../../test_helper', __FILE__)

# The tags offered under the tag input: used tags first, with room kept for tags nobody uses yet.
class RfFluxTagsSuggestControllerTest < Redmine::ControllerTest
  tests RfFluxTagsSuggestController
  include FluxTagsTestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enabled_modules, :enumerations

  def setup
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all
    @request.session[:user_id] = 1
  end

  def names
    JSON.parse(response.body).map { |item| item['name'] }
  end

  def counts
    JSON.parse(response.body).each_with_object({}) { |item, memo| memo[item['name']] = item['count'] }
  end

  def used_tags(how_many)
    Array.new(how_many) { |i| flux_tag("used-#{format('%02d', i)}") }.each { |tag| flux_tagging(tag, 'Issue', 1) }
  end

  def unused_tags(how_many)
    Array.new(how_many) { |i| flux_tag("unused-#{format('%02d', i)}") }
  end

  def test_used_and_unused_tags_are_both_listed
    used_tags(3)
    unused_tags(2)
    get :index, params: { context: 'issue', q: '' }
    assert_response :success
    assert_equal %w[used-00 used-01 used-02 unused-00 unused-01].sort, names.sort
    assert_equal 0, counts['unused-00']
    assert_equal 1, counts['used-00']
  end

  def test_unused_tags_keep_their_places_when_there_are_more_used_tags_than_the_list_holds
    used_tags(20)
    unused_tags(6)
    get :index, params: { context: 'issue', q: '' }
    assert_response :success
    assert_equal 12, names.size
    assert_equal 4, names.count { |name| name.start_with?('unused-') }, names.inspect
    assert_equal 8, names.count { |name| name.start_with?('used-') }, names.inspect
  end

  def test_few_unused_tags_do_not_waste_places
    used_tags(20)
    unused_tags(1)
    get :index, params: { context: 'issue', q: '' }
    assert_equal 12, names.size
    assert_equal 1, names.count { |name| name.start_with?('unused-') }
    assert_equal 11, names.count { |name| name.start_with?('used-') }
  end

  def test_few_used_tags_leave_the_places_to_unused_ones
    used_tags(2)
    unused_tags(20)
    get :index, params: { context: 'issue', q: '' }
    assert_equal 12, names.size
    assert_equal 2, names.count { |name| name.start_with?('used-') }
    assert_equal 10, names.count { |name| name.start_with?('unused-') }
  end

  def test_typing_filters_both_kinds
    used_tags(20)
    unused_tags(6)
    get :index, params: { context: 'issue', q: 'unused-0' }
    assert names.all? { |name| name.include?('unused-0') }, names.inspect
    assert_equal 6, names.size
  end

  def test_a_tag_is_never_listed_twice
    used_tags(2)
    get :index, params: { context: 'issue', q: '' }
    assert_equal names.uniq, names
  end
end
