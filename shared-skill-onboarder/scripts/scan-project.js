#!/usr/bin/env node
/**
 * scan-project.js
 *
 * Shared Skill Onboarder 的粗篩工具。
 * 職責：收集線索，不做模式判斷。判斷交給 AI。
 *
 * 輸出：
 *   1. 框架與技術棧偵測
 *   2. 目錄結構 fingerprint
 *   3. 重複檔案模式（哪些目錄有相同的檔案組合）
 *   4. 核心文件存在性
 *   5. 現有 project skills 清單
 */

const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const ROOT = process.cwd()

// ─── Helpers ──────────────────────────────────────────────────────────────

function exists(relPath) {
  return fs.existsSync(path.join(ROOT, relPath))
}

function firstExisting(candidates) {
  return candidates.find(exists) || null
}

function listDirs(relPath) {
  const abs = path.join(ROOT, relPath)
  if (!fs.existsSync(abs)) return []
  return fs
    .readdirSync(abs, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('.'))
    .map((d) => d.name)
}

function listFiles(relPath) {
  const abs = path.join(ROOT, relPath)
  if (!fs.existsSync(abs)) return []
  return fs
    .readdirSync(abs, { withFileTypes: true })
    .filter((d) => d.isFile())
    .map((d) => d.name)
}

// ─── 1. Framework Detection ───────────────────────────────────────────────

function detectFramework() {
  const pkg = readPkg()
  if (!pkg) return { framework: 'unknown', notable: {} }
  const allDeps = Object.assign({}, pkg.dependencies, pkg.devDependencies)

  const framework = allDeps['next']
    ? `Next.js ${allDeps['next']}`
    : allDeps['nuxt']
      ? `Nuxt ${allDeps['nuxt']}`
      : allDeps['vite']
        ? `Vite ${allDeps['vite']}`
        : allDeps['express']
          ? `Express ${allDeps['express']}`
          : 'unknown'

  const notable = {}
  const check = [
    'typescript',
    'tailwindcss',
    'zustand',
    'redux',
    '@tanstack/react-query',
    'echarts',
    'echarts-for-react',
    'vitest',
    'jest',
    'playwright',
    '@heroicons/react',
    'lucide-react',
  ]
  for (const dep of check) {
    if (allDeps[dep]) notable[dep] = allDeps[dep]
  }

  return { framework, notable }
}

// ─── 2. Directory Structure Fingerprint ───────────────────────────────────

function getStructureFingerprint() {
  const dirs = [
    'src/app',
    'src/pages',
    'src/components',
    'src/components/ui',
    'src/components/features',
    'src/components/blocks',
    'src/components/layout',
    'src/config',
    'src/hooks',
    'src/lib',
    'src/lib/server',
    'src/store',
    'src/types',
    'src/utils',
    'src/styles',
    'e2e',
    'src/__tests__',
    'tests',
    'docs',
    '.agent',
    '.agent/knowledge',
    '.agent/skills/project',
    '.agent/skills/_shared',
  ]

  const found = []
  const missing = []
  for (const d of dirs) {
    if (exists(d)) found.push(d)
    else missing.push(d)
  }
  return { found, missing }
}

// ─── 3. Repeating File Patterns ───────────────────────────────────────────

function findRepeatingPatterns() {
  const scanDirs = [
    'src/components/features',
    'src/components/blocks',
    'src/app',
    'src/pages',
  ]

  const results = []

  for (const scanDir of scanDirs) {
    if (!exists(scanDir)) continue

    const subDirs = listDirs(scanDir)
    if (subDirs.length < 2) continue

    const dirFileMap = {}
    for (const sub of subDirs) {
      const relDir = `${scanDir}/${sub}`
      const files = listFiles(relDir)
      const signature = files
        .map((f) => {
          if (/^use[A-Z]/.test(f)) return 'use*.ts'
          if (/^get[A-Z]/.test(f)) return 'get*.ts'
          return f
        })
        .sort()
        .join(', ')
      if (!dirFileMap[signature]) dirFileMap[signature] = []
      dirFileMap[signature].push(relDir)
    }

    for (const [sig, dirs] of Object.entries(dirFileMap)) {
      if (dirs.length >= 2) {
        results.push({
          parentDir: scanDir,
          filePattern: sig,
          occurrences: dirs.length,
          examples: dirs.slice(0, 3),
        })
      }
    }
  }

  return results
}

