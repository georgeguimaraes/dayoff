defmodule Dayoff.Evaluator do
  @moduledoc false
  # Turns one parsed rule into its dates for a year. A port of the reference
  # DateFn, Rule, CalEvent and PostRule put together.
  #
  # Every fn token yields candidate dates for the year before, the year and the
  # year after, the rule tokens move and filter them, and only dates in the
  # requested year survive the final active filter. Each candidate is a
  # `Dayoff.CalDate`.

  alias Dayoff.CalDate
  alias Dayoff.Calendar.{Bengali, Easter, Jalaali, Julian, Tables}

  @type event :: %{fn: map(), dates: [CalDate.t()], active: [map()] | nil}
  @type result :: %{dates: [CalDate.t()], kind: atom()}

  @weekday_numbers %{
    sunday: 0,
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6
  }

  @doc """
  The dates of `compiled` in `year`. `siblings` are the other compiled rules
  of the same selection, needed by bridge and if-holiday rules; `memo_key`
  scopes their memoized evaluation in the process dictionary, see
  `memoized/4` and `clear_memo/1`.
  """
  @spec evaluate(map(), integer(), [map()], term()) :: result()
  def evaluate(compiled, year, siblings, memo_key) do
    state = %{
      events: [],
      modifier: nil,
      year: year,
      siblings: siblings,
      memo_key: memo_key,
      rule: compiled.rule
    }

    state = Enum.reduce(compiled.tokens, state, &apply_token/2)

    case state.events do
      [] ->
        %{dates: [], kind: nil}

      [first | _] ->
        first =
          first
          |> disable(compiled.spec, year)
          |> filter_active(year, active_from_spec(compiled.spec))

        %{dates: first.dates, kind: first.fn.fn}
    end
  end

  @doc """
  `evaluate/4` memoized in the process dictionary under `memo_key`, so a
  rule evaluated as a sibling of a bridge rule isn't evaluated again. A rule
  that is already being evaluated (rules referring to each other) yields no
  dates. Call `clear_memo/1` when done.
  """
  @spec memoized(map(), integer(), [map()], term()) :: result()
  def memoized(compiled, year, siblings, memo_key) do
    key = {__MODULE__, memo_key, year, compiled.rule}

    case Process.get(key) do
      nil ->
        Process.put(key, :in_progress)
        result = evaluate(compiled, year, siblings, memo_key)
        Process.put(key, result)
        result

      :in_progress ->
        %{dates: [], kind: nil}

      result ->
        result
    end
  end

  @doc "Drops what `memoized/4` stored under `memo_key`."
  @spec clear_memo(term()) :: :ok
  def clear_memo(memo_key) do
    for {__MODULE__, ^memo_key, _year, _rule} = key <- Process.get_keys(), do: Process.delete(key)
    :ok
  end

  defp sibling_dates(compiled, state) do
    memoized(compiled, state.year, state.siblings, state.memo_key).dates
  end

  ## Tokens

  defp apply_token(%{fn: _} = token, state) do
    dates = Enum.flat_map((state.year - 1)..(state.year + 1), &dates_in_year(token, &1))
    %{state | events: state.events ++ [%{fn: token, dates: dates, active: nil}]}
  end

  defp apply_token(%{modifier: modifier}, state), do: %{state | modifier: modifier}

  defp apply_token(%{rule: :bridge} = token, state), do: bridge(token, state)
  defp apply_token(%{rule: :if_holiday} = token, state), do: if_holiday(token, state)

  defp apply_token(%{rule: _} = token, state) do
    update_last_event(state, fn event -> apply_rule(token, event, state.modifier) end)
  end

  defp update_last_event(%{events: events} = state, fun) do
    {last, rest} = List.pop_at(events, -1)
    %{state | events: rest ++ [fun.(last)]}
  end

  ## Candidate dates per calendar

  defp dates_in_year(%{fn: :gregorian, year: fixed_year}, year)
       when fixed_year not in [nil, year], do: []

  defp dates_in_year(%{fn: :gregorian, month: month, day: day}, year),
    do: [CalDate.new(year, month, day)]

  defp dates_in_year(%{fn: :julian, year: fixed_year}, year) when fixed_year not in [nil, year],
    do: []

  defp dates_in_year(%{fn: :julian, month: month, day: day}, year),
    do: [CalDate.new(Julian.to_gregorian(year, month, day))]

  defp dates_in_year(%{fn: :easter, type: type, offset: offset}, year) do
    easter = if type == :orthodox, do: Easter.orthodox(year), else: Easter.gregorian(year)
    [easter |> CalDate.new() |> CalDate.add_days(offset)]
  end

  defp dates_in_year(%{fn: :islamic, month: month, day: day, year: calendar_year}, year) do
    Enum.map(Tables.mapped_dates(:hijri, year, month, day, calendar_year), &CalDate.new/1)
  end

  defp dates_in_year(%{fn: :hebrew, month: month, day: day, year: calendar_year}, year) do
    Enum.map(Tables.mapped_dates(:hebrew, year, month, day, calendar_year), &CalDate.new/1)
  end

  defp dates_in_year(%{fn: :jalaali, month: month, day: day, year: calendar_year}, year) do
    {nowruz_year, _month, _day} = Jalaali.from_gregorian(Date.new!(year, 1, 1))

    if calendar_year != nil and calendar_year != nowruz_year do
      []
    else
      [CalDate.new(Jalaali.to_gregorian(calendar_year || nowruz_year, month, day))]
    end
  end

  defp dates_in_year(%{fn: calendar, solarterm: term, day: day}, year)
       when calendar in [:chinese, :korean, :vietnamese] do
    calendar |> Tables.solar_term(year, term, day) |> List.wrap() |> Enum.map(&CalDate.new/1)
  end

  defp dates_in_year(%{fn: calendar, month: month, leap_month: leap?, day: day}, year)
       when calendar in [:chinese, :korean, :vietnamese] do
    calendar
    |> Tables.lunar_date(year, month, leap?, day)
    |> List.wrap()
    |> Enum.map(&CalDate.new/1)
  end

  defp dates_in_year(%{fn: :bengali_revised, month: month, day: day}, year) do
    [CalDate.new(Bengali.to_gregorian(year - 593, month, day))]
  end

  defp dates_in_year(%{fn: :equinox, season: season, timezone: timezone}, year) do
    season |> Tables.equinox(year, timezone) |> List.wrap() |> Enum.map(&CalDate.new/1)
  end

  ## Rules on the current event

  defp apply_rule(%{rule: :date_dir} = token, event, _modifier) do
    %{event | dates: Enum.map(event.dates, &date_dir(&1, token))}
  end

  defp apply_rule(%{rule: :date_if_then} = token, event, modifier) do
    {dates, copies} =
      Enum.map_reduce(event.dates, [], fn date, copies ->
        if date.lock? do
          {date, copies}
        else
          date_if_then(date, token, modifier, copies)
        end
      end)

    %{event | dates: Enum.reverse(copies) ++ dates}
  end

  defp apply_rule(%{rule: :weekday, if: weekdays, not: negate?}, event, _modifier) do
    %{
      event
      | dates: Enum.filter(event.dates, fn date -> weekday_name(date) in weekdays != negate? end)
    }
  end

  defp apply_rule(%{rule: :year} = token, event, _modifier) do
    %{event | dates: Enum.filter(event.dates, &year_matches?(CalDate.year(&1), token))}
  end

  defp apply_rule(%{rule: :time, hour: hour, minute: minute}, event, _modifier) do
    %{event | dates: Enum.map(event.dates, &CalDate.set_time(&1, hour, minute))}
  end

  defp apply_rule(%{rule: :duration, duration: duration}, event, _modifier) do
    %{event | dates: Enum.map(event.dates, &%{&1 | duration: duration})}
  end

  defp apply_rule(%{rule: :active_from, year: year, month: month, day: day}, event, _modifier) do
    set_active(event, %{from: NaiveDateTime.new!(year, month, day, 0, 0, 0)})
  end

  defp apply_rule(%{rule: :active_to, year: year, month: month, day: day}, event, _modifier) do
    set_active(event, %{to: NaiveDateTime.new!(year, month, day, 0, 0, 0)})
  end

  # `count`th `weekday` before/after the date. "after" (and "in") includes the
  # date itself, "before" and "previous" never do, "next" skips the same day.
  # The pseudo weekday `day` counts days, skipping omitted weekdays.
  defp date_dir(date, token) do
    weekday = CalDate.weekday(date)
    count = token.count - 1
    before? = token.direction in [:before, :previous]

    offset =
      case token.weekday do
        :day ->
          day_offset(
            count,
            before?,
            weekday,
            Enum.map(Map.get(token, :omit, []), &@weekday_numbers[&1])
          )

        name ->
          weekday_offset(count, before?, weekday, @weekday_numbers[name], token.direction)
      end

    CalDate.add_days(date, offset)
  end

  defp weekday_offset(count, true, weekday, rule_weekday, _direction) do
    count = if weekday == rule_weekday, do: count + 1, else: count
    -(Integer.mod(7 + weekday - rule_weekday, 7) + count * 7)
  end

  defp weekday_offset(count, false, weekday, rule_weekday, direction) do
    count = if direction == :next and weekday == rule_weekday, do: count + 1, else: count
    Integer.mod(7 - weekday + rule_weekday, 7) + count * 7
  end

  defp day_offset(count, before?, weekday, omitted) do
    step = if before?, do: -1, else: 1
    start = (count + 1) * step

    Enum.reduce_while(1..7, start, fn _attempt, offset ->
      if Integer.mod(offset + weekday, 7) in omitted,
        do: {:cont, offset + step},
        else: {:halt, offset}
    end)
  end

  # The clause fires when the date's weekday is listed. With the `and`
  # modifier the original stays and the moved copy is a substitute; with
  # `substitutes` dates the clause doesn't match are filtered out and moved
  # dates are substitutes. A moved date is locked so later clauses skip it.
  defp date_if_then(date, token, modifier, copies) do
    if weekday_name(date) in token.if do
      copies = if modifier == :and, do: [CalDate.copy(date) | copies], else: copies

      date =
        %{date | filter?: false, substitute?: date.substitute? or modifier == :and}
        |> move_to_then(token, modifier)
        |> apply_clause_rules(token.rules)

      {date, copies}
    else
      {if(modifier == :substitutes, do: %{date | filter?: true}, else: date), copies}
    end
  end

  # `then next X` from an X moves a full week, unlike date_dir.
  defp move_to_then(date, %{then: nil}, _modifier), do: date

  defp move_to_then(date, %{then: then, direction: direction}, modifier) do
    weekday = CalDate.weekday(date)
    then = @weekday_numbers[then]

    offset =
      if direction == :previous do
        -Integer.mod(7 + weekday - then, 7)
      else
        Integer.mod(7 - weekday + then, 7)
      end

    offset =
      case {offset, direction} do
        {0, :previous} -> -7
        {0, _} -> 7
        {offset, _} -> offset
      end

    date = date |> CalDate.add_days(offset) |> Map.put(:lock?, true)
    if modifier == :substitutes, do: %{date | substitute?: true}, else: date
  end

  defp apply_clause_rules(date, rules) do
    Enum.reduce(rules, date, fn
      %{rule: :time, hour: hour, minute: minute}, date -> CalDate.set_time(date, hour, minute)
      %{rule: :duration, duration: duration}, date -> %{date | duration: duration}
    end)
  end

  defp year_matches?(year, %{cardinality: :leap}), do: Date.leap_year?(Date.new!(year, 1, 1))

  defp year_matches?(year, %{cardinality: :"non-leap"}),
    do: not Date.leap_year?(Date.new!(year, 1, 1))

  defp year_matches?(year, %{cardinality: :even}), do: Integer.mod(year, 2) == 0
  defp year_matches?(year, %{cardinality: :odd}), do: Integer.mod(year, 2) == 1

  defp year_matches?(year, %{cardinality: nil, every: every, since: since})
       when every != nil and since != nil do
    rem(year - since, every) == 0
  end

  defp year_matches?(_year, _token), do: false

  # A lone `prior to` closes the preceding open `since` into one range.
  defp set_active(event, %{to: to} = active) when not is_map_key(active, :from) do
    case Enum.reverse(event.active || []) do
      [%{from: _} = last | rest] when not is_map_key(last, :to) ->
        %{event | active: Enum.reverse([Map.put(last, :to, to) | rest])}

      _ ->
        %{event | active: (event.active || []) ++ [active]}
    end
  end

  defp set_active(event, active), do: %{event | active: (event.active || []) ++ [active]}

  ## Post rules

  # `09-22 if 09-21 and 09-23 is public holiday`: the extra dates must each
  # coincide with another holiday of the type, otherwise nothing is emitted.
  defp bridge(token, %{events: [first | predicates]} = state) do
    type = token.type || :public

    all_found? =
      Enum.all?(predicates, fn predicate ->
        Enum.any?(other_rules(state), fn sibling ->
          sibling.type == type and any_same_date?(sibling_dates(sibling, state), predicate.dates)
        end)
      end)

    if all_found?, do: state, else: %{state | events: [%{first | dates: []} | predicates]}
  end

  # `if is public holiday then next monday`: when the date collides with
  # another holiday of the type, move it like a date_dir rule.
  defp if_holiday(token, state) do
    type = token.type || :public
    direction_token = Map.merge(token, %{rule: :date_dir, direction: token.direction || :next})

    collision =
      Enum.find_value(other_rules(state), fn sibling ->
        if sibling.type == type do
          dates = sibling_dates(sibling, state)
          index = Enum.find_index(state.events, &any_same_date?(dates, &1.dates))
          index && {index, sibling}
        end
      end)

    case collision do
      nil ->
        state

      {index, _sibling} ->
        events =
          List.update_at(state.events, index, &apply_rule(direction_token, &1, state.modifier))

        %{state | events: events}
    end
  end

  defp other_rules(state), do: Enum.reject(state.siblings, &(&1.rule == state.rule))

  defp any_same_date?(left, right) do
    Enum.any?(left, fn l -> Enum.any?(right, &CalDate.same_date?(l, &1)) end)
  end

  ## disable / enable / active

  # A full date in `disable` for the year: when it equals the computed date
  # the event is reset and an `enable` date for the year replaces it; when it
  # doesn't, nothing happens at all. Without a full date, a bare year or
  # year-month entry filters the dates it covers.
  defp disable(event, %{"disable" => [_ | _] = disable} = spec, year) do
    case full_date_in_year(disable, year) do
      nil -> disable_period(event, disable, year)
      disabled -> replace_disabled(event, disabled, full_date_in_year(spec["enable"] || [], year))
    end
  end

  defp disable(event, _spec, _year), do: event

  # The replacement is a plain date: a Hijri or Hebrew rule moved this way
  # loses its 18:00 start, and the rule's own since/prior ranges no longer
  # apply to it, both as upstream.
  defp replace_disabled(event, disabled, enabled) do
    cond do
      not Enum.any?(event.dates, &CalDate.same_date?(&1, disabled)) -> event
      enabled == nil -> %{event | dates: []}
      true -> %{event | dates: [enabled], fn: %{fn: :gregorian}, active: nil}
    end
  end

  defp disable_period(event, disable, year) do
    case Enum.find_value(disable, fn entry -> match_year(iso_parts(entry), year) end) do
      nil ->
        event

      {y, nil} ->
        %{event | dates: Enum.reject(event.dates, &(CalDate.year(&1) == y))}

      {y, m} ->
        %{
          event
          | dates:
              Enum.reject(event.dates, &(CalDate.year(&1) == y and CalDate.date(&1).month == m))
        }
    end
  end

  defp full_date_in_year(entries, year) do
    Enum.find_value(entries, fn entry ->
      case iso_parts(entry) do
        [^year, month, day] when month != nil and day != nil -> CalDate.new(year, month, day)
        _ -> nil
      end
    end)
  end

  defp match_year([year, month | _], year), do: {year, month}
  defp match_year(_parts, _year), do: nil

  defp iso_parts(entry) do
    parts = entry |> to_string() |> String.split("-") |> Enum.map(&String.to_integer/1)
    parts ++ List.duplicate(nil, 3 - length(parts))
  end

  # A data `active:` list beats the rule's own since/prior ranges. Ranges are
  # half-open and compared against the date's wall-clock start.
  defp filter_active(event, year, spec_active) do
    active = spec_active || event.active

    dates =
      Enum.filter(event.dates, fn date ->
        not date.filter? and CalDate.year(date) == year and
          (active == nil or in_active?(date, active))
      end)

    %{event | dates: dates}
  end

  defp in_active?(date, active) do
    Enum.any?(active, fn range ->
      from = range[:from]
      to = range[:to]

      cond do
        from && to ->
          NaiveDateTime.compare(from, date.naive) != :gt and
            NaiveDateTime.compare(to, date.naive) == :gt

        from ->
          NaiveDateTime.compare(from, date.naive) != :gt

        to ->
          NaiveDateTime.compare(to, date.naive) == :gt

        true ->
          false
      end
    end)
  end

  defp active_from_spec(%{"active" => ranges}) when is_list(ranges) and ranges != [] do
    Enum.map(ranges, fn range ->
      %{}
      |> then(
        &if(range["from"], do: Map.put(&1, :from, active_boundary(range["from"])), else: &1)
      )
      |> then(&if(range["to"], do: Map.put(&1, :to, active_boundary(range["to"])), else: &1))
    end)
  end

  defp active_from_spec(_spec), do: nil

  # `2004`, `"2004-05"` and `"2004-05-14"` all mean midnight of that day.
  defp active_boundary(value) do
    [year, month, day] = iso_parts(value)
    NaiveDateTime.new!(year, month || 1, day || 1, 0, 0, 0)
  end

  defp weekday_name(date) do
    Enum.find_value(@weekday_numbers, fn {name, number} ->
      number == CalDate.weekday(date) && name
    end)
  end
end
