defmodule Dayoff.Data do
  @moduledoc """
  Access to the holiday dataset in `priv/data/holidays.json`.

  The file is decoded once into `:persistent_term` on first use. Rules for a
  country, state and region are merged the way the reference implementation
  merges them and cached per selection, so repeated calls are cheap.

  Codes are what the dataset uses: uppercase ISO 3166-1 country codes and the
  upstream state and region codes (`"CA"`, `"BY"`, `"07"`, `"KATH"`). All of
  them are strings, and a lowercase country code is accepted.
  """

  @data_file "holidays.json"
  @version_file "VERSION.json"

  @typedoc "Country, state and region selection."
  @type selection :: %{country: String.t(), state: String.t() | nil, region: String.t() | nil}

  @doc false
  def priv_path(file), do: Path.join([:code.priv_dir(:dayoff), "data", file])

  @doc "The decoded dataset: `holidays` by country code and the shared `names`."
  @spec raw() :: map()
  def raw do
    case :persistent_term.get({__MODULE__, :raw}, nil) do
      nil ->
        data = @data_file |> priv_path() |> File.read!() |> JSON.decode!()
        :persistent_term.put({__MODULE__, :raw}, data)
        data

      data ->
        data
    end
  end

  @doc "What `mix dayoff.sync` recorded about the upstream commits."
  @spec version() :: map()
  def version do
    @version_file |> priv_path() |> File.read!() |> JSON.decode!()
  end

  @doc """
  Normalizes a country, state and region into a selection, raising
  `ArgumentError` with the known codes when something doesn't exist.

  `country` may carry the state and region separated by dashes (`"US-CA"`,
  `"DE-BY-A"`), as the reference implementation allows.
  """
  @spec selection!(String.t(), keyword()) :: selection()
  def selection!(country, opts \\ []) do
    {country, state, region} = split_codes(country, opts[:state], opts[:region])
    country_code = country_code!(country)
    country_data = raw()["holidays"][country_code]

    subdivisions = country_data["states"] || country_data["regions"] || %{}

    state_code =
      if state,
        do: subdivision_code!(subdivisions, state, "#{country_code} has no state or region")

    regions = if state_code, do: subdivisions[state_code]["regions"] || %{}, else: %{}

    region_code =
      if region,
        do: subdivision_code!(regions, region, "#{country_code}-#{state_code} has no region")

    %{country: country_code, state: state_code, region: region_code}
  end

  defp split_codes(country, state, region) when is_binary(country) do
    case String.split(country, "-") do
      [country] ->
        {country, state, region}

      [country, state] ->
        {country, state, region}

      [country, state, region] ->
        {country, state, region}

      _ ->
        raise ArgumentError,
              "expected a country code like \"US\" or \"US-CA\", got #{inspect(country)}"
    end
  end

  defp split_codes(country, _state, _region) do
    raise ArgumentError, "expected a country code like \"US\", got #{inspect(country)}"
  end

  defp country_code!(country) do
    code = String.upcase(country)

    if Map.has_key?(raw()["holidays"], code) do
      code
    else
      raise ArgumentError,
            "unknown country #{inspect(country)}. Known: #{raw()["holidays"] |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
    end
  end

  defp subdivision_code!(_candidates, code, _message) when not is_binary(code) do
    raise ArgumentError, "expected a state or region code like \"CA\", got #{inspect(code)}"
  end

  defp subdivision_code!(candidates, code, message) do
    cond do
      Map.has_key?(candidates, code) ->
        code

      match = Enum.find(Map.keys(candidates), &(String.downcase(&1) == String.downcase(code))) ->
        match

      true ->
        raise ArgumentError,
              "#{message} #{inspect(code)}. Known: #{candidates |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
    end
  end

  @doc "The country entry, or the state or region entry when selected."
  @spec entry(selection()) :: map()
  def entry(%{country: country, state: nil}), do: raw()["holidays"][country]

  def entry(%{country: country, state: state, region: nil}),
    do: subdivisions(raw()["holidays"][country])[state]

  def entry(%{country: country, state: state, region: region}) do
    subdivisions(raw()["holidays"][country])[state]["regions"][region]
  end

  defp subdivisions(country_data), do: country_data["states"] || country_data["regions"] || %{}

  @doc """
  A field looked up from the region, then the state, then the country, the
  first one that has it. The reference implementation never reaches the
  region level here because of a typo; dayoff does.
  """
  @spec inherited(selection(), String.t()) :: term()
  def inherited(selection, key) do
    [
      selection,
      %{selection | region: nil},
      %{selection | state: nil, region: nil}
    ]
    |> Enum.uniq()
    |> Enum.find_value(fn candidate -> present(entry(candidate)[key]) end)
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present([]), do: nil
  defp present(value), do: value

  @doc """
  The rules for a selection: country rules, then the state's, then the
  region's, each level overriding by exact rule string, `false` deleting a
  rule, and `_name` references resolved from the shared names. Cached.
  """
  @spec rules(selection()) :: %{String.t() => map()}
  def rules(selection) do
    key = {__MODULE__, :rules, selection}

    case :persistent_term.get(key, nil) do
      nil ->
        rules = build_rules(selection)
        :persistent_term.put(key, rules)
        rules

      rules ->
        rules
    end
  end

  defp build_rules(%{country: country, state: state, region: region}) do
    data = raw()
    country_data = data["holidays"][country]

    levels =
      [country_data] ++
        List.wrap(state && subdivisions(country_data)[state]) ++
        List.wrap(region && subdivisions(country_data)[state]["regions"][region])

    levels
    |> Enum.reduce(%{}, &assign(&2, &1, data))
    |> Map.new(fn {rule, spec} -> {rule, resolve_name(spec, data["names"])} end)
  end

  # Mirrors Data._assign: the `_days` reference's days come first, the node's
  # own days on top, then each rule is layered over what the lower levels had.
  # A rule without a type in this node becomes public, even if the level below
  # made it an observance. That is what upstream does, so parity keeps it.
  defp assign(out, node, data) do
    referenced =
      case node["_days"] do
        nil -> %{}
        reference -> referenced_days!(data, reference)
      end

    days = Map.merge(referenced, node["days"] || %{})

    Enum.reduce(days, out, fn
      {rule, false}, acc ->
        Map.delete(acc, rule)

      {rule, spec}, acc ->
        merged = Map.merge(acc[rule] || %{}, spec)

        merged =
          if Map.has_key?(spec, "type"), do: merged, else: Map.put(merged, "type", "public")

        Map.put(acc, rule, merged)
    end)
  end

  defp referenced_days!(data, reference) do
    path = List.wrap(reference)

    case get_in(data, ["holidays" | path] ++ ["days"]) do
      nil -> raise ArgumentError, "unknown path for _days: #{Enum.join(path, ".")}"
      days -> days
    end
  end

  # `_name` points at the shared names table. Upstream deep merges the shared
  # entry under the rule's own fields, so a partial `name` map only overrides
  # the languages it lists.
  defp resolve_name(%{"_name" => reference} = spec, names) do
    case names[reference] do
      nil -> spec
      shared -> deep_merge(shared, Map.delete(spec, "_name"))
    end
  end

  defp resolve_name(spec, _names), do: spec

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, l, r -> deep_merge(l, r) end)
  end

  defp deep_merge(_left, right), do: right
end
