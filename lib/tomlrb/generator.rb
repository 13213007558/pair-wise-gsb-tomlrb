# frozen_string_literal: true

require_relative 'downgrade_result'

module Tomlrb
  class Generator
    SIGNED_64_BIT_MIN = -(2 ** 63)
    SIGNED_64_BIT_MAX = (2 ** 63) - 1

    def self.generate(data, target_version: '1.0', version: nil)
      new(target_version: version || target_version).generate(data)
    end

    def self.try_generate(data, target_version: '1.0', version: nil)
      generator = new(target_version: version || target_version)
      generator.collect(data)
    end

    def initialize(target_version: '1.0')
      @target_version = target_version.to_s
      @lines = []

      unless %w[1.0 1.1].include?(@target_version)
        raise ArgumentError, "Unsupported TOML version: #{@target_version}"
      end
    end

    def generate(data)
      unless data.is_a?(Hash)
        raise GenerationError.new('$', 'TOML documents must be a table')
      end

      validate_value(data, [])
      write_table(data, [])
      output
    end

    def collect(data)
      errors = []
      gather_errors(data, [], errors)
      return DowngradeResult.new(errors: errors) unless errors.empty?

      validate_value(data, [])
      write_table(data, [])
      DowngradeResult.new(output: output)
    end

    def output
      @lines.empty? ? '' : "#{@lines.join("\n")}\n"
    end

    private

    def write_table(table, path)
      scalars = {}
      subtables = {}

      table.each do |key, value|
        key = normalized_key(key, path)

        case value
        when Hash
          subtables[key] = value
        when Array
          scalars[key] = value
        else
          scalars[key] = value
        end

        validate_value(value, append_path(path, key))
      end

      scalars.each do |key, value|
        @lines << "#{format_key(key)} = #{format_value(value, append_path(path, key))}"
      end

      subtables.each do |key, value|
        child_path = append_path(path, key)
        @lines << '' unless @lines.empty?
        @lines << "[#{format_key_path(child_path)}]"
        write_table(value, child_path)
      end
    end

    def validate_value(value, path)
      case value
      when nil
        error_path(path, 'nil cannot be represented in TOML')
      when String
        error_path(path, 'string contains invalid or incomplete UTF-8') unless value.valid_encoding?
      when Integer
        if @target_version == '1.0' && !value.between?(SIGNED_64_BIT_MIN, SIGNED_64_BIT_MAX)
          error_path(path, 'integer is outside the signed 64-bit range supported by TOML 1.0')
        end
      when Float, Time, LocalDateTime, LocalDate, LocalTime, true, false
        nil
      when Hash
        value.each do |key, entry|
          key = normalized_key(key, path)
          validate_value(entry, append_path(path, key))
        end
      when Array
        value.each_with_index do |entry, index|
          validate_value(entry, append_path(path, index))
        end
      else
        error_path(path, "#{value.class} cannot be represented in TOML")
      end
    end

    def normalized_key(key, path)
      return key.to_s if key.is_a?(String) || key.is_a?(Symbol)

      error_path(path, 'table keys must be strings')
    end

    def gather_errors(value, path, errors)
      case value
      when nil
        errors << error_entry(path, 'nil cannot be represented in TOML')
      when String
        unless value.valid_encoding?
          errors << error_entry(path, 'string contains invalid or incomplete UTF-8')
        end
      when Integer
        if @target_version == '1.0' && !value.between?(SIGNED_64_BIT_MIN, SIGNED_64_BIT_MAX)
          errors << error_entry(path, 'integer is outside the signed 64-bit range supported by TOML 1.0')
        end
      when Float, Time, LocalDateTime, LocalDate, LocalTime, true, false
        nil
      when Hash
        value.each do |key, entry|
          unless key.is_a?(String) || key.is_a?(Symbol)
            errors << error_entry(path, 'table keys must be strings')
          end
          key_path = key.is_a?(String) || key.is_a?(Symbol) ? append_path(path, key.to_s) : path
          gather_errors(entry, key_path, errors)
        end
      when Array
        value.each_with_index do |entry, index|
          gather_errors(entry, append_path(path, index), errors)
        end
      else
        errors << error_entry(path, "#{value.class} cannot be represented in TOML")
      end
    end

    def format_value(value, path)
      case value
      when String then format_string(value)
      when Integer then value.to_s
      when Float then format_float(value)
      when true then 'true'
      when false then 'false'
      when LocalDateTime then value.to_s
      when LocalDate then value.to_s
      when LocalTime then value.to_s
      when Time then format_time(value)
      when Array then format_array(value, path)
      when Hash then format_inline_table(value, path)
      else
        error_path(path, "#{value.class} cannot be represented in TOML")
      end
    end

    def format_array(value, path)
      formatted = value.each_with_index.map do |entry, index|
        format_value(entry, append_path(path, index))
      end
      "[#{formatted.join(', ')}]"
    end

    def format_inline_table(value, path)
      pairs = value.map do |key, entry|
        key = normalized_key(key, path)
        "#{format_key(key)} = #{format_value(entry, append_path(path, key))}"
      end
      "{#{pairs.join(', ')}}"
    end

    def format_float(value)
      if value.nan?
        'nan'
      elsif value.infinite?
        value.positive? ? 'inf' : '-inf'
      else
        value.to_s
      end
    end

    def format_time(value)
      offset = value.utc_offset
      sign = offset.negative? ? '-' : '+'
      absolute_offset = offset.abs
      zone = "#{sign}#{format_two_digits(absolute_offset / 3600)}:#{format_two_digits((absolute_offset % 3600) / 60)}"
      value.strftime('%Y-%m-%dT%H:%M:') + format_seconds(value) + zone
    end

    def format_seconds(value)
      seconds = format_two_digits(value.sec)
      subsecond = value.subsec
      return seconds if subsecond.zero?

      "#{seconds}.#{decimal_fraction(subsecond)}"
    end

    def decimal_fraction(value)
      numerator = value.numerator
      denominator = value.denominator
      digits = []
      until numerator.zero?
        numerator *= 10
        digits << numerator / denominator
        numerator %= denominator
      end
      digits.join
    end

    def format_two_digits(value)
      format('%02d', value)
    end

    def format_string(value)
      escaped = value.gsub(/[\u0000-\u001f\u007f"\\]/) do |character|
        case character
        when '\\' then '\\\\'
        when '"' then '\\"'
        when "\b" then '\b'
        when "\t" then '\t'
        when "\n" then '\n'
        when "\f" then '\f'
        when "\r" then '\r'
        else
          format('\u%04X', character.ord)
        end
      end
      %("#{escaped}")
    end

    def format_key(key)
      format_string(key.to_s)
    end

    def format_key_path(path)
      path.map { |key| format_key(key.to_s) }.join('.')
    end

    def append_path(path, key)
      path + [key]
    end

    def error_path(path, reason)
      raise GenerationError.new(format_error_path(path), reason)
    end

    def error_entry(path, reason)
      {path: format_error_path(path), reason: reason}
    end

    def format_error_path(path)
      return '$' if path.empty?

      path.each_with_object(+'$') do |key, result|
        if key.is_a?(Integer)
          result << "[#{key}]"
        else
          result << '.'
          result << key.to_s
        end
      end
    end
  end
end
