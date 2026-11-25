# frozen_string_literal: true

require 'zlib'

module RfFluxTags
  # One request at a time per tag name (ignoring capital letters) while a tag is looked up and created.
  #
  # Names are unique ignoring case, but PostgreSQL's unique index on the name tells "bug" from "BUG". Two
  # requests that arrive together both find no "bug" and both create one - one as "bug", one as "BUG" - and
  # the index lets both through. This lock makes the second request wait, then find the tag the first one made.
  # MySQL needs nothing: its name column already ignores case, so the index itself refuses the second tag.
  module NameLock
    NAMESPACE = 0x52_46_54 # "RFT"

    # Runs the block while holding the lock of every given name (sorted, so two requests never wait for each
    # other). The lock lasts until the surrounding transaction ends, which is after the new tag is saved.
    def self.with(*names, &block)
      keys = names.flatten.compact.map { |name| name.to_s.downcase }.uniq.sort
      return yield unless keys.any? && postgres?

      ActiveRecord::Base.transaction do
        keys.each do |key|
          # two 32-bit keys: the plugin's own number space and the name's checksum
          checksum = [Zlib.crc32(key)].pack('L').unpack1('l')
          ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{NAMESPACE}, #{checksum})")
        end
        block.call
      end
    end

    def self.postgres?
      ActiveRecord::Base.connection.adapter_name.to_s.downcase.start_with?('postgres')
    end

    # Tags created by the issue, project and time entry forms, bulk edit and the API go through
    # find_or_create_all_with_like_by_name; the lock goes around it so those paths cannot create "bug" and "BUG"
    # together either.
    module TagLookup
      def find_or_create_all_with_like_by_name(*list)
        RfFluxTags::NameLock.with(list) { super }
      end
    end

    def self.apply!
      tag = ActsAsTaggableOn::Tag
      singleton = tag.singleton_class
      return if singleton.include?(TagLookup)

      singleton.prepend(TagLookup)
    end
  end
end
