# frozen-string-literal: true

module Tomlrb
  class VersionError < ArgumentError; end

  VERSIONS = {
    '1'     => '1.0.0',
    '1.0'   => '1.0.0',
    '1.0.0' => '1.0.0',
    '1.1'   => '1.1.0',
    '1.1.0' => '1.1.0'
  }.freeze

  def self.normalize_version(version)
    normalized = VERSIONS[version.to_s]
    return normalized if normalized

    raise VersionError, "unsupported TOML version: #{version}"
  end
end
