defmodule Dayoff.DataTest do
  use ExUnit.Case, async: true

  alias Dayoff.Data

  describe "selection!/2" do
    test "normalizes country codes and splits dashed codes" do
      assert Data.selection!("us") == %{country: "US", state: nil, region: nil}
      assert Data.selection!("us-ca") == %{country: "US", state: "CA", region: nil}

      assert Data.selection!("DE", state: "BY", region: "A") == %{
               country: "DE",
               state: "BY",
               region: "A"
             }

      assert Data.selection!("DE-BY-A") == %{country: "DE", state: "BY", region: "A"}
    end

    test "country-level regions are selected as states, like upstream" do
      assert Data.selection!("AD", state: "07").state == "07"
    end

    test "atoms are not codes" do
      assert_raise ArgumentError, ~r/expected a country code like "US", got :us/, fn ->
        Data.selection!(:us)
      end

      assert_raise ArgumentError, ~r/expected a state or region code like "CA", got :ca/, fn ->
        Data.selection!("US", state: :ca)
      end
    end

    test "unknown codes raise with the known ones" do
      assert_raise ArgumentError, ~r/unknown country "XX". Known: AD, AE/, fn ->
        Data.selection!("XX")
      end

      assert_raise ArgumentError, ~r/US has no state or region "XX". Known: AK, AL/, fn ->
        Data.selection!("US", state: "XX")
      end

      assert_raise ArgumentError, ~r/DE-BY has no region "XX". Known: A, EVANG, KATH/, fn ->
        Data.selection!("DE-BY-XX")
      end
    end
  end

  describe "rules/1" do
    test "a state can delete a country rule with false" do
      assert Map.has_key?(Data.rules(Data.selection!("AU")), "04-25")
      refute Map.has_key?(Data.rules(Data.selection!("AU", state: "ACT")), "04-25")
    end

    test "rules without a type are public, even when overriding a typed country rule" do
      assert Data.rules(Data.selection!("DE"))["easter"]["type"] == "observance"
      assert Data.rules(Data.selection!("DE", state: "BB"))["easter"]["type"] == "public"
    end

    test "_name resolves from the shared names and a partial name overrides only its languages" do
      rule = Data.rules(Data.selection!("US", state: "LA"))["easter -47"]
      assert rule["name"]["en"] == "Mardi Gras"
      assert rule["name"]["de"] == "Faschingsdienstag"
      refute Map.has_key?(rule, "_name")
    end

    test "_days pulls another node's rules, as a code or a path" do
      canary = Data.rules(Data.selection!("IC"))
      assert Map.has_key?(canary, "01-01")
      assert canary["05-30"]["name"]["en"] == "Canary Islands Day"

      augsburg = Data.rules(Data.selection!("DE", state: "BY", region: "A"))
      assert augsburg["08-15"]["type"] == "public"
      assert Map.has_key?(augsburg, "08-08")
    end
  end

  describe "inherited/2" do
    test "falls back from region to state to country and skips empty values" do
      assert Data.inherited(Data.selection!("US", state: "CA"), "zones") == [
               "America/Los_Angeles"
             ]

      assert Data.inherited(Data.selection!("US", state: "CA", region: "LA"), "langs") == [
               "en-us",
               "en"
             ]

      assert Data.inherited(Data.selection!("ES", state: "CN"), "dayoff") == "sunday"
    end
  end
end
