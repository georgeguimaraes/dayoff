defmodule Dayoff.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Dayoff.{Evaluator, Parser}

  # Evaluates one rule on its own, with optional sibling rules for the bridge
  # and if-holiday cases, and returns {date, start, end, substitute?} tuples.
  defp dates(rule, year, opts \\ []) do
    spec = Map.merge(%{"type" => "public"}, Map.new(opts[:spec] || %{}))

    compiled = %{
      rule: rule,
      tokens: Parser.parse!(rule),
      spec: spec,
      type: String.to_atom(spec["type"])
    }

    siblings =
      Enum.map(opts[:siblings] || [], fn {sibling, type} ->
        %{
          rule: sibling,
          tokens: Parser.parse!(sibling),
          spec: %{"type" => type},
          type: String.to_atom(type)
        }
      end)

    %{dates: dates} = Evaluator.evaluate(compiled, year, [compiled | siblings], make_ref())

    Enum.map(dates, fn date ->
      {Dayoff.CalDate.date(date), NaiveDateTime.to_time(date.naive),
       NaiveDateTime.to_time(Dayoff.CalDate.end_naive(date)), date.substitute?}
    end)
    |> Enum.map(fn {date, start, finish, substitute?} -> {date, start, finish, substitute?} end)
  end

  defp only_dates(rule, year, opts \\ []), do: rule |> dates(year, opts) |> Enum.map(&elem(&1, 0))

  test "candidates come from the neighbouring years and only the requested year survives" do
    assert only_dates("Sunday before 01-08", 2026) == [~D[2026-01-04]]

    # January 3rd 2027 is a Sunday, so the Sunday before it is in 2026 and dropped.
    assert only_dates("Sunday before 01-03", 2027) == []
    [~D[2025-12-28]] |> Enum.filter(&(&1.year == 2026))

    assert only_dates("4th thursday in November", 2026) == [~D[2026-11-26]]
    assert only_dates("2015-10-09", 2015) == [~D[2015-10-09]]
    assert only_dates("2015-10-09", 2016) == []
  end

  test "a start time shortens the day and a duration overrides it" do
    assert dates("12-31 14:00", 2026) == [{~D[2026-12-31], ~T[14:00:00], ~T[00:00:00], false}]

    assert dates("12-31 14:00 PT5H", 2026) == [
             {~D[2026-12-31], ~T[14:00:00], ~T[19:00:00], false}
           ]

    assert dates("06-05 12:00 if sunday then 00:00", 2022) == [
             {~D[2022-06-05], ~T[00:00:00], ~T[00:00:00], false}
           ]

    assert dates("06-05 12:00 if sunday then 00:00", 2023) == [
             {~D[2023-06-05], ~T[12:00:00], ~T[00:00:00], false}
           ]
  end

  test "date_dir: after includes the anchor day, before never does, next skips it" do
    assert only_dates("monday after 06-01", 2026) == [~D[2026-06-01]]
    assert only_dates("monday before 06-01", 2026) == [~D[2026-05-25]]
    assert only_dates("2nd monday after 06-01", 2026) == [~D[2026-06-08]]
    assert only_dates("friday after 4th thursday in November", 2026) == [~D[2026-11-27]]
    assert only_dates("1st friday before October", 2026) == [~D[2026-09-25]]
  end

  test "if-then: first matching clause wins and substitutes flag the moved copy" do
    rule = "12-25 and if saturday then next monday if sunday then next tuesday"
    assert only_dates(rule, 2027) == [~D[2027-12-25], ~D[2027-12-27]]
    assert dates(rule, 2027) |> Enum.map(&elem(&1, 3)) == [false, true]
    assert only_dates(rule, 2028) == [~D[2028-12-25]]

    assert only_dates("substitutes 01-01 if Sunday then next Monday", 2023) == [~D[2023-01-02]]
    assert only_dates("substitutes 01-01 if Sunday then next Monday", 2024) == []
    assert only_dates("01-01 if sunday then next sunday", 2023) == [~D[2023-01-08]]
  end

  test "substitutes ... and if behaves like and if, the modifier is never reset" do
    assert only_dates("substitutes 04-29 and if sunday then next monday", 2029) == [
             ~D[2029-04-29],
             ~D[2029-04-30]
           ]
  end

  test "year and weekday filters" do
    assert only_dates("07-01 every 5 years since 2014", 2024) == [~D[2024-07-01]]
    assert only_dates("07-01 every 5 years since 2014", 2025) == []
    assert only_dates("1st sunday in October in even years", 2027) == []
    assert only_dates("01-07 in leap years", 2028) == [~D[2028-01-07]]
    assert only_dates("01-01 not on Sunday", 2023) == []
    assert only_dates("01-02 on monday", 2023) == [~D[2023-01-02]]
  end

  test "since and prior to build half-open ranges, a data active list wins" do
    assert only_dates("02-01 since 2020 prior to 2050", 2019) == []

    assert only_dates(
             "02-01 since 2020 prior of nothing" |> String.replace(" prior of nothing", ""),
             2020
           ) == [~D[2020-02-01]]

    assert only_dates("02-01 since 2020 prior to 2050", 2050) == []
    assert only_dates("02-01 prior to 2020", 2019) == [~D[2019-02-01]]
    assert only_dates("Monday after 2nd saturday in June since 2022-09-09", 2022) == []

    assert only_dates("Monday after 2nd saturday in June since 2022-09-09", 2023) == [
             ~D[2023-06-12]
           ]

    active = [%{"from" => 2004}, %{"from" => "1990-01-01", "to" => "1995-06"}]
    assert only_dates("03-15 since 1900", 2000, spec: %{"active" => active}) == []
    assert only_dates("03-15 since 1900", 1993, spec: %{"active" => active}) == [~D[1993-03-15]]
    assert only_dates("03-15 since 1900", 2010, spec: %{"active" => active}) == [~D[2010-03-15]]
  end

  test "disable and enable move or drop a single occurrence" do
    spec = %{"disable" => ["2015-11-23"], "enable" => ["2015-11-27"]}
    assert only_dates("4th monday in November", 2015, spec: spec) == [~D[2015-11-27]]
    assert only_dates("4th monday in November", 2016, spec: spec) == [~D[2016-11-28]]
    assert only_dates("1st monday in May", 2020, spec: %{"disable" => ["2020-05-04"]}) == []

    assert only_dates("1st monday in May", 2020, spec: %{"disable" => ["2020-05-05"]}) == [
             ~D[2020-05-04]
           ]

    assert only_dates("08-10", 2015, spec: %{"disable" => [2015]}) == []
    assert only_dates("08-10", 2015, spec: %{"disable" => ["2015-08"]}) == []
    assert only_dates("08-10", 2015, spec: %{"disable" => ["2015-09"]}) == [~D[2015-08-10]]
  end

  test "bridge days need every referenced day to be a holiday of the type" do
    rule = "09-22 if 09-21 and 09-23 is public holiday"

    siblings_2009 = [
      {"3rd monday in September", "public"},
      {"september equinox in +09:00", "public"}
    ]

    assert only_dates(rule, 2009, siblings: siblings_2009) == [~D[2009-09-22]]
    assert only_dates(rule, 2026, siblings: siblings_2009) == [~D[2026-09-22]]
    assert only_dates(rule, 2025, siblings: siblings_2009) == []

    assert only_dates(rule, 2009,
             siblings: [
               {"3rd monday in September", "observance"},
               {"september equinox in +09:00", "public"}
             ]
           ) == []
  end

  test "if is holiday moves the date past a colliding holiday" do
    rule =
      "03-23 if Tuesday,Wednesday,Thursday then previous Monday if Friday,Saturday,Sunday then next Monday if is public holiday then next Monday"

    assert only_dates(rule, 2026, siblings: []) == [~D[2026-03-23]]
    assert only_dates(rule, 2026, siblings: [{"03-23", "public"}]) == [~D[2026-03-30]]
    assert only_dates(rule, 2026, siblings: [{"03-23", "observance"}]) == [~D[2026-03-23]]
  end

  test "other calendars" do
    # Julian December 25th 2025 falls in Gregorian 2026, that is the one 2026 gets.
    assert only_dates("julian 12-25", 2026) == [~D[2026-01-07]]
    assert only_dates("orthodox -2", 2026) == [~D[2026-04-10]]
    assert only_dates("1 Shawwal", 2026) == [~D[2026-03-20]]
    assert only_dates("14 AdarII", 2026) == [~D[2026-03-03]]
    assert only_dates("1 Farvardin", 2026) == [~D[2026-03-21]]
    assert only_dates("29 Esfand", 2026) == [~D[2026-03-20]]
    assert only_dates("bengali-revised 1-1", 2018) == [~D[2018-04-14]]
    assert only_dates("chinese 01-0-00", 2026) == [~D[2026-02-16]]
    assert only_dates("chinese 5-01 solarterm", 2026) == [~D[2026-04-05]]
    assert only_dates("march equinox in +09:00", 2026) == [~D[2026-03-20]]
    assert only_dates("june solstice in America/Santiago", 2026) == [~D[2026-06-21]]
  end
end
