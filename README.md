# Dayoff

Public holidays for 200+ countries, their states and regions, offline, in Elixir. The data and the rule grammar come from [date-holidays](https://github.com/commenthol/date-holidays), the most complete open holiday dataset around, and a daily sync keeps them current. No runtime dependencies.

```elixir
Dayoff.holidays("BR", 2026, types: [:public])
# [%Dayoff.Holiday{date: ~D[2026-01-01], name: "Ano Novo", type: :public, rule: "01-01", ...}, ...]

Dayoff.holiday?(~D[2026-11-26], "US")
# true

Dayoff.on(~D[2026-12-25], "DE", state: "BY", language: "en") |> Enum.map(& &1.name)
# ["Christmas Day"]
```

> **Warning**: work in progress, the API and the data files will change until 0.1.0 is out.

## Installation

```elixir
def deps do
  [
    {:dayoff, "~> 0.1"}
  ]
end
```

Elixir 1.20 on OTP 29 or newer.

## Usage

Country codes are ISO 3166-1 alpha-2, as `"US"`, `"us"` or `:us`. States and regions use the codes of the dataset, and `Dayoff.states/1` and `Dayoff.regions/2` list them with their names.

```elixir
Dayoff.countries()["AT"]               # "Österreich"
Dayoff.countries(language: "en")["AT"] # "Austria"
Dayoff.states("US")["CA"]              # "California"
Dayoff.regions("DE", "BY")             # %{"A" => "Stadt Augsburg", "EVANG" => ..., "KATH" => ...}

Dayoff.holidays("DE", 2026, state: "BY", region: "A")
Dayoff.holidays("US-CA", 2026)         # the state can ride along in the code
```

Each holiday is a `Dayoff.Holiday` with its `date`, `start` and `end` as wall-clock times in the country's zone, `name` in the country's language (or `language:`), `type`, the `rule` it came from, whether it is a `substitute?` day, and a `note` when the data has one.

Types are `:public`, `:bank`, `:school`, `:optional` and `:observance`, in decreasing order of how binding they are. `types:` keeps only some:

```elixir
Dayoff.holidays("US", 2026, types: [:public, :bank])
```

`Dayoff.on/3` gives the holidays covering a date, or a `NaiveDateTime` for the ones running at that time, since some holidays start in the afternoon or span several days. `Dayoff.holiday?/3` is the boolean version.

Also there: `Dayoff.languages/2`, `Dayoff.zones/2`, `Dayoff.day_off/2` and `Dayoff.weekend/2` for a country's weekly day off, `Dayoff.rules/2` for the raw rules behind a selection, and `Dayoff.version/0` for the upstream commits the data was built from.

## How it works

The dataset is one JSON file of rules such as `4th thursday in November`, `easter -2`, `1 Shawwal P3D` or `substitutes 12-25 if saturday then previous friday`, one per holiday, with names and attributes. Dayoff parses those rules and evaluates them for the year you ask about. The grammar is described in the [Rules](guides/rules.md) guide. The Hijri, Hebrew, Chinese, Korean and Vietnamese calendars and the equinox dates come as tables generated from the same libraries the reference implementation uses, so dates match it exactly.

The whole file is decoded once on first use, and each country's rules are parsed the first time they are asked for. A first lookup takes a few tens of milliseconds, the next ones well under a millisecond.

### Parity with date-holidays

Every release is checked against date-holidays itself: the sync runs the reference implementation over all countries, states and regions and the test suite compares `Dayoff.holidays/3` with it holiday by holiday, on 2010 to 2035 in the repository and on 1970 to 2076 in the sync workflow. Three deliberate differences are listed at the end of the Rules guide.

### Data sync

`mix dayoff.sync` rebuilds `priv/data` from the upstream master branch (needs Node) and records the commits it used in `priv/data/VERSION.json`. A workflow runs it every day: when the upstream data folders moved, it regenerates everything, runs the tests, and pushes `fix: sync date-holidays data <sha>` to main, which release-please turns into a patch release. When the tests fail instead, it opens a pull request with the differences, so a new rule form or a data problem is visible within a day of the upstream commit.

## Data license

The holiday data in `priv/data/holidays.json` is from [commenthol/date-holidays](https://github.com/commenthol/date-holidays), licensed [CC BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/). Source and attribution lines are kept inside the file. The rule grammar and evaluation semantics are a port of [date-holidays-parser](https://github.com/commenthol/date-holidays-parser) (ISC), see `NOTICE`.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated releases. See the [release documentation](https://github.com/georgeguimaraes/dayoff/blob/main/.github/RELEASE.md) for details.

## License

Copyright 2026 George Guimarães

Dayoff is released under the Apache License 2.0. See the LICENSE file for details.
