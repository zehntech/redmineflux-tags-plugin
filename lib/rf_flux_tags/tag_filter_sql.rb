# frozen_string_literal: true

module RfFluxTags
  # The SQL behind the "Tags" filter of the issue, project and time entry lists.
  #
  # It used to load every tag and every tagged record of the whole database into memory and then paste the ids
  # into the query ("any tag" / "no tag" on a big instance was slow for whoever chose it, and ignored what the
  # viewer may see). It is now a single sub-select on the taggings table.
  module TagFilterSql
    # operator: '=' (one of these tags), '!' (none of these), '*' (has a tag), '!*' (no tag at all)
    def self.build(taggable_type, table_name, operator, names)
      connection = ActiveRecord::Base.connection
      type = connection.quote(taggable_type)
      taggings = "SELECT taggings.taggable_id FROM taggings WHERE taggings.taggable_type = #{type} " \
                 "AND taggings.taggable_id IS NOT NULL AND taggings.context = 'tags'"

      case operator
      when '=', '!'
        wanted = Array(names).map { |name| connection.quote(name.to_s.downcase) }
        wanted = ["''"] if wanted.empty?
        taggings += ' AND taggings.tag_id IN (SELECT tags.id FROM tags ' \
                    "WHERE LOWER(tags.name) IN (#{wanted.join(', ')}))"
        compare = operator == '!' ? 'NOT IN' : 'IN'
      when '!*'
        compare = 'NOT IN'
      else
        compare = 'IN'
      end

      "( #{table_name}.id #{compare} (#{taggings}) )"
    end
  end
end
