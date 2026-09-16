# Dayoff

Public holidays for 200+ countries, their states and regions, offline, in Elixir. The data and the rule grammar come from [date-holidays](https://github.com/commenthol/date-holidays) and a daily sync keeps them current. No runtime dependencies.

```elixir
Dayoff.holidays("BR", 2026, types: [:public])
# [%Dayoff.Holiday{date: ~D[2026-01-01], name: "Ano Novo", type: :public, rule: "01-01", ...}, ...]

Dayoff.holiday?(~D[2026-11-26], "US")
# true

Dayoff.on(~D[2026-12-25], "DE", state: "BY", language: "en") |> Enum.map(& &1.name)
# ["Christmas Day"]
```

## Installation

```elixir
def deps do
  [
    {:dayoff, "~> 0.2"}
  ]
end
```

Elixir 1.18 or newer.

## Usage

Country codes are ISO 3166-1 alpha-2 strings (`"US"` or `"us"`). States and regions use the dataset's codes, listed by `Dayoff.states/1` and `Dayoff.regions/2`.

```elixir
Dayoff.countries(language: "en")["AT"]      # "Austria"
Dayoff.states("US")["CA"]                   # "California"
Dayoff.holidays("DE", 2026, state: "BY", region: "A")
Dayoff.holidays("US-CA", 2026)              # the state can ride along in the code
Dayoff.holidays("US", 2026, types: [:public, :bank])
```

A `Dayoff.Holiday` has its `date`, `start` and `end` as wall-clock times in the country's zone, the `name` in the country's language (or `language:`), a `type` (`:public`, `:bank`, `:school`, `:optional`, `:observance`), the `rule` it came from, whether it is a `substitute?` day and a `note`. `Dayoff.on/3` gives the holidays covering a date or a `NaiveDateTime`, since some start in the afternoon or span days. Also there: `languages/2`, `zones/2`, `day_off/2`, `weekend/2`, `rules/2` and `version/0`.

## How it works

The data is one JSON file of rules like `4th thursday in November` or `substitutes 12-25 if saturday then previous friday`, one per holiday. Dayoff parses them and evaluates them for the year you ask about, see the [Rules](guides/rules.md) guide. Every date is checked against date-holidays itself, holiday by holiday for all countries, states and regions. The guide lists the three places where dayoff deliberately differs.

`mix dayoff.sync` rebuilds the data from upstream master (needs Node). A workflow runs it daily and, when the upstream data changed and the tests pass, pushes a `fix:` commit that release-please turns into a patch release.

## A holiday is wrong or missing

The data lives upstream in [date-holidays](https://github.com/commenthol/date-holidays), one YAML file per country under `data/countries`. Fix it there (their [contributing guide](https://github.com/commenthol/date-holidays/blob/master/CONTRIBUTING.md) explains the format) and dayoff picks it up within a day of the merge, as a patch release on Hex. Open an issue here only when the dates differ from what date-holidays gives.

## License

Code: Apache-2.0, Copyright 2026 George Guimarães. The holiday data is from [commenthol/date-holidays](https://github.com/commenthol/date-holidays) under [CC BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/), the rule grammar is a port of [date-holidays-parser](https://github.com/commenthol/date-holidays-parser) (ISC), see `NOTICE`. Releases follow [Conventional Commits](https://www.conventionalcommits.org/), see [RELEASE.md](.github/RELEASE.md).
