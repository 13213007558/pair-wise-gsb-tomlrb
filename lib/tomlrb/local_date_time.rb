# frozen-string-literal: true

require 'forwardable'

module Tomlrb
  class LocalDateTime
    extend Forwardable

    def_delegators :@time, :year, :month, :day, :hour, :min, :sec, :usec, :nsec

    def initialize(year, month, day, hour, min, sec, sec_text = nil) # rubocop:disable Metrics/ParameterLists
      @time = Time.utc(year, month, day, hour, min, sec)
      raise ArgumentError, "Invalid Local Date-Time: #{year}-#{month}-#{day}T#{hour}:#{min}:#{sec}" unless min.to_i == @time.min && hour.to_i == @time.hour && day.to_i == @time.day && month.to_i == @time.month && year.to_i == @time.year

      @sec = decimal_to_seconds(sec)
      @sec_text = sec_text || sec.to_s
    end

    # @param offset [String, Symbol, Numeric, nil] time zone offset.
    #   * when +String+, must be '+HH:MM' format, '-HH:MM' format, 'UTC', 'A'..'I' or 'K'..'Z'. Arguments excluding '+-HH:MM' are supporeted at Ruby >= 2.7.0
    #   * when +Symbol+, must be +:dst+(for summar time for local) or +:std+(for standard time).
    #   * when +Numeric+, it is time zone offset in second.
    #   * when +nil+, local time zone offset is used.
    # @return [Time]
    def to_time(offset = '-00:00')
      return @time if offset == '-00:00'
      Time.new(year, month, day, hour, min, @sec, offset)
    end

    def to_s
      frac_str = fractional_seconds
      @time.strftime('%FT%T') << frac_str
    end

    def ==(other)
      other.is_a?(self.class) &&
        to_time == other.to_time &&
        @sec == other.instance_variable_get(:@sec)
    end

    def inspect
      "#<#{self.class}: #{self}>"
    end

    private

    def fractional_seconds
      return '' unless @sec_text.include?('.')

      ".#{@sec_text.split('.', 2).last}"
    end

    def decimal_to_seconds(value)
      return value if value.is_a?(Numeric)

      whole, fraction = value.to_s.split('.', 2)
      result = whole.to_r
      result += Rational(fraction, 10 ** fraction.length) if fraction
      result
    end
  end
end
