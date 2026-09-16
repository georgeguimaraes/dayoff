# Dayoff

Public holidays for 200+ countries, their states and regions, offline, in Elixir. The data and the rule grammar come from [date-holidays](https://github.com/commenthol/date-holidays), the most complete open holiday dataset around, and a daily sync keeps them current.

> **Warning**: work in progress, the API and the data files will change until 0.1.0 is out.

## Installation

```elixir
def deps do
  [
    {:dayoff, "~> 0.1"}
  ]
end
```

## Data license

The holiday data in `priv/data/holidays.json` is from [commenthol/date-holidays](https://github.com/commenthol/date-holidays), licensed [CC BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/). Source and attribution lines are kept inside the file. The rule grammar and evaluation semantics are a port of [date-holidays-parser](https://github.com/commenthol/date-holidays-parser) (ISC), see `NOTICE`.

## License

Copyright 2026 George Guimarães

Dayoff is released under the Apache License 2.0. See the LICENSE file for details.
