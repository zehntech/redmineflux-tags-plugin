# The API description needs a login like the rest of the plugin. The file is NOT in assets/ (everything there is
# published at /plugin_assets/ without a login).
class TagSwaggerController < ApplicationController
  before_action :require_login


  def index
    render html: '', layout: 'tag_swagger', content_type: 'text/html' 
  end 
 
  def swagger 
    yaml_file = File.expand_path('../../lib/flux_tags/tag_swagger.yaml', __dir__)
 
    if File.exist?(yaml_file) 
      yaml_content = File.read(yaml_file) 
      # From the settings, not from the Host header of the request.
      server_url = "#{Setting.protocol}://#{Setting.host_name}".chomp('/')
      yaml_content.gsub!("{server_url}", server_url) 
      render plain: yaml_content, content_type: 'application/x-yaml' 
    else 
      render plain: "tag_swagger.yaml not found", status: 404 
    end 
  end 
end