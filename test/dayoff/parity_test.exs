defmodule Dayoff.ParityTest do
  @moduledoc """
  Compares `Dayoff.holidays/3` with what the reference implementation
  returned for the same data. Fixtures come from `mix dayoff.sync`
  (`scripts/sync/fixtures.mjs`); `DAYOFF_FIXTURES` points at another
  directory, the sync workflow uses that for the wide year range.
  """
  use ExUnit.Case, async: true

  @fixtures_dir System.get_env("DAYOFF_FIXTURES", "test/fixtures/reference")
  @fixture_files @fixtures_dir
                 |> Path.join("*.json")
                 |> Path.wildcard()
                 |> Enum.reject(&String.ends_with?(&1, "unparseable_rules.json"))

  for file <- @fixture_files do
    test "#{Path.basename(file, ".json")} matches the reference implementation" do
      fixture = unquote(file) |> File.read!() |> JSON.decode!()
      country = fixture["country"]

      differences =
        compare(country, [], fixture["national"]) ++
          Enum.flat_map(fixture["states"], fn {state, by_year} ->
            compare(country, [state: state], by_year)
          end) ++
          Enum.flat_map(fixture["regions"], fn {path, by_year} ->
            [state, region] = String.split(path, "/")
            compare(country, [state: state, region: region], by_year)
          end)

      assert differences == [], Enum.join(differences, "\n")
    end
  end

  defp compare(country, opts, by_year) do
    Enum.flat_map(by_year, fn {year, expected} ->
      actual = country |> Dayoff.holidays(String.to_integer(year), opts) |> Enum.map(&row/1)
      expected = expected |> Enum.map(&List.delete_at(&1, 7)) |> Enum.sort()

      case {expected -- actual, actual -- expected} do
        {[], []} -> []
        {missing, extra} -> describe(country, opts, year, missing, extra)
      end
    end)
  end

  defp row(holiday) do
    [
      Date.to_iso8601(holiday.date),
      wall_clock(holiday.start),
      wall_clock(holiday.end),
      holiday.name,
      Atom.to_string(holiday.type),
      holiday.rule,
      holiday.substitute?
    ]
  end

  defp wall_clock(naive),
    do: naive |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()

  defp describe(country, opts, year, missing, extra) do
    where = Enum.map_join([country | Keyword.values(opts)], "-", &to_string/1)

    Enum.map(missing, &"#{where} #{year} missing #{inspect(&1)}") ++
      Enum.map(extra, &"#{where} #{year} extra   #{inspect(&1)}")
  end
end
