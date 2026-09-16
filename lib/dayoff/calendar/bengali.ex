defmodule Dayoff.Calendar.Bengali do
  @moduledoc """
  The revised Bengali calendar as `date-bengali-revised` implements it: the
  year starts on April 14th, months have 31 days for the first five and 30
  for the rest, and the eleventh month gets a 31st day when the Gregorian
  year it falls in is a leap year.
  """

  @year_offset 593
  @month_days [31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 30, 30]
  @month_days_leap [31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 31, 30]

  @doc """
  The Gregorian date of a Bengali date.

      iex> Dayoff.Calendar.Bengali.to_gregorian(1425, 1, 1)
      ~D[2018-04-14]
  """
  @spec to_gregorian(integer(), 1..12, 1..31) :: Date.t()
  def to_gregorian(bengali_year, month, day) do
    year = bengali_year + @year_offset
    epoch = Date.new!(year, 4, 13)
    leap_reference = if month > 10, do: year + 1, else: year

    month_days =
      if Date.leap_year?(Date.new!(leap_reference, 1, 1)), do: @month_days_leap, else: @month_days

    Date.add(epoch, day + (month_days |> Enum.take(month - 1) |> Enum.sum()))
  end
end
