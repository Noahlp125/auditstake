// Copia los ABIs compilados por Foundry (../out) y las direcciones desplegadas
// (../deployments) a src/contracts/generated.ts, para usarlos con tipos en wagmi.
//
// Uso:  npm run sync      (despues de `forge build` y del script de despliegue)

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..') // raiz del proyecto Foundry
const outDir = join(root, 'out')
const deploymentsDir = join(root, 'deployments')
const target = join(here, '..', 'src', 'contracts', 'generated.ts')

const CONTRACTS = ['CoveragePool', 'ClaimManager', 'CoverageRegistry', 'MockERC20']

function readAbi(name) {
  const file = join(outDir, `${name}.sol`, `${name}.json`)
  if (!existsSync(file)) {
    console.error(`No encuentro ${file}. Ejecuta "forge build" en la raiz del proyecto.`)
    process.exit(1)
  }
  return JSON.parse(readFileSync(file, 'utf8')).abi
}

const deployments = {}
if (existsSync(deploymentsDir)) {
  for (const f of readdirSync(deploymentsDir).filter((f) => f.endsWith('.json'))) {
    const d = JSON.parse(readFileSync(join(deploymentsDir, f), 'utf8'))
    deployments[d.chainId] = d
  }
}
if (Object.keys(deployments).length === 0) {
  console.warn('Aviso: no hay despliegues en deployments/. Lanza el script Deploy.s.sol primero.')
}

let ts = '// Archivo generado por scripts/sync-contracts.mjs. No lo edites a mano.\n\n'
for (const name of CONTRACTS) {
  const varName = name.charAt(0).toLowerCase() + name.slice(1) + 'Abi'
  ts += `export const ${varName} = ${JSON.stringify(readAbi(name), null, 2)} as const\n\n`
}
ts += `export const deployments = ${JSON.stringify(deployments, null, 2)} as const\n`

writeFileSync(target, ts)
console.log(`OK: ${CONTRACTS.length} ABIs y ${Object.keys(deployments).length} despliegue(s) -> src/contracts/generated.ts`)
