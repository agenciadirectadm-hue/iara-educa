/**
 * Desliga a ponte do WhatsApp da IARA Educa com segurança: desliga o canal no painel (a IARA para de responder
 * neste número) e encerra o processo. Serve para quando a ponte roda sem janela (sem Ctrl+C).
 *   npm run parar        (nesta pasta)   ·   npm run whatsapp:parar   (na raiz do projeto)
 */
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = dirname(fileURLToPath(import.meta.url))
const env = existsSync(join(RAIZ, '.env'))
  ? Object.fromEntries(readFileSync(join(RAIZ, '.env'), 'utf8').split(/\r?\n/)
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()] }))
  : {}
const PORTA = Number(process.env.PORTA_QR || env.PORTA_QR || 5299)

try {
  const r = await fetch(`http://127.0.0.1:${PORTA}/parar`, { method: 'POST' })
  console.log(r.ok ? 'Ponte desligada: o canal da IARA Educa foi desligado no painel.' : `A ponte respondeu ${r.status}.`)
} catch {
  console.log('Nenhuma ponte ligada neste computador (nada a desligar).')
}
