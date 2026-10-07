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
      /"{3}((?:[^\u0000-\u0008\u000A-\u001F\u007F]|\r\n|\n)*?(?<!\\)"{3,5})/m.freeze
    STRING_LITERAL =
      /(')(?:\\?[^\u0000-\u0008\u000A-\u001F\u007F])*?\1/.freeze
    STRING_LITERAL_MULTI =
      /'{3}((?:[^\u0000-\u0008\u000A-\u001F\u007F]|\r\n|\n)*?'{3,5})/m.freeze
    DATETIME =
      /(-?\d{4})-([01]\d)-([0-3]\d)(?:(?:[tT]|\s)([0-2]\d):((?>[0-5]\d)):([0-6]\d(?:\.\d+)?)(z|[-+][01]\d:\d{2})?)?(?![A-Za-z0-9_-])/i.freeze
    DATETIME_1_1 =
      /(-?\d{4})-([01]\d)-([0-3]\d)(?:(?:[tT]|\s)([0-2]\d):(?>([0-5]\d))(?::([0-6]\d(?:\.\d+)?))?(z|[-+][01]\d:\d{2})?)?(?![A-Za-z0-9_-])/i.freeze
    LOCAL_TIME =
      /([0-2]\d):([0-5]\d)(?::([0-6]\d(?:\.\d+)?))?(?![A-Za-z0-9_:.+-])/
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
    INLINE_TRAILING_COMMA =
      /\A[ \t]*(?:(?=\})|(?:#[^\r\n]*)?\r?\n(?:[ \t]*(?:#[^\r\n]*)?\r?\n)*[ \t]*(?=\}))/

    def initialize(io, version: '1.0')
      @version = version.to_s
      unless %w[1.0 1.1].include?(@version)
        raise ArgumentError, "Unsupported TOML version: #{@version}"
      end

      @ss = StringScanner.new(io.read)
      @eos = false
      @containers = []
    end

    def next_token
      case
      when @ss.scan(SPACED_ARRAY_OF_TABLES_START) then raise ParseError.new('Array of tables has spaces in starting brackets')
      when @ss.scan(SPACED_ARRAY_OF_TABLES_END) then raise ParseError.new('Array of tables has spaces in ending brackets')
      when @ss.scan(SPACED_ARRAY_OF_TABLES_BOTH) then raise ParseError.new('Array of tables has spaces in starting and ending brackets')
      when @ss.check(/[\[\]{}]/) then process_container_bracket
      when @ss.check(',') && inside_inline_table? then process_inline_comma
      when @ss.scan(NEWLINE)
        if @version == '1.0' && inside_inline_table?
          raise ParseError.new('Newlines are not allowed in inline tables before TOML 1.1')
        end
        [:NEWLINE, nil]
      when @ss.scan(SPACE) then next_token
      when @ss.scan(COMMENT) then next_token
      when @ss.scan(datetime_pattern) then process_datetime
      when @ss.scan(LOCAL_TIME) then process_local_time
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
      else x = @ss.getch; [x, x]
      end
    end

    def allow_1_1?
      @version == '1.1'
    end

    def process_datetime
      offset = @ss[7].gsub(/[zZ]/, '+00:00') if @ss[7]
      args = [@ss[0], @ss[1], @ss[2], @ss[3], @ss[4], @ss[5], @ss[6], offset]
      args[5] ||= '0' if args[3]
      [:DATETIME, args]
    end

    def process_local_time
      if @version == '1.0' && @ss[3].nil?
        raise ParseError.new('Time without seconds is only supported in TOML 1.1')
      end

      seconds_text = @ss[3] || '0'
      args = [@ss[0], @ss[1], @ss[2], seconds_text.to_f, seconds_text]
      [:LOCAL_TIME, args]
    end

    def process_container_bracket
      bracket = @ss.getch
      case bracket
      when '{', '[' then @containers << bracket
      when '}' then @containers.pop
      when ']' then @containers.pop unless @containers.last == '{'
      end
      [bracket, bracket]
    end

    def process_inline_comma
      @ss.getch
      if @ss.rest.match?(INLINE_TRAILING_COMMA)
        @ss.scan(INLINE_TRAILING_COMMA)
        [:INLINE_TRAILING_COMMA, ',']
      else
        [:INLINE_COMMA, ',']
      end
    end

    def datetime_pattern
      allow_1_1? ? DATETIME_1_1 : DATETIME
    end

    def inside_inline_table?
      @containers.last == '{'
    end

    def process_eos
      return if @eos

      @eos = true
      [:EOS, nil]
    end
  end
end
