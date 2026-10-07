# frozen-string-literal: true

require 'time'
require 'stringio'
require 'tomlrb/version'
require 'tomlrb/local_date_time'
require 'tomlrb/local_date'
require 'tomlrb/local_time'
require 'tomlrb/string_utils'
require 'tomlrb/scanner'
require 'tomlrb/parser'
require 'tomlrb/handler'
require 'tomlrb/generator'
require 'tomlrb/downgrade_result'

module Tomlrb
  class ParseError < StandardError; end

  SUPPORTED_VERSIONS = %w[1.0 1.1].freeze

  # Parses a valid TOML string into its Ruby data structure
  #
  # @param string_or_io [String, StringIO] the content
  # @param options [Hash] the options hash
  # @option options [Boolean] :symbolize_keys (false) whether to return the keys as symbols or strings
  # @option options [String] :version ("1.0") TOML version to parse
  # @return [Hash] the Ruby data structure represented by the input
  def self.parse(string_or_io, **options)
    io = string_or_io.is_a?(String) ? StringIO.new(string_or_io) : string_or_io
    scanner = Scanner.new(io, version: options.fetch(:version, '1.0'))
    parser = Parser.new(scanner, **options)
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

  # Serializes a Ruby data structure as TOML.
  #
  # @param data [Hash] the data structure
  # @param options [Hash] the options hash
  # @option options [String] :target_version ("1.0") target TOML version
  # @return [String] the generated TOML document
  def self.dump(data, **options)
    target_version = options.delete(:target_version) { options.delete(:version) { '1.0' } }
    Generator.generate(data, target_version: target_version)
  end

  class << self
    alias generate dump
  end

  # Parses TOML and serializes the resulting value for a target TOML version.
  #
  # @param string_or_io [String, StringIO] the content
  # @param options [Hash] the options hash
  # @option options [String] :source_version ("1.1") source TOML version
  # @option options [String] :from ("1.1") alias for :source_version
  # @option options [String] :target_version ("1.0") target TOML version
  # @option options [String] :to ("1.0") alias for :target_version
  # @return [DowngradeResult] the generated document or path-scoped errors
  def self.downgrade(string_or_io, **options)
    source_version = options.delete(:source_version) { options.delete(:from) { '1.1' } }
    target_version = options.delete(:target_version) { options.delete(:to) { '1.0' } }
    data = parse(string_or_io, **options.merge(version: source_version))
    Generator.try_generate(data, target_version: target_version)
  end

  class << self
    alias downgrade_to downgrade
  end

  # Like {.downgrade}, but raises the first generation error.
  #
  # @return [String] the generated TOML document
  def self.downgrade!(string_or_io, **options)
    result = downgrade(string_or_io, **options)
    return result.output if result.success?

    error = result.errors.first
    raise DowngradeError.new(error[:path], error[:reason])
  end

  class << self
    alias downgrade_to! downgrade!
  end
end
