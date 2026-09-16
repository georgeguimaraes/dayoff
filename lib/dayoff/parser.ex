defmodule Dayoff.Parser do
  @moduledoc """
  Turns a rule string like `"4th thursday in November"` or
  `"substitutes 12-25 if saturday then previous friday"` into tokens.

  A port of the reference implementation's `Parser.js`: an ordered list of
  anchored regular expressions is tried at the head of the remaining string,
  the first match wins and is consumed, spaces are skipped, and a pass that
  consumes nothing makes the rule unparseable. Two token reorderings follow,
  see `reorder/1`. The grammar is documented in the "Rules" guide.

  Tokens are maps of three kinds:

    * `%{fn: ...}` produce candidate dates for a year (`:gregorian`,
      `:julian`, `:easter`, `:equinox`, `:hebrew`, `:islamic`, `:jalaali`,
      `:chinese`, `:korean`, `:vietnamese`, `:bengali_revised`)
    * `%{rule: ...}` move, filter or annotate those dates
    * `%{modifier: ...}` change how the following rules behave
      (`:substitutes`, `:and`, `:if`, `:then`, `:if_equal`)

      iex> Dayoff.Parser.parse!("12-25 and if sunday then next monday")
      [
        %{fn: :gregorian, year: nil, month: 12, day: 25},
        %{modifier: :and},
        %{rule: :date_if_then, if: [:sunday], direction: :next, then: :monday, rules: []}
      ]
  """

  @weekdays "[Ss]unday|[Mm]onday|[Tt]uesday|[Ww]ednesday|[Tt]hursday|[Ff]riday|[Ss]aturday|day"
  @months ~w(January February March April May June July August September October November December)
  @islamic_months [
    "Muharram",
    "Safar",
    "Rabi al-awwal",
    "Rabi al-thani",
    "Jumada al-awwal",
    "Jumada al-thani",
    "Rajab",
    "Shaban",
    "Ramadan",
    "Shawwal",
    "Dhu al-Qidah",
    "Dhu al-Hijjah"
  ]
  @hebrew_months ~w(Nisan Iyyar Sivan Tamuz Av Elul Tishrei Cheshvan Kislev Tevet Shvat AdarII Adar)
  @jalaali_months ~w(Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand)

  @direction "(before|after|next|previous|in)"
  @counts "(\\d+)(?:st|nd|rd|th)?"
  @holiday_type "(public|bank|school|observance|optional)"
  @weekday_list "((?:(?:#{@weekdays})(?:,\\s?)?)*)"
  @days "(#{@weekdays})s?"

  @grammar [
    julian: ~r/^julian (?:0*(\d{1,4})-)?0?(\d{1,2})-0?(\d{1,2})/,
    date: ~r/^(?:0*(\d{1,4})-)?0?(\d{1,2})-0?(\d{1,2})/,
    easter: ~r/^(easter|orthodox)(?: ([-+]?\d{1,2}) ?(?:days?|d)?)?/,
    islamic:
      Regex.compile!("^0?(\\d{1,2}) (#{Enum.join(@islamic_months, "|")})(?: 0*(\\d{1,}))?"),
    hebrew: Regex.compile!("^0?(\\d{1,2}) (#{Enum.join(@hebrew_months, "|")})(?: 0*(\\d{1,}))?"),
    jalaali:
      Regex.compile!("^0?(\\d{1,2}) (#{Enum.join(@jalaali_months, "|")})(?: 0*(\\d{1,}))?"),
    equinox:
      ~r/^([Mm]arch|[Jj]une|[Ss]eptember|[Dd]ecember) (?:equinox|solstice)(?: in ([^\s]*|[+-]\d{2}:\d{2}))?/,
    chinese_solar:
      ~r/^(chinese|korean|vietnamese) (?:(\d+)-(\d{1,2})-)?(\d{1,2})-(\d{1,2}) solarterm/,
    chinese_lunar:
      ~r/^(chinese|korean|vietnamese) (?:(\d+)-(\d{1,2})-)?(\d{1,2})-([01])-(\d{1,2})/,
    bengali_revised: ~r/^(bengali-revised) (?:-?0*(\d{1,4})-)?0?(\d{1,2})-0?(\d{1,2})/,
    date_month: Regex.compile!("^(#{Enum.join(@months, "|")})"),
    date_if_then: Regex.compile!("^if #{@weekday_list} then (?:#{@direction} #{@days})?"),
    weekday: Regex.compile!("^(not )?on #{@weekday_list}"),
    year: ~r/^(?:in (even|odd|leap|non-leap) years|every (\d+) years? since 0*(\d{1,4}))/,
    date_dir: Regex.compile!("^(?:#{@counts} )?#{@days} #{@direction}"),
    if_holiday:
      Regex.compile!(
        "^if is (?:#{@holiday_type} )?holiday then (?:#{@counts} )?(?:#{@direction} #{@days})?(?: omit #{@weekday_list})?"
      ),
    bridge: Regex.compile!("^is (?:#{@holiday_type} )?holiday"),
    time: ~r/^(?:T?0?(\d{1,2}):0?(\d{1,2})|T0?(\d{1,2}))/,
    duration: ~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?/,
    modifier: ~r/^(substitutes|and|if equal|then|if)\b/,
    same_day: ~r/^#\d+/,
    active_from: ~r/^since (0*\d{1,4})(?:-0*(\d{1,2})(?:-0*(\d{1,2})|)|)(?: and|)/,
    active_to: ~r/^prior to (0*\d{1,4})(?:-0*(\d{1,2})(?:-0*(\d{1,2})|)|)/
  ]

  @full_grammar Keyword.keys(@grammar)
  @sub_grammar [:time, :duration]

  @typedoc "A parsed token, see the module documentation."
  @type token :: %{optional(atom()) => term()}

  @doc """
  Parses a rule string, `{:error, :unparseable}` when part of it matches no
  production.
  """
  @spec parse(String.t()) :: {:ok, [token()]} | {:error, :unparseable}
  def parse(rule) when is_binary(rule) do
    case tokenize(rule, @full_grammar) do
      {:ok, tokens, _rest} -> {:ok, reorder(tokens)}
      {:error, :unparseable} -> {:error, :unparseable}
    end
  end

  @doc "Like `parse/1` but raises `ArgumentError`."
  @spec parse!(String.t()) :: [token()]
  def parse!(rule) do
    case parse(rule) do
      {:ok, tokens} -> tokens
      {:error, :unparseable} -> raise ArgumentError, "could not parse rule: #{inspect(rule)}"
    end
  end

  # Tries every production in order at the head of the string; the first
  # match is consumed. A round that consumes nothing is a parse error.
  defp tokenize(string, productions, tokens \\ [])
  defp tokenize("", _productions, tokens), do: {:ok, Enum.reverse(tokens), ""}

  defp tokenize(string, productions, tokens) do
    {rest, tokens} =
      case Enum.find_value(productions, &match(&1, string)) do
        {rest, token} -> {rest, List.wrap(token) ++ tokens}
        nil -> {string, tokens}
      end

    rest = String.trim_leading(rest)

    cond do
      rest == "" ->
        {:ok, Enum.reverse(tokens), ""}

      rest == string ->
        if(productions == @sub_grammar,
          do: {:ok, Enum.reverse(tokens), rest},
          else: {:error, :unparseable}
        )

      true ->
        tokenize(rest, productions, tokens)
    end
  end

  defp match(production, string) do
    regex = Keyword.fetch!(@grammar, production)

    case Regex.run(regex, string) do
      nil ->
        nil

      [matched | captures] ->
        rest = binary_part(string, byte_size(matched), byte_size(string) - byte_size(matched))
        build(production, pad(captures, 6), rest)
    end
  end

  defp pad(captures, size), do: captures ++ List.duplicate("", size - length(captures))

  defp build(:date, [year, month, day | _], rest),
    do: {rest, %{fn: :gregorian, year: number(year), month: number(month), day: number(day)}}

  defp build(:julian, [year, month, day | _], rest),
    do: {rest, %{fn: :julian, year: number(year), month: number(month), day: number(day)}}

  defp build(:easter, [type, offset | _], rest),
    do: {rest, %{fn: :easter, type: String.to_atom(type), offset: number(offset) || 0}}

  defp build(:equinox, [season, timezone | _], rest),
    do:
      {rest,
       %{
         fn: :equinox,
         season: season |> String.downcase() |> String.to_atom(),
         timezone: blank(timezone) || "GMT"
       }}

  defp build(:hebrew, [day, month, year | _], rest),
    do: {rest, %{fn: :hebrew, day: number(day), month: hebrew_month(month), year: number(year)}}

  defp build(:islamic, [day, month, year | _], rest),
    do:
      {rest,
       %{fn: :islamic, day: number(day), month: index(@islamic_months, month), year: number(year)}}

  defp build(:jalaali, [day, month, year | _], rest),
    do:
      {rest,
       %{fn: :jalaali, day: number(day), month: index(@jalaali_months, month), year: number(year)}}

  defp build(:chinese_solar, [calendar, cycle, year, solarterm, day | _], rest) do
    {rest,
     %{
       fn: String.to_atom(calendar),
       cycle: number(cycle),
       year: number(year),
       solarterm: number(solarterm),
       day: number(day)
     }}
  end

  defp build(:chinese_lunar, [calendar, cycle, year, month, leap, day | _], rest) do
    {rest,
     %{
       fn: String.to_atom(calendar),
       cycle: number(cycle),
       year: number(year),
       month: number(month),
       leap_month: number(leap) == 1,
       day: number(day)
     }}
  end

  defp build(:bengali_revised, [_calendar, year, month, day | _], rest),
    do:
      {rest, %{fn: :bengali_revised, year: number(year), month: number(month), day: number(day)}}

  defp build(:date_month, [month | _], rest),
    do: {rest, %{fn: :gregorian, year: nil, month: index(@months, month), day: 1}}

  # The rest of the string is handed to a sub-parser that only knows time and
  # duration, whose tokens become the clause's own rules (`if sunday then 00:00`).
  defp build(:date_if_then, [weekdays, direction, then | _], rest) do
    {:ok, rules, remaining} = tokenize(rest, @sub_grammar)

    {remaining,
     %{
       rule: :date_if_then,
       if: weekday_list(weekdays),
       direction: direction_atom(direction),
       then: weekday_atom(then),
       rules: rules
     }}
  end

  defp build(:weekday, [not_, weekdays | _], rest),
    do: {rest, %{rule: :weekday, not: not_ != "", if: weekday_list(weekdays)}}

  defp build(:year, [cardinality, every, since | _], rest),
    do:
      {rest,
       %{
         rule: :year,
         cardinality: blank(cardinality) && String.to_atom(cardinality),
         every: number(every),
         since: number(since)
       }}

  defp build(:date_dir, [count, weekday, direction | _], rest) do
    direction = if direction == "in", do: :after, else: direction_atom(direction)

    {rest,
     %{
       rule: :date_dir,
       count: number(count) || 1,
       weekday: weekday_atom(weekday),
       direction: direction
     }}
  end

  defp build(:if_holiday, [type, count, direction, weekday, omit | _], rest) do
    {rest,
     %{
       rule: :if_holiday,
       type: blank(type) && String.to_atom(type),
       count: number(count) || 1,
       direction: direction_atom(direction),
       weekday: weekday_atom(weekday),
       omit: omit |> weekday_list() |> Enum.reject(&(&1 == :day))
     }}
  end

  defp build(:bridge, [type | _], rest),
    do: {rest, %{rule: :bridge, type: blank(type) && String.to_atom(type)}}

  defp build(:time, [hour, minute, bare_hour | _], rest) do
    hour = number(hour) || 0

    {rest,
     %{
       rule: :time,
       hour: if(hour == 0, do: number(bare_hour) || 0, else: hour),
       minute: number(minute) || 0
     }}
  end

  defp build(:duration, [days, hours, minutes | _], rest) do
    hours = (number(days) || 0) * 24 + (number(hours) || 0) + (number(minutes) || 0) / 60
    {rest, %{rule: :duration, duration: hours}}
  end

  defp build(:modifier, [modifier | _], rest),
    do: {rest, %{modifier: modifier |> String.replace(" ", "_") |> String.to_atom()}}

  defp build(:same_day, _captures, rest), do: {rest, []}

  defp build(:active_from, [year, month, day | _], rest),
    do:
      {rest,
       %{rule: :active_from, year: number(year), month: number(month) || 1, day: number(day) || 1}}

  defp build(:active_to, [year, month, day | _], rest),
    do:
      {rest,
       %{rule: :active_to, year: number(year), month: number(month) || 1, day: number(day) || 1}}

  defp number(""), do: nil
  defp number(string), do: String.to_integer(string)

  defp blank(""), do: nil
  defp blank(string), do: string

  defp index(list, name), do: Enum.find_index(list, &(&1 == name)) + 1

  # AdarII is listed before Adar so the longer token wins, then the numbering
  # is corrected: Adar is 12, Adar II is 13.
  defp hebrew_month("Adar"), do: 12
  defp hebrew_month("AdarII"), do: 13
  defp hebrew_month(name), do: index(@hebrew_months, name)

  defp weekday_list(""), do: []

  defp weekday_list(string) do
    string |> String.split(~r/,\s?/) |> Enum.reject(&(&1 == "")) |> Enum.map(&weekday_atom/1)
  end

  defp weekday_atom(""), do: nil
  defp weekday_atom(name), do: name |> String.downcase() |> String.to_atom()

  defp direction_atom(""), do: nil
  defp direction_atom(name), do: String.to_atom(name)

  @doc """
  The two reorderings the reference parser applies after tokenizing.

  Buffered `date_dir` tokens come out reversed after the next other token,
  so `friday after 4th thursday in November` evaluates November 1st, then
  the 4th Thursday, then the Friday after it. Modifiers written before the
  first `fn` token are rotated behind it, so `substitutes 01-01 if ...`
  applies the modifier after the date exists.

      iex> Dayoff.Parser.parse!("friday after 4th thursday in November") |> Enum.map(&Map.take(&1, [:fn, :rule, :count, :weekday]))
      [%{fn: :gregorian}, %{rule: :date_dir, count: 4, weekday: :thursday}, %{rule: :date_dir, count: 1, weekday: :friday}]

      iex> Dayoff.Parser.parse!("substitutes 01-01 if Sunday then next Monday") |> Enum.map(&Map.take(&1, [:fn, :rule, :modifier]))
      [%{fn: :gregorian}, %{modifier: :substitutes}, %{rule: :date_if_then}]
  """
  @spec reorder([token()]) :: [token()]
  def reorder(tokens) do
    {result, _buffer} =
      Enum.reduce(tokens, {[], []}, fn token, {result, buffer} ->
        {result, buffer} =
          if token[:rule] == :date_dir do
            {result, [token | buffer]}
          else
            {result ++ [token] ++ buffer, []}
          end

        {rotate_modifiers(result, token), buffer}
      end)

    result
  end

  defp rotate_modifiers([%{modifier: _} | _] = result, %{fn: _}) do
    {modifiers, rest} = Enum.split_while(result, &Map.has_key?(&1, :modifier))
    rest ++ modifiers
  end

  defp rotate_modifiers(result, _token), do: result
end
