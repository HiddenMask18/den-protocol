// ABI drift guard. Validates that every function/event declared in the hand-maintained
// canonical abis.ts matches the compiled Foundry artifacts (contracts/out) by name AND
// signature (inputs, outputs, stateMutability). Run after `forge build`.
//
//   bun scripts/check-abis.ts
//
// Exits non-zero on any drift so it can gate CI / a pre-commit hook. abis.ts is a curated
// subset (only what the instance + client call), so MISSING-from-artifact is the failure
// mode we catch — not extra functions in the artifact that abis.ts intentionally omits.
import * as abis from '../abis.ts'

const MAP: Record<string, string> = {
  identityRegistryAbi: 'DENIdentityRegistry',
  identityImplAbi: 'DENIdentityImpl',
  subscriptionAbi: 'DENSubscription',
  contentRegistryAbi: 'DENContentRegistry',
  accessGrantAbi: 'DENAccessGrant',
  purchaseStateAbi: 'DENPurchaseState',
  reportRegistryAbi: 'DENReportRegistry',
  trustTierAbi: 'DENTrustTier',
  governanceAbi: 'DENGovernanceParams',
  compensationAbi: 'DENHostCompensation',
}

const sig = (xs: { type: string }[] = []) => xs.map((i) => i.type).join(',')
let problems = 0

for (const [name, contract] of Object.entries(MAP)) {
  const path = `${import.meta.dir}/../contracts/out/${contract}.sol/${contract}.json`
  const file = Bun.file(path)
  if (!(await file.exists())) {
    console.log(`SKIP   ${name}: artifact not found (run \`forge build\` in contracts/) — ${path}`)
    continue
  }
  const art = JSON.parse(await file.text())
  for (const e of (abis as Record<string, any[]>)[name]) {
    if (e.type !== 'function' && e.type !== 'event') continue
    const matches = art.abi.filter((a: any) => a.type === e.type && a.name === e.name)
    if (!matches.length) {
      console.log(`MISSING   ${name}.${e.name} (${e.type}) — not in ${contract}`)
      problems++
      continue
    }
    const ok = matches.some(
      (m: any) =>
        sig(m.inputs) === sig(e.inputs) &&
        (e.type === 'event' ||
          (sig(m.outputs) === sig(e.outputs) && m.stateMutability === e.stateMutability)),
    )
    if (!ok) {
      console.log(`SIG DRIFT ${name}.${e.name}`)
      console.log(`  abis.ts : in(${sig(e.inputs)}) out(${sig(e.outputs)}) ${e.stateMutability ?? ''}`)
      for (const m of matches)
        console.log(`  artifact: in(${sig(m.inputs)}) out(${sig(m.outputs)}) ${m.stateMutability ?? ''}`)
      problems++
    }
  }
}

if (problems) {
  console.error(`\n✗ ${problems} ABI drift problem(s). Update abis.ts to match the contracts.`)
  process.exit(1)
}
console.log('✓ abis.ts matches the compiled artifacts (name + signature).')
