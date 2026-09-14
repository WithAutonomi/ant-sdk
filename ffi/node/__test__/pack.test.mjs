// Packed-tarball check: the ROOT package must ship its JS loader and type
// declarations (they are its only entry points), and must NOT ship any native
// `.node` binary (those go in the per-platform packages).
//
// Runs `npm pack --dry-run --json` from the package root, so it exercises the
// real `files` allowlist + .npmignore semantics npm will apply at publish time.

import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { test } from 'node:test'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')

test('root tarball ships index.js + index.d.ts and no .node binary', () => {
  const out = execFileSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts'], {
    cwd: root,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    stdio: ['ignore', 'pipe', 'ignore'],
  })
  const [pkg] = JSON.parse(out)
  const files = pkg.files.map((f) => f.path).sort()
  for (const required of ['README.md', 'index.d.ts', 'index.js', 'package.json']) {
    assert.ok(files.includes(required), `tarball is missing ${required}; got ${files.join(', ')}`)
  }
  const native = files.filter((f) => f.endsWith('.node'))
  assert.deepEqual(native, [], `root tarball must not carry native binaries: ${native.join(', ')}`)
  assert.equal(pkg.name, '@withautonomi/ant-sdk')
})
