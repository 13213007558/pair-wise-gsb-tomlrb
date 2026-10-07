# frozen-string-literal: true

module Tomlrb
  class StringUtils
    SPECIAL_CHARS = {
      '\\t'  => "\t",
      '\\b'  => "\b",
      '\\f'  => "\f",
      '\\n'  => "\n",
      '\\r'  => "\r",
      '\\"'  => '"',
      '\\\\' => '\\',
      '\\e'  => "\e"
    }.freeze

    def self.multiline_replacements(str)
      strip_spaces(str).gsub(/\\+\s*\n\s*/) do |matched|
        if matched.match(/\\+/)[0].length.odd?
          matched.gsub(/\\\s*\n\s*/, '')
        else
          matched
        end
      end
    end

    def self.replace_escaped_chars(str, version: '1.0')
      str.gsub(/\\(u[\da-fA-F]{4}|U[\da-fA-F]{8}|x[\da-fA-F]{2}|x|.)/) do |m|
        if m.start_with?('\\x')
          if version.to_s != '1.1'
            raise Tomlrb::ParseError.new("Escape sequence #{m} is only supported in TOML 1.1")
          end
          if m == '\\x'
            raise Tomlrb::ParseError.new('Escape sequence \\x must be followed by two hexadecimal digits')
          end

          m[2..-1].to_i(16).chr(Encoding::UTF_8)
        elsif m == '\\e'
          raise Tomlrb::ParseError.new('Escape sequence \\e is only supported in TOML 1.1') unless version.to_s == '1.1'

          SPECIAL_CHARS[m]
        elsif m.size == 2
          SPECIAL_CHARS[m] || (raise Tomlrb::ParseError.new "Escape sequence #{m} is reserved")
        else
          codepoint = m[2..-1].to_i(16)
          if codepoint >= 0xD800 && codepoint <= 0xDFFF
            raise Tomlrb::ParseError.new("Escape sequence #{m} is not a Unicode scalar value")
          end

          codepoint.chr(Encoding::UTF_8)
        end
      end
    end

    def self.strip_spaces(str)
      str[0] = '' if str[0] == "\n"
      str
    end
  end
end
