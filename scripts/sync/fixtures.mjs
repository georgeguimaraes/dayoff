// Runs the reference implementation (date-holidays-parser with dayoff's copy of
// holidays.json) and writes what it returns, so the Elixir tests can compare
// list to list. One file per country:
//   { country, zone, national: { "2026": [holiday, ...] },
//     states: { "CA": { "2026": [...] } }, regions: { "BY/A": { "2026": [...] } } }
// with holiday = [date, start, end, name, type, rule, substitute, note].
// start and end are wall-clock in the country's default zone. Run with TZ=UTC:
// the parser's CalDate goes through the machine's local time.
import fs from 'node:fs'
import path from 'node:path'
import Holidays from 'date-holidays-parser'
import CalDate from 'caldate'
import { dataDir, readJson, writeJson, log } from './lib.mjs'

export const committedRange = { national: [2010, 2035], states: [2020, 2030] }
export const fullRange = { national: [1970, 2076], states: [2000, 2050] }

const parseErrors = new Set()
const originalError = console.error
console.error = (...args) => {
  const message = args.join(' ')
  if (message.startsWith('could not parse rule: ')) {
    parseErrors.add(message.slice('could not parse rule: '.length))
  } else {
    originalError(...args)
  }
}

// The parser converts wall-clock times to instants through the selection's
// timezone, which shifts times that fall into a DST gap (Iran's midnight on
// the first day of spring). dayoff keeps wall-clock times, so the oracle is
// made to report them too: toTimezone returns the wall clock as if it were UTC.
CalDate.prototype.toTimezone = function () {
  return new Date(this.toString(true))
}

function wallClock (date) {
  return date.toISOString().slice(0, 19).replace('T', ' ')
}

function dump (data, args, years) {
  const holidays = new Holidays(data, ...args)
  const byYear = {}
  for (let year = years[0]; year <= years[1]; year++) {
    byYear[year] = holidays.getHolidays(year).map((holiday) => [
      holiday.date.slice(0, 10),
      wallClock(holiday.start),
      wallClock(holiday.end),
      holiday.name,
      holiday.type,
      holiday.rule,
      holiday.substitute === true,
      holiday.note || null
    ])
  }
  return byYear
}

// One holiday per line so git diffs stay readable and delta well.
function serialize (result) {
  const section = (byYear) =>
    Object.entries(byYear).map(([year, holidays]) =>
      `    "${year}": [\n${holidays.map((holiday) => '      ' + JSON.stringify(holiday)).join(',\n')}\n    ]`
    ).join(',\n')
  const nested = (map) =>
    Object.entries(map).map(([key, byYear]) => `    ${JSON.stringify(key)}: {\n${section(byYear).replace(/^/gm, '  ')}\n    }`).join(',\n')
  return [
    '{',
    `  "country": ${JSON.stringify(result.country)},`,
    `  "zone": ${JSON.stringify(result.zone)},`,
    `  "range": ${JSON.stringify(result.range)},`,
    `  "national": {\n${section(result.national)}\n  },`,
    `  "states": {\n${nested(result.states)}\n  },`,
    `  "regions": {\n${nested(result.regions)}\n  }`,
    '}',
    ''
  ].join('\n')
}

export function buildFixtures (outDir, range) {
  if (process.env.TZ !== 'UTC') throw new Error('run the fixture generator with TZ=UTC')
  const data = readJson(path.join(dataDir, 'holidays.json'))
  fs.rmSync(outDir, { recursive: true, force: true })
  fs.mkdirSync(outDir, { recursive: true })

  for (const [code, country] of Object.entries(data.holidays)) {
    const zone = country.zones[0]
    const result = { country: code, zone, range, national: dump(data, [code], range.national), states: {}, regions: {} }

    // The parser uppercases state and region codes before looking them up, so
    // mixed-case codes (Cook Islands' "Aitutaki", New Zealand's "Buller") never
    // resolve upstream and silently give the parent's holidays. dayoff resolves
    // them, so there is no reference to compare against and they are skipped.
    const selectable = (subdivisionCode) => subdivisionCode === subdivisionCode.toUpperCase()
    const subdivisions = country.states || country.regions || {}
    for (const [stateCode, state] of Object.entries(subdivisions)) {
      if (!selectable(stateCode)) continue
      result.states[stateCode] = dump(data, [code, stateCode], range.states)
      for (const regionCode of Object.keys(state.regions || {})) {
        if (!selectable(regionCode)) continue
        result.regions[`${stateCode}/${regionCode}`] = dump(data, [code, stateCode, regionCode], range.states)
      }
    }
    fs.writeFileSync(path.join(outDir, `${code}.json`), serialize(result))
  }

  writeJson(path.join(outDir, 'unparseable_rules.json'), [...parseErrors].sort())
  log(`fixtures: ${Object.keys(data.holidays).length} countries in ${outDir}, ${parseErrors.size} unparseable rules`)
  return parseErrors
}
