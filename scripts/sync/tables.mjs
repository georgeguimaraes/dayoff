// Converts the parser's generated Hijri and Hebrew tables (ES modules exporting
// `calendar`) into JSON. Shape kept from upstream: entries are
// [gregorian month (0-based), day, calendar year offset from base_year], six
// numbers when the same month starts twice in one Gregorian year, null when a
// month doesn't start in that year.
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { dataDir, writeJson } from './lib.mjs'

export async function buildCalendarTables (parserRepoDir) {
  for (const [name, file, months] of [['hijri', 'hijri-calendar.js', 12], ['hebrew', 'hebrew-calendar.js', 13]]) {
    const modulePath = path.join(parserRepoDir, 'src', 'internal', file)
    const { calendar } = await import(pathToFileURL(modulePath))
    const years = {}
    for (const [key, value] of Object.entries(calendar)) {
      if (key === 'year' || key === 'months') continue
      years[key] = value
    }
    writeJson(path.join(dataDir, `${name}.json`), {
      base_year: calendar.year,
      months: calendar.months || months,
      years
    }, 0)
  }
}
