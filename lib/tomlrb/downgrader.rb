# frozen-string-literal: true

module Tomlrb
  class DowngradeError < StandardError
    attr_reader :path, :reason

    def initialize(path, reason)
      @path = path
      @reason = reason
      super("#{path}: #{reason}")
    end
  end

  class Downgrader
    def initialize
      @active_objects = {}
    end

    def dump(data)
      raise TypeError, "expected a Hash, got #{data.class}" unless data.is_a?(Hash)

      @output = +''
      emit_table(data, [])
      @output
    end

    private

    def emit_table(table, path)
      with_object(table, path) do
        pairs, nested = table.partition { |_, value| value.is_a?(Array) || scalar?(value) }
        pairs.each { |key, value| emit_pair(key, value, path) }
        nested.each { |key, value| emit_nested(key, value, path + [key]) }
      end
    end

    def emit_pair(key, value, path)
      @output << "#{format_key(key, path)} = #{format_value(value, path + [key])}\n"
    end

    def emit_nested(key, value, path)
      if value.is_a?(Hash)
        @output << "\n[#{format_key_path(path)}]\n"
        emit_table(value, path)
      else
        unsupported(value, path, "#{value.class} has no TOML table representation")
      end
    end

    def scalar?(value)
      value.nil? ||
        value.is_a?(String) ||
        value.is_a?(Integer) ||
        value.is_a?(Float) ||
        value == true || value == false ||
        value.is_a?(LocalDate) ||
        value.is_a?(LocalDateTime) ||
        value.is_a?(LocalTime) ||
        value.is_a?(Time)
    end

    def format_value(value, path)
      case value
      when nil then unsupported(value, path, 'nil has no TOML representation')
      when String then format_string(value)
      when Integer then format_integer(value, path)
      when Float then format_float(value)
      when true then 'true'
      when false then 'false'
      when LocalDate then value.to_s
      when LocalDateTime then format_local_date_time(value)
      when LocalTime then format_local_time(value)
      when Time then format_time(value, path)
      when Hash then format_inline_table(value, path)
      when Array then format_array(value, path)
      else unsupported(value, path, "#{value.class} has no TOML representation")
      end
    end

    def format_inline_table(table, path)
      with_object(table, path) do
        members = table.map do |key, value|
          "#{format_key(key, path)} = #{format_value(value, path + [key])}"
        end
        "{#{members.join(', ')}}"
      end
    end

    def format_array(array, path)
      with_object(array, path) do
        values = array.each_with_index.map do |value, index|
          format_value(value, path + [index])
        end
        "[#{values.join(', ')}]"
      end
    end

    def format_key(key, path)
      key = key.to_s if key.is_a?(Symbol)
      unless key.is_a?(String)
        unsupported(key, path, "#{key.class} cannot be used as a TOML key")
      end

      return key if bare_key?(key)

      format_string(key)
    end

    def format_key_path(path)
      path.map { |key| format_key(key, []) }.join('.')
    end

    def bare_key?(key)
      key.match?(/\A[A-Za-z0-9_-]+\z/)
    end

    def format_string(value)
      escaped = value.each_char.map do |character|
        case character
        when '\\' then '\\\\'
        when '"' then '\\"'
        when '\b' then '\\b'
        when '\t' then '\\t'
        when '\n' then '\\n'
        when '\f' then '\\f'
        when '\r' then '\\r'
        when '\e' then '\\u001b'
        else
          code = character.ord
          code <= 0x1f || code == 0x7f ? format('\\u%04X', code) : character
        end
      end
      "\"#{escaped.join}\""
    end

    def format_integer(value, path)
      unless value.between?(-9223372036854775808, 9223372036854775807)
        unsupported(value, path, 'integer is outside the TOML 64-bit signed integer range')
      end

      value.to_s
    end

    def format_float(value)
      return 'nan' if value.nan?
      return 'inf' if value.infinite? == 1
      return '-inf' if value.infinite? == -1

      value.to_s
    end

    def format_time(value, path)
      year = value.year
      unless year.between?(0, 9999) && value.utc_offset % 60 == 0
        unsupported(value, path, 'time cannot be represented in TOML 1.0')
      end

      offset = value.utc_offset
      zone = offset.zero? ? 'Z' : format_offset(offset)
      "#{format_local_date_time(value)}#{zone}"
    end

    def format_offset(offset)
      sign = offset.negative? ? '-' : '+'
      absolute = offset.abs
      "#{sign}#{format('%02d', absolute / 3600)}:#{format('%02d', (absolute % 3600) / 60)}"
    end

    def format_local_date_time(value)
      "#{format_date(value.year, value.month, value.day)}T#{format_clock(value)}"
    end

    def format_local_time(value)
      format_clock(value)
    end

    def format_date(year, month, day)
      format('%04d-%02d-%02d', year, month, day)
    end

    def format_clock(value)
      fraction = value.nsec
      suffix = fraction.zero? ? '' : ".#{format('%09d', fraction).sub(/0+\z/, '')}"
      format('%02d:%02d:%02d', value.hour, value.min, value.sec) << suffix
    end

    def with_object(object, path)
      object_id = object.object_id
      if @active_objects[object_id]
        unsupported(object, path, 'cyclic data cannot be represented in TOML')
      end

      @active_objects[object_id] = true
      begin
        yield
      ensure
        @active_objects.delete(object_id)
      end
    end

    def unsupported(_value, path, reason)
      raise DowngradeError.new(format_path(path), reason)
    end

    def format_path(parts)
      return '$' if parts.empty?

      result = +'$'
      parts.each do |part|
        if part.is_a?(Integer)
          result << "[#{part}]"
        else
          result << '.' << part.to_s
        end
      end
      result
    end
  end
end
