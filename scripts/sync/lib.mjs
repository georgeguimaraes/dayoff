import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

export const syncDir = path.dirname(fileURLToPath(import.meta.url))
export const rootDir = path.resolve(syncDir, '..', '..')
export const dataDir = path.join(rootDir, 'priv', 'data')
export const upstreamDir = path.join(syncDir, 'upstream')
export const versionFile = path.join(dataDir, 'VERSION.json')

export const repos = {
  holidays: { name: 'commenthol/date-holidays', paths: ['data'] },
  parser: { name: 'commenthol/date-holidays-parser', paths: ['src/internal', 'scripts'] }
}

export function readVersion () {
  if (!fs.existsSync(versionFile)) return null
  return JSON.parse(fs.readFileSync(versionFile, 'utf8'))
}

export function writeJson (file, value, indent = 2) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, JSON.stringify(value, null, indent) + '\n')
}

export function readJson (file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

async function github (url) {
  const headers = { accept: 'application/vnd.github+json', 'user-agent': 'dayoff-sync' }
  if (process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`
  const response = await fetch(url, { headers })
  if (!response.ok) throw new Error(`GitHub API ${response.status} for ${url}`)
  return response.json()
}

// The newest commit on master that touched any of the repo's data paths.
export async function latestDataCommit (repo) {
  let newest = null
  for (const repoPath of repo.paths) {
    const url = `https://api.github.com/repos/${repo.name}/commits?sha=master&path=${repoPath}&per_page=1`
    const [commit] = await github(url)
    if (!commit) continue
    const candidate = { sha: commit.sha, date: commit.commit.committer.date }
    if (!newest || candidate.date > newest.date) newest = candidate
  }
  return newest
}

export function clone (repo, sha) {
  const dir = path.join(upstreamDir, repo.name.split('/')[1])
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(dir, { recursive: true })
  const git = (...args) => execFileSync('git', ['-C', dir, ...args], { stdio: ['ignore', 'ignore', 'inherit'] })
  git('init', '-q')
  git('remote', 'add', 'origin', `https://github.com/${repo.name}.git`)
  git('fetch', '-q', '--depth', '1', 'origin', sha)
  git('checkout', '-q', 'FETCH_HEAD')
  return dir
}

export function log (message) {
  process.stderr.write(message + '\n')
}
