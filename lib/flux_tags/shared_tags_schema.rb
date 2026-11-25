# frozen_string_literal: true

module FluxTags
  # rtg-010: whether the shared tag tables (acts-as-taggable-on's `tags` and
  # `taggings`, also used by the Redmineflux Password Manager) have every
  # column that flux_tags' migrations create.
  module SharedTagsSchema
    REFERENCE_COLUMNS = {
      'tags' => %w[id name taggings_count created_at updated_at],
      'taggings' => %w[id tag_id taggable_type taggable_id tagger_type tagger_id context created_at]
    }.freeze

    # The missing tables ("tags") and columns ("taggings.context"); empty when complete.
    def self.missing
      REFERENCE_COLUMNS.flat_map do |table, columns|
        next [table] unless table_exists?(table)

        (columns - existing_columns(table)).map { |column| "#{table}.#{column}" }
      end
    end

    # nil when complete, otherwise the missing tables and columns, comma-separated.
    def self.problem
      list = missing
      list.empty? ? nil : list.join(', ')
    end

    def self.table_exists?(table)
      ActiveRecord::Base.connection.data_source_exists?(table)
    end

    def self.existing_columns(table)
      ActiveRecord::Base.connection.columns(table).map(&:name)
    end
  end
end
