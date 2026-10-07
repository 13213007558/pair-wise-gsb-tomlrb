# frozen-string-literal: true

module Tomlrb
  class Handler
    attr_reader :output, :symbolize_keys

    def initialize(**options)
      @output = {}
      @current = @output
      @stack = []
      @current_table = []
      @keys = Keys.new
      @statement_line = nil
      @symbolize_keys = options[:symbolize_keys]
    end

    def audit_report
      @keys.report
    end

    def set_context(identifiers, is_array_of_tables: false)
      if identifiers.empty?
        raise ParseError, 'Array needs a name'
      end

      @current_table = identifiers.dup
      @keys.add_table_key identifiers, is_array_of_tables, line: @statement_line
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
      @keys.add_pair_key k, @current_table, line: @statement_line
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
        keys.add_pair_key inline_array, [], line: @statement_line

        inline_array.each_with_index do |inline_key, inline_index|
          inline_key = inline_key.to_sym if @symbolize_keys
          last_key = inline_index == inline_array.size - 1

          if last_key
            if current[inline_key].nil?
              current[inline_key] = value
            else
              raise ParseError, "Inline key #{inline_key} is already used"
            end
          else
            current[inline_key] ||= {}
            current = current[inline_key]
          end
        end
      end

      push(merged_inline)
    end

    def start_(type, line: nil)
      @statement_line = line if line
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

  # A single node in the declaration tree built while parsing.
  #
  # Every table found in a document gets exactly one TableDeclaration per
  # scope, recording how its semantic identity was established:
  #
  # - +:implicit+ -- parent table auto-created by a child declaration
  #   ([a.b] implicitly creates +a+). May later be explicitly declared.
  # - +:explicit+ -- declared with a [table] header.
  # - +:dotted+ -- created and defined by a dotted key (a.b = 1 defines +a+).
  #   Cannot be redeclared with a header, but new sub-tables may be
  #   declared underneath it.
  # - +:array+ -- an array of tables established by [[table]] headers.
  # - +:element+ -- one element of an array of tables; each element opens a
  #   fresh scope so sibling elements never conflict with each other.
  # - +:value+ -- a plain key/value pair leaf (not a table).
  class TableDeclaration
    KIND_DESCRIPTIONS = {
      implicit: 'implicit parent table',
      explicit: 'explicit table',
      dotted: 'dotted-key table',
      array: 'array of tables',
      element: 'array-of-tables element',
      value: 'value'
    }.freeze

    attr_reader :key, :kind, :line, :defined_line, :parent, :children, :elements

    def initialize(key, kind, line, parent = nil)
      @key = key
      @kind = kind
      @line = line
      @defined_line = kind == :implicit ? nil : line
      @parent = parent
      @children = {}
      @elements = []
    end

    def describe
      KIND_DESCRIPTIONS.fetch(kind)
    end

    # Line at which the current semantic identity was established.
    def formation_line
      defined_line || line
    end

    def path
      keys = []
      node = self
      while node&.key
        keys.unshift(node.key) unless node.kind == :element
        node = node.parent
      end
      keys
    end

    # A [table] header arriving after the table was implicitly created as a
    # parent is legal: the implicit declaration is upgraded in place.
    def mark_explicit(line)
      @kind = :explicit
      @defined_line = line
    end

    # A dotted key traversing an implicit parent defines it (a.b.c = 1 under
    # an implicit +a.b+ defines +a.b+), so a later [a.b] header conflicts.
    def mark_dotted(line)
      @kind = :dotted
      @defined_line = line
    end

    def add_element(line)
      element = self.class.new(key, :element, line, self)
      elements << element
      element
    end

    # Scope into which nested declarations of the current document position
    # are recorded: the latest element for arrays, the table itself otherwise.
    def current_scope
      kind == :array ? elements.last : self
    end
  end

  # Declaration audit shared by Tomlrb.parse and Tomlrb.audit.
  #
  # Tracks how every table in the document was formed and diagnoses duplicate
  # definitions, pointing at both the declaration that first established the
  # semantic identity and the conflicting declaration.
  class Keys
    TABLE_KINDS = %i[implicit explicit dotted array element].freeze

    REPORT_KINDS = {
      implicit: :implicit,
      explicit: :explicit,
      dotted: :dotted,
      array: :array_of_tables,
      element: :array_element
    }.freeze

    def initialize
      @root = TableDeclaration.new(nil, :explicit, nil)
      @declarations = []
    end

    def add_table_key(keys, is_array_of_tables = false, line: nil)
      scope = @root
      keys.each_with_index do |key, index|
        last = index == keys.length - 1
        declaration = scope.children[key]
        if last
          scope = declare_table_leaf(scope, declaration, key, is_array_of_tables, line)
        else
          declaration ||= record(scope, key, :implicit, line)
          unless %i[implicit explicit dotted array].include?(declaration.kind)
            raise_conflict(declaration, :explicit, line)
          end
          scope = declaration.current_scope
        end
      end
    end

    def add_pair_key(keys, context, line: nil)
      scope = @root
      context.each do |key|
        scope = scope.children[key].current_scope
      end
      keys.each_with_index do |key, index|
        last = index == keys.length - 1
        declaration = scope.children[key]
        if last
          raise_conflict(declaration, :value, line) if declaration
          scope.children[key] = TableDeclaration.new(key, :value, line, scope)
        else
          case declaration&.kind
          when nil
            declaration = record(scope, key, :dotted, line)
          when :dotted
            # already defined by an earlier dotted key; nothing to do
          when :implicit
            declaration.mark_dotted(line)
          else
            raise_conflict(declaration, :dotted, line)
          end
          scope = declaration.current_scope
        end
      end
    end

    # Audit report explaining how each table in the document was formed.
    def report
      entries = @declarations.map do |declaration|
        AuditReport::TableEntry.new(declaration.path, REPORT_KINDS.fetch(declaration.kind), declaration.formation_line)
      end
      AuditReport.new(entries)
    end

    private

    def declare_table_leaf(scope, declaration, key, is_array_of_tables, line)
      if is_array_of_tables
        if declaration.nil?
          declaration = record(scope, key, :array, line)
        elsif declaration.kind != :array
          raise_conflict(declaration, :array, line)
        end
        record_declaration(declaration.add_element(line))
        declaration
      else
        case declaration&.kind
        when nil
          record(scope, key, :explicit, line)
        when :implicit
          declaration.mark_explicit(line)
          declaration
        else
          raise_conflict(declaration, :explicit, line)
        end
      end
    end

    def record(scope, key, kind, line)
      record_declaration(scope.children[key] = TableDeclaration.new(key, kind, line, scope))
    end

    def record_declaration(declaration)
      @declarations << declaration if TABLE_KINDS.include?(declaration.kind)
      declaration
    end

    def raise_conflict(declaration, new_kind, line)
      raise Key::KeyConflict.new(
        path: declaration.path,
        existing_kind: declaration.kind,
        existing_line: declaration.formation_line,
        new_kind: new_kind,
        new_line: line
      )
    end
  end

  # Audit report returned by Tomlrb.audit, explaining how each table in the
  # document was formed.
  class AuditReport
    TableEntry = Struct.new(:path, :kind, :line)

    include Enumerable

    attr_reader :tables

    def initialize(tables)
      @tables = tables
    end

    def each(&block)
      @tables.each(&block)
    end

    def find(path)
      path = path.split('.') if path.is_a?(String)
      @tables.find { |entry| entry.path == path }
    end
  end

  class Key
    # Raised when a declaration conflicts with the semantic identity a
    # previous declaration already established. Carries both locations.
    class KeyConflict < ParseError
      attr_reader :path, :existing_kind, :existing_line, :new_kind, :new_line

      def initialize(path:, existing_kind:, existing_line:, new_kind:, new_line:)
        @path = path
        @existing_kind = existing_kind
        @existing_line = existing_line
        @new_kind = new_kind
        @new_line = new_line
        super(build_message)
      end

      private

      def build_message
        message = "Duplicate declaration of '#{path.join('.')}': "
        message << "first defined as #{TableDeclaration::KIND_DESCRIPTIONS.fetch(existing_kind)}"
        message << " at line #{existing_line}" if existing_line
        message << ", cannot be redefined as #{TableDeclaration::KIND_DESCRIPTIONS.fetch(new_kind)}"
        message << " at line #{new_line}" if new_line
        message
      end
    end
  end
end
