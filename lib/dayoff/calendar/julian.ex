defmodule Dayoff.Calendar.Julian do
  @moduledoc """
  Proleptic Julian calendar dates as Gregorian `Date`s, for rules like
  `julian 12-25` (Orthodox Christmas).
  """

  # ISO days of Julian 0001-01-01, which is Gregorian 0000-12-30.
  @epoch Calendar.ISO.date_to_iso_days(0, 12, 30)

  @doc """
  The Gregorian date of a Julian calendar date.

      iex> Dayoff.Calendar.Julian.to_gregorian(2026, 12, 25)
      ~D[2027-01-07]

      iex> Dayoff.Calendar.Julian.to_gregorian(2026, 1, 1)
      ~D[2026-01-14]
  """
  @spec to_gregorian(integer(), 1..12, 1..31) :: Date.t()
  def to_gregorian(year, month, day) do
    y = if year < 0, do: year + 1, else: year

    correction =
      cond do
        month <= 2 -> 0
        leap?(year) -> -1
        true -> -2
      end

    iso_days =
      @epoch - 1 + 365 * (y - 1) + Integer.floor_div(y - 1, 4) +
        div(367 * month - 362, 12) + correction + day

    {gregorian_year, gregorian_month, gregorian_day} = Calendar.ISO.date_from_iso_days(iso_days)
    Date.new!(gregorian_year, gregorian_month, gregorian_day)
  end

  defp leap?(year), do: Integer.mod(if(year > 0, do: year, else: year + 1), 4) == 0
end
