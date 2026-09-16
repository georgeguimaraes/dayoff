// Builds priv/data/holidays.json from the upstream YAML the way upstream's
// scripts/holidays2json.cjs does: the 0.yaml header, every country file merged
// into `holidays`, then names.yaml. The version field is the data commit's date
// instead of the build date so regenerating gives the same bytes.
import fs from 'node:fs'
import path from 'node:path'
import { load as loadYaml } from 'js-yaml'
import { dataDir, writeJson } from './lib.mjs'

export function buildHolidaysJson (holidaysRepoDir, commitDate) {
  const countriesDir = path.join(holidaysRepoDir, 'data', 'countries')
  const load = (file) => loadYaml(fs.readFileSync(file, 'utf8'))

  const result = load(path.join(countriesDir, '0.yaml'))
  result.holidays = {}

  const countryFiles = fs.readdirSync(countriesDir)
    .filter((file) => /^[A-Z]+\.yaml$/.test(file))
    .sort()

  for (const file of countryFiles) {
    Object.assign(result.holidays, load(path.join(countriesDir, file)).holidays)
  }

  Object.assign(result, load(path.join(holidaysRepoDir, 'data', 'names.yaml')))
  result.version = commitDate.slice(0, 10)

  writeJson(path.join(dataDir, 'holidays.json'), result)
  return result
}
