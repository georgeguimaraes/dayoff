defmodule Dayoff.Calendar.Easter do
  @moduledoc """
  Easter Sunday in the Gregorian and the Julian (Orthodox) computus, the
  Gauss algorithm as the reference implementation's `date-easter` has it.
  """

  @doc """
  Western Easter Sunday.

      iex> Dayoff.Calendar.Easter.gregorian(2026)
      ~D[2026-04-05]
  """
  @spec gregorian(integer()) :: Date.t()
  def gregorian(year) do
    k = div(year, 100)
    m = 15 + div(3 * k + 3, 4) - div(8 * k + 13, 25)
    s = 2 - div(3 * k + 3, 4)
    compute(year, m, s, false)
  end

  @doc """
  Orthodox Easter Sunday, computed in the Julian calendar and shifted to
  the Gregorian date.

      iex> Dayoff.Calendar.Easter.orthodox(2026)
      ~D[2026-04-12]
  """
  @spec orthodox(integer()) :: Date.t()
  def orthodox(year), do: compute(year, 15, 0, true)

  defp compute(year, m, s, shift_to_gregorian?) do
    a = rem(year, 19)
    d = rem(19 * a + m, 30)
    r = floor((d + a / 11) / 29)
    og = 21 + d - r
    sz = 7 - rem(floor(year + year / 4 + s), 7)
    oe = 7 - rem(og - sz, 7)
    os = og + oe

    os = if shift_to_gregorian?, do: os + div(year, 100) - div(year, 400) - 2, else: os

    # `os` is a day of March that may run past the month's end.
    Date.add(Date.new!(year, 3, 1), os - 1)
  end
end
