require_relative '../test_helper'

# The API documentation page and its OpenAPI file. They need a login (they used to be open to anyone).
class TagSwaggerControllerTest < Redmine::ControllerTest
  tests TagSwaggerController

  fixtures :users, :email_addresses, :user_preferences

  def test_the_documentation_page_needs_a_login
    get :index
    assert_response :redirect
    assert_redirected_to %r{/login}
  end

  def test_the_openapi_file_needs_a_login
    get :swagger, format: :yaml
    assert_includes [302, 401], response.status
  end

  def test_the_documentation_page_opens_for_a_signed_in_user
    @request.session[:user_id] = 2
    get :index
    assert_response :success
    assert_select '#swagger-ui'
  end

  def test_the_openapi_file_describes_every_endpoint
    @request.session[:user_id] = 2
    get :swagger, format: :yaml
    assert_response :success
    spec = YAML.safe_load(response.body)
    assert_equal '3.0.0', spec['openapi']
    paths = spec['paths'].keys
    %w[/api/v1/flux_tags/tags /api/v1/flux_tags/tags/{id}
       /api/v1/flux_tags/tags/{id}/records /api/v1/flux_tags/issues/{issue_id}/tags
       /api/v1/flux_tags/projects/{project_id}/tags /api/v1/flux_tags/time_entries/{time_entry_id}/tags].each do |path|
      assert_includes paths, path
    end
    assert_not_includes response.body, '{server_url}', 'the server url must be filled in'
  end
end
