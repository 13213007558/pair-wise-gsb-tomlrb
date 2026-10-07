# frozen-string-literal: true

require 'forwardable'

module Tomlrb
  class LocalTime
    extend Forwardable

    def_delegators :@time, :hour, :min, :sec, :usec, :nsec

    def initialize(hour, min, sec, sec_text = nil)
      @time = Time.utc(0, 1, 1, hour, min, sec)
      raise ArgumentError, "Invalid Local Time: #{hour}-#{min}-#{sec}" unless min.to_i == @time.min && hour.to_i == @time.hour
      @sec = decimal_to_seconds(sec)
      @sec_text = sec_text || sec.to_s
    end

    # @param year [Integer]
    # @param month [Integer]
    # @param day [Integer]
    # @param offset see {LocalDateTime#to_time}
    # @return [Time] the time of the date specified by params
    def to_time(year, month, day, offset = '-00:00')
      Time.new(year, month, day, hour, min, @sec, offset)
    end

    def to_s
      frac_str = @sec_text.include?('.') ? ".#{@sec_text.split('.', 2).last}" : ''
      @time.strftime('%T') << frac_str
    end

    def ==(other)
      other.is_a?(self.class) &&
        @time == other.to_time(0, 1, 1) &&
        @sec == other.instance_variable_get(:@sec)
    end

    def inspect
      "#<#{self.class}: #{self}>"
    end

    private

    def decimal_to_seconds(value)
      return value if value.is_a?(Numeric)

      whole, fraction = value.to_s.split('.', 2)
      result = whole.to_r
      result += Rational(fraction, 10 ** fraction.length) if fraction
      result
    end
  end
end
