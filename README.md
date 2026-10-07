# Tomlrb

[![Code Climate](https://codeclimate.com/github/fbernier/tomlrb/badges/gpa.svg)](https://codeclimate.com/github/fbernier/tomlrb)
[![Gem Version](https://badge.fury.io/rb/tomlrb.svg)](http://badge.fury.io/rb/tomlrb)
[![Build status](https://github.com/fbernier/tomlrb/workflows/ci/badge.svg)](https://github.com/fbernier/tomlrb/actions)

A Racc based [TOML](https://github.com/toml-lang/toml) Ruby parser supporting the 1.0.0 version of the spec.

## TODO

* Dumper

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
### Cash-Flow Valuation (XIRR)

`Money.xirr` finds **all** internal rates of return of a dated cash-flow
series inside a caller-specified rate interval, instead of converging to
whichever root a guess happens to land on:

```ruby
result = Money.xirr(
  [[Money.from_amount(-1000, "USD"), Date.new(2024, 1, 1)],
   [Money.from_amount( 2300, "USD"), Date.new(2025, 1, 1)],
   [Money.from_amount(-1320, "USD"), Date.new(2026, 1, 1)]],
  day_count: :thirty_360,   # caller-selected basis: :act_365, :act_360,
                            # :act_act, :thirty_360, or a custom callable
  rate_range: -0.5..1.0     # search interval, must lie within r > -1
)
result.status # => :solved
result.rates  # => [0.1, 0.2] (approximately)
```

- Every root is reported with its isolating interval and the NPV residual
  at the reported rate (`result.roots`).
- Multiple roots, no root (`:no_root`), and all-zero cash flows
  (`:all_zero`) are reported separately via `result.status`.
- All amounts must already share a single currency; mixed currencies raise
  `Money::CashFlow::CurrencyMismatch` and no exchange rate is ever fetched
  implicitly.
- The search is bounded by an evaluation budget (`max_evaluations:`); if it
  runs out, `result.unresolved_intervals` lists the rate ranges that could
  not be excluded.


### Declaration audit

\`Tomlrb.audit\` explains how each table in a document was formed and
diagnoses duplicate definitions, using the same declaration audit as
\`Tomlrb.parse\`:

\`\`\`ruby
report = Tomlrb.audit("[x.y]\n[x]\ndotted.key = 1\n[[arr]]\n")
report.tables.each { |table| p [table.path, table.kind, table.line] }
# ["x", :explicit, 2]        ([x.y] implicitly created x; [x] declared it on line 2)
# ["x", "y", :explicit, 1]
# ["dotted", :dotted, 3]     (created and defined by the dotted key)
# ["arr", :array_of_tables, 4]
# ["arr", :array_element, 4]
\`\`\`

Each table is reported with its formation kind (\`:implicit\`, \`:explicit\`,
\`:dotted\`, \`:array_of_tables\` or \`:array_element\`) and the line at which
its semantic identity was established. A table appearing at the same path
twice is not necessarily a duplicate: parent tables may be declared after
their children, and each array-of-tables element opens a fresh scope.

Actual duplicates raise \`Tomlrb::Key::KeyConflict\` (a \`Tomlrb::ParseError\`)
pointing at both the first establishment and the conflicting declaration:

\`\`\`ruby
Tomlrb.audit("fruit.apple = 1\n[fruit]\n")
# => Duplicate declaration of 'fruit': first defined as dotted-key table
#    at line 1, cannot be redefined as explicit table at line 2
\`\`\`


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
