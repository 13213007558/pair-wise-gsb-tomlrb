# frozen-string-literal: true

require 'strscan'

module Tomlrb
  class Scanner
    COMMENT =
      /#[^\u0000-\u0008\u000A-\u001F\u007F]*/.freeze
    IDENTIFIER =
      /[A-Za-z0-9_-]+/.freeze
    SPACE =
      /[ \t]/.freeze
    NEWLINE =
      /(?:[ \t]*(?:\r?\n)[ \t]*)+/.freeze
    STRING_BASIC =
      /(")(?:\\?[^\u0000-\u0008\u000A-\u001F\u007F\\]|(?:\\[^\u0000-\u0008\u000A-\u001F\u007F]))*?\1/.freeze
    STRING_MULTI =
      /"{3}([^\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]*?(?<!\\)"{3,5})/m.freeze
    STRING_LITERAL =
      /(')(?:\\?[^\u0000-\u0008\u000A-\u001F\u007F])*?\1/.freeze
    STRING_LITERAL_MULTI =
      /'{3}([^\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]*?'{3,5})/m.freeze
    TIME_OFFSET =
      /(?:z|[-+][01]\d:\d{2})/i.freeze
    DATETIME =
      /(-?\d{4})-([01]\d)-([0-3]\d)(?:(?:t|\s)([0-2]\d):([0-5]\d):([0-6]\d(?:\.\d+)?)(#{TIME_OFFSET})?)?/i.freeze
    DATETIME_1_1 =
      /(-?\d{4})-([01]\d)-([0-3]\d)(?:(?:t|\s)([0-2]\d):([0-5]\d)(?::([0-6]\d(?:\.\d+)?))?(#{TIME_OFFSET})?)?/i.freeze
    LOCAL_TIME =
      /([0-2]\d):([0-5]\d):([0-6]\d(?:\.\d+)?)/.freeze
    LOCAL_TIME_1_1 =
      /([0-2]\d):([0-5]\d)(?::([0-6]\d(?:\.\d+)?))?(?![\d.])/.freeze
    FLOAT =
      /[+-]?(?:(?:\d|[1-9](?:_?\d)*)\.\d(?:_?\d)*|\d+(?=[eE]))(?:[eE][+-]?[0-9]+(_[0-9])*[0-9]*)?(?!\w)/.freeze
    FLOAT_KEYWORD =
      /[+-]?(?:inf|nan)\b/.freeze
    INTEGER =
      /[+-]?([1-9](_?\d)*|0)(?![A-Za-z0-9_-]+)/.freeze
    NON_DEC_INTEGER =
      /0(?:x[0-9A-Fa-f](_?[0-9A-Fa-f])*|o[0-7](_?[0-7])*|b[01](_?[01])*)/.freeze
    BOOLEAN =
      /true|false/.freeze
    SPACED_ARRAY_OF_TABLES_START =
      /^\[[ \t]+\[(#{IDENTIFIER}|#{STRING_BASIC}|#{STRING_LITERAL}|#{INTEGER}|#{NON_DEC_INTEGER}|#{FLOAT_KEYWORD}|#{BOOLEAN})\]\]$/.freeze
    SPACED_ARRAY_OF_TABLES_END =
      /^\[\[(#{IDENTIFIER}|#{STRING_BASIC}|#{STRING_LITERAL}|#{INTEGER}|#{NON_DEC_INTEGER}|#{FLOAT_KEYWORD}|#{BOOLEAN})\][ \t]+\]$/.freeze
    SPACED_ARRAY_OF_TABLES_BOTH =
      /^\[[ \t]+\[(#{IDENTIFIER}|#{STRING_BASIC}|#{STRING_LITERAL}|#{INTEGER}|#{NON_DEC_INTEGER}|#{FLOAT_KEYWORD}|#{BOOLEAN})\][ \t]+\]$/.freeze

    def initialize(io, version: '1.0.0')
      @ss = StringScanner.new(io.read)
      @eos = false
      @version = version
      @inline_brackets = []
      @datetime = version == '1.1.0' ? DATETIME_1_1 : DATETIME
      @local_time = version == '1.1.0' ? LOCAL_TIME_1_1 : LOCAL_TIME
    end

    def next_token
      token = scan_inline_trailing_comma
      return token if token

      case
      when @ss.scan(NEWLINE) then inline_newline_or_whitespace
      when @ss.scan(SPACED_ARRAY_OF_TABLES_START) then raise ParseError.new('Array of tables has spaces in starting brackets')
      when @ss.scan(SPACED_ARRAY_OF_TABLES_END) then raise ParseError.new('Array of tables has spaces in ending brackets')
      when @ss.scan(SPACED_ARRAY_OF_TABLES_BOTH) then raise ParseError.new('Array of tables has spaces in starting and ending brackets')
      when @ss.scan(SPACE) then next_token
      when @ss.scan(COMMENT) then next_token
      when @ss.scan(@datetime) then process_datetime
      when @ss.scan(@local_time) then process_local_time
      when text = @ss.scan(STRING_MULTI) then [:STRING_MULTI, text[3..-4]]
      when text = @ss.scan(STRING_BASIC) then [:STRING_BASIC, text[1..-2]]
      when text = @ss.scan(STRING_LITERAL_MULTI) then [:STRING_LITERAL_MULTI, text[3..-4]]
      when text = @ss.scan(STRING_LITERAL) then [:STRING_LITERAL, text[1..-2]]
      when text = @ss.scan(FLOAT) then [:FLOAT, text]
      when text = @ss.scan(FLOAT_KEYWORD) then [:FLOAT_KEYWORD, text]
      when text = @ss.scan(INTEGER) then [:INTEGER, text]
      when text = @ss.scan(NON_DEC_INTEGER) then [:NON_DEC_INTEGER, text]
      when text = @ss.scan(BOOLEAN) then [:BOOLEAN, text]
      when text = @ss.scan(IDENTIFIER) then [:IDENTIFIER, text]
      when @ss.eos? then process_eos
      when @ss.peek(1) == '{' then open_inline_table
      when @ss.peek(1) == '}' then close_inline_table
      when @ss.peek(1) == '[' then open_array
      when @ss.peek(1) == ']' then close_array
      else x = @ss.getch; [x, x]
      end
    end

    def process_datetime
      offset = @ss[7]&.gsub(/[zZ]/, '+00:00')
      second = @ss[6] || '0'
      args = [@ss[0], @ss[1], @ss[2], @ss[3], @ss[4], @ss[5], second, offset]
      [:DATETIME, args]
    end

    def process_local_time
      second = @ss[3] || '0'
      args = [@ss[0], @ss[1], @ss[2], second.to_f]
      [:LOCAL_TIME, args]
    end

    def scan_inline_trailing_comma
      return unless @version == '1.1.0' && @inline_brackets.last == '{' && @ss.peek(1) == ','

      position = @ss.pos
      @ss.getch

      loop do
        if @ss.scan(SPACE) || @ss.scan(COMMENT) || @ss.scan(NEWLINE)
          next
        elsif @ss.peek(1) == '}'
          return [:INLINE_TRAILING_COMMA, ',']
        else
          @ss.pos = position
          return
        end
      end
    end

    def inline_newline_or_whitespace
      if @version == '1.1.0' && @inline_brackets.last == '{'
        [:INLINE_NEWLINE, nil]
      else
        [:NEWLINE, nil]
      end
    end

    def open_inline_table
      character = @ss.getch
      @inline_brackets << '{'
      [character, character]
    end

    def open_array
      character = @ss.getch
      @inline_brackets << '[' unless @inline_brackets.empty?
      [character, character]
    end

    def close_array
      character = @ss.getch
      @inline_brackets.pop if @inline_brackets.last == '['
      [character, character]
    end

    def close_inline_table
      character = @ss.getch
      @inline_brackets.pop if @inline_brackets.last == '{'
      [character, character]
    end

    def process_eos
      return if @eos

      @eos = true
      [:EOS, nil]
    end
  end
end
