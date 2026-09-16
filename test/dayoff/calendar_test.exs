defmodule Dayoff.CalendarTest do
  use ExUnit.Case, async: true

  alias Dayoff.Calendar.{Bengali, Easter, Jalaali, Julian, Tables}

  doctest Easter
  doctest Julian
  doctest Bengali
  doctest Jalaali
  doctest Tables

  test "easter across the century boundary and a late orthodox easter" do
    assert Easter.gregorian(2000) == ~D[2000-04-23]
    assert Easter.gregorian(2038) == ~D[2038-04-25]
    assert Easter.orthodox(2000) == ~D[2000-04-30]
    assert Easter.orthodox(2024) == ~D[2024-05-05]
  end

  test "jalaali round trips and leap years" do
    assert Jalaali.to_gregorian(1403, 12, 30) == ~D[2025-03-20]
    assert Jalaali.from_gregorian(~D[2025-03-20]) == {1403, 12, 30}
    assert Jalaali.from_gregorian(~D[2026-03-21]) == {1405, 1, 1}
    assert Jalaali.from_gregorian(~D[2026-12-31]) == {1405, 10, 10}
  end

  test "bengali leap day in the eleventh month" do
    assert Bengali.to_gregorian(1430, 11, 31) == ~D[2024-03-14]
    assert Bengali.to_gregorian(1431, 12, 1) == ~D[2025-03-15]
  end

  test "mapped calendars honour an explicit calendar year and a month starting twice" do
    assert Tables.mapped_dates(:hijri, 2026, 10, 1, 1447) == [~D[2026-03-20]]
    assert Tables.mapped_dates(:hijri, 2026, 10, 1, 1400) == []
    assert Tables.mapped_dates(:hijri, 1970, 11, 1, nil) == [~D[1970-01-08], ~D[1970-12-30]]
  end

  test "lunar leap requests take the following month and the tables know their range" do
    assert Tables.lunar_date(:chinese, 2025, 6, true, 1) == ~D[2025-07-25]
    assert Tables.lunar_date(:chinese, 2026, 5, true, 1) == ~D[2026-07-14]
    assert Tables.lunar_date(:vietnamese, 2026, 1, false, 1) == ~D[2026-02-17]
    assert Tables.lunar_date(:chinese, 1850, 1, false, 1) == nil
    assert Tables.mapped_dates(:hebrew, 1900, 1, 1, nil) == []
  end
end
