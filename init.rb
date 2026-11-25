Redmine::Plugin.register :flux_tags do
  name 'Redmineflux Tags plugin'
  author 'Redmineflux - Powered by Zehntech Technologies Inc'
  description 'Streamline project management tasks using Redmineflux Tag Plugin for categorize and retrieve information efficiently with tags.'
  version '7.0.0'
  url 'https://www.redmineflux.com/knowledge-base/plugins/tag-plugin'
  author_url 'https://www.redmineflux.com'

  settings default: {
    issue_inline: "0"
  }, :partial => 'tags/settings'

  # Global tag permissions (not project-scoped)
  permission :view_tags,    {}, read: true   # list and get global tags
  permission :manage_tags,  {}               # create, update, delete, merge tags
  permission :manage_project_tags, {}        # update project-level tag assignments

  project_module :issue_tracking do
    permission :manage_issues_tags, {}       # update issue-level tag assignments
  end
  project_module :time_tracking do
    permission :manage_time_entries_tags, {} # update time-entry-level tag assignments
  end
 
end

require 'redmineflux_icon_compat'





if Redmine::VERSION::MAJOR == 4
  require_relative './lib/issues_tag/view_issues_hooks.rb'
  require_relative './lib/issues_tag/model_issue_hooks.rb'
  require_relative './lib/flux_tags/patches/issue_patch.rb'
  require_relative './lib/flux_tags/patches/issues_controller_patch'
  require_relative './lib/flux_tags/patches/issue_query_patch'
  require_relative './lib/flux_tags/patches/queries_helper_patch'
  require_relative './lib/flux_tags/patches/auto_completes_controller_patch.rb'
  require_relative './lib/flux_tags/patches/project_patch.rb'
  require_relative './lib/flux_tags/patches/project_query_patch'
  require_relative './lib/flux_tags/patches/time_entries_controller_patch'
  require_relative './lib/flux_tags/patches/time_entry_patch'
  require_relative './lib/flux_tags/patches/time_entry_query_patch'
  require_relative './lib/flux_tags/patches/issues_pdf_helper_patch'
  require_relative './lib/custom_will_paginate_renderer.rb'
  require_relative './lib/flux_tags/shared_tags_schema'
  require_relative './lib/flux_tags/password_tags'
  require_relative './lib/flux_tags/tag_merge'

elsif Redmine::VERSION::MAJOR >= 5
  require File.expand_path('./lib/issues_tag/view_issues_hooks.rb', __dir__)
  require File.expand_path('./lib/issues_tag/model_issue_hooks.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/issue_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/issues_controller_patch', __dir__)
  require File.expand_path('./lib/flux_tags/patches/issue_query_patch', __dir__)
  require File.expand_path('./lib/flux_tags/patches/queries_helper_patch', __dir__)
  require File.expand_path('./lib/flux_tags/patches/auto_completes_controller_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/project_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/project_query_patch', __dir__)
  require File.expand_path('./lib/flux_tags/patches/time_entries_controller_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/time_entry_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/time_entry_query_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/issues_controller_patch.rb', __dir__)
  require File.expand_path('./lib/flux_tags/patches/issues_pdf_helper_patch', __dir__)
  require File.expand_path('./lib/custom_will_paginate_renderer.rb', __dir__)
  # rtg-010: Password Manager compatibility (checked at request time, never here:
  # that plugin registers after this one).
  require File.expand_path('./lib/flux_tags/shared_tags_schema', __dir__)
  require File.expand_path('./lib/flux_tags/password_tags', __dir__)
  require File.expand_path('./lib/flux_tags/tag_merge', __dir__)

end
