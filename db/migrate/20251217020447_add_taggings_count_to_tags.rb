class AddTaggingsCountToTags < ActiveRecord::Migration[6.1]
  def up
    return if column_exists?(:tags, :taggings_count)

    add_column :tags, :taggings_count, :integer, default: 0, null: false
    add_index  :tags, :taggings_count

    # rtg-010: a correlated sub-query runs on PostgreSQL, MySQL and MariaDB
    # (UPDATE ... INNER JOIN ... SET was MySQL-only).
    execute <<~SQL
      UPDATE tags
      SET taggings_count = (
        SELECT COUNT(*)
        FROM taggings
        WHERE taggings.tag_id = tags.id
      )
    SQL
  end

  # rtg-010: taggings_count belongs to acts-as-taggable-on's schema, which the
  # first migration also creates and other plugins (the Password Manager) use
  # too. Removing it here would break them; the first migration's down decides.
  def down; end
end
