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

  alias Dayoff.Data

  @typedoc "A country code as `\"US\"`, `\"us\"`, `:us` or `\"US-CA\"`."
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
