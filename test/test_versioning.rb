require 'minitest_helper'

describe 'TOML version handling' do
  it 'accepts the TOML 1.1 escape sequence when targeting 1.1' do
    value = Tomlrb.parse('message = "escape: \\e"', version: '1.1')
    _(value.fetch('message')).must_equal("escape: \e")
  end

  it 'rejects the TOML 1.1 escape sequence in TOML 1.0 mode' do
    _{ Tomlrb.parse('message = "escape: \\e"', version: '1.0') }
      .must_raise Tomlrb::ParseError
  end

  it 'downgrades the TOML 1.1 escape sequence without changing its value' do
    text = Tomlrb.downgrade('message = "escape: \\e"', version: '1.1')
    original = Tomlrb.parse('message = "escape: \\e"', version: '1.1')

    _(text).must_include('\\u001B')
    _(Tomlrb.parse(text, version: '1.0')).must_equal original
  end

  it 'accepts local times with omitted seconds in TOML 1.1' do
    value = Tomlrb.parse('at = 07:32', version: '1.1').fetch('at')

    _(value).must_be_instance_of Tomlrb::LocalTime
    _(value.hour).must_equal 7
    _(value.min).must_equal 32
    _(value.sec).must_equal 0
  end

  it 'downgrades local times with omitted seconds' do
    text = Tomlrb.downgrade('at = 07:32', version: '1.1')
    original = Tomlrb.parse('at = 07:32', version: '1.1')

    _(text).must_equal "at = 07:32:00\n"
    _(Tomlrb.parse(text, version: '1.0')).must_equal original
  end

  it 'accepts date-times with omitted seconds in TOML 1.1' do
    local = Tomlrb.parse('at = 1979-05-27T07:32', version: '1.1').fetch('at')
    offset = Tomlrb.parse('at = 1979-05-27 07:32Z', version: '1.1').fetch('at')

    _(local).must_be_instance_of Tomlrb::LocalDateTime
    _(local.sec).must_equal 0
    _(offset).must_be_instance_of Time
    _(offset.sec).must_equal 0
  end

  it 'downgrades local and offset date-times with omitted seconds' do
    input = "local = 1979-05-27T07:32\noffset = 1979-05-27 07:32Z\n"
    text = Tomlrb.downgrade(input, version: '1.1')
    original = Tomlrb.parse(input, version: '1.1')

    _(Tomlrb.parse(text, version: '1.0')).must_equal original
  end

  it 'rejects omitted seconds in TOML 1.0 mode' do
    _{ Tomlrb.parse('at = 07:32', version: '1.0') }.must_raise Tomlrb::ParseError
    _{ Tomlrb.parse('at = 1979-05-27T07:32', version: '1.0') }.must_raise Tomlrb::ParseError
  end

  it 'rejects fractional minutes when seconds are omitted in TOML 1.1' do
    _{ Tomlrb.parse('at = 07:32.5', version: '1.1') }.must_raise Tomlrb::ParseError
    _{ Tomlrb.parse('at = 1979-05-27T07:32.5Z', version: '1.1') }.must_raise Tomlrb::ParseError
  end

  it 'accepts multiline inline tables and trailing commas in TOML 1.1' do
    input = <<~TOML
      point = {
        x = 1,
        y = 2,
      }
    TOML

    _(Tomlrb.parse(input, version: '1.1')).must_equal('point' => {'x' => 1, 'y' => 2})
  end

  it 'rejects multiline inline tables and trailing commas in TOML 1.0' do
    multiline = "point = {\n x = 1\n}\n"
    trailing = "point = {x = 1,}\n"

    _{ Tomlrb.parse(multiline, version: '1.0') }.must_raise Tomlrb::ParseError
    _{ Tomlrb.parse(trailing, version: '1.0') }.must_raise Tomlrb::ParseError
  end

  it 'downgrades multiline inline tables to TOML 1.0 syntax' do
    input = <<~TOML
      point = {
        x = 1,
        nested = { a = 1,
          b = 2,
        },
        values = [
          1,
          2,
        ],
      }
    TOML
    text = Tomlrb.downgrade(input, version: '1.1')
    original = Tomlrb.parse(input, version: '1.1')

    _(Tomlrb.parse(text, version: '1.0')).must_equal original
  end

  it 'preserves special floats while downgrading' do
    input = "plus = inf\nminus = -inf\nnot_a_number = nan\nvalue = 1.5\n"
    text = Tomlrb.downgrade(input, version: '1.1')
    reread = Tomlrb.parse(text, version: '1.0')

    _(reread.fetch('plus')).must_equal Float::INFINITY
    _(reread.fetch('minus')).must_equal(-Float::INFINITY)
    _(reread.fetch('not_a_number')).must_be(:nan?)
    _(reread.fetch('value')).must_equal 1.5
  end

  it 'preserves all TOML temporal types while downgrading' do
    input = <<~TOML
      date = 1979-05-27
      local = 1979-05-27T07:32:00.500000000
      at = 07:32:00.25
      offset = 1979-05-27T07:32:00Z
    TOML
    text = Tomlrb.downgrade(input, version: '1.1')
    reread = Tomlrb.parse(text, version: '1.0')

    _(reread.fetch('date')).must_be_instance_of Tomlrb::LocalDate
    _(reread.fetch('local')).must_be_instance_of Tomlrb::LocalDateTime
    _(reread.fetch('at')).must_be_instance_of Tomlrb::LocalTime
    _(reread.fetch('offset')).must_be_instance_of Time
    _(reread).must_equal Tomlrb.parse(input, version: '1.1')
  end

  it 'reports a path and reason for values that cannot be represented in TOML 1.0' do
    error = _{ Tomlrb.dump({'outer' => {'inner' => [Object.new]}}) }.must_raise Tomlrb::DowngradeError

    _(error.path).must_equal '$.outer.inner[0]'
    _(error.reason).must_include 'Object'
  end

  it 'reports unsupported integer ranges with a path' do
    error = _{ Tomlrb.dump({'number' => 2**63}) }.must_raise Tomlrb::DowngradeError

    _(error.path).must_equal '$.number'
    _(error.reason).must_include '64-bit'
  end

  it 'reports semantic values that TOML 1.0 cannot represent with a path' do
    unusual_offset = Time.new(1979, 5, 27, 7, 32, 0, 30)
    error = _{ Tomlrb.dump({'schedule' => {'at' => unusual_offset}}) }.must_raise Tomlrb::DowngradeError

    _(error.path).must_equal '$.schedule.at'
    _(error.reason).must_include 'TOML 1.0'
  end
end
