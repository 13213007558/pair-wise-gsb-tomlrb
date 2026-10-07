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
require 'tomlrb/audit'
require 'tomlrb/handler'

module Tomlrb
  class ParseError < StandardError; end

  # Parses a valid TOML string into its Ruby data structure
  #
  # @param string_or_io [String, StringIO] the content
  # @param options [Hash] the options hash
  # @option options [Boolean] :symbolize_keys (false) whether to return the keys as symbols or strings
  # @return [Hash] the Ruby data structure represented by the input
  def self.parse(string_or_io, **options)
    parse_with_handler(string_or_io, **options).output
  end

  # Parses a TOML string and audits how every table was formed
  #
  # Tables are classified as implicit parents, explicit tables, tables
  # created by dotted keys, or array-of-tables elements. Duplicate
  # definitions are diagnosed with both the line where the key first
  # established its semantic identity and the line of the conflicting
  # declaration.
  #
  # @param string_or_io [String, StringIO] the content
  # @param options [Hash] the options hash
  # @option options [Boolean] :symbolize_keys (false) whether to return the keys as symbols or strings
  # @return [AuditReport] the parsed output plus the table formation audit trail
  def self.audit(string_or_io, **options)
    handler = parse_with_handler(string_or_io, **options)
    AuditReport.new(handler.output, handler.keys.formations)
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

  def self.parse_with_handler(string_or_io, **options)
    io = string_or_io.is_a?(String) ? StringIO.new(string_or_io) : string_or_io
    scanner = Scanner.new(io)
    parser = Parser.new(scanner, **options)
    begin
      parser.parse
    rescue Racc::ParseError => e
      raise ParseError, e.message
    end
  end
  private_class_method :parse_with_handler
end
