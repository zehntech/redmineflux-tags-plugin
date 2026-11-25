require File.expand_path('../../test_helper', __FILE__)

# Create, rename and delete tags for the administration page, and the
# list behind it (search, sort, unused filter, counts).
class RfFluxTagsTagOperationsTest < ActiveSupport::TestCase
  include FluxTagsTestHelper

  Ops = RfFluxTags::TagOperations

  def setup
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all
  end

  # ---- create ----

  def test_create_trims_the_name
    result = Ops.create(name: '  customer   request  ')
    assert result.ok?
    assert_equal 'customer request', result.tag.name
  end

  def test_create_rejects_a_blank_name
    result = Ops.create(name: '   ')
    assert_not result.ok?
    assert_equal :rf_flux_tags_error_name_blank, result.error
  end

  def test_create_rejects_a_name_over_the_limit
    result = Ops.create(name: 'x' * (RfFluxTags::TAG_NAME_MAX + 1))
    assert_equal :rf_flux_tags_error_name_too_long, result.error
  end

  def test_create_rejects_a_duplicate_ignoring_case
    flux_tag('Bug')
    result = Ops.create(name: 'bUG')
    assert_equal :rf_flux_tags_error_name_taken, result.error
    assert_equal 1, ActsAsTaggableOn::Tag.count
  end

  def test_create_stores_color_and_description
    skip 'plugin migrations not run' unless RfFluxTags::Schema.extras?

    tag = Ops.create(name: 'urgent', color: '#C0392B', description: ' Needs  attention ').tag
    assert_equal '#c0392b', tag.rf_flux_tags_color
    assert_equal 'Needs attention', tag.rf_flux_tags_description
  end

  def test_an_invalid_color_is_ignored
    skip 'plugin migrations not run' unless RfFluxTags::Schema.extras?

    tag = Ops.create(name: 'odd', color: 'red; background:url(x)').tag
    assert_nil tag.rf_flux_tags_color
  end

  # ---- update ----

  def test_update_renames
    tag = flux_tag('old')
    assert Ops.update(tag, name: 'new').ok?
    assert_equal 'new', tag.reload.name
  end

  def test_update_refuses_a_name_that_belongs_to_another_tag
    flux_tag('taken')
    tag = flux_tag('mine')
    assert_equal :rf_flux_tags_error_name_taken, Ops.update(tag, name: 'TAKEN').error
  end

  def test_update_can_change_only_the_case_of_its_own_name
    tag = flux_tag('bug')
    assert Ops.update(tag, name: 'Bug').ok?
    assert_equal 'Bug', tag.reload.name
  end

  def test_update_keeps_the_password_manager_name_limit
    tag = flux_tag('vault')
    flux_tagging(tag, PASSWORD_ENTRY, 1)
    result = Ops.update(tag, name: 'x' * 61)
    # the generic limit (60) answers first; the vault limit is the same 60
    assert_not result.ok?
  end

  def test_update_publishes_the_event_for_password_entries
    tag = flux_tag('vault')
    flux_tagging(tag, PASSWORD_ENTRY, 5)
    events = capture_password_tag_events { Ops.update(tag, name: 'vault-2') }
    assert_equal [['rename', [5]]], events.map { |e| [e[:action], e[:password_entry_ids]] }
  end

  # ---- destroy ----

  def test_destroy_removes_the_tags_and_their_taggings
    tag = flux_tag('gone')
    flux_tagging(tag, 'Issue', 1)
    other = flux_tag('stays')
    flux_tagging(other, 'Issue', 1)

    result = Ops.destroy([tag])

    assert result.ok?
    assert_equal 1, result.count
    assert_not ActsAsTaggableOn::Tag.exists?(tag.id)
    assert_equal 1, ActsAsTaggableOn::Tagging.count
  end

  def test_destroy_unused_keeps_tags_that_are_in_use
    flux_tagging(flux_tag('used'), 'Issue', 1)
    flux_tag('idle-1')
    flux_tag('idle-2')

    result = Ops.destroy_unused

    assert_equal 2, result.count
    assert_equal ['used'], ActsAsTaggableOn::Tag.pluck(:name)
  end

  # ---- catalog ----

  def test_catalog_lists_the_tags_of_one_kind_with_counts
    bug = flux_tag('bug')
    ui = flux_tag('ui')
    flux_tagging(bug, 'Issue', 1)
    flux_tagging(bug, 'Issue', 2)
    flux_tagging(ui, 'Project', 1)

    rows = RfFluxTags::TagCatalog.new(context: 'issue').rows

    assert_equal ['bug'], rows.map(&:name)
    assert_equal 2, rows.first[:rf_flux_tags_count].to_i
  end

  def test_catalog_unused_filter_and_search
    flux_tagging(flux_tag('used'), 'Issue', 1)
    flux_tag('idle')
    flux_tag('Idle-too')

    unused = RfFluxTags::TagCatalog.new(filter: 'unused')
    assert_equal %w[idle Idle-too], unused.rows.map(&:name)
    assert_equal ['Idle-too'], RfFluxTags::TagCatalog.new(filter: 'unused', q: 'TOO').rows.map(&:name)
  end

  def test_catalog_search_treats_percent_literally
    flux_tagging(flux_tag('100%'), 'Issue', 1)
    flux_tagging(flux_tag('other'), 'Issue', 2)
    assert_equal ['100%'], RfFluxTags::TagCatalog.new(context: 'issue', q: '%').rows.map(&:name)
  end

  def test_catalog_sorts_by_count_and_pages
    popular = flux_tag('popular')
    quiet = flux_tag('quiet')
    3.times { |i| flux_tagging(popular, 'Issue', i + 1) }
    flux_tagging(quiet, 'Issue', 1)

    catalog = RfFluxTags::TagCatalog.new(context: 'issue', sort: 'count', dir: 'desc', per_page: 10)
    assert_equal %w[popular quiet], catalog.rows.map(&:name)
    assert_equal 2, catalog.total
    assert_equal 1, catalog.pages
  end

  def test_catalog_stats
    flux_tagging(flux_tag('a'), 'Issue', 1)
    flux_tag('idle')
    stats = RfFluxTags::TagCatalog.stats
    assert_equal 1, stats['issue']
    assert_equal 1, stats['unused']
    assert_equal 2, stats['total']
  end
end
