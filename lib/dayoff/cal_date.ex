defmodule Dayoff.CalDate do
  @moduledoc false
  # A candidate holiday date while a rule is being evaluated. Mirrors the
  # reference implementation's mutable CalDate as an immutable struct:
  # a wall-clock naive datetime, a duration in hours (24 by default, shortened
  # by a start time so the holiday still ends at midnight), and the three flags
  # the rule evaluation sets.

  @type t :: %__MODULE__{
          naive: NaiveDateTime.t(),
          duration: number(),
          lock?: boolean(),
          filter?: boolean(),
          substitute?: boolean()
        }

  defstruct [:naive, duration: 24, lock?: false, filter?: false, substitute?: false]

  @spec new(Date.t()) :: t()
  def new(%Date{} = date), do: %__MODULE__{naive: NaiveDateTime.new!(date, ~T[00:00:00])}

  @spec new(integer(), 1..12, integer()) :: t()
  def new(year, month, day), do: new(Date.add(Date.new!(year, month, 1), day - 1))

  @doc "A clean copy: same moment and duration, flags reset (upstream `new CalDate(date)`)."
  @spec copy(t()) :: t()
  def copy(%__MODULE__{naive: naive, duration: duration}),
    do: %__MODULE__{naive: naive, duration: duration}

  @spec date(t()) :: Date.t()
  def date(%__MODULE__{naive: naive}), do: NaiveDateTime.to_date(naive)

  @spec year(t()) :: integer()
  def year(%__MODULE__{naive: naive}), do: naive.year

  @doc "Day of week with Sunday as 0, like JavaScript's `getDay`."
  @spec weekday(t()) :: 0..6
  def weekday(%__MODULE__{} = cal_date), do: Date.day_of_week(date(cal_date), :sunday) - 1

  @spec add_days(t(), integer()) :: t()
  def add_days(%__MODULE__{} = cal_date, 0), do: cal_date

  def add_days(%__MODULE__{naive: naive} = cal_date, days),
    do: %{cal_date | naive: NaiveDateTime.add(naive, days, :day)}

  @spec add_hours(t(), integer()) :: t()
  def add_hours(%__MODULE__{naive: naive} = cal_date, hours),
    do: %{cal_date | naive: NaiveDateTime.add(naive, hours, :hour)}

  @doc "Sets the start time and shortens the duration so the holiday ends at midnight."
  @spec set_time(t(), 0..23, 0..59) :: t()
  def set_time(%__MODULE__{naive: naive} = cal_date, hour, minute) do
    %{
      cal_date
      | naive: NaiveDateTime.new!(NaiveDateTime.to_date(naive), Time.new!(hour, minute, 0)),
        duration: 24 - (hour + minute / 60)
    }
  end

  @spec end_naive(t()) :: NaiveDateTime.t()
  def end_naive(%__MODULE__{naive: naive, duration: duration}),
    do: NaiveDateTime.add(naive, trunc(duration * 60), :minute)

  @spec same_date?(t(), t()) :: boolean()
  def same_date?(left, right), do: date(left) == date(right)
end
