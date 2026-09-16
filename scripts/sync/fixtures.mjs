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
import moment from 'moment-timezone'
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

function wallClock (date, zone) {
  return moment(date).tz(zone).format('YYYY-MM-DD HH:mm:ss')
}

function dump (data, args, years, zone) {
  const holidays = new Holidays(data, ...args)
  const byYear = {}
  for (let year = years[0]; year <= years[1]; year++) {
    byYear[year] = holidays.getHolidays(year).map((holiday) => [
      holiday.date.slice(0, 10),
      wallClock(holiday.start, zone),
      wallClock(holiday.end, zone),
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
    const result = { country: code, zone, range, national: dump(data, [code], range.national, zone), states: {}, regions: {} }

    const subdivisions = country.states || country.regions || {}
    for (const [stateCode, state] of Object.entries(subdivisions)) {
      result.states[stateCode] = dump(data, [code, stateCode], range.states, zone)
      for (const regionCode of Object.keys(state.regions || {})) {
        result.regions[`${stateCode}/${regionCode}`] = dump(data, [code, stateCode, regionCode], range.states, zone)
      }
    }
    fs.writeFileSync(path.join(outDir, `${code}.json`), serialize(result))
  }

  writeJson(path.join(outDir, 'unparseable_rules.json'), [...parseErrors].sort())
  log(`fixtures: ${Object.keys(data.holidays).length} countries in ${outDir}, ${parseErrors.size} unparseable rules`)
  return parseErrors
}
