# frozen_string_literal: true

module RfFluxTags
  # Colours of the tag chips. A tag keeps the colour an administrator chose;
  # without one it gets a stable colour generated from its name, so the same
  # tag looks the same everywhere.
  module Colors
    HEX = /\A#[0-9a-fA-F]{6}\z/
    # The colours an administrator can pick from.
    PALETTE = %w[#2f6fb3 #2e8b57 #c77d12 #c0392b #7b4fb3 #b8962e #1f8a8a #6b7785].freeze
    # The colours a tag gets by its name when nobody picked one: many, so that tags on one record rarely share a
    # colour. rf_flux_tags.js has the same list.
    GENERATED = %w[#dc2626 #ea580c #d97706 #a16207 #65a30d #16a34a #059669 #0d9488 #0891b2 #0284c7 #2563eb #4f46e5 #7c3aed #9333ea #c026d3 #db2777 #e11d48 #92400e #475569 #166534 #1e40af #86198f #115e59 #9f1239].freeze

    def self.valid?(value)
      value.to_s.match?(HEX)
    end

    # nil when blank or not a #rrggbb colour.
    def self.normalize(value)
      value = value.to_s.strip
      valid?(value) ? value.downcase : nil
    end

    # The colour to show for a tag (record or plain name).
    def self.for(tag)
      chosen = tag.respond_to?(:rf_flux_tags_color) ? tag.rf_flux_tags_color : nil
      return chosen.downcase if valid?(chosen)

      generated(tag.respond_to?(:name) ? tag.name : tag.to_s)
    end

    # { name => '#rrggbb' } for many names in one query.
    def self.map_for(names)
      names = Array(names).map(&:to_s).uniq
      custom = {}
      if names.any? && Schema.extras?
        ActsAsTaggableOn::Tag.where(name: names).where.not(rf_flux_tags_color: [nil, ''])
                             .pluck(:name, :rf_flux_tags_color).each do |name, color|
          custom[name] = color.downcase if valid?(color)
        end
      end
      names.each_with_object({}) { |name, map| map[name] = custom[name] || generated(name) }
    end

    # FNV-1a over the UTF-8 bytes of the lower-cased name. rf_flux_tags.js uses the very same sum for a tag that
    # was just typed and is not saved yet, so a chip keeps its colour when the page is saved and reloaded.
    def self.generated(name)
      hash = 2_166_136_261
      name.to_s.downcase.each_byte { |byte| hash = ((hash ^ byte) * 16_777_619) & 0xffffffff }
      GENERATED[hash % GENERATED.size]
    end
  end
end
