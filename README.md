# Tomlrb

[![Code Climate](https://codeclimate.com/github/fbernier/tomlrb/badges/gpa.svg)](https://codeclimate.com/github/fbernier/tomlrb)
[![Gem Version](https://badge.fury.io/rb/tomlrb.svg)](http://badge.fury.io/rb/tomlrb)
[![Build status](https://github.com/fbernier/tomlrb/workflows/ci/badge.svg)](https://github.com/fbernier/tomlrb/actions)

A Racc based [TOML](https://github.com/toml-lang/toml) Ruby parser supporting TOML 1.0.0 and 1.1.0.

## TOML versions

`Tomlrb.parse` uses TOML 1.0.0 by default. Pass `version: "1.1"` to accept TOML 1.1 syntax such as escape, date-times and times with omitted seconds, and multiline inline tables.

```ruby
Tomlrb.parse('at = 07:32', version: "1.1")
```

Use `Tomlrb.downgrade` to parse TOML 1.1 and emit TOML 1.0 text when the data can be represented without loss. The emitted document can be parsed again in 1.0 mode and retains TOML temporal and float types.

```ruby
toml_1_0 = Tomlrb.downgrade(toml_1_1, version: "1.1")
```

Values outside TOML's data model raise `Tomlrb::DowngradeError`, which exposes `path` and `reason`. `Tomlrb.dump` emits TOML 1.0 directly from a Ruby data structure.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tomlrb'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install tomlrb

## Usage

```ruby
Tomlrb.parse("[toml]\na = [\"array\", 123]")
```

or

```ruby
Tomlrb.load_file('my_file', symbolize_keys: true)
```

## Benchmark

You can run the benchmark against the only other v0.5.0 compliant parser to my knowledge with `ruby benchmarks/bench.rb`.

Here are the results on my machine:

```
Warming up --------------------------------------
      emancu/toml-rb     1.000  i/100ms
     fbernier/tomlrb    33.000  i/100ms
Calculating -------------------------------------
      emancu/toml-rb     15.597  (± 6.4%) i/s -     78.000  in   5.020321s
     fbernier/tomlrb    348.307  (± 5.2%) i/s -      1.749k in   5.034878s

Comparison:
     fbernier/tomlrb:      348.3 i/s
      emancu/toml-rb:       15.6 i/s - 22.33x  (± 0.00) slower

```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt that will allow you to experiment.

Do not forget to regenerate the parser when you modify rules in the `parser.y` file using `rake compile`.

Run the tests using `rake test`.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release` to create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/[my-github-username]/tomlrb/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Thanks

Thanks to [@jpbougie](https://github.com/jpbougie) for the crash course on  the Chomsky hierarchy and general tips.
