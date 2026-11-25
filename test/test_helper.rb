# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

# rtg-010: tags and taggings for tests, including taggings of password entries
# (PasswordManager::Entry) written without loading their record, so the tests
# run whether or not the Redmineflux Password Manager is installed.
module FluxTagsTestHelper
  PASSWORD_ENTRY = FluxTags::PasswordTags::TAGGABLE_TYPE

  def flux_tag(name)
    ActsAsTaggableOn::Tag.create!(name: name)
  end

  def flux_tagging(tag, taggable_type, taggable_id)
    tagging = ActsAsTaggableOn::Tagging.new(tag: tag, taggable_type: taggable_type,
                                            taggable_id: taggable_id, context: 'tags')
    tagging.save!(validate: false)
    tagging
  end

  # The payloads of the password_tags_changed.flux_tags events published by the block.
  def capture_password_tag_events
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(FluxTags::PasswordTags::EVENT) do |_name, _start, _finish, _id, payload|
      events << payload
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
