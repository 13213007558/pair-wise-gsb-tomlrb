require 'minitest_helper'

describe 'TOML versioning' do
  it 'parses TOML 1.1 escapes and downgrades them losslessly' do
    source = <<~TOML
      escape = "ESC:\\e, hex:\\x61, delete:\\x7f, null:\\x00"
      "\\x65" = "keyed escape"
    TOML

    data = Tomlrb.parse(source, version: '1.1')
    result = Tomlrb.downgrade(source, version: '1.1')

    assert result.success?
    assert_equal data, Tomlrb.parse(result.output, version: '1.0')
    assert_includes result.output, '\\u001B'
    assert_includes result.output, '\\u007F'
    assert_includes result.output, '\\u0000'

    assert_raises(Tomlrb::ParseError) do
      Tomlrb.parse('a = "\\e"', version: '1.0')
    end
    assert_raises(Tomlrb::ParseError) do
      Tomlrb.parse('a = "\\x61"', version: '1.0')
    end
  end

  it 'rejects incomplete hex escapes and bare carriage returns in TOML 1.1' do
    ['a = "\\x0g"', 'a = "\\xAg"', 'a = "\\x"', "a = \"\"\"\r\"\"\"", "a = '''\r'''"].each do |source|
      assert_raises(Tomlrb::ParseError) do
        Tomlrb.parse(source, version: '1.1')
      end
    end
  end

  it 'expands omitted seconds when downgrading dates and times' do
    source = <<~TOML
      local = 07:32
      local_date_time = 2010-02-03T14:15
      spaced_date_time = 2010-02-03 14:15
      offset_date_time = 2010-02-03t14:15Z
      precise = 07:32:00.123456789
    TOML

    data = Tomlrb.parse(source, version: '1.1')
    result = Tomlrb.downgrade(source, version: '1.1')

    assert result.success?
    assert_equal data, Tomlrb.parse(result.output, version: '1.0')
    assert_match(/^"local" = 07:32:00$/, result.output)
    assert_match(/^"local_date_time" = 2010-02-03T14:15:00$/, result.output)
    assert_match(/^"offset_date_time" = 2010-02-03T14:15:00\+00:00$/, result.output)
    assert_match(/^"precise" = 07:32:00\.123456789$/, result.output)

    assert_raises(Tomlrb::ParseError) do
      Tomlrb.parse('a = 07:32', version: '1.0')
    end
    assert_raises(Tomlrb::ParseError) do
      Tomlrb.parse('a = 2010-02-03T07:32', version: '1.0')
    end
  end

  it 'flattens multiline and trailing-comma inline tables into standard TOML 1.0 tables' do
    source = <<~TOML
      point = {
        x = 1,
        nested = {
          y = 2,
          # comment inside a 1.1 inline table
          z = {
            deep = true,
          },
        },
      }
      points = [
        { name = "first", value = 1, },
        { name = "second", value = 2, },
      ]
    TOML

    data = Tomlrb.parse(source, version: '1.1')
    result = Tomlrb.downgrade(source, version: '1.1')

    assert result.success?
    assert_equal data, Tomlrb.parse(result.output, version: '1.0')
    refute_match(/\{\s/, result.output)

    assert_raises(Tomlrb::ParseError) do
      Tomlrb.parse("a = {\n b = 1\n}", version: '1.0')
    end
    assert_raises(Tomlrb::ParseError) do
      Tomlrb.parse('a = { b = 1, }', version: '1.0')
    end
  end

  it 'keeps special floats and native temporal values as typed TOML values' do
    source = <<~TOML
      positive = inf
      negative = -inf
      not_a_number = nan
      date = 1979-05-27
      local_date_time = 1979-05-27T07:32:00.5
      offset_date_time = 1979-05-27T07:32:00.999999Z
    TOML

    result = Tomlrb.downgrade(source, version: '1.0')
    reparsed = Tomlrb.parse(result.output, version: '1.0')

    assert result.success?
    assert_equal Float::INFINITY, reparsed.fetch('positive')
    assert_equal(-Float::INFINITY, reparsed.fetch('negative'))
    assert_predicate reparsed.fetch('not_a_number'), :nan?
    assert_kind_of Tomlrb::LocalDate, reparsed.fetch('date')
    assert_kind_of Tomlrb::LocalDateTime, reparsed.fetch('local_date_time')
    assert_kind_of Time, reparsed.fetch('offset_date_time')
    refute_match(/"inf"|"nan"|"1979/, result.output)
  end

  it 'reports unrepresentable values with document paths' do
    result = Tomlrb::Generator.try_generate(
      {
        'ok' => 1,
        'missing' => nil,
        'large' => 2 ** 63,
        'items' => [1, nil, Object.new],
        'nested' => {'invalid' => /re/}
      },
      target_version: '1.0'
    )

    refute result.success?
    assert_nil result.output
    paths = result.errors.map { |error| error[:path] }
    assert_equal %w[$.missing $.large $.items[1] $.items[2] $.nested.invalid], paths
    assert(result.errors.all? { |error| error[:reason].is_a?(String) && !error[:reason].empty? })

    assert_raises(Tomlrb::DowngradeError) do
      Tomlrb.downgrade!(
        Tomlrb.dump({'large' => 2 ** 63}, target_version: '1.1'),
        from: '1.1'
      )
    end
  end
end
