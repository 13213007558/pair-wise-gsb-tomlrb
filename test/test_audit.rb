require 'minitest_helper'

describe Tomlrb do
  describe '.audit' do
    it 'explains how each table was formed' do
      report = Tomlrb.audit("[a.b]\n[a]\n")
      formations = report.formations.map { |f| [f.path, f.kind, f.line] }
      _(formations).must_equal [
        [%w[a], :implicit, 1],
        [%w[a b], :explicit, 1],
        [%w[a], :explicit, 2]
      ]
    end

    it 'classifies dotted-key tables and array-of-tables elements' do
      report = Tomlrb.audit("[t]\nu.v = 1\n[[arr]]\n[[arr]]\n")
      formations = report.formations.map { |f| [f.path, f.kind, f.line] }
      _(formations).must_equal [
        [%w[t], :explicit, 1],
        [%w[t u], :dotted, 2],
        [%w[arr], :array_of_tables, 3],
        [%w[arr], :array_of_tables, 4]
      ]
    end

    it 'shares the parse result with the audit report' do
      src = "[a.b]\nc = 1\n[a]\n"
      _(Tomlrb.audit(src).output).must_equal Tomlrb.parse(src)
    end

    it 'accepts a StringIO like .parse' do
      report = Tomlrb.audit(StringIO.new("[a]\n"))
      _(report.output).must_equal({ 'a' => {} })
    end
  end

  describe 'declaration audit' do
    it 'allows declaring an implicit parent table afterwards' do
      _(Tomlrb.parse("[a]\n[a.b.c]\n[a.b]\n")).must_equal({ 'a' => { 'b' => { 'c' => {} } } })
      _(Tomlrb.parse("[a.b.c]\n[a.b]\n")).must_equal({ 'a' => { 'b' => { 'c' => {} } } })
    end

    it 'allows same-named subtables under different array-of-tables elements' do
      parsed = Tomlrb.parse("[[a]]\n[a.b]\n[[a]]\n[a.b]\n")
      _(parsed).must_equal({ 'a' => [{ 'b' => {} }, { 'b' => {} }] })
    end

    it 'allows a table where a sibling element established an array' do
      parsed = Tomlrb.parse("[[a]]\n[[a.b]]\n[[a]]\n[a.b]\n")
      _(parsed).must_equal({ 'a' => [{ 'b' => [{}] }, { 'b' => {} }] })
    end

    it 'points to the first establishment and the conflicting declaration' do
      error = _{ Tomlrb.parse("[a]\n\n[a]\n") }.must_raise(Tomlrb::ParseError)
      _(error.message).must_include 'line 1'
      _(error.message).must_include 'line 3'
    end

    it 'diagnoses a table redefined after a dotted key with both locations' do
      error = _{ Tomlrb.parse("[fruit]\napple.color = \"red\"\n[fruit.apple]\n") }.must_raise(Tomlrb::ParseError)
      _(error.message).must_include 'line 2'
      _(error.message).must_include 'line 3'
    end

    it 'diagnoses a normal table defined over an established array' do
      error = _{ Tomlrb.parse("[[a]]\n[[a.b]]\n[a.b]\n") }.must_raise(Tomlrb::ParseError)
      _(error.message).must_include 'line 2'
      _(error.message).must_include 'line 3'
    end

    it 'rejects duplicate subtables within the same array-of-tables element' do
      _{ Tomlrb.parse("[[a]]\n[a.b]\n[a.b]\n") }.must_raise(Tomlrb::ParseError)
    end

    it 'rejects extending a table created by an inline table' do
      _{ Tomlrb.parse("a = {b=1}\na.c = 2\n") }.must_raise(Tomlrb::ParseError)
    end
  end
end
