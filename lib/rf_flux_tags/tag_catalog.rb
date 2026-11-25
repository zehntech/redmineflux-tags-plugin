# frozen_string_literal: true

module RfFluxTags
  # The tag list of the administration page: one tab per kind of record,
  # with search, sort, the "unused" filter and paging, done in the database.
  class TagCatalog
    CONTEXTS = {
      'issue' => 'Issue',
      'time_entry' => 'TimeEntry',
      'project' => 'Project',
      FluxTags::PasswordTags::TAB => FluxTags::PasswordTags::TAGGABLE_TYPE
    }.freeze
    SORTS = %w[name count].freeze
    PER_PAGE_OPTIONS = [10, 20, 50, 100].freeze
    # "Select all matching tags" never returns more ids than this.
    MAX_IDS = 5000

    attr_reader :context, :query, :filter, :sort, :direction, :page, :per_page

    def initialize(params = {})
      @context = CONTEXTS.key?(params[:context].to_s) ? params[:context].to_s : 'issue'
      @query = params[:q].to_s.strip.first(100)
      @filter = params[:filter].to_s == 'unused' ? 'unused' : 'all'
      @sort = SORTS.include?(params[:sort].to_s) ? params[:sort].to_s : 'name'
      @direction = params[:dir].to_s == 'desc' ? 'desc' : 'asc'
      @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 10
      @page = [params[:page].to_i, 1].max
    end

    def taggable_type
      CONTEXTS[context]
    end

    def tag_class
      ActsAsTaggableOn::Tag
    end

    def unused?
      filter == 'unused'
    end

    def matching
      scope = tag_class.all
      scope = if unused?
                scope.where(self.class.unused_sql)
              else
                scope.where(id: ActsAsTaggableOn::Tagging.where(taggable_type: taggable_type).select(:tag_id))
              end
      return scope if query.blank?

      scope.where('LOWER(tags.name) LIKE ?', "%#{tag_class.sanitize_sql_like(query.downcase)}%")
    end

    def total
      @total ||= matching.count
    end

    def pages
      [(total.to_f / per_page).ceil, 1].max
    end

    def current_page
      [page, pages].min
    end

    # The rows of the current page, each with rf_flux_tags_count (uses in this
    # tab) and rf_flux_tags_total (uses everywhere).
    def rows
      select = ['tags.*',
                "(#{count_sql(taggable_type)}) AS rf_flux_tags_count",
                "(#{count_sql(nil)}) AS rf_flux_tags_total"].join(', ')
      matching.select(select)
              .order(order_sql)
              .limit(per_page).offset((current_page - 1) * per_page).to_a
    end

    def ids
      matching.limit(MAX_IDS).pluck(:id)
    end

    # [[id, name], ...] of everything matching, for "select all N tags".
    def id_name_pairs
      matching.order(Arel.sql('LOWER(tags.name) ASC')).limit(MAX_IDS).pluck(:id, :name)
    end

    # { 'issue' => 12, ..., 'unused' => 3, 'total' => 40 } for the tab badges.
    def self.stats
      per_type = ActsAsTaggableOn::Tagging.group(:taggable_type).distinct.count(:tag_id)
      result = CONTEXTS.each_with_object({}) { |(key, type), memo| memo[key] = per_type[type].to_i }
      result['unused'] = ActsAsTaggableOn::Tag.where(unused_sql).count
      result['total'] = ActsAsTaggableOn::Tag.count
      result
    end

    def self.unused_sql
      'NOT EXISTS (SELECT 1 FROM taggings WHERE taggings.tag_id = tags.id)'
    end

    private

    def count_sql(type)
      sql = 'SELECT COUNT(*) FROM taggings WHERE taggings.tag_id = tags.id'
      sql += " AND taggings.taggable_type = #{tag_class.connection.quote(type)}" if type
      sql
    end

    def order_sql
      dir = direction.upcase
      if sort == 'count'
        Arel.sql("rf_flux_tags_count #{dir}, LOWER(tags.name) ASC, tags.id ASC")
      else
        Arel.sql("LOWER(tags.name) #{dir}, tags.id ASC")
      end
    end
  end
end
