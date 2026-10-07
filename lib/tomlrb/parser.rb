# frozen-string-literal: true

require 'tomlrb/generated_parser'

class Tomlrb::Parser < Tomlrb::GeneratedParser

  def initialize(tokenizer, **options)
    @version = options.fetch(:version, '1.0').to_s
    unless %w[1.0 1.1].include?(@version)
      raise ArgumentError, "Unsupported TOML version: #{@version}"
    end

    @tokenizer = tokenizer
    @handler   = Tomlrb::Handler.new(**options)
    super()
  end

  def allow_1_1?
    @version == '1.1'
  end

  def reject_1_1_feature(feature)
    raise ParseError, "#{feature} is only supported in TOML 1.1" unless allow_1_1?
  end

  def parse_seconds(value)
    return 0 if value.nil?
    return value if value.is_a?(Numeric)

    whole, fraction = value.to_s.split('.', 2)
    seconds = whole.to_r
    seconds += Rational(fraction, 10 ** fraction.length) if fraction
    seconds
  end

  def next_token
    @tokenizer.next_token
  end

  def parse
    do_parse
    @handler
  end
end
