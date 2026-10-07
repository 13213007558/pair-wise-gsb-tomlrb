require 'minitest_helper'

describe Tomlrb do
  describe 'declaration audit' do
    describe 'table formation kinds' do
      it 'distinguishes implicit parents, explicit tables, dotted-key tables and arrays of tables' do
        report = Tomlrb.audit(<<~TOML)
          dotted.key = 1
          [explicit.sub]
          [explicit]
          [[arr]]
          [arr.child]
          [[arr]]
        TOML

        _(report.find('explicit').kind).must_equal :explicit
        _(report.find('explicit').line).must_equal 3
        _(report.find('explicit.sub').kind).must_equal :explicit
        _(report.find('explicit.sub').line).must_equal 2
        _(report.find('dotted').kind).must_equal :dotted
        _(report.find('dotted').line).must_equal 1
        _(report.find('arr').kind).must_equal :array_of_tables
        _(report.find('arr').line).must_equal 4
        _(report.find('arr.child').kind).must_equal :explicit
        _(report.find('arr.child').line).must_equal 5
      end

      it 'records implicit parents before they are explicitly declared' do
        report = Tomlrb.audit("[x.y.z.w]\n[x]\n")

        _(report.find('x').kind).must_equal :explicit
        _(report.find('x').line).must_equal 2
        _(report.find('x.y').kind).must_equal :implicit
        _(report.find('x.y').line).must_equal 1
        _(report.find('x.y.z.w').kind).must_equal :explicit
      end

      it 'records one entry per array-of-tables element' do
        report = Tomlrb.audit("[[a]]\n[[a]]\n[[a]]\n")

        elements = report.tables.select { |entry| entry.kind == :array_element }
        _(elements.size).must_equal 3
        _(elements.map(&:line)).must_equal [1, 2, 3]
        _(elements.map(&:path)).must_equal [%w[a], %w[a], %w[a]]
      end

      it 'keeps tables scoped to their array-of-tables element' do
        report = Tomlrb.audit(<<~TOML)
          [[fruit]]
          [fruit.physical]
          [[fruit]]
          [fruit.physical]
        TOML

        physical = report.tables.select { |entry| entry.path == %w[fruit physical] }
        _(physical.size).must_equal 2
        _(physical.map(&:line)).must_equal [2, 4]
      end
    end

    describe 'legal declarations rejected by the previous implementation' do
      it 'allows a sub-table under a table created by a dotted key' do
        _(Tomlrb.parse("t.x = 1\n[t.u]\n")).must_equal('t' => { 'x' => 1, 'u' => {} })
      end

      it 'allows an array of tables under a table created by a dotted key' do
        _(Tomlrb.parse("t.x = 1\n[[t.u]]\n")).must_equal('t' => { 'x' => 1, 'u' => [{}] })
      end

      it 'allows a sibling sub-table of a dotted-key table' do
        _(Tomlrb.parse("a.b = 1\n[a.c]\nd = 2\n")).must_equal('a' => { 'b' => 1, 'c' => { 'd' => 2 } })
      end
    end

    describe 'legal declarations kept legal' do
      it 'allows declaring a parent table after its children' do
        _(Tomlrb.parse("[x.y.z.w]\n[x]\n")).must_equal('x' => { 'y' => { 'z' => { 'w' => {} } } })
      end

      it 'allows the same sub-table name under two array-of-tables elements' do
        result = Tomlrb.parse(<<~TOML)
          [[fruit]]
          [fruit.physical]
          color = "red"
          [[fruit]]
          [fruit.physical]
          color = "green"
        TOML
        _(result['fruit'].map { |f| f['physical']['color'] }).must_equal %w[red green]
      end

      it 'allows the same dotted key under two array-of-tables elements' do
        result = Tomlrb.parse("[[a]]\nb.c = 1\n[[a]]\nb.c = 2\n")
        _(result['a'].map { |e| e['b']['c'] }).must_equal [1, 2]
      end

      it 'allows repeating nested arrays of tables with sub-tables' do
        result = Tomlrb.parse("[[a]]\n[[a.b]]\n[a.b.c]\nx = 1\n[[a]]\n[[a.b]]\n[a.b.c]\nx = 2\n")
        _(result['a'].size).must_equal 2
      end

      it 'allows a dotted key in one element and a header in the next' do
        _(Tomlrb.parse("[[a]]\nb.c = 1\n[[a]]\n[a.b]\n")).must_equal(
          'a' => [{ 'b' => { 'c' => 1 } }, { 'b' => {} }]
        )
      end
    end

    describe 'duplicate diagnosis' do
      it 'points at both the first establishment and the conflicting declaration' do
        error = _{ Tomlrb.parse("[a]\n[a]\n") }.must_raise Tomlrb::Key::KeyConflict
        _(error.path).must_equal %w[a]
        _(error.existing_kind).must_equal :explicit
        _(error.existing_line).must_equal 1
        _(error.new_kind).must_equal :explicit
        _(error.new_line).must_equal 2
        _(error.message).must_include 'line 1'
        _(error.message).must_include 'line 2'
      end

      it 'diagnoses redeclaring a dotted-key table with a header' do
        error = _{ Tomlrb.parse("fruit.apple = 1\n[fruit]\n") }.must_raise Tomlrb::Key::KeyConflict
        _(error.path).must_equal %w[fruit]
        _(error.existing_kind).must_equal :dotted
        _(error.existing_line).must_equal 1
        _(error.new_line).must_equal 2
        _(error.message).must_match(/dotted-key table at line 1.*explicit table at line 2/)
      end

      it 'diagnoses redeclaring a nested dotted-key table' do
        error = _{ Tomlrb.parse("[fruit]\napple.color = 'red'\n[fruit.apple]\n") }
          .must_raise Tomlrb::Key::KeyConflict
        _(error.path).must_equal %w[fruit apple]
        _(error.existing_kind).must_equal :dotted
        _(error.existing_line).must_equal 2
        _(error.new_line).must_equal 3
      end

      it 'diagnoses an implicit parent defined by a dotted key and redeclared' do
        error = _{ Tomlrb.parse("[a.b.c]\n[a]\nb.d = 1\n[a.b]\n") }
          .must_raise Tomlrb::Key::KeyConflict
        _(error.path).must_equal %w[a b]
        _(error.existing_kind).must_equal :dotted
        _(error.existing_line).must_equal 3
        _(error.new_line).must_equal 4
      end

      it 'diagnoses a table conflicting with an array of tables' do
        error = _{ Tomlrb.parse("[[a]]\n[a]\n") }.must_raise Tomlrb::Key::KeyConflict
        _(error.existing_kind).must_equal :array
        _(error.new_kind).must_equal :explicit
      end

      it 'diagnoses a duplicate sub-table inside one array-of-tables element' do
        error = _{ Tomlrb.parse("[[a]]\n[a.b]\n[a.b]\n") }.must_raise Tomlrb::Key::KeyConflict
        _(error.path).must_equal %w[a b]
        _(error.existing_line).must_equal 2
        _(error.new_line).must_equal 3
      end

      it 'diagnoses a header conflicting with an inline value' do
        error = _{ Tomlrb.parse("a = {b = 1}\n[a]\n") }.must_raise Tomlrb::Key::KeyConflict
        _(error.existing_kind).must_equal :value
        _(error.existing_line).must_equal 1
      end

      it 'reports the line where a statement starts, not where its value ends' do
        error = _{ Tomlrb.parse("fruits = [\n  'apple',\n]\nfruits = 1\n") }
          .must_raise Tomlrb::Key::KeyConflict
        _(error.existing_line).must_equal 1
        _(error.new_line).must_equal 4
      end
    end

    describe 'Tomlrb.audit' do
      it 'shares the diagnosis of Tomlrb.parse' do
        source = "[a]\n[a]\n"
        parse_error = _{ Tomlrb.parse(source) }.must_raise Tomlrb::Key::KeyConflict
        audit_error = _{ Tomlrb.audit(source) }.must_raise Tomlrb::Key::KeyConflict
        _(audit_error.message).must_equal parse_error.message
      end

      it 'returns a report for valid documents' do
        report = Tomlrb.audit("[a]\nb = 1\n")
        _(report).must_be_kind_of Tomlrb::AuditReport
        _(report.find('a').kind).must_equal :explicit
      end
    end
  end
end
