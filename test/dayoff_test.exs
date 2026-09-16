defmodule DayoffTest do
  use ExUnit.Case, async: true

  doctest Dayoff

  test "countries are named in their own language by default" do
    assert Dayoff.countries()["AT"] == "Österreich"
    assert Dayoff.countries(language: "en")["AT"] == "Austria"
    assert map_size(Dayoff.countries()) == 206
  end

  test "states and regions come with display names" do
    assert Dayoff.states("US")["CA"] == "California"

    assert Dayoff.states("AD") == %{
             "03" => Dayoff.states("AD")["03"],
             "07" => Dayoff.states("AD")["07"]
           }

    assert Dayoff.regions("DE", "BY", language: "en")["KATH"] ==
             "Predominantly catholic communities"
  end

  test "day off and weekend normalize the messy upstream field" do
    assert Dayoff.day_off("US") == :sunday
    assert Dayoff.day_off("BD") == :friday
    assert Dayoff.weekend("US") == [:sunday]
    assert Dayoff.weekend("AG") == [:saturday, :sunday]
  end
end
