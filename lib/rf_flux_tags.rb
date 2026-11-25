# frozen_string_literal: true

# Namespace of everything added by the redesigned tag pages. Every new class,
# file, route, DOM id, CSS class, JS global, i18n key, setting and database
# column carries the rf_flux_tags prefix so nothing can clash with Redmine or
# with another plugin that shares the tags tables.
module RfFluxTags
  SETTING_KEYS = %w[issues_use_colors rf_flux_tags_sidebar rf_flux_tags_sidebar_limit
                    rf_flux_tags_sidebar_counts rf_flux_tags_sidebar_open_only].freeze

  DEFAULT_SETTINGS = {
    'issues_use_colors' => '1',
    'rf_flux_tags_sidebar' => 'list',
    'rf_flux_tags_sidebar_limit' => '10',
    'rf_flux_tags_sidebar_counts' => '1',
    'rf_flux_tags_sidebar_open_only' => '0'
  }.freeze

  TAG_NAME_MAX = 60
  TAG_LIST_LIMIT = 30
  DESCRIPTION_MAX = 255

  # The plugin settings with defaults filled in. Never nil, never raises.
  def self.settings
    saved = Setting[:plugin_flux_tags]
    saved = {} unless saved.respond_to?(:to_h)
    DEFAULT_SETTINGS.merge(saved.to_h.stringify_keys)
  rescue StandardError
    DEFAULT_SETTINGS
  end

  def self.setting(key)
    settings[key.to_s]
  end

  SIDEBAR_STYLES = %w[list colored none].freeze
  SIDEBAR_LIMITS = [5, 10, 15, 20].freeze

  # 'list', 'colored' or 'none'. The old 'cloud' choice shows colored tags now.
  def self.sidebar_style
    style = setting('rf_flux_tags_sidebar').to_s
    style = 'colored' if style == 'cloud'
    SIDEBAR_STYLES.include?(style) ? style : 'list'
  end

  def self.sidebar_limit
    limit = setting('rf_flux_tags_sidebar_limit').to_i
    SIDEBAR_LIMITS.include?(limit) ? limit : 10
  end

  def self.use_colors?
    setting('issues_use_colors').to_s == '1'
  end

  # Splits "a, b ,c" (or an array) into clean, de-duplicated names. Names are
  # compared case-insensitively; the first spelling wins.
  # Characters that do not show but make two names look alike or flip the text around them: zero-width space,
  # left-to-right / right-to-left marks and overrides, word joiner, soft hyphen, byte order mark. (The zero-width
  # joiner stays: emoji sequences need it.)
  INVISIBLE_CHARACTERS = /[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060\uFEFF]/.freeze

  # One name, the way every entry point cleans it: no invisible characters, control characters become spaces,
  # runs of spaces become one.
  def self.clean_name(value)
    value.to_s.gsub(INVISIBLE_CHARACTERS, '').gsub(/[[:cntrl:]]/, ' ').squish
  end

  def self.parse_names(value)
    Array(value).flat_map { |item| item.to_s.split(',') }
                .map { |name| clean_name(name) }
                .reject(&:blank?)
                .uniq(&:downcase)
  end
end
