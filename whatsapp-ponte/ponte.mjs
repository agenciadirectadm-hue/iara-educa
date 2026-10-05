/**
 * PONTE DO WHATSAPP — IARA Educa (Baileys, num processo só).
 *
 * Liga um número de WhatsApp ao agente da IARA Educa. Nada é decidido aqui: a ponte só leva texto entre o
 * WhatsApp e o gateway — toda regra vive no gateway e no banco, com o MESMO agente que atende no portal.
 *
 *   mensagem chega  →  POST /whatsapp/entrada  →  respostas da IARA  →  WhatsApp
 *   laço da fila    →  POST /whatsapp/saida    →  (servidor respondendo, aviso de oferta…)  →  WhatsApp → confirmar
 *
 *   npm run ligar     conecta e LIGA o canal (a IARA Educa passa a responder neste número)
 *   Ctrl+C            DESLIGA o canal e encerra
 *   npm run conectar  só conecta; quem manda é o interruptor do painel (WhatsApp da IARA)
 *
 * O chip é o mesmo da IARA Saúde. Cada sistema tem o SEU aparelho conectado (esta pasta guarda o da Educação
 * em .wa-sessao-educa/), então trocar não exige parear de novo: pare a ponte de um e ligue a do outro.
 * Com as duas ligadas, as duas responderiam — ligue UMA de cada vez.
 *
 * .wa-sessao-educa/ vale o mesmo que o celular: quem tiver a pasta, fala pelo número. Nunca vai para o git.
 */
import {
  makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, Browsers,
} from '@whiskeysockets/baileys'
import qrcodeTerminal from 'qrcode-terminal'
import QRImagem from 'qrcode'
import P from 'pino'
import { createServer } from 'node:http'
import { existsSync, mkdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = dirname(fileURLToPath(import.meta.url))
const SESSAO = join(RAIZ, '.wa-sessao-educa')
const env = { ...lerEnv(join(RAIZ, '.env')), ...process.env }
const API = String(env.IARA_API_URL ?? '').replace(/\/+$/, '')
const SEGREDO = String(env.IARA_CANAL_SEGREDO ?? '')
const NUMERO = '+' + String(env.IARA_WHATSAPP_NUMERO ?? '').replace(/\D/g, '')
const PORTA_QR = Number(env.PORTA_QR || 5299)
const LIGAR = process.argv.includes('--ligar')
const INICIO = Date.now()
/** Mensagens que chegaram antes de a ponte subir (quando a outra IARA estava ligada) não são respondidas. */
const TOLERANCIA_ATRASO_MS = 90_000
const BATIMENTO_MS = 60_000
const FILA_MS = 5_000

let sock = null
let conectado = false
let qrAtual = null
let lacos = []
let encerrando = false

function lerEnv(arquivo) {
  if (!existsSync(arquivo)) return {}
  return Object.fromEntries(readFileSync(arquivo, 'utf8').split(/\r?\n/)
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()] }))
}

const log = (...a) => console.log(new Date().toLocaleTimeString('pt-BR'), '·', ...a)
const espera = (ms) => new Promise((r) => setTimeout(r, ms))
const soNumero = (jid) => String(jid ?? '').split('@')[0].split(':')[0].replace(/\D/g, '')
const mascara = (n) => (n.length > 4 ? '…' + n.slice(-4) : n)

