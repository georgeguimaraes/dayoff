// Generates the Chinese, Korean and Vietnamese lunisolar tables with
// date-chinese, the library the reference parser uses, so dayoff's dates match
// it exactly without porting the astronomy. For every Gregorian year Y:
//   months: the new moons of the lunar year that starts in Y, in order, as
//           [gregorian month, day, gregorian year, lunar month, leap (0|1)]
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

function lunarYear (calendar, gregorianYear) {
  const newYear = calendar.newYear(gregorianYear)
  const nextNewYear = calendar.newYear(gregorianYear + 1)
  const months = []
  let newMoon = newYear
  while (newMoon < nextNewYear - 1) {
    calendar.fromJDE(newMoon)
    const { year, month, day } = calendar.toGregorian()
    months.push([month, day, year, calendar.month, calendar.leap ? 1 : 0])
    newMoon = calendar.nextNewMoon(newMoon + 1)
  }
  return months
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
    const years = {}
    for (let year = yearRange[0]; year <= yearRange[1]; year++) {
      years[year] = { months: lunarYear(calendar, year), solar_terms: solarTerms(calendar, year) }
    }
    result.calendars[name] = years
    log(`lunisolar: ${name} done`)
  }
  writeJson(path.join(dataDir, 'lunisolar.json'), result, 0)
  return result
}
