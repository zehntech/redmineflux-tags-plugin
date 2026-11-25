class AddTaggerToTaggings < ActiveRecord::Migration[6.1]
   def up
    unless column_exists?(:taggings, :tagger_id)
      add_column :taggings, :tagger_id, :integer
      add_index  :taggings, :tagger_id
    end

    unless column_exists?(:taggings, :tagger_type)
      add_column :taggings, :tagger_type, :string
      add_index  :taggings, :tagger_type
    end
  end

  # rtg-010: tagger_* belong to acts-as-taggable-on's schema, which the first
  # migration also creates and other plugins (the Password Manager) use too.
  # Removing them here would break them; the first migration's down decides.
  def down; end
end