async function api(metodo, caminho, corpo) {
  const r = await fetch(`${API}${caminho}`, {
    method: metodo,
    headers: { 'content-type': 'application/json', 'x-iara-canal': SEGREDO, 'x-request-id': `ponte-${Date.now()}` },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  const dados = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(`${caminho}: ${r.status} ${dados?.error ?? ''}`.trim())
  return dados
}
const estado = (e, ok) => api('POST', '/whatsapp/estado', { estado: e, conectado: ok }).catch((err) => log('⚠ estado:', err.message))

/* ───────────────────────────────────────────── página local do QR de pareamento */

function pagina() {
  const base = 'body{font-family:system-ui;background:#2E0F4F;color:#fff;display:grid;place-items:center;min-height:100vh;margin:0;padding:24px;box-sizing:border-box;text-align:center}p{color:#E7D6FB;margin:6px 0;font-size:14px;line-height:1.5;max-width:400px}code{background:#4B1E7A;padding:2px 6px;border-radius:4px}'
  if (conectado) return `<!doctype html><meta charset="utf-8"><title>IARA Educa · conectado</title><style>${base}h1{font-size:28px;margin:0 0 8px}</style><div><h1>✓ WhatsApp conectado</h1><p>A IARA Educa ${LIGAR ? 'já responde' : 'está conectada'} no número <code>${NUMERO}</code>.</p><p style="opacity:.7">Pode fechar esta aba.</p></div>`
  if (!qrAtual) return `<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="2"><title>IARA Educa · aguarde</title><style>${base}</style><p>gerando o QR…</p>`
  return `<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="5"><title>IARA Educa · parear WhatsApp</title>
<style>${base}img{background:#fff;padding:12px;border-radius:14px;width:320px;height:320px}h1{font-size:20px;margin:0 0 4px}</style>
<div><h1>Parear o WhatsApp da IARA Educa</h1>
<p>No celular do número <code>${NUMERO}</code>:<br><b>WhatsApp → Aparelhos conectados → Conectar aparelho</b></p>
<img src="${qrAtual}" alt="QR de pareamento"><p>É um aparelho a mais no mesmo número — o da IARA Saúde continua pareado.<br>A página se renova a cada 5 s.</p></div>`
}
createServer((_, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' })
  res.end(pagina())
}).listen(PORTA_QR, () => log(`página do QR: http://localhost:${PORTA_QR}`))

/* ───────────────────────────────────────────── mensagens */

function extrair(m) {
  const key = m?.key
  if (!key?.remoteJid || key.fromMe) return null
  const jid = String(key.remoteJid)
  if (jid.endsWith('@g.us') || jid.includes('broadcast') || jid.endsWith('@newsletter')) return null
  // O WhatsApp pode entregar um LID (id de privacidade) no lugar do telefone; o telefone vem num campo ao lado.
  const jidTelefone = jid.endsWith('@lid') ? (key.senderPn ?? key.remoteJidAlt ?? m.senderPn ?? null) : jid
  const msg = m.message ?? {}
  const texto = msg.conversation ?? msg.extendedTextMessage?.text ?? msg.imageMessage?.caption ?? msg.documentMessage?.caption
    ?? msg.buttonsResponseMessage?.selectedDisplayText ?? msg.listResponseMessage?.title ?? null
  const audio = msg.audioMessage ?? msg.pttMessage
  const midia = msg.imageMessage ?? msg.documentMessage ?? msg.documentWithCaptionMessage?.message?.documentMessage ?? msg.videoMessage
  const tipo = audio ? 'audio' : texto ? 'texto' : midia ? 'midia' : null
  if (!tipo) return null // figurinha, reação, enquete… não são atendimento
  const ts = Number(m.messageTimestamp ?? 0) * 1000
  return {
    de: soNumero(jidTelefone ?? jid), jid, wa_id: String(key.id ?? ''), nome: m.pushName ?? null,
    texto: texto ?? '', tipo, ts, key,
  }
}

async function responder(e) {
  let r
  try {
    r = await api('POST', '/whatsapp/entrada', { de: e.de, jid: e.jid, nome: e.nome, texto: e.texto, wa_id: e.wa_id, ts: e.ts, tipo: e.tipo })
  } catch (err) {
    log(`✗ ${mascara(e.de)}: ${err.message}`)
    return
  }
  if (r.ativo === false) { log(`  canal DESLIGADO no painel — mensagem de ${mascara(e.de)} não respondida`); return }
  if (r.duplicada) return
  try { await sock.readMessages([e.key]) } catch { /* sem confirmação de leitura não é problema */ }
  if (r.humano) { log(`  ${mascara(e.de)} está com um servidor — a IARA não responde`); return }
  for (const texto of r.respostas ?? []) {
    try {
      await sock.sendPresenceUpdate('composing', e.jid)
      await espera(Math.min(1800, 400 + texto.length * 6))
      await sock.sendMessage(e.jid, { text: texto })
    } catch (err) {
      log(`✗ envio para ${mascara(e.de)}: ${err.message}`)
    }
  }
  try { await sock.sendPresenceUpdate('paused', e.jid) } catch { /* ignora */ }
  log(`  ↳ ${r.respostas?.length ?? 0} resposta(s) para ${mascara(e.de)}`)
}

async function jidPara(item) {
  if (item.jid) return item.jid
  const digitos = String(item.para ?? '').replace(/\D/g, '')
  const [achado] = (await sock.onWhatsApp(digitos).catch(() => [])) ?? []
  return achado?.exists ? achado.jid : `${digitos}@s.whatsapp.net`
}

async function drenarFila() {
  if (!conectado) return
  let lote
  try { lote = await api('POST', '/whatsapp/saida') } catch (err) { log('⚠ fila:', err.message); return }
  for (const item of lote.itens ?? []) {
    try {
      const r = await sock.sendMessage(await jidPara(item), { text: item.texto })
      await api('POST', '/whatsapp/saida/confirmar', { id: item.id, wa_id: r?.key?.id ?? null })
      log(`  ↳ fila: enviado para ${mascara(String(item.para ?? ''))}`)
    } catch (err) {
      await api('POST', '/whatsapp/saida/confirmar', { id: item.id, erro: String(err?.message ?? err) }).catch(() => {})
    }
  }
}

/* ───────────────────────────────────────────── conexão */

async function conectar() {
  mkdirSync(SESSAO, { recursive: true })
  const { state, saveCreds } = await useMultiFileAuthState(SESSAO)
  const { version } = await fetchLatestBaileysVersion()
  sock = makeWASocket({ version, auth: state, browser: Browsers.appropriate('IARA Educa'), logger: P({ level: 'silent' }), markOnlineOnConnect: false })
  sock.ev.on('creds.update', saveCreds)

  sock.ev.on('connection.update', async (u) => {
    if (u.qr) {
      qrAtual = await QRImagem.toDataURL(u.qr)
      qrcodeTerminal.generate(u.qr, { small: true })
      log(`Pareie: WhatsApp do ${NUMERO} → Aparelhos conectados → Conectar aparelho (ou abra http://localhost:${PORTA_QR})`)
      await estado('AGUARDANDO_PAREAMENTO', false)
    }
    if (u.connection === 'open') {
      conectado = true
      qrAtual = null
      log(`✓ conectado ao WhatsApp${LIGAR ? ' — a IARA Educa está respondendo' : ''}`)
      await estado('CONECTADO', true)
    }
    if (u.connection === 'close') {
      conectado = false
      const codigo = u.lastDisconnect?.error?.output?.statusCode
      await estado('DESCONECTADO', false)
      if (encerrando) return
      if (codigo === DisconnectReason.loggedOut) {
        log('✗ o aparelho foi desconectado no celular. Apague a pasta .wa-sessao-educa e rode de novo para parear.')
        await desligarEsair(1)
        return
      }
      if (codigo === DisconnectReason.connectionReplaced) {
        log('✗ outra conexão assumiu ESTA sessão (a mesma pasta aberta em outro lugar?). Encerrando para não brigar por ela.')
        await desligarEsair(1)
        return
      }
      log(`conexão caiu (${codigo ?? 'sem código'}) — reconectando em 3 s`)
      setTimeout(() => conectar().catch((err) => log('✗ reconexão:', err.message)), 3000)
    }
  })

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return
    for (const m of messages) {
      const e = extrair(m)
      if (!e) continue
      if (e.ts && e.ts < INICIO - TOLERANCIA_ATRASO_MS) {
        log(`  (ignorada: mensagem de ${mascara(e.de)} anterior a esta ponte — período em que a outra IARA estava ligada)`)
        continue
      }
      log(`← ${mascara(e.de)}${e.nome ? ` (${e.nome})` : ''}: ${e.tipo === 'texto' ? e.texto.slice(0, 60) : `[${e.tipo}]`}`)
      await responder(e)
    }
  })
}

