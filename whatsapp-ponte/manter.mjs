/**
 * VIGIA da ponte do WhatsApp — IARA Educa.
 * Roda `ponte.mjs --ligar` e a religa sozinho se ela cair (internet instável, erro inesperado), esperando
 * 5 s, 10 s, 20 s… até 1 min entre tentativas. NÃO religa quando o desligamento foi intencional:
 *   0  desligada de propósito (Ctrl+C ou `npm run parar`)
 *   3  aparelho removido no celular (precisa parear de novo)
 *   4  a mesma sessão foi aberta em outro lugar (não brigar por ela)
 */
import { spawn } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = dirname(fileURLToPath(import.meta.url))
const NAO_RELIGAR = new Set([0, 3, 4])
const log = (...a) => console.log(new Date().toLocaleTimeString('pt-BR'), '· vigia ·', ...a)
let espera = 5_000
let filho = null
let parando = false

function iniciar() {
  const inicio = Date.now()
  filho = spawn(process.execPath, [join(RAIZ, 'ponte.mjs'), '--ligar'], { cwd: RAIZ, stdio: 'inherit' })
  filho.on('exit', (codigo, sinal) => {
    filho = null
    if (parando || NAO_RELIGAR.has(codigo ?? -1)) {
      log(`ponte encerrada (${codigo ?? sinal}); o vigia também encerra.`)
      process.exit(codigo ?? 0)
    }
    // ficou de pé por mais de 5 min: a queda é nova, recomeça a contagem curta
    if (Date.now() - inicio > 5 * 60_000) espera = 5_000
    log(`a ponte caiu (${codigo ?? sinal}). Religando em ${Math.round(espera / 1000)} s…`)
    setTimeout(iniciar, espera)
    espera = Math.min(espera * 2, 60_000)
  })
}

// Ctrl+C chega também à ponte (mesmo console); o vigia só espera ela desligar o canal e sair.
for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => { parando = true; if (!filho) process.exit(0) })

log('ponte sob vigia: se cair, religa sozinha.')
iniciar()
