/**
 * Configura a ponte: cria o .env a partir do .env.example e gera o segredo da ponte (se ainda não existir).
 * O segredo fica SÓ no .env desta pasta (fora do git). Na tela sai apenas o hash, que é o que o banco guarda.
 *
 *   npm run configurar           → mantém o segredo atual, se houver
 *   npm run configurar -- --novo → troca o segredo (a ponte antiga deixa de ser aceita)
 */
import { randomBytes, createHash } from 'node:crypto'
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = dirname(fileURLToPath(import.meta.url))
const ENV = join(RAIZ, '.env')
if (!existsSync(ENV)) copyFileSync(join(RAIZ, '.env.example'), ENV)

let txt = readFileSync(ENV, 'utf8')
const linha = /^IARA_CANAL_SEGREDO=(.*)$/m
let segredo = (linha.exec(txt)?.[1] ?? '').trim()
const trocou = !segredo || process.argv.includes('--novo')
if (trocou) {
  segredo = randomBytes(32).toString('base64url')
  txt = linha.test(txt) ? txt.replace(linha, `IARA_CANAL_SEGREDO=${segredo}`) : `${txt.trimEnd()}\nIARA_CANAL_SEGREDO=${segredo}\n`
  writeFileSync(ENV, txt)
}
const numero = (/^IARA_WHATSAPP_NUMERO=(.*)$/m.exec(txt)?.[1] ?? '').trim()
const hash = createHash('sha256').update(segredo).digest('hex')

console.log(hash)
console.error(trocou ? '✓ segredo novo gravado em whatsapp-ponte/.env' : '✓ segredo existente mantido')
console.error('Registre o hash no banco (uma vez, ou a cada troca de segredo):')
console.error(`  update iara.whatsapp_channels set segredo_hash = '${hash}' where numero_e164 = '${numero}';`)
