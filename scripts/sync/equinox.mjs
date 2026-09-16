// Equinox and solstice instants the way the parser's Equinox.js computes them
// (astronomia VSOP87 Earth series), plus the local calendar date in every
// timezone the rule strings mention, floored the way moment-timezone floors it.
// Elixir reads the local dates, so no timezone database is needed at runtime.
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { solstice, julian, planetposition } from 'astronomia'
import moment from 'moment-timezone'
import { dataDir, writeJson, syncDir } from './lib.mjs'

export const yearRange = [1900, 2100]

const seasons = { march: 'march2', june: 'june2', september: 'september2', december: 'december2' }

export function zonesInRules (holidaysData) {
  const zones = new Set(['GMT'])
  const visit = (node) => {
    for (const rule of Object.keys(node.days || {})) {
      const match = /(?:equinox|solstice) in ([^\s]*|[+-]\d{2}:\d{2})/.exec(rule)
      if (match) zones.add(match[1])
    }
    for (const child of Object.values(node.states || {})) visit(child)
    for (const child of Object.values(node.regions || {})) visit(child)
  }
  for (const country of Object.values(holidaysData.holidays)) visit(country)
  return [...zones].sort()
}

function localDate (isoString, zone) {
  const date = /^[+-]\d{2}:\d{2}$/.test(zone) ? moment(isoString).utcOffset(zone) : moment(isoString).tz(zone)
  return `${String(date.month() + 1).padStart(2, '0')}-${String(date.date()).padStart(2, '0')}`
}

export async function buildEquinoxTable (holidaysData) {
  const vsop87Path = path.join(syncDir, 'node_modules', 'date-holidays-parser', 'src', 'vsop87Bearth.js')
  const { vsop87Bearth } = await import(pathToFileURL(vsop87Path))
  const earth = new planetposition.Planet(vsop87Bearth)
  const zones = zonesInRules(holidaysData)

  const years = {}
  for (let year = yearRange[0]; year <= yearRange[1]; year++) {
    years[year] = {}
    for (const [season, fn] of Object.entries(seasons)) {
      const jde = solstice[fn](year, earth)
      const utc = new julian.Calendar().fromJDE(jde).toDate().toISOString()
      const local = {}
      for (const zone of zones) local[zone] = localDate(utc, zone)
      years[year][season] = { utc, local }
    }
  }
  writeJson(path.join(dataDir, 'equinox.json'), { range: yearRange, zones, years }, 0)
}
