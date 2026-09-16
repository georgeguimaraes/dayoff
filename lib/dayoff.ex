defmodule Dayoff do
  @moduledoc """
  Public holidays for 200+ countries, states and regions, offline.

  The data and the rule grammar come from
  [date-holidays](https://github.com/commenthol/date-holidays) and are synced
  from its master branch daily.

      iex> Dayoff.countries()["BR"]
      "Brasil"

      iex> Dayoff.states("US")["CA"]
      "California"

  Country codes are ISO 3166-1 alpha-2, given as `"US"`, `"us"` or `:us`.
  States and regions use the upstream codes, see `states/1` and `regions/2`.
  A state can also ride along in the country code: `"US-CA"`.
  """

  alias Dayoff.{CalDate, Data, Evaluator, Holiday, Rules}

  @typedoc "A country code: `US`, `us` or `:us`, optionally with the state as in `US-CA`."
  @type country :: String.t() | atom()

  @typedoc """
  Options shared by the lookup functions.

    * `:state` - state or region code inside the country (`"CA"`, `"07"`)
    * `:region` - region code inside the state (`"A"` in `"DE"`, `"BY"`)
    * `:language` - ISO 639-1 code for names; falls back to the country's
      languages and then English
  """
  @type option :: {:state, String.t()} | {:region, String.t()} | {:language, String.t()}

  @weekdays ~w(monday tuesday wednesday thursday friday saturday sunday)a

  @doc """
  The holidays of a year for a country, state or region, sorted by start.

  Options: `:state`, `:region`, `:language` (see `t:option/0`) and `:types`,
  a list of `t:Dayoff.Holiday.type/0` to keep, all five by default.

      iex> [thanksgiving] = Dayoff.holidays("US", 2026) |> Enum.filter(&(&1.rule == "4th thursday in November"))
      iex> {thanksgiving.date, thanksgiving.name, thanksgiving.type}
      {~D[2026-11-26], "Thanksgiving Day", :public}

      iex> Dayoff.holidays("BR", 2026, types: [:public]) |> Enum.map(& &1.date) |> Enum.take(3)
      [~D[2026-01-01], ~D[2026-04-03], ~D[2026-04-21]]
  """
  @spec holidays(country(), integer(), keyword()) :: [Holiday.t()]
  def holidays(country, year, opts \\ []) when is_integer(year) do
    selection = Data.selection!(country, opts)
    types = Keyword.get(opts, :types, Holiday.types())
    languages = List.wrap(opts[:language]) ++ languages(country, opts)
    compiled = Rules.compiled(selection)
    substitute_names = Data.raw()["names"]["substitutes"]["name"]

    memo_key = make_ref()

    try do
      compiled
      |> Enum.filter(&(&1.type in types))
      |> Enum.flat_map(fn rule ->
        %{dates: dates, kind: kind} = Evaluator.memoized(rule, year, compiled, memo_key)
        Enum.map(dates, &to_holiday(&1, rule, kind, languages, substitute_names))
      end)
      |> Enum.sort_by(&sort_key/1)
      |> Enum.uniq_by(&{&1.name, &1.start})
    after
      Evaluator.clear_memo(memo_key)
    end
  end

  @doc """
  The holidays covering a moment. With a `Date`, every holiday whose start
  and end overlap that calendar day; with a `NaiveDateTime`, the holidays
  running at that wall-clock time in the country's zone. Takes the same
  options as `holidays/3`.

      iex> Dayoff.on(~D[2026-12-25], "BR") |> Enum.map(& &1.name)
      ["Natal"]

      iex> Dayoff.on(~N[2026-12-24 15:00:00], "BR") |> Enum.map(& &1.name)
      ["Noite de Natal"]

      iex> Dayoff.on(~D[2026-12-23], "BR")
      []
  """
  @spec on(Date.t() | NaiveDateTime.t(), country(), keyword()) :: [Holiday.t()]
  def on(date, country, opts \\ [])

  def on(%Date{} = date, country, opts) do
    day_start = NaiveDateTime.new!(date, ~T[00:00:00])
    day_end = NaiveDateTime.add(day_start, 1, :day)

    for year <- [date.year - 1, date.year] |> Enum.uniq(),
        holiday <- holidays(country, year, opts),
        NaiveDateTime.compare(holiday.start, day_end) == :lt and
          NaiveDateTime.compare(holiday.end, day_start) == :gt,
        uniq: true,
        do: holiday
  end

  def on(%NaiveDateTime{} = moment, country, opts) do
    for year <- [moment.year - 1, moment.year] |> Enum.uniq(),
        holiday <- holidays(country, year, opts),
        NaiveDateTime.compare(holiday.start, moment) != :gt and
          NaiveDateTime.compare(holiday.end, moment) == :gt,
        uniq: true,
        do: holiday
  end

  @doc """
  Whether anything in `on/3` matches.

      iex> Dayoff.holiday?(~D[2026-12-25], "BR")
      true

      iex> Dayoff.holiday?(~D[2026-02-14], "US", types: [:public])
      false
  """
  @spec holiday?(Date.t() | NaiveDateTime.t(), country(), keyword()) :: boolean()
  def holiday?(date, country, opts \\ []), do: on(date, country, opts) != []

  # Hijri and Hebrew days start at 18:00 the evening before. The reference
  # implementation shifts the start by six hours and computes the end from
  # the shifted start, while the date keeps the unshifted day.
  defp to_holiday(%CalDate{} = cal_date, rule, kind, languages, substitute_names) do
    start = if kind in [:islamic, :hebrew], do: CalDate.add_hours(cal_date, -6), else: cal_date
    substitute? = rule.spec["substitute"] == true and cal_date.substitute?

    %Holiday{
      date: CalDate.date(cal_date),
      start: start.naive,
      end: CalDate.end_naive(start),
      name: translate(rule.spec["name"], languages, substitute?, substitute_names),
      type: rule.type,
      rule: rule.rule,
      substitute?: substitute?,
      note: rule.spec["note"]
    }
  end

  # A name given as a plain string is used as is, without the substitute
  # suffix, as upstream does.
  defp translate(name, _languages, _substitute?, _substitute_names) when is_binary(name), do: name

  defp translate(names, languages, substitute?, substitute_names) do
    name = first_translation(names, languages) || names |> Map.values() |> List.first() || ""

    case substitute? && first_translation(substitute_names, languages) do
      nil -> name
      false -> name
      suffix -> name <> " (" <> suffix <> ")"
    end
  end

  defp first_translation(nil, _languages), do: nil
  defp first_translation(names, languages), do: Enum.find_value(languages, &names[&1])

  # Start, then public before the other types, then plain rules before
  # substitute clauses, then the shorter rule string: the upstream order, with
  # the rule string itself as the final tiebreak.
  @type_rank Holiday.types() |> Enum.with_index() |> Map.new()

  defp sort_key(%Holiday{} = holiday) do
    substitute_rank = if Regex.match?(~r/substitutes|and if /, holiday.rule), do: 1, else: 0

    {NaiveDateTime.to_erl(holiday.start), @type_rank[holiday.type], substitute_rank,
     String.length(holiday.rule), holiday.rule}
  end

  @doc """
  Every country in the dataset, by code, named in its own first language or
  in `:language` when given.

      iex> Dayoff.countries(language: "en")["DE"]
      "Germany"
  """
  @spec countries(keyword()) :: %{String.t() => String.t()}
  def countries(opts \\ []) do
    Map.new(Data.raw()["holidays"], fn {code, entry} ->
      {code, display_name(entry, opts[:language])}
    end)
  end

  @doc """
  The states (or top-level regions, for countries that only have those) of a
  country, by code.

      iex> Dayoff.states("AT")["9"]
      "Wien"
  """
  @spec states(country(), keyword()) :: %{String.t() => String.t()}
  def states(country, opts \\ []) do
    selection = Data.selection!(country)
    entry = Data.entry(selection)
    languages = languages(country)

    (entry["states"] || entry["regions"] || %{})
    |> Map.new(fn {code, state} ->
      {code, display_name(state, opts[:language] || hd(languages))}
    end)
  end

  @doc """
  The regions of a state, by code.

      iex> Dayoff.regions("DE", "BY")["A"]
      "Stadt Augsburg"
  """
  @spec regions(country(), String.t(), keyword()) :: %{String.t() => String.t()}
  def regions(country, state, opts \\ []) do
    selection = Data.selection!(country, state: state)
    entry = Data.entry(selection)
    languages = languages(country, state: state)

    (entry["regions"] || %{})
    |> Map.new(fn {code, region} ->
      {code, display_name(region, opts[:language] || hd(languages))}
    end)
  end

  @doc """
  The languages holiday names are available in for a country, state or
  region, most specific first, always ending in `"en"`.

      iex> Dayoff.languages("AT")
      ["de-at", "de", "en"]
  """
  @spec languages(country(), keyword()) :: [String.t()]
  def languages(country, opts \\ []) do
    selection = Data.selection!(country, opts)
    Enum.uniq((Data.inherited(selection, "langs") || []) ++ ["en"])
  end

  @doc """
  The IANA timezones of a country, state or region. The first one is the
  zone holiday times are expressed in.

      iex> Dayoff.zones("US", state: "CA")
      ["America/Los_Angeles"]
  """
  @spec zones(country(), keyword()) :: [String.t()]
  def zones(country, opts \\ []) do
    selection = Data.selection!(country, opts)
    Data.inherited(selection, "zones") || []
  end

  @doc """
  The weekly day off as a weekday atom, `nil` when the dataset doesn't say.

      iex> Dayoff.day_off("BD")
      :friday
  """
  @spec day_off(country(), keyword()) :: atom() | nil
  def day_off(country, opts \\ []) do
    selection = Data.selection!(country, opts)
    weekday(Data.inherited(selection, "dayoff"))
  end

  @doc """
  The weekend as weekday atoms. From the dataset's `weekend` field when it
  has one, otherwise the single day off, otherwise Saturday and Sunday.

      iex> Dayoff.weekend("BD")
      [:friday, :saturday]

      iex> Dayoff.weekend("BR")
      [:sunday]
  """
  @spec weekend(country(), keyword()) :: [atom()]
  def weekend(country, opts \\ []) do
    selection = Data.selection!(country, opts)

    case Data.inherited(selection, "weekend") do
      days when is_list(days) and days != [] ->
        days |> Enum.map(&weekday/1) |> Enum.reject(&is_nil/1)

      _ ->
        List.wrap(day_off(country, opts))
        |> then(&if(&1 == [], do: [:saturday, :sunday], else: &1))
    end
  end

  @doc """
  The merged rule map for a country, state or region: rule string to its
  attributes (`name`, `type`, `substitute`, `active`, `disable`, `enable`,
  `note`). Mostly for debugging and for tests.
  """
  @spec rules(country(), keyword()) :: %{String.t() => map()}
  def rules(country, opts \\ []) do
    country |> Data.selection!(opts) |> Data.rules()
  end

  @doc """
  The upstream commits the shipped data was built from.

      iex> Dayoff.version() |> Map.keys() |> Enum.sort()
      ["holidays", "holidays_version", "parser", "synced_at"]
  """
  @spec version() :: map()
  def version, do: Data.version()

  defp display_name(entry, language) do
    names = entry["names"] || %{}
    first_language = (entry["langs"] || []) |> List.first()
    language = language || first_language || names |> Map.keys() |> List.first()

    entry["name"] || names[language] || names[major_language(language)] ||
      names |> Map.values() |> List.first()
  end

  defp major_language(nil), do: nil
  defp major_language(language), do: language |> String.split("-") |> hd()

  defp weekday(value) when is_binary(value) do
    value = value |> String.downcase() |> String.trim_trailing("s")
    Enum.find(@weekdays, &(Atom.to_string(&1) == value))
  end

  defp weekday(_value), do: nil
end
