# frozen-string-literal: true

module Tomlrb
  class Handler
    attr_reader :output, :symbolize_keys, :keys
    attr_accessor :scanner_line

    def initialize(**options)
      @output = {}
      @current = @output
      @stack = []
      @current_table = []
      @keys = Keys.new
      @symbolize_keys = options[:symbolize_keys]
      @scanner_line = nil
      @header_line = nil
      @assignment_line = nil
    end

    def set_context(identifiers, is_array_of_tables: false)
      if identifiers.empty?
        raise ParseError, 'Array needs a name'
      end

      @current_table = identifiers.dup
      @keys.add_table_key identifiers, is_array_of_tables, line: @header_line
      @current = @output

      deal_with_array_of_tables(identifiers, is_array_of_tables) do |identifierz|
        identifierz.each do |k|
          k = k.to_sym if @symbolize_keys
          if @current[k].is_a?(Array)
            @current = @current[k].last
          else
            @current[k] ||= {}
            @current = @current[k]
          end
        end
      end
    end

    def deal_with_array_of_tables(identifiers, is_array_of_tables)
      if is_array_of_tables
        last_identifier = identifiers.pop
      end

      yield(identifiers)

      if is_array_of_tables
        last_identifier = last_identifier.to_sym if @symbolize_keys
        @current[last_identifier] ||= []
        raise ParseError, "Cannot use key #{last_identifier} for both table and array at once" unless @current[last_identifier].respond_to?(:<<)
        @current[last_identifier] << {}
        @current = @current[last_identifier].last
      end
    end

    def assign(k)
      @keys.add_pair_key k, @current_table, line: @assignment_line
      current = @current
      while (key = k.shift)
        key = key.to_sym if @symbolize_keys
        current = assign_key_path(current, key, k.empty?)
      end
    end

    def push(o)
      @stack << o
    end

    def push_inline(inline_arrays)
      merged_inline = {}
      keys = Keys.new

      inline_arrays.each do |inline_array|
        current = merged_inline
        value = inline_array.pop
        keys.add_pair_key inline_array, [], line: @assignment_line

        inline_array.each_with_index do |inline_key, inline_index|
          inline_key = inline_key.to_sym if @symbolize_keys
          last_key = inline_index == inline_array.size - 1

          if last_key
            if current[inline_key].nil?
              current[inline_key] = value
            else
              raise Key::KeyConflict, "Inline key #{inline_key} is already used"
            end
          else
            current[inline_key] ||= {}
            current = current[inline_key]
          end
        end
      end

      push(merged_inline)
    end

    def start_(type)
      @header_line = @scanner_line if type == :table || type == :array_of_tables
      @assignment_line = @scanner_line if type == :keys || type == :inline_keys
      push([type])
    end

    def end_(type)
      array = []
      while (value = @stack.pop) != [type]
        raise ParseError, 'Unclosed table' if @stack.empty?

        array.unshift(value)
      end
      array
    end

    def validate_value(value)
      if value.nil?
        raise ParseError, 'Value must be present'
      end
    end

    private

    def assign_key_path(current, key, key_emptied)
      existed = current.key?(key)
      raise ParseError, "Cannot overwrite value with key #{key}" if existed && !current[key].is_a?(Hash)
      if key_emptied
        raise ParseError, "Cannot overwrite value with key #{key}" unless current.is_a?(Hash)

        value = @stack.pop
        raise ParseError, "Cannot overwrite value with key #{key}" if current[key].is_a?(Hash) && !value.is_a?(Hash)
        current[key] = value
        return current
      end
      current[key] ||= {}
      current[key]
    end
  end
end
