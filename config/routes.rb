# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

get '/issue_tags/auto_complete/:project_id', to: 'auto_completes#issue_tags', as: 'auto_complete_issue_tags'
get '/time_entry_tags/auto_complete', to: 'auto_completes#time_entry_tags', as: 'auto_complete_time_entry_tags'
get '/project_tags/auto_complete_v2', to: 'auto_completes#project_tags', as: 'auto_complete_project_tags_v2'


match '/tags/context_menu', to: 'tags#context_menu', as: 'tags_context_menu', via: [:get, :post]
delete '/tags', controller: 'tags', action: 'destroy'
resources :tags, only: [:destroy]
resources :tags, only: [:edit, :update] do
  collection do
    post :merge
    get :context_menu
    get :merge
    post :update_tags_for_record  # Add this line for the new route
  end
end
# resources :issue_tags_zt, only: %i[edit] do 
#   collection do 
#     post :update
#   end 
# end 
resources :tags, only: [:show, :update, :destroy]

get :edit_issue_tags, to: 'issue_tags_zt#edit'
post :update_issue_tags, to: 'issue_tags_zt#update'
get '/flux_tags/api_doc', to: 'tag_swagger#index'
get '/tag-api.yaml', to: 'tag_swagger#swagger', defaults: { format: :yaml }

namespace :api do
  namespace :v1 do
    scope :flux_tags, controller: :flux_tags do
      get 'tags', action: :index
      post 'tags', action: :create
      post 'tags/merge', action: :merge
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

match '*path', to: 'tag_swagger#preflight', via: :options
