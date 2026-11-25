class AddContextToTaggings < ActiveRecord::Migration[6.1]
  def up
    return if column_exists?(:taggings, :context)

    add_column :taggings, :context, :string, limit: 128
    add_index  :taggings, :context

    # Backfill for existing records (required by acts-as-taggable-on)
    execute <<~SQL
      UPDATE taggings
      SET context = 'tags'
      WHERE context IS NULL
    SQL
  end

  # rtg-010: context belongs to acts-as-taggable-on's schema, which the first
  # migration also creates and other plugins (the Password Manager) use too.
  # Removing it here would break them; the first migration's down decides.
  def down; end
end
