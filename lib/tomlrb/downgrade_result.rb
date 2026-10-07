# frozen_string_literal: true

module Tomlrb
  class GenerationError < StandardError
    attr_reader :path, :reason

    def initialize(path, reason)
      @path = path
      @reason = reason
      super("#{path}: #{reason}")
    end
  end

  class DowngradeError < GenerationError; end

  class DowngradeResult
    attr_reader :output, :errors

    def initialize(output: nil, errors: [])
      @output = output
      @errors = errors
    end

    def success?
      errors.empty?
    end
  end

end
