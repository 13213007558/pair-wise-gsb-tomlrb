# frozen-string-literal: true

require 'time'
require 'stringio'
require 'tomlrb/version'
require 'tomlrb/local_date_time'
require 'tomlrb/local_date'
require 'tomlrb/local_time'
require 'tomlrb/string_utils'
require 'tomlrb/version_support'
require 'tomlrb/scanner'
require 'tomlrb/parser'
require 'tomlrb/handler'
require 'tomlrb/downgrader'

module Tomlrb
  class ParseError < StandardError; end

  # Parses a valid TOML string into its Ruby data structure
  #
  # @param string_or_io [String, StringIO] the content
  # @param options [Hash] the options hash
  # @option options [Boolean] :symbolize_keys (false) whether to return the keys as symbols or strings
  # @return [Hash] the Ruby data structure represented by the input
  def self.parse(string_or_io, **options)
    io = string_or_io.is_a?(String) ? StringIO.new(string_or_io) : string_or_io
    version = normalize_version(options[:version] || '1.0.0')
    scanner = Scanner.new(io, version: version)
    parser = Parser.new(scanner, **options, version: version)
    begin
      handler = parser.parse
    rescue Racc::ParseError => e
      raise ParseError, e.message
    end

    handler.output
  end

  # Reads a file content and parses it into its Ruby data structure
  #
  # @param path [String] the path to the file
  # @param options [Hash] the options hash
  # @option options [Boolean] :symbolize_keys (false) whether to return the keys as symbols or strings
  # @return [Hash] the Ruby data structure represented by the input
  def self.load_file(path, **options)
    # By default Ruby sets the external encoding of an IO object to the
    # default external encoding. The default external encoding is set by
    # locale encoding or the interpreter -E option.
    tmp = File.read(path, encoding: 'utf-8')
    Tomlrb.parse(tmp, **options)
  end

  def self.dump(data, **options)
    target_version = normalize_version(options[:target_version] || options[:version] || '1.0.0')
    raise VersionError, 'Tomlrb.dump currently supports TOML 1.0.0' unless target_version == '1.0.0'

    Downgrader.new.dump(data)
  end

  def self.dump_1_0(data, **options)
    dump(data, **options, target_version: '1.0.0')
  end
  class << self
    alias generate dump
    alias to_toml dump
  end

  def self.downgrade(string_or_io, target_version: '1.0.0', **options)
    source_version = normalize_version(options[:source_version] || options[:version] || '1.1.0')
    target = normalize_version(target_version)
    raise VersionError, 'downgrade target must be TOML 1.0.0' unless target == '1.0.0'

    data = parse(string_or_io, symbolize_keys: options[:symbolize_keys], version: source_version)
    dump(data, target_version: target, symbolize_keys: options[:symbolize_keys])
  end

  def self.downgrade_to_1_0(string_or_io, **options)
    downgrade(string_or_io, **options, target_version: '1.0.0')
  end

  def self.parse_as(string_or_io, version, **options)
    parse(string_or_io, **options, version: version)
  end
end
