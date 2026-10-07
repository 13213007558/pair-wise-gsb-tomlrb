# frozen-string-literal: true

require 'tomlrb/generated_parser'

class Tomlrb::Parser < Tomlrb::GeneratedParser

  def initialize(tokenizer, **options)
    @tokenizer = tokenizer
    @handler   = Tomlrb::Handler.new(**options)
    super()
  end

  def next_token
    token = @tokenizer.next_token
    @handler.scanner_line = @tokenizer.token_line if token
    token
  end

  def parse
    do_parse
    @handler
  end
end
