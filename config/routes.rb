# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Redesigned tag pages. Every new route and route name starts with rf_flux_tags.
get '/rf_flux_tags/suggest', to: 'rf_flux_tags_suggest#index', as: 'rf_flux_tags_suggest'
patch '/rf_flux_tags/issues/:id/tags', to: 'rf_flux_tags_issue_tags#update', as: 'rf_flux_tags_issue_tags'

scope '/rf_flux_tags/admin', controller: 'rf_flux_tags_admin' do
  get    'tags',             action: :index,          as: 'rf_flux_tags_admin_tags'
  post   'tags',             action: :create
  delete 'tags',             action: :destroy
  get    'tags/ids',         action: :ids,            as: 'rf_flux_tags_admin_tag_ids'
  delete 'tags/unused',      action: :destroy_unused, as: 'rf_flux_tags_admin_unused_tags'
  patch  'tags/:id',         action: :update,         as: 'rf_flux_tags_admin_tag'
  get    'tags/:id/records', action: :records,        as: 'rf_flux_tags_admin_tag_records'
end

get '/issue_tags/auto_complete/:project_id', to: 'auto_completes#issue_tags', as: 'auto_complete_issue_tags'
get '/time_entry_tags/auto_complete', to: 'auto_completes#time_entry_tags', as: 'auto_complete_time_entry_tags'
get '/project_tags/auto_complete_v2', to: 'auto_completes#project_tags', as: 'auto_complete_project_tags_v2'


delete '/tags', controller: 'tags', action: 'destroy'
resources :tags, only: [:destroy]
resources :tags, only: [:edit, :update]
# resources :issue_tags_zt, only: %i[edit] do 
#   collection do 
#     post :update
#   end 
# end 
resources :tags, only: [:show, :update, :destroy]

post :update_issue_tags, to: 'issue_tags_zt#update'
get '/flux_tags/api_doc', to: 'tag_swagger#index'
get '/tag-api.yaml', to: 'tag_swagger#swagger', defaults: { format: :yaml }

namespace :api do
  namespace :v1 do
    scope :flux_tags, controller: :flux_tags do
      get 'tags', action: :index
      post 'tags', action: :create
      get 'tags/:id', action: :show
      patch 'tags/:id', action: :update
      put 'tags/:id', action: :update
      delete 'tags/:id', action: :destroy
      get 'tags/:id/records', action: :tagged_records

      get 'issues/:issue_id/tags', action: :issue_tags
      patch 'issues/:issue_id/tags', action: :update_issue_tags
      put 'issues/:issue_id/tags', action: :update_issue_tags

      get 'projects/:project_id/tags', action: :project_tags
      patch 'projects/:project_id/tags', action: :update_project_tags
      put 'projects/:project_id/tags', action: :update_project_tags

      get 'time_entries/:time_entry_id/tags', action: :time_entry_tags
      patch 'time_entries/:time_entry_id/tags', action: :update_time_entry_tags
      put 'time_entries/:time_entry_id/tags', action: :update_time_entry_tags
    end
  end
end

