class RemoveIndexTags < ActiveRecord::Migration[5.2]
  def up
    change_column :tags, :name, :string,  unique: false
    #Ex:- change_column("admin_users", "email", :string, :limit =>25)
  end

  # rtg-010: nothing to undo (name stays a string). As `change`, rolling back
  # raised IrreversibleMigration and stopped uninstalling half way.
  def down; end
end
