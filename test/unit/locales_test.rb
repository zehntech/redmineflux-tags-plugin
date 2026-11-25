require File.expand_path('../../test_helper', __FILE__)

# rtg-010: every locale has the Password Manager strings, and no locale
# defines a key twice (the later one silently wins, see rtg-004).
class FluxTagsLocalesTest < ActiveSupport::TestCase
  LOCALE_FILES = Dir[File.expand_path('../../config/locales/*.yml', __dir__)].sort
  PASSWORD_TAG_KEYS = %w[label_password_entry_tags text_flux_tags_pm_legacy_tags
                         text_flux_tags_pm_schema_incomplete
                         error_flux_tags_name_too_long_for_password_tags].freeze

  def test_every_locale_has_the_password_tag_strings
    LOCALE_FILES.each do |path|
      strings = YAML.load_file(path).values.first
      PASSWORD_TAG_KEYS.each do |key|
        assert strings[key].present?, "#{File.basename(path)} lacks #{key}"
      end
    end
  end

  def test_no_locale_defines_a_key_twice
    LOCALE_FILES.each do |path|
      mapping = Psych.parse_file(path).root.children[1]
      keys = mapping.children.each_slice(2).map { |key, _value| key.value }
      assert_equal keys.uniq, keys, "#{File.basename(path)} defines a key twice"
    end
  end
end