// ─── 4. Core Documents Check ──────────────────────────────────────────────

const CORE_DOCS = {
  project_manifest: ['.agent/project-manifest.md'],
  guardrails: ['.agent/guardrails.md'],
  system_context: ['.agent/knowledge/system-context.md'],
  api_reference: [
    '.agent/knowledge/api-reference.md',
    'docs/api-reference.md',
  ],
  architecture_map: [
    'docs/architecture/system_architecture_map.md',
    'docs/architecture.md',
    'ARCHITECTURE.md',
  ],
  types_entry: ['src/types/index.ts', 'src/types.ts'],
  api_client_entry: [
    'src/utils/api.ts',
    'src/lib/api.ts',
    'src/api/client.ts',
  ],
  design_tokens: [
    'DESIGN_TOKENS.md',
    'src/design-system/DESIGN_TOKENS.md',
    'docs/design/DESIGN_TOKENS.md',
    'docs/DESIGN_TOKENS.md',
  ],
}

function checkCoreDocs() {
  const found = {}
  const missing = []

  for (const [key, candidates] of Object.entries(CORE_DOCS)) {
    const hit = firstExisting(candidates)
    if (hit) {
      found[key] = hit
    } else {
      missing.push(key)
    }
  }

  return { found, missing }
}

// ─── 5. Existing Project Skills ───────────────────────────────────────────

function scanProjectSkills() {
  const roots = ['.agent/skills/project', '.agent/skills/public']
  const skills = []

  for (const root of roots) {
    if (!exists(root)) continue
    const dirs = listDirs(root)
    for (const dir of dirs) {
      const skillFile = `${root}/${dir}/SKILL.md`
      if (exists(skillFile)) {
        const hasRefs = exists(`${root}/${dir}/references`)
        skills.push({
          name: dir,
          path: skillFile,
          hasReferences: hasRefs,
          root,
        })
      }
    }
  }

  return skills
}

// ─── 6b. Manifest Variable Suggestions (paths / stack / git_workflow) ──────
// Collects clues for the new manifest sections. Does NOT decide; AI confirms
// and writes them into .agent/project-manifest.md. Missing -> report as gap.

function readPkg() {
  const pkgPath = path.join(ROOT, 'package.json')
  if (!fs.existsSync(pkgPath)) return null
  try {
    return JSON.parse(fs.readFileSync(pkgPath, 'utf-8'))
  } catch (err) {
    return null
  }
}

