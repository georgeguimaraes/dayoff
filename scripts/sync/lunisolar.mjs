// Generates the Chinese, Korean and Vietnamese lunisolar tables with
// date-chinese, the library the reference parser uses, so dayoff's dates match
// it exactly without porting the astronomy. For every Gregorian year Y:
//   months: day 1 of lunar months 1..12 of the lunar year that starts in Y, as
//           [gregorian month, day, gregorian year]
//   leap_months: the same for a leap month request, which date-chinese answers
//           with the month after the regular one
//   exceptions: "month-day" => date, where the reference's own round trip
//           doesn't give day 1 plus the offset
//   solar_terms: the 24 dates solarTerm(n, Y) gives, as [month, day, year]
import path from 'node:path'
import { CalendarChinese, CalendarKorean, CalendarVietnamese } from 'date-chinese'
import { dataDir, writeJson, log } from './lib.mjs'

export const yearRange = [1900, 2100]

const calendars = {
  chinese: CalendarChinese,
  korean: CalendarKorean,
  vietnamese: CalendarVietnamese
}

function gregorian (calendar, jde) {
  calendar.fromJDE(jde)
  const { year, month, day } = calendar.toGregorian()
  return [month, day, year]
}

// What the reference parser gets for a lunar date: `toJDE(year)` then a round
// trip through `fromJDE(...).toGregorian()`. Day 1 of every month, regular and
// leap (a leap request is answered with the month after the regular one), plus
// the days where that round trip doesn't land on "day 1 plus the offset", so
// the Elixir side reproduces even the reference's own edge cases (2011, 2033).
function lunarDate (calendar, gregorianYear, month, leap, day) {
  calendar.set(undefined, undefined, month, leap, day)
  return gregorian(calendar, calendar.toJDE(gregorianYear))
}

function addDays ([month, day, year], days) {
  const date = new Date(Date.UTC(year, month - 1, day + days))
  return [date.getUTCMonth() + 1, date.getUTCDate(), date.getUTCFullYear()]
}

function lunarYear (calendar, gregorianYear) {
  const months = []
  const leapMonths = []
  const exceptions = {}
  for (let month = 1; month <= 12; month++) {
    const first = lunarDate(calendar, gregorianYear, month, false, 1)
    months.push(first)
    leapMonths.push(lunarDate(calendar, gregorianYear, month, true, 1))
    for (let day = 0; day <= 30; day++) {
      const actual = lunarDate(calendar, gregorianYear, month, false, day)
      const expected = addDays(first, day - 1)
      if (actual.join('-') !== expected.join('-')) {
        exceptions[`${month}-${day}`] = actual
      }
    }
  }
  return { months, leap_months: leapMonths, exceptions }
}

// newYear is the expensive part of every toJDE call and depends only on the
// year, so memoize it on the calendar instance.
function memoizeNewYear (calendar) {
  const original = calendar.newYear.bind(calendar)
  const memo = new Map()
  calendar.newYear = (year) => {
    if (!memo.has(year)) memo.set(year, original(year))
    return memo.get(year)
  }
}

function solarTerms (calendar, gregorianYear) {
  const terms = []
  for (let term = 1; term <= 24; term++) {
    terms.push(gregorian(calendar, calendar.solarTerm(term, gregorianYear)))
  }
  return terms
}

export function buildLunisolarTable () {
  const result = { range: yearRange, calendars: {} }
  for (const [name, Calendar] of Object.entries(calendars)) {
    const calendar = new Calendar()
    memoizeNewYear(calendar)
    const years = {}
    for (let year = yearRange[0]; year <= yearRange[1]; year++) {
      years[year] = { ...lunarYear(calendar, year), solar_terms: solarTerms(calendar, year) }
    }
    result.calendars[name] = years
    log(`lunisolar: ${name} done`)
  }
  writeJson(path.join(dataDir, 'lunisolar.json'), result, 0)
  return result
}
