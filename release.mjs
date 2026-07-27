#!/usr/bin/env node

import { execSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync, rmSync, globSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = __dirname
const REPO_ROOT = ROOT
const VERSION_PATH = resolve(ROOT, 'VERSION')
const CHANGELOG_PATH = resolve(ROOT, 'CHANGELOG.md')
const TEMP_RELEASE_NOTES_PATH = resolve(ROOT, '.release-notes-tmp.md')

const VALID_BUMPS = ['patch', 'minor', 'major']
const TERMINATION_SIGNALS = ['SIGINT', 'SIGTERM']
const EXIT_CODES = {
  invalidUsage: 1,
  sigint: 130,
  sigterm: 143,
}

const ARTIFACT_PATTERNS = [
  'seafari_*.deb',
  'Seafari-*.AppImage',
  'seafari-*.rpm',
  'seafari-*.pkg.tar.zst',
]

function normalizeRepoUrl(rawUrl) {
  const fallback = 'https://github.com/Victor1890/seafari'
  if (!rawUrl || typeof rawUrl !== 'string') return fallback

  let url = rawUrl.trim()
  if (url.startsWith('git+https://')) url = url.replace(/^git\+/, '')
  if (/^git@github\.com:/.test(url)) url = url.replace(/^git@github\.com:/, 'https://github.com/')
  if (/^ssh:\/\/git@github\.com\//.test(url)) url = url.replace(/^ssh:\/\/git@github\.com\//, 'https://github.com/')
  url = url.replace(/\.git$/, '').replace(/\/+$/, '')
  if (!/^https?:\/\//.test(url)) return fallback
  return url
}

function run(cmd, opts = {}) {
  return execSync(cmd, { encoding: 'utf-8', cwd: ROOT, stdio: 'pipe', ...opts }).trim()
}

function runVisible(cmd, opts = {}) {
  execSync(cmd, { cwd: ROOT, stdio: 'inherit', ...opts })
}

function fail(msg) {
  console.error(`\n❌ ${msg}`)
  process.exit(EXIT_CODES.invalidUsage)
}

function cleanupTempReleaseNotes() {
  try {
    if (existsSync(TEMP_RELEASE_NOTES_PATH)) rmSync(TEMP_RELEASE_NOTES_PATH)
  } catch {
    console.warn('⚠️  Could not delete the temporary release notes file')
  }
}

function bumpVersion(version, type) {
  const [major, minor, patch] = version.split('.').map(Number)
  if (type === 'major') return `${major + 1}.0.0`
  if (type === 'minor') return `${major}.${minor + 1}.0`
  if (type === 'patch') return `${major}.${minor}.${patch + 1}`
}

function getVersion() {
  if (!existsSync(VERSION_PATH)) return '0.0.0'
  return readFileSync(VERSION_PATH, 'utf-8').trim()
}

function getLastTag() {
  try {
    return run('git describe --tags --abbrev=0', { cwd: REPO_ROOT })
  } catch {
    return null
  }
}

function getCommitsSinceTag(tag) {
  const range = tag ? `${tag}..HEAD` : 'HEAD'
  const log = run(`git log ${range} --pretty=format:"%s|%h"`, { cwd: REPO_ROOT })
  if (!log) return []
  return log.split('\n').filter(Boolean).map((line) => {
    const [message, hash] = line.split('|')
    return { message, hash }
  })
}

function getPeopleSinceTag(tag) {
  const range = tag ? `${tag}..HEAD` : 'HEAD'
  const toUnique = (raw) => [...new Set(raw.split('\n').map((l) => l.trim()).filter(Boolean))]
  const authors = toUnique(run(`git log ${range} --pretty=format:"%an <%ae>"`, { cwd: REPO_ROOT }))
  return { authors  }
}

function buildReleasePeopleSection(people) {
  let md = ''
  if (people.authors.length) {
    md += '### Authors\n\n'
    for (const a of people.authors) md += `- ${a}\n`
    md += '\n'
  }
  return md
}

function categorizeCommits(commits) {
  const categories = { breaking: [], feat: [], fix: [], other: [] }
  for (const { message, hash } of commits) {
    const lower = message.toLowerCase()
    if (lower.startsWith('feat') || lower.includes('add ') || lower.includes('add:')) {
      categories.feat.push({ message, hash })
    } else if (lower.startsWith('fix') || lower.includes('fix ') || lower.includes('fix:')) {
      categories.fix.push({ message, hash })
    } else if (lower.includes('breaking') || lower.includes('!:')) {
      categories.breaking.push({ message, hash })
    } else {
      categories.other.push({ message, hash })
    }
  }
  return categories
}

function buildChangelog(version, categories, repoUrl) {
  const date = new Date().toISOString().split('T')[0]
  let md = `## [${version}](${repoUrl}/releases/tag/v${version}) (${date})\n\n`

  if (categories.breaking.length) {
    md += '### ⚠️ Breaking Changes\n\n'
    for (const { message, hash } of categories.breaking) md += `- ${message} [\`${hash}\`](${repoUrl}/commit/${hash})\n`
    md += '\n'
  }
  if (categories.feat.length) {
    md += '### ✨ Features\n\n'
    for (const { message, hash } of categories.feat) md += `- ${message} [\`${hash}\`](${repoUrl}/commit/${hash})\n`
    md += '\n'
  }
  if (categories.fix.length) {
    md += '### 🐛 Bug Fixes\n\n'
    for (const { message, hash } of categories.fix) md += `- ${message} [\`${hash}\`](${repoUrl}/commit/${hash})\n`
    md += '\n'
  }
  if (categories.other.length) {
    md += '### 📦 Other Changes\n\n'
    for (const { message, hash } of categories.other) md += `- ${message} [\`${hash}\`](${repoUrl}/commit/${hash})\n`
    md += '\n'
  }
  return md
}

function updateChangelog(newEntry) {
  if (existsSync(CHANGELOG_PATH)) {
    const existing = readFileSync(CHANGELOG_PATH, 'utf-8')
    const headerEnd = existing.indexOf('\n## ')
    if (headerEnd !== -1) {
      writeFileSync(CHANGELOG_PATH, existing.slice(0, headerEnd + 1) + newEntry + existing.slice(headerEnd + 1))
    } else {
      const lines = existing.split('\n')
      writeFileSync(CHANGELOG_PATH, lines.slice(0, 2).join('\n') + '\n\n' + newEntry)
    }
  } else {
    writeFileSync(CHANGELOG_PATH, `# Changelog\n\n${newEntry}`)
  }
}

function parseArgs() {
  const args = process.argv.slice(2)
  const bump = args.find((a) => VALID_BUMPS.includes(a))
  if (!bump) fail(`Use: node release.mjs <${VALID_BUMPS.join('|')}> [--skip-build] [--arch amd64|arm64|both]`)

  const skipBuild = args.includes('--skip-build')
  const archIdx = args.indexOf('--arch')
  const arch = archIdx !== -1 ? args[archIdx + 1] : 'both'
  if (!['amd64', 'arm64', 'both'].includes(arch)) fail(`Invalid arch: ${arch}. Use amd64, arm64, or both.`)

  return { bump, skipBuild, arch }
}

function createReleaseContext(bump, skipBuild, arch) {
  const currentVersion = getVersion()
  const repoUrl = normalizeRepoUrl()
  return {
    bump,
    skipBuild,
    arch,
    repoUrl,
    currentVersion,
    newVersion: bumpVersion(currentVersion, bump),
    originalVersionContent: existsSync(VERSION_PATH) ? readFileSync(VERSION_PATH, 'utf-8') : null,
    originalChangelogContent: existsSync(CHANGELOG_PATH) ? readFileSync(CHANGELOG_PATH, 'utf-8') : null,
    releaseStartHead: run('git rev-parse HEAD', { cwd: REPO_ROOT }),
  }
}

function createReleaseState() {
  return {
    versionFileCreated: false,
    tagCreated: false,
    buildStarted: false,
    remotePublishStarted: false,
    tagPushed: false,
    rollbackStarted: false,
    releaseFinished: false,
  }
}

function ensureReleasePreconditions() {
  const currentBranch = run('git branch --show-current', { cwd: REPO_ROOT })
  if (currentBranch !== 'main') fail(`Release can only run on main. Current branch: ${currentBranch}`)

  const status = run('git status --porcelain', { cwd: REPO_ROOT })
  const dirtyFiles = status.split('\n').filter((f) => f.trim())
  if (dirtyFiles.length) fail(`Uncommitted changes:\n${dirtyFiles.join('\n')}`)
}

function ensureGitHubCLI() {
  try {
    run('gh --version')
  } catch {
    fail('GitHub CLI (gh) is not installed.\n  Install it: https://cli.github.com/')
  }
  try {
    run('gh auth status')
  } catch {
    fail('GitHub CLI is installed but not authenticated.\n  Run: gh auth login')
  }
}

function generateReleaseNotes(context) {
  console.log('\n📝 Generating changelog...')
  const lastTag = getLastTag()
  const commits = getCommitsSinceTag(lastTag)
  if (commits.length === 0) fail('No new commits since the last tag.')

  const categories = categorizeCommits(commits)
  const changelogEntry = buildChangelog(context.newVersion, categories, context.repoUrl)
  const people = getPeopleSinceTag(lastTag)
  const releaseNotesEntry = `${changelogEntry}${buildReleasePeopleSection(people)}`
  console.log(releaseNotesEntry)
  return { changelogEntry, releaseNotesEntry }
}

function updateVersionFile(context) {
  writeFileSync(VERSION_PATH, context.newVersion + '\n')
  context.versionFileCreated = !context.originalVersionContent
  console.log(`✅ VERSION updated to ${context.newVersion}`)
}

function updateChangelogFile(changelogEntry) {
  updateChangelog(changelogEntry)
  console.log('✅ CHANGELOG.md updated')
}

function createReleaseTag(context, state) {
  console.log('\n🔖 Creating tag...')
  run('git add VERSION CHANGELOG.md', { cwd: ROOT })
  run(`git commit -m "release: v${context.newVersion}"`, { cwd: REPO_ROOT })
  run(`git tag -a v${context.newVersion} -m "v${context.newVersion}"`, { cwd: REPO_ROOT })
  state.tagCreated = true
  console.log(`✅ Tag v${context.newVersion} created`)
}

function buildReleaseArtifacts(context) {
  console.log('\n🔨 Building project...')
  state.buildStarted = true

  const archs = context.arch === 'both' ? ['amd64', 'arm64'] : [context.arch]
  for (const a of archs) {
    console.log(`\n  📦 Building for ${a}...`)
    runVisible(`./build_seafari.sh --version ${context.newVersion} ${a}`)
  }
  console.log('✅ Build complete')
}

function findBuildArtifacts() {
  const artifacts = []
  for (const pattern of ARTIFACT_PATTERNS) {
    const matches = globSync(pattern, { cwd: ROOT })
    for (const m of matches) artifacts.push(resolve(ROOT, m))
  }
  return artifacts
}

function publishRelease(state) {
  console.log('\n📤 Pushing to GitHub...')
  state.remotePublishStarted = true
  run('git push', { cwd: REPO_ROOT })
  run('git push --tags', { cwd: REPO_ROOT })
  state.tagPushed = true
  console.log('✅ Pushed')
}

function createGitHubRelease(context, releaseNotesEntry) {
  console.log('\n🏷️  Creating GitHub Release...')
  const releaseNotes = releaseNotesEntry.replace(/^## .*\n\n/, '')
  writeFileSync(TEMP_RELEASE_NOTES_PATH, releaseNotes)

  const artifacts = findBuildArtifacts()
  const assetArgs = artifacts.length ? artifacts.map((a) => `"${a}"`).join(' ') : ''

  try {
    runVisible(
      `gh release create v${context.newVersion} --title "v${context.newVersion}" --notes-file .release-notes-tmp.md ${assetArgs}`,
      { cwd: ROOT },
    )
    console.log(`✅ Release v${context.newVersion} created on GitHub`)
  } catch {
    console.warn('⚠️  Could not create the release on GitHub (is gh installed and authenticated?)')
    console.warn(`   Create it manually: ${context.repoUrl}/releases/new?tag=v${context.newVersion}`)
  } finally {
    cleanupTempReleaseNotes()
  }
}

const { bump, skipBuild, arch } = parseArgs()
const releaseContext = createReleaseContext(bump, skipBuild, arch)
const releaseState = createReleaseState()

function rollbackRelease() {
  if (releaseState.rollbackStarted || releaseState.releaseFinished) return
  releaseState.rollbackStarted = true
  console.log('\n↩️  Reverting changes from failed release...')

  cleanupTempReleaseNotes()

  if (releaseState.remotePublishStarted || releaseState.tagPushed) {
    console.warn('⚠️  Remote push already started. Skipping local rollback to avoid divergence.')
    return
  }

  if (releaseState.tagCreated) {
    try {
      run(`git tag -d v${releaseContext.newVersion}`, { cwd: REPO_ROOT })
      console.log(`✅ Tag v${releaseContext.newVersion} deleted`)
    } catch {
      console.warn(`⚠️  Could not delete tag v${releaseContext.newVersion}`)
    }
  }

  // Reset the release commit
  try {
    run(`git reset --hard ${releaseContext.releaseStartHead}`, { cwd: REPO_ROOT })
    console.log('✅ Release commit reverted')
  } catch {
    console.warn('⚠️  Could not revert release commit automatically')
  }
}

function handleTerminationSignal(signal) {
  if (releaseState.releaseFinished) process.exit(0)
  if (releaseState.rollbackStarted) {
    console.warn(`\n⚠️  Received ${signal} during rollback. Exiting.`)
    process.exit(signal === 'SIGINT' ? EXIT_CODES.sigint : EXIT_CODES.sigterm)
  }
  console.warn(`\n⚠️  Received ${signal}. Canceling release...`)
  rollbackRelease()
  console.error('\n❌ Release canceled by user.')
  process.exit(signal === 'SIGINT' ? EXIT_CODES.sigint : EXIT_CODES.sigterm)
}

for (const signal of TERMINATION_SIGNALS) {
  process.on(signal, () => handleTerminationSignal(signal))
}

function main() {
  console.log(`\n📦 seafari ${releaseContext.currentVersion} → ${releaseContext.newVersion} (${releaseContext.bump})\n`)

  ensureGitHubCLI()
  ensureReleasePreconditions()

  const { changelogEntry, releaseNotesEntry } = generateReleaseNotes(releaseContext)

  try {
    updateVersionFile(releaseContext)
    updateChangelogFile(changelogEntry)
    createReleaseTag(releaseContext, releaseState)

    if (!releaseContext.skipBuild) {
      buildReleaseArtifacts(releaseContext)
    } else {
      console.log('\n⏭️  Skipping build (--skip-build)')
    }

    publishRelease(releaseState)
  } catch (error) {
    rollbackRelease()
    const message = error instanceof Error ? error.message : String(error)
    fail(`The release failed.\n${message}`)
  }

  createGitHubRelease(releaseContext, releaseNotesEntry)

  releaseState.releaseFinished = true
  console.log(`\n🎉 Release v${releaseContext.newVersion} completed!\n`)
}

main()
