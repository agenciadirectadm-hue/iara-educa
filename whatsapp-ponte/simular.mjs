/**
 * Simula a ponte sem celular: manda mensagens ao gateway como se viessem do WhatsApp e mostra o que a IARA
 * responderia. Nada é enviado de verdade. Usa o segredo do .env desta pasta.
 *
 *   node simular.mjs                          → conversa de exemplo (família nova)
 *   node simular.mjs +5544900001234 "oi" "1"  → telefone e mensagens à sua escolha
 *
 * O canal precisa estar LIGADO (painel ou `npm run ligar`); com --ligar, liga no início e desliga no fim.
 */
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries((existsSync(join(RAIZ, '.env')) ? readFileSync(join(RAIZ, '.env'), 'utf8') : '').split(/\r?\n/)
  .filter((l) => l.includes('=') && !l.trim().startsWith('#')).map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]))
const API = String(env.IARA_API_URL ?? '').replace(/\/+$/, '')
const args = process.argv.slice(2).filter((a) => a !== '--ligar')
const ligar = process.argv.includes('--ligar')
const telefone = args[0]?.startsWith('+') ? args.shift() : '+5544900001234'
const roteiro = args.length ? args : ['Olá, IARA! Quero atendimento da Educação de Maringá.', '2']

async function api(metodo, caminho, corpo) {
  const r = await fetch(`${API}${caminho}`, {
    method: metodo, headers: { 'content-type': 'application/json', 'x-iara-canal': env.IARA_CANAL_SEGREDO ?? '' },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  const d = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(`${caminho}: ${r.status} ${d.error ?? ''}`)
  return d
}

const canal = await api('GET', '/whatsapp/canal')
console.log(`canal ${canal.numero_e164} · ${canal.ativo ? 'LIGADO' : 'DESLIGADO'} · simulando ${telefone}\n`)
if (ligar) await api('POST', '/whatsapp/canal', { ativo: true })
try {
  for (const [i, texto] of roteiro.entries()) {
    const tipo = texto === '[audio]' ? 'audio' : 'texto'
    console.log(`📱 ${telefone}: ${texto}`)
    const r = await api('POST', '/whatsapp/entrada', {
      de: telefone, jid: telefone.replace(/\D/g, '') + '@s.whatsapp.net', nome: 'Teste Simulado',
      texto: tipo === 'texto' ? texto : '', tipo, wa_id: `SIMULADO-${Date.now()}-${i}`, ts: Date.now(),
    })
    if (r.ativo === false) { console.log('   (canal desligado — sem resposta)\n'); continue }
    for (const resp of r.respostas ?? []) console.log('🤖 IARA:\n' + resp.split('\n').map((l) => '   ' + l).join('\n'))
    console.log('')
  }
} finally {
  if (ligar) await api('POST', '/whatsapp/canal', { ativo: false })
}
