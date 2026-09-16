defmodule Dayoff.ParserTest do
  use ExUnit.Case, async: true

  alias Dayoff.Parser

  doctest Parser

  test "every rule string in the shipped data parses" do
    rules =
      for {_code, country} <- Dayoff.Data.raw()["holidays"],
          rule <- rules_of(country),
          uniq: true,
          do: rule

    failures = Enum.reject(rules, &match?({:ok, _}, Parser.parse(&1)))
    assert failures == [], "unparseable rules:\n" <> Enum.join(failures, "\n")
    assert length(rules) > 1_500
  end

  defp rules_of(entry) do
    Map.keys(entry["days"] || %{}) ++
      Enum.flat_map(Map.values(entry["states"] || %{}), &rules_of/1) ++
      Enum.flat_map(Map.values(entry["regions"] || %{}), &rules_of/1)
  end

  describe "productions" do
    test "fixed dates, with and without a year" do
      assert Parser.parse!("01-01") == [%{fn: :gregorian, year: nil, month: 1, day: 1}]
      assert Parser.parse!("2015-10-09") == [%{fn: :gregorian, year: 2015, month: 10, day: 9}]
      assert Parser.parse!("February") == [%{fn: :gregorian, year: nil, month: 2, day: 1}]
    end

    test "easter, orthodox and julian" do
      assert Parser.parse!("easter -2") == [%{fn: :easter, type: :easter, offset: -2}]
      assert Parser.parse!("orthodox +9") == [%{fn: :easter, type: :orthodox, offset: 9}]
      assert Parser.parse!("julian 12-25") == [%{fn: :julian, year: nil, month: 12, day: 25}]
    end

    test "other calendars" do
      assert Parser.parse!("1 Shawwal P3D") == [
               %{fn: :islamic, day: 1, month: 10, year: nil},
               %{rule: :duration, duration: 72}
             ]

      assert Parser.parse!("14 AdarII") == [%{fn: :hebrew, day: 14, month: 13, year: nil}]
      assert Parser.parse!("13 Adar") == [%{fn: :hebrew, day: 13, month: 12, year: nil}]
      assert Parser.parse!("22 Bahman") == [%{fn: :jalaali, day: 22, month: 11, year: nil}]

      assert Parser.parse!("bengali-revised 1-1") == [
               %{fn: :bengali_revised, year: nil, month: 1, day: 1}
             ]

      assert Parser.parse!("chinese 01-0-01") == [
               %{fn: :chinese, cycle: nil, year: nil, month: 1, leap_month: false, day: 1}
             ]

      assert Parser.parse!("chinese 5-01 solarterm") == [
               %{fn: :chinese, cycle: nil, year: nil, solarterm: 5, day: 1}
             ]

      assert Parser.parse!("march equinox in +09:00") == [
               %{fn: :equinox, season: :march, timezone: "+09:00"}
             ]

      assert Parser.parse!("december solstice") == [
               %{fn: :equinox, season: :december, timezone: "GMT"}
             ]
    end

    test "if then clauses, with a sub-parsed time" do
      [_date, clause] =
        Parser.parse!("12-24 14:00 if sunday then 00:00" |> String.replace(" 14:00", ""))

      assert clause == %{
               rule: :date_if_then,
               if: [:sunday],
               direction: nil,
               then: nil,
               rules: [%{rule: :time, hour: 0, minute: 0}]
             }

      tokens = Parser.parse!("01-01 and if saturday then next monday if sunday then next tuesday")

      assert Enum.map(tokens, &(&1[:rule] || &1[:modifier] || &1[:fn])) == [
               :gregorian,
               :and,
               :date_if_then,
               :date_if_then
             ]
    end

    test "time shortens nothing here, duration is in hours" do
      assert Parser.parse!("12-31 14:00") == [
               %{fn: :gregorian, year: nil, month: 12, day: 31},
               %{rule: :time, hour: 14, minute: 0}
             ]

      assert Parser.parse!("easter -46 PT14H") |> List.last() == %{rule: :duration, duration: 14}
      assert Parser.parse!("julian 12-25 P2D") |> List.last() == %{rule: :duration, duration: 48}
    end

    test "year filters, weekday filters and active ranges" do
      assert Parser.parse!("1st sunday in October in even years") |> List.last() == %{
               rule: :year,
               cardinality: :even,
               every: nil,
               since: nil
             }

      assert Parser.parse!("12-01 every 6 years since 1934") |> List.last() == %{
               rule: :year,
               cardinality: nil,
               every: 6,
               since: 1934
             }

      assert Parser.parse!("05-04 not on sunday, monday") |> List.last() == %{
               rule: :weekday,
               not: true,
               if: [:sunday, :monday]
             }

      assert Parser.parse!("02-01 since 2020 prior to 2050") |> Enum.drop(1) == [
               %{rule: :active_from, year: 2020, month: 1, day: 1},
               %{rule: :active_to, year: 2050, month: 1, day: 1}
             ]

      assert Parser.parse!("Monday after 2nd saturday in June since 2022-09-09") |> List.last() ==
               %{rule: :active_from, year: 2022, month: 9, day: 9}
    end

    test "bridge days, if-holiday and the discarded #N suffix" do
      tokens = Parser.parse!("09-22 if 09-21 and 09-23 is public holiday")

      assert Enum.map(tokens, &(&1[:rule] || &1[:modifier] || &1[:fn])) == [
               :gregorian,
               :if,
               :gregorian,
               :and,
               :gregorian,
               :bridge
             ]

      assert List.last(tokens) == %{rule: :bridge, type: :public}

      assert Parser.parse!("Thursday after 04-02 if is observance holiday then next Thursday")
             |> List.last() ==
               %{
                 rule: :if_holiday,
                 type: :observance,
                 count: 1,
                 direction: :next,
                 weekday: :thursday,
                 omit: []
               }

      assert Parser.parse!("04-29 #1") == Parser.parse!("04-29")
    end

    test "unparseable rules" do
      assert Parser.parse("not a rule") == {:error, :unparseable}

      assert_raise ArgumentError, ~r/could not parse rule/, fn ->
        Parser.parse!("01-01 on mars")
      end
    end
  end
end
