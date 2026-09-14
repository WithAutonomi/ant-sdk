// TypeScript consumer check — compiled by `npm run typecheck` with
// `isolatedModules: true` (the mode Vite/esbuild/Next.js projects use).
//
// Under isolatedModules a `declare const enum` cannot be referenced by value
// (TS2748), so this guards the `--no-const-enum` build flag: the public enums
// must be ordinary runtime enums that a bundled app can use.

import { Client, PaymentMode, ProgressPhase, Visibility } from '../index.js'
import type { ProgressUpdate } from '../index.js'

export const mode: PaymentMode = PaymentMode.Auto
export const visibility: Visibility = Visibility.Public

export function describe(p: ProgressUpdate): string {
  const phase: ProgressPhase = p.phase
  return `${ProgressPhase[phase]} ${p.done}/${p.total}`
}

export async function upload(client: Client, path: string): Promise<string> {
  const res = await client.fileUploadPublicWithProgress(path, PaymentMode.Auto, (p) => {
    void describe(p)
  })
  return res.address
}
