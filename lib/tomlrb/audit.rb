# frozen-string-literal: true

module Tomlrb
  # Records how one table in a TOML document was formed.
  #
  # +path+ is the array of key segments from the document root, +kind+ is
  # one of :implicit (parent created by a child declaration), :explicit
  # ([table] header), :dotted (table created by dotted keys) or
  # :array_of_tables ([[table]] header, one record per element), and +line+
  # is the 1-based line where that formation happened.
  TableFormation = Struct.new(:path, :kind, :line) do
    def to_s
      location = line ? " at line #{line}" : ''
      "#{path.join('.')} (#{kind}#{location})"
    end
  end

  # Result of Tomlrb.audit: the parsed document plus the audit trail
  # explaining how each table was formed.
  class AuditReport
    attr_reader :output, :formations

    def initialize(output, formations)
      @output = output
      @formations = formations
    end
  end

  # Declaration audit tree shared by Tomlrb.parse and Tomlrb.audit.
  #
  # Tracks the semantic identity of every table (implicit parent, explicit
  # table, table created by dotted keys, array of tables) instead of a flat
  # set of "seen" paths, so that legal late declarations of parent tables
  # stay legal and same-named tables under different array-of-tables
  # elements are not mistaken for duplicates.
  class Keys
    attr_reader :formations

    def initialize
      @root = Key.new(nil, :root)
      @formations = []
    end

    def add_table_key(keys, is_array_of_tables = false, line: nil)
      node = @root
      keys.each_with_index do |key, index|
        node, event = if index == keys.length - 1
                        node.declare_table(key, is_array_of_tables, line)
                      else
                        node.descend(key, line)
                      end
        record_formation(node, event, line)
      end
    end

    def add_pair_key(keys, context, line: nil)
      node = @root
      context.each do |key|
        node, event = node.descend(key, line)
        record_formation(node, event, line)
      end
      keys.each_with_index do |key, index|
        node, event = if index == keys.length - 1
                        node.declare_pair(key, line)
                      else
                        node.descend_dotted(key, line)
                      end
        record_formation(node, event, line)
      end
    end

    private

    def record_formation(node, event, line)
      case event
      when :created
        @formations << TableFormation.new(node.path, node.kind, node.line)
      when :upgraded
        @formations << TableFormation.new(node.path, :explicit, node.declared_line)
      when :element
        @formations << TableFormation.new(node.path, :array_of_tables, line)
      end
    end
  end

  class Key
    class KeyConflict < ParseError; end

    KIND_DESCRIPTIONS = {
      implicit: 'implicit parent table',
      explicit: 'explicit table',
      dotted: 'table defined by dotted keys',
      array_of_tables: 'array of tables',
      pair: 'key/value pair'
    }.freeze

    attr_reader :key, :kind, :line, :declared_line, :elements, :children

    def initialize(key, kind, line = nil, parent = nil)
      @key = key
      @kind = kind
      @line = line
      @declared_line = kind == :explicit ? line : nil
      @elements = kind == :array_of_tables ? 1 : 0
      @parent = parent
      @children = {}
    end

    def path
      @parent ? @parent.path + [@key] : []
    end

    # Walks into a non-final segment of a [table] header or of a pair
    # context, creating an implicit parent table when missing.
    def descend(key, line)
      existed = @children[key]
      if existed.nil?
        node = Key.new(key, :implicit, line, self)
        @children[key] = node
        [node, :created]
      elsif existed.kind == :pair
        existed.conflict_with(:table, line)
      else
        [existed, nil]
      end
    end

    # Walks into a non-final segment of a dotted key, creating a table
    # defined by dotted keys when missing.
    def descend_dotted(key, line)
      existed = @children[key]
      if existed.nil?
        node = Key.new(key, :dotted, line, self)
        @children[key] = node
        [node, :created]
      elsif existed.kind == :dotted
        [existed, nil]
      else
        existed.conflict_with(:dotted, line)
      end
    end

    def declare_table(key, is_array_of_tables, line)
      existed = @children[key]
      return declare_array_element(key, existed, line) if is_array_of_tables

      if existed.nil?
        node = Key.new(key, :explicit, line, self)
        @children[key] = node
        [node, :created]
      elsif existed.kind == :implicit
        existed.declare_explicitly(line)
        [existed, :upgraded]
      else
        existed.conflict_with(:explicit, line)
      end
    end

    def declare_pair(key, line)
      existed = @children[key]
      if existed.nil?
        node = Key.new(key, :pair, line, self)
        @children[key] = node
        [node, nil]
      else
        existed.conflict_with(:pair, line)
      end
    end

    def declare_explicitly(line)
      @kind = :explicit
      @declared_line = line
    end

    def add_element(_line)
      @elements += 1
      @children.clear
    end

    def conflict_with(new_kind, new_line)
      first_line = declared_line || line
      first = first_line ? "first established as #{kind_description} at line #{first_line}" : "already established as #{kind_description}"
      conflicting = new_line ? " at line #{new_line}" : ''
      raise KeyConflict, "Key '#{key}' #{first}; conflicting #{KIND_DESCRIPTIONS.fetch(new_kind, new_kind)} declaration#{conflicting}"
    end

    private

    def declare_array_element(key, existed, line)
      if existed.nil?
        node = Key.new(key, :array_of_tables, line, self)
        @children[key] = node
        [node, :created]
      elsif existed.kind == :array_of_tables
        existed.add_element(line)
        [existed, :element]
      else
        existed.conflict_with(:array_of_tables, line)
      end
    end

    def kind_description
      KIND_DESCRIPTIONS.fetch(@kind, @kind.to_s)
    end
  end
end
