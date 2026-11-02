#!/usr/bin/env node
// Aplica arquivos SQL no Supabase publicado, em ordem, sem o token passar por chat ou arquivo:
// lê SUPABASE_ACCESS_TOKEN do ambiente ou, se não houver, da área de transferência (a pessoa copia e tecla Enter; a área é
// limpa em seguida). O token é testado antes de qualquer passo. Migrations param na primeira falha (cada uma é uma transação);
// testes de supabase/tests/ seguem (eles devolvem o resultado como erro: RESULTADO: ...).
// Uso: node scripts/aplicar.mjs supabase/migrations/<arquivo>.sql [supabase/tests/<teste>.sql ...]
// Log (sem o token): %TEMP%/iara-aplicar.log
import { spawnSync } from 'node:child_process';
import { appendFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const REF = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
const arquivos = process.argv.slice(2);
if (!arquivos.length) {
  console.error('Informe os arquivos .sql, na ordem. Ex.: node scripts/aplicar.mjs supabase/migrations/<arquivo>.sql');
  process.exit(1);
}
const log = join(tmpdir(), 'iara-aplicar.log');
writeFileSync(log, `início ${new Date().toISOString()} · ${arquivos.join(' ')}\n`);
const escreve = (t) => appendFileSync(log, t + '\n');

const esperarEnter = (msg) => new Promise((ok) => {
  process.stdout.write(msg);
  process.stdin.resume();
  process.stdin.once('data', () => { process.stdin.pause(); ok(); });
});
const clipboard = () => spawnSync('powershell', ['-NoProfile', '-Command', 'Get-Clipboard -Raw'], { encoding: 'utf8' }).stdout ?? '';
const limparClipboard = () => spawnSync('powershell', ['-NoProfile', '-Command', "Set-Clipboard -Value ' '"]);
const aceito = async (t) => (await fetch(`https://api.supabase.com/v1/projects/${REF}`, { headers: { Authorization: `Bearer ${t}` } }).catch(() => ({ ok: false }))).ok;

let token = process.env.SUPABASE_ACCESS_TOKEN ?? '';
if (token && !(await aceito(token))) {
  console.log('O token da variável SUPABASE_ACCESS_TOKEN foi recusado pelo Supabase.');
  token = '';
}
for (let tentativa = 1; tentativa <= 3 && !token; tentativa++) {
  await esperarEnter(tentativa === 1
    ? 'Copie o token pessoal do Supabase (Ctrl+C) e tecle SÓ Enter aqui — não cole: '
    : 'Copie o token de novo e tecle só Enter (ou Ctrl+C para sair): ');
  const t = clipboard().match(/sbp_[0-9A-Za-z_]+/)?.[0] ?? '';
  if (!t) { console.log('A área de transferência não tem um texto começando com sbp_.'); continue; }
  if (await aceito(t)) { token = t; limparClipboard(); console.log('Token aceito pelo Supabase. Área de transferência limpa.'); }
  else console.log('O Supabase recusou o token. Gere um novo em Account > Access Tokens, se precisar.');
}
if (!token) {
  console.log('Sem token válido: nada foi feito.');
  escreve('PARADO: sem token válido');
  process.exit(1);
}

const env = { ...process.env, SUPABASE_ACCESS_TOKEN: token, SQL_OUT_LIMIT: '200000' };
for (const arquivo of arquivos) {
  const teste = /supabase[\\/]tests[\\/]/.test(arquivo);
  console.log(`== ${arquivo}`);
  escreve(`\n== ${arquivo}`);
  const r = spawnSync(process.execPath, ['scripts/sql.mjs', arquivo], { env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  escreve((r.stdout ?? '') + (r.stderr ?? ''));
  escreve(`== fim ${arquivo}: código ${r.status}`);
  console.log(`   código ${r.status}${teste ? ' (teste: o resultado vem como erro, veja o log)' : ''}`);
  if (r.status !== 0 && !teste) {
    console.log('Parado: a migration falhou e foi revertida.');
    escreve('PARADO');
    break;
  }
}
escreve(`FIM ${new Date().toISOString()}`);
console.log(`FIM — log em ${log}`);