async function desligarEsair(codigo = 0) {
  if (encerrando) return
  encerrando = true
  lacos.forEach(clearInterval)
  try {
    if (LIGAR) {
      await api('POST', '/whatsapp/canal', { ativo: false })
      log('canal DESLIGADO — a IARA Educa parou de responder neste número.')
    }
    await api('POST', '/whatsapp/estado', { estado: 'SEM_PONTE', conectado: false })
  } catch (err) {
    log('⚠ não consegui avisar o gateway:', err.message)
  }
  try { sock?.end?.(undefined) } catch { /* ignora */ }
  process.exit(codigo)
}
process.on('SIGINT', () => desligarEsair(0))
process.on('SIGTERM', () => desligarEsair(0))

async function principal() {
  if (!API || SEGREDO.length < 24 || NUMERO.length < 11) {
    console.error('Configuração incompleta. Rode `npm run configurar` nesta pasta e registre o hash no banco (veja o README).')
    process.exit(1)
  }
  const canal = await api('GET', '/whatsapp/canal').catch((err) => {
    console.error(`O gateway recusou a ponte (${err.message}). Confira IARA_API_URL e se o hash do segredo foi registrado.`)
    process.exit(1)
  })
  if (canal.numero_e164 !== NUMERO) {
    console.error(`O canal registrado é ${canal.numero_e164}, mas o .env diz ${NUMERO}. Corrija antes de continuar.`)
    process.exit(1)
  }
  log(`IARA Educa · WhatsApp ${NUMERO}`)
  if (LIGAR) {
    await api('POST', '/whatsapp/canal', { ativo: true })
    log('canal LIGADO. Lembrete: a ponte da IARA Saúde precisa estar PARADA (mesmo chip).')
  } else {
    log(`canal ${canal.ativo ? 'LIGADO' : 'DESLIGADO'} no painel${canal.ativo ? '' : ' — conectado, mas sem responder até ligar no painel'}`)
  }
  await conectar()
  lacos = [
    setInterval(() => conectado && estado('CONECTADO', true), BATIMENTO_MS),
    setInterval(() => drenarFila().catch(() => {}), FILA_MS),
  ]
}

principal().catch((err) => {
  console.error('✗', err?.message ?? err)
  process.exit(1)
})
