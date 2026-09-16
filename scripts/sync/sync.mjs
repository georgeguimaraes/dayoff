#!/usr/bin/env node
// dayoff's data sync. Driven by `mix dayoff.sync`.
//
//   node sync.mjs --check                 compare upstream master with priv/data/VERSION.json
//   node sync.mjs                         rebuild every data file and the committed fixtures
//   node sync.mjs --fixtures DIR --full   write the wide fixture range into DIR (nothing else)
//
// Writes `changed=true|false` to $GITHUB_OUTPUT when set.
import fs from 'node:fs'
import path from 'node:path'
import { rootDir, repos, readVersion, writeJson, versionFile, latestDataCommit, clone, log } from './lib.mjs'
import { buildHolidaysJson } from './data.mjs'
import { buildCalendarTables } from './tables.mjs'
import { buildLunisolarTable } from './lunisolar.mjs'
import { buildEquinoxTable } from './equinox.mjs'
import { buildFixtures, committedRange, fullRange } from './fixtures.mjs'

const args = process.argv.slice(2)
const flag = (name) => args.includes(name)
const option = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : null)

function githubOutput (key, value) {
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`)
}

async function check () {
  const current = readVersion()
  const latest = {
    holidays: await latestDataCommit(repos.holidays),
    parser: await latestDataCommit(repos.parser)
  }
  const changed = []
  for (const key of Object.keys(latest)) {
    const have = current?.[key]?.sha
    if (have !== latest[key].sha) changed.push(`${repos[key].name}: ${have ? have.slice(0, 7) : 'none'} -> ${latest[key].sha.slice(0, 7)} (${latest[key].date})`)
  }
  if (changed.length) {
    log('upstream data moved:\n  ' + changed.join('\n  '))
  } else {
    log(`up to date with ${repos.holidays.name} ${current.holidays.sha.slice(0, 7)} and ${repos.parser.name} ${current.parser.sha.slice(0, 7)}`)
  }
  githubOutput('changed', changed.length > 0)
  githubOutput('holidays_sha', latest.holidays.sha.slice(0, 7))
  return { latest, changed: changed.length > 0 }
}

async function sync () {
  const { latest } = await check()
  log(`cloning ${repos.holidays.name} at ${latest.holidays.sha.slice(0, 7)}`)
  const holidaysDir = clone(repos.holidays, latest.holidays.sha)
  log(`cloning ${repos.parser.name} at ${latest.parser.sha.slice(0, 7)}`)
  const parserDir = clone(repos.parser, latest.parser.sha)

  const data = buildHolidaysJson(holidaysDir, latest.holidays.date)
  log(`holidays.json: ${Object.keys(data.holidays).length} countries, version ${data.version}`)
  await buildCalendarTables(parserDir)
  log('hijri.json and hebrew.json written')
  buildLunisolarTable()
  await buildEquinoxTable(data)
  log('equinox.json written')

  const errors = buildFixtures(path.join(rootDir, 'test', 'fixtures', 'reference'), committedRange)
  writeJson(versionFile, {
    holidays: latest.holidays,
    parser: latest.parser,
    holidays_version: data.version,
    synced_at: new Date().toISOString().slice(0, 10)
  })
  if (errors.size) log('WARNING: upstream could not parse:\n  ' + [...errors].join('\n  '))
}

if (flag('--check')) {
  await check()
} else if (option('--fixtures')) {
  buildFixtures(path.resolve(option('--fixtures')), flag('--full') ? fullRange : committedRange)
} else {
  await sync()
}
