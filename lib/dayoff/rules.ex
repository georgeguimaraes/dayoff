defmodule Dayoff.Rules do
  @moduledoc false
  # The parsed rules of a selection, cached in persistent_term: one entry per
  # rule string with its tokens and its attributes from the data. Rules the
  # parser rejects are logged and left out, as upstream does. Rules whose type
  # isn't one of the five known ones are left out too, which is also what
  # upstream does (two typos in the data today).

  require Logger

  alias Dayoff.{Data, Holiday, Parser}

  @type compiled :: %{
          rule: String.t(),
          tokens: [Parser.token()],
          spec: map(),
          type: Holiday.type()
        }

  @types Enum.map(Holiday.types(), &Atom.to_string/1)

  @spec compiled(Data.selection()) :: [compiled()]
  def compiled(selection) do
    key = {__MODULE__, selection}

    case :persistent_term.get(key, nil) do
      nil ->
        compiled = selection |> Data.rules() |> compile()
        :persistent_term.put(key, compiled)
        compiled

      compiled ->
        compiled
    end
  end

  defp compile(rules) do
    rules
    |> Enum.sort()
    |> Enum.flat_map(fn {rule, spec} ->
      with {:type, type} when type in @types <- {:type, spec["type"] || "public"},
           {:ok, tokens} <- Parser.parse(rule) do
        [%{rule: rule, tokens: tokens, spec: spec, type: String.to_atom(type)}]
      else
        {:type, type} ->
          Logger.warning(
            "dayoff dropped rule #{inspect(rule)} with unknown type #{inspect(type)}"
          )

          []

        {:error, :unparseable} ->
          Logger.warning("dayoff could not parse rule #{inspect(rule)}")
          []
      end
    end)
  end
end
