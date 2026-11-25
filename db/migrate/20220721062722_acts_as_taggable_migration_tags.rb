class ActsAsTaggableMigrationTags < ActiveRecord::Migration[5.2]
  # rtg-010: the tables may already exist, made by another user of
  # acts-as-taggable-on's schema (the Redmineflux Password Manager creates
  # the same tables when it is installed first). These columns make them
  # acts-as-taggable-on tables.
  REQUIRED_COLUMNS = { tags: %w[id name], taggings: %w[id tag_id taggable_type taggable_id] }.freeze
  # The types flux_tags tags; taggings of any other type belong to another plugin.
  FLUX_TAGS_TYPES = %w[Issue Project TimeEntry].freeze
  OTHER_PLUGINS = %i[redmineflux_password_manager].freeze

  # Lightweight table class: migrations do not use the application's models.
  class MigrationTagging < ActiveRecord::Base; end

  def up
    tags_exist = table_exists?(ActsAsTaggableOn.tags_table)
    taggings_exist = table_exists?(ActsAsTaggableOn.taggings_table)

    if tags_exist && taggings_exist
      check_columns!(ActsAsTaggableOn.tags_table, REQUIRED_COLUMNS[:tags])
      check_columns!(ActsAsTaggableOn.taggings_table, REQUIRED_COLUMNS[:taggings])
    elsif tags_exist || taggings_exist
      present, missing = [ActsAsTaggableOn.tags_table, ActsAsTaggableOn.taggings_table]
      present, missing = missing, present unless tags_exist
      raise ActiveRecord::MigrationError,
            "flux_tags: the table #{present} exists but #{missing} does not. A half-made tag schema is not " \
            'repaired automatically; restore both tables (or remove the leftover one) and migrate again.'
    else
      create_table ActsAsTaggableOn.tags_table do |t|
        t.string :name, index: { unique: true }
        t.integer :taggings_count, default: 0
        t.timestamps
      end

      create_table ActsAsTaggableOn.taggings_table do |t|
        t.references :tag, foreign_key: { to_table: ActsAsTaggableOn.tags_table }, index: false
        t.references :taggable, polymorphic: true
        t.references :tagger, polymorphic: true
        t.string :context, limit: 128

        t.datetime :created_at

        t.index %i[tag_id taggable_id taggable_type context tagger_id tagger_type], unique: true, name: 'ataggings_idx'
        t.index %i[taggable_id taggable_type context], name: 'ataggings_taggable_context_idx'
        t.index :taggable_type
        t.index :context
        t.index %i[tagger_id tagger_type]
        t.index %i[taggable_id taggable_type tagger_id context], name: 'ataggings_idy'
      end
    end

    return unless ActsAsTaggableOn::Utils.using_mysql?

    execute "ALTER TABLE #{ActsAsTaggableOn.tags_table} MODIFY name varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"

  end

  # rtg-010: while another plugin still uses the tables, only flux_tags' own
  # taggings are removed; the tables, the tag rows and every column stay.
  def down
    return unless table_exists?(ActsAsTaggableOn.tags_table) && table_exists?(ActsAsTaggableOn.taggings_table)

    MigrationTagging.table_name = ActsAsTaggableOn.taggings_table
    if shared_tables_in_use?
      MigrationTagging.where(taggable_type: FLUX_TAGS_TYPES).delete_all
      recount_taggings
      say "flux_tags: #{ActsAsTaggableOn.tags_table} and #{ActsAsTaggableOn.taggings_table} are kept, " \
          'because another plugin still uses them; only the issue, project and time entry tags were removed.'
    else
      drop_table ActsAsTaggableOn.taggings_table
      drop_table ActsAsTaggableOn.tags_table
    end
  end

  private

  def check_columns!(table, required)
    missing = required - columns(table).map(&:name)
    return if missing.empty?

    raise ActiveRecord::MigrationError,
          "flux_tags: the existing table #{table} is not an acts-as-taggable-on table " \
          "(missing #{missing.join(', ')}). It was left unchanged."
  end

  def shared_tables_in_use?
    OTHER_PLUGINS.any? { |id| Redmine::Plugin.installed?(id) } ||
      MigrationTagging.where.not(taggable_type: FLUX_TAGS_TYPES).exists?
  end

  def recount_taggings
    return unless column_exists?(ActsAsTaggableOn.tags_table, :taggings_count)

    tags = quote_table_name(ActsAsTaggableOn.tags_table)
    taggings = quote_table_name(ActsAsTaggableOn.taggings_table)
    execute "UPDATE #{tags} SET taggings_count = (SELECT COUNT(*) FROM #{taggings} WHERE #{taggings}.tag_id = #{tags}.id)"
  end
end
