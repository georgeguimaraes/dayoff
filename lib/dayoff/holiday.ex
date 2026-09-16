defmodule Dayoff.Holiday do
  @moduledoc """
  One holiday occurrence.

  `start` and `end` are wall-clock times in the country's default timezone
  (see `Dayoff.zones/1`), the way the reference implementation reports them.
  Most holidays run from midnight to the next midnight. Some start in the
  afternoon (`12-24 14:00`), span several days (`1 Shawwal P3D`) or, for the
  Hijri and Hebrew calendars, start at 18:00 the evening before.
  """

  @type type :: :public | :bank | :school | :optional | :observance

  @type t :: %__MODULE__{
          date: Date.t(),
          start: NaiveDateTime.t(),
          end: NaiveDateTime.t(),
          name: String.t(),
          type: type(),
          rule: String.t(),
          substitute?: boolean(),
          note: String.t() | nil
        }

  @enforce_keys [:date, :start, :end, :name, :type, :rule]
  defstruct [:date, :start, :end, :name, :type, :rule, :note, substitute?: false]

  @types [:public, :bank, :school, :optional, :observance]

  @doc "The five holiday types, from the most to the least binding."
  @spec types() :: [type()]
  def types, do: @types
end