function detectStack(pkg) {
  const scripts = (pkg && pkg.scripts) || {}
  const allDeps = pkg ? Object.assign({}, pkg.dependencies, pkg.devDependencies) : {}
  const has = (name) => Object.prototype.hasOwnProperty.call(scripts, name)
  const declaredManager =
    pkg && typeof pkg.packageManager === 'string'
      ? pkg.packageManager.split('@')[0]
      : null
  const packageManager =
    declaredManager ||
    (!pkg && exists('uv.lock')
      ? 'uv'
      : !pkg && exists('poetry.lock')
        ? 'poetry'
        : !pkg && exists('pyproject.toml')
          ? 'python'
          : exists('pnpm-lock.yaml')
      ? 'pnpm'
      : exists('yarn.lock')
        ? 'yarn'
        : exists('bun.lock') || exists('bun.lockb')
          ? 'bun'
          : 'npm')
  const cmd = (name) =>
    has(name)
      ? name === 'test' && ['npm', 'pnpm', 'yarn'].includes(packageManager)
        ? `${packageManager} test`
        : `${packageManager} run ${name}`
      : null

  const testCmd = cmd('test') || cmd('test:unit')
  const e2eCmd = cmd('e2e') || cmd('test:e2e')

  const hasPython = exists('pyproject.toml') || exists('requirements.txt')
  let framework = hasPython && !pkg ? 'python' : null
  if (allDeps['next']) framework = 'next'
  else if (allDeps['nuxt']) framework = 'nuxt'
  else if (allDeps['vite']) framework = 'vite-react'
  else if (allDeps['express']) framework = 'express'

  const hasUi = Boolean(
    allDeps['react'] || allDeps['next'] || allDeps['vue'] || allDeps['nuxt'] || allDeps['svelte']
  )
  const hasApi = Boolean(allDeps['express'] || allDeps['fastify'])
  const typedContracts = Boolean(
    allDeps['typescript'] || exists('tsconfig.json') || cmd('type-check') || cmd('typecheck')
  )

  return {
    test_cmd: testCmd,
    typecheck_cmd: cmd('type-check') || cmd('typecheck') || null,
    lint_cmd: cmd('lint'),
    e2e_cmd: e2eCmd,
    framework,
    package_manager: packageManager,
    source_extensions: hasPython && !pkg ? 'py' : typedContracts ? 'ts,tsx,js,jsx' : 'js,jsx',
    has_ui: hasUi,
    has_api: hasApi,
    typed_contracts: typedContracts,
    has_e2e: Boolean(e2eCmd || exists('e2e')),
  }
}

function detectPaths() {
  const testsRoot = firstExisting(['tests', 'test', 'src/__tests__', '__tests__'])
  const mockupRoot = firstExisting([
    'src/design-system/sprints',
    'design/mockups',
    'docs/mockups',
    'mockups',
  ])
  return {
    source_roots: firstExisting(['src', 'app', 'lib']),
    tests_root: testsRoot,
    test_glob: testsRoot ? `${testsRoot}/**/*.{test,spec}.*` : null,
    mockup_root: mockupRoot,
    work_root: 'docs/work',
    docs_root: 'docs',
    has_legacy_artifacts: exists('.agent/artifacts'),
  }
}

