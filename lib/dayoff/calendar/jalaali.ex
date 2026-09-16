defmodule Dayoff.Calendar.Jalaali do
  @moduledoc """
  The Jalaali (Persian) calendar, the arithmetic algorithm of `jalaali-js`
  (Behrooz Khosravi, after Borkowski) which the reference implementation
  uses. Valid for Jalaali years -61 to 3177.
  """

  @breaks [
    -61,
    9,
    38,
    199,
    426,
    686,
    756,
    818,
    1111,
    1181,
    1210,
    1635,
    2060,
    2097,
    2192,
    2262,
    2324,
    2394,
    2456,
    3178
  ]

  @doc """
  The Gregorian date of a Jalaali date.

      iex> Dayoff.Calendar.Jalaali.to_gregorian(1405, 1, 1)
      ~D[2026-03-21]
  """
  @spec to_gregorian(integer(), 1..12, 1..31) :: Date.t()
  def to_gregorian(jalaali_year, month, day) do
    {gregorian_year, march} = new_year(jalaali_year)

    iso_days =
      Calendar.ISO.date_to_iso_days(gregorian_year, 3, march) + (month - 1) * 31 -
        div(month, 7) * (month - 7) + day - 1

    iso_days |> Calendar.ISO.date_from_iso_days() |> then(fn {y, m, d} -> Date.new!(y, m, d) end)
  end

  @doc """
  The Jalaali date of a Gregorian date, as `{year, month, day}`.

      iex> Dayoff.Calendar.Jalaali.from_gregorian(~D[2026-01-01])
      {1404, 10, 11}
  """
  @spec from_gregorian(Date.t()) :: {integer(), 1..12, 1..31}
  def from_gregorian(%Date{year: gregorian_year} = date) do
    jalaali_year = gregorian_year - 621
    {leap, _gregorian_year, march} = calendar(jalaali_year)
    k = Date.diff(date, Date.new!(gregorian_year, 3, march))

    cond do
      k >= 0 and k <= 185 -> {jalaali_year, 1 + div(k, 31), rem(k, 31) + 1}
      k >= 0 -> autumn(jalaali_year, k - 186)
      leap == 1 -> autumn(jalaali_year - 1, k + 180)
      true -> autumn(jalaali_year - 1, k + 179)
    end
  end

  defp autumn(jalaali_year, k), do: {jalaali_year, 7 + div(k, 30), rem(k, 30) + 1}

  defp new_year(jalaali_year) do
    {_leap, gregorian_year, march} = calendar(jalaali_year)
    {gregorian_year, march}
  end

  # jalCal: the Gregorian year and the day of March the Jalaali year starts
  # on, plus the years since the last leap year.
  defp calendar(jalaali_year) do
    if jalaali_year < hd(@breaks) or jalaali_year >= List.last(@breaks) do
      raise ArgumentError, "invalid Jalaali year #{jalaali_year}"
    end

    gregorian_year = jalaali_year + 621

    {leap_j, jp, jump} =
      Enum.reduce_while(tl(@breaks), {-14, hd(@breaks), 0}, fn jm, {leap_j, jp, _jump} ->
        jump = jm - jp

        if jalaali_year < jm do
          {:halt, {leap_j, jp, jump}}
        else
          {:cont, {leap_j + div(jump, 33) * 8 + div(rem(jump, 33), 4), jm, jump}}
        end
      end)

    n = jalaali_year - jp
    leap_j = leap_j + div(n, 33) * 8 + div(rem(n, 33) + 3, 4)
    leap_j = if rem(jump, 33) == 4 and jump - n == 4, do: leap_j + 1, else: leap_j
    leap_g = div(gregorian_year, 4) - div((div(gregorian_year, 100) + 1) * 3, 4) - 150
    march = 20 + leap_j - leap_g

    n = if jump - n < 6, do: n - jump + div(jump + 4, 33) * 33, else: n
    leap = rem(rem(n + 1, 33) - 1, 4)
    leap = if leap == -1, do: 4, else: leap

    {leap, gregorian_year, march}
  end
end
