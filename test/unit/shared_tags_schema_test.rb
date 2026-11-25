require File.expand_path('../../test_helper', __FILE__)

# rtg-010: the shared tags/taggings tables have every column flux_tags' migrations create.
class FluxTagsSharedTagsSchemaTest < ActiveSupport::TestCase
  def test_complete_on_the_migrated_database
    assert_empty FluxTags::SharedTagsSchema.missing
    assert_nil FluxTags::SharedTagsSchema.problem
  end

  def test_reports_missing_tables_and_columns
    FluxTags::SharedTagsSchema.stubs(:table_exists?).with('tags').returns(false)
    FluxTags::SharedTagsSchema.stubs(:table_exists?).with('taggings').returns(true)
    FluxTags::SharedTagsSchema.stubs(:existing_columns).with('taggings')
                              .returns(%w[id tag_id taggable_type taggable_id created_at])

    assert_equal %w[tags taggings.tagger_type taggings.tagger_id taggings.context],
                 FluxTags::SharedTagsSchema.missing
    assert_equal 'tags, taggings.tagger_type, taggings.tagger_id, taggings.context',
                 FluxTags::SharedTagsSchema.problem
  end
end
