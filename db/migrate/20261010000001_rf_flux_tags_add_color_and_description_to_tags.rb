# frozen_string_literal: true

# Per-tag colour and description for the redesigned tag pages.
#
# The `tags` table is shared (acts-as-taggable-on, also used by the Password
# Manager and the CRM), so the two new columns carry the rf_flux_tags_ prefix
# and can never clash with a column another plugin adds. Both are optional:
# a tag without a colour keeps the colour generated from its name.
#
# Safe to run twice and safe in either install order.
class RfFluxTagsAddColorAndDescriptionToTags < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:tags)

    unless column_exists?(:tags, :rf_flux_tags_color)
      add_column :tags, :rf_flux_tags_color, :string, limit: 16
    end
    unless column_exists?(:tags, :rf_flux_tags_description)
      add_column :tags, :rf_flux_tags_description, :string, limit: 255
    end
  end

  # Only the columns added here are removed; the shared tables stay.
  def down
    return unless table_exists?(:tags)

    remove_column :tags, :rf_flux_tags_description if column_exists?(:tags, :rf_flux_tags_description)
    remove_column :tags, :rf_flux_tags_color if column_exists?(:tags, :rf_flux_tags_color)
  end
end
