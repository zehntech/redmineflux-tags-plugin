# frozen_string_literal: true

# Suggestions for the tag input: tags already used on this kind of record,
# plus tags nobody uses yet (created on the administration page), most used first.
#
# The list holds LIMIT tags. UNUSED_RESERVED of them are kept for tags nobody uses yet (while there are such
# tags), so they still show up when the kind of record already has more used tags than the list can hold.
class RfFluxTagsSuggestController < ApplicationController
  LIMIT = 12
  UNUSED_RESERVED = 4
  MODELS = { 'issue' => 'Issue', 'time_entry' => 'TimeEntry', 'project' => 'Project' }.freeze

  before_action :require_login

  # GET /rf_flux_tags/suggest?context=issue&q=bu
  def index
    response.headers['Cache-Control'] = 'no-store'
    model = MODELS[params[:context].to_s]&.safe_constantize
    return render(json: []) unless model

    query = params[:q].to_s.strip.first(100)
    used = model.available_tags(name_like: query.presence).limit(LIMIT).to_a
    names = used.map(&:name)
    unused = rf_flux_tags_unused_tags(query).reject { |tag| names.include?(tag.name) }
    # keep room for the unused tags, then fill what is left over with whichever kind there is more of
    used = used.first(LIMIT - [unused.size, UNUSED_RESERVED].min)
    unused = unused.first(LIMIT - used.size)
    colors = RfFluxTags::Colors.map_for((used + unused).map(&:name))
    list = used.map { |tag| { name: tag.name, count: tag[:count].to_i, color: colors[tag.name] } } +
           unused.map { |tag| { name: tag.name, count: 0, color: colors[tag.name] } }
    render json: list.sort_by { |item| [-item[:count], item[:name].downcase] }.first(LIMIT)
  end

  private

  def rf_flux_tags_unused_tags(query)
    scope = ActsAsTaggableOn::Tag.where(RfFluxTags::TagCatalog.unused_sql)
    if query.present?
      scope = scope.where('LOWER(tags.name) LIKE ?',
                          "%#{ActsAsTaggableOn::Tag.sanitize_sql_like(query.downcase)}%")
    end
    scope.order(:name).limit(LIMIT).to_a
  end
end