function detectGitWorkflow() {
  const git = function () {
    const args = Array.prototype.slice.call(arguments)
    try {
      return execFileSync('git', args, {
        cwd: ROOT,
        encoding: 'utf-8',
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim()
    } catch (err) {
      return ''
    }
  }

  const current = git('branch', '--show-current') || null
  const remoteHead = git(
    'symbolic-ref',
    '--quiet',
    '--short',
    'refs/remotes/origin/HEAD'
  )
  const baseBranch = remoteHead ? remoteHead.replace(/^origin\//, '') : null
  const remote = remoteHead ? remoteHead.split('/')[0] : null

  return { current_branch: current, base_branch: baseBranch, remote }
}

// ─── 6. System Context Validation ─────────────────────────────────────────

function validateSystemContext() {
  const scPath = path.join(ROOT, '.agent/knowledge/system-context.md')
  if (!fs.existsSync(scPath)) return { exists: false }

  const content = fs.readFileSync(scPath, 'utf-8')
  const firstLine = content.split('\n').find((l) => l.startsWith('#')) || ''

  return {
    exists: true,
    firstHeading: firstLine.replace(/^#+\s*/, '').trim(),
  }
}

// ─── Run ──────────────────────────────────────────────────────────────────

const framework = detectFramework()
const structure = getStructureFingerprint()
const patterns = findRepeatingPatterns()
const coreDocs = checkCoreDocs()
const projectSkills = scanProjectSkills()
const systemContext = validateSystemContext()
const pkg = readPkg()
const stack = detectStack(pkg)
const paths = detectPaths()
const gitWorkflow = detectGitWorkflow()

// ─── Output ───────────────────────────────────────────────────────────────

const lines = []

lines.push('# Scan Report')
lines.push('')

lines.push('## 1. Framework & Tech Stack')
lines.push(`- Framework: ${framework.framework}`)
if (Object.keys(framework.notable).length) {
  for (const [dep, ver] of Object.entries(framework.notable)) {
    lines.push(`- ${dep}: ${ver}`)
  }
}
lines.push('')

lines.push('## 2. Directory Structure')
lines.push('### Present')
for (const d of structure.found) lines.push(`- ${d}`)
lines.push('### Absent')
for (const d of structure.missing) lines.push(`- ${d}`)
lines.push('')

lines.push('## 3. Repeating File Patterns')
if (patterns.length === 0) {
  lines.push('- No repeating patterns detected')
} else {
  for (const p of patterns) {
    lines.push(`### ${p.parentDir} (${p.occurrences} directories)`)
    lines.push(`File pattern: \`${p.filePattern}\``)
    lines.push('Examples:')
    for (const ex of p.examples) lines.push(`- ${ex}`)
    lines.push('')
  }
}

lines.push('## 4. Core Documents')
lines.push('### Found')
for (const [key, val] of Object.entries(coreDocs.found)) {
  lines.push(`- ${key}: \`${val}\``)
}
if (coreDocs.missing.length) {
  lines.push('### Missing')
  for (const key of coreDocs.missing) lines.push(`- ${key}`)
}
lines.push('')

lines.push('## 5. System Context Validation')
if (systemContext.exists) {
  lines.push(`- Exists: YES`)
  lines.push(`- First heading: "${systemContext.firstHeading}"`)
  lines.push(
    '- **AI should verify this heading matches the current project name**'
  )
} else {
  lines.push('- Exists: NO → run codebase-understanding first')
}
lines.push('')

lines.push('## 6. Existing Project Skills')
if (projectSkills.length === 0) {
  lines.push('- None found → domain skills need to be created from codebase')
} else {
  for (const s of projectSkills) {
    lines.push(
      `- ${s.name}: \`${s.path}\`${s.hasReferences ? ' (has references/)' : ''}`
    )
  }
}

lines.push('')
lines.push('## 7. Manifest Variable Suggestions')
lines.push(
  '> AI: 確認後寫入 manifest 的 `## Paths` / `## Stack` / `## Git Workflow`；偵測為 null 的列為缺口請使用者補，不要猜。'
)
const sugg = (key, val) => lines.push(`- ${key}: ${val == null ? '⚠️ not detected' : '`' + val + '`'}`)
lines.push('### Paths')
sugg('source_roots', paths.source_roots)
sugg('tests_root', paths.tests_root)
sugg('test_glob', paths.test_glob)
sugg('mockup_root', paths.mockup_root)
sugg('work_root', paths.work_root)
sugg('docs_root', paths.docs_root)
if (paths.has_legacy_artifacts) {
  lines.push('- migration: legacy `.agent/artifacts/` detected; keep it in place as history and use `work_root` for new work items')
}
lines.push('### Stack')
sugg('test_cmd', stack.test_cmd)
sugg('typecheck_cmd', stack.typecheck_cmd)
sugg('lint_cmd', stack.lint_cmd)
sugg('e2e_cmd', stack.e2e_cmd)
sugg('framework', stack.framework)
sugg('package_manager', stack.package_manager)
sugg('source_extensions', stack.source_extensions)
sugg('has_ui', stack.has_ui)
sugg('has_api', stack.has_api)
sugg('typed_contracts', stack.typed_contracts)
sugg('has_e2e', stack.has_e2e)
lines.push('### Git Workflow')
sugg('base_branch', gitWorkflow.base_branch)
sugg('remote', gitWorkflow.remote)
sugg('current_branch', gitWorkflow.current_branch)
lines.push(
  '- ticket_pattern / branch_pattern / commit_format / integration_flow: ⚠️ 詢問使用者（無法可靠自動偵測）'
)
lines.push(
  '- 若 git 流程複雜（多階段整合 / 角色分支 / ticket 綁定）→ 用 `templates/git-workflow-skill.md` scaffold `project/git-workflow` domain skill'
)

console.log(lines.join('\n'))
