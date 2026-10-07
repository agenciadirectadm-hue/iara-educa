// Backup lógico independente do provedor (Fase 2, item 14 do documento de estrutura — SEC-BKP-03, 04 e 08).
//   exportar:          node scripts/backup/backup.mjs exportar --saida D:\backups-iara
//   testar restauração: node scripts/backup/backup.mjs restaurar-teste --pasta D:\backups-iara\iara-20261007-0130
//   decifrar (emergência): node scripts/backup/backup.mjs decifrar --pasta <pasta> --saida <pasta>
// Variáveis (só no ambiente do comando, nunca em arquivo): SUPABASE_ACCESS_TOKEN, BACKUP_SENHA (frase longa, guardada no
// cofre de senhas da Prefeitura — sem ela o backup não abre), SUPABASE_PROJECT_REF (padrão: projeto de demonstração).
// Cada tabela vira um arquivo NDJSON compactado (gzip) e cifrado (AES-256-GCM, chave scrypt da senha). O manifesto
// (sem dados pessoais) traz contagens, hashes do conteúdo e do arquivo, o ponto da corrente de auditoria e o commit.
// O esquema (tabelas, funções, regras de acesso) se reconstrói pelas migrações do repositório; o backup guarda os dados.
// A cópia precisa sair deste computador: armazenamento externo com versionamento e bloqueio contra exclusão (decisão pendente).
import { createCipheriv, createDecipheriv, createHash, randomBytes, scryptSync } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname, relative } from 'node:path';
import { gunzipSync, gzipSync } from 'node:zlib';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
const senha = process.env.BACKUP_SENHA;
const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const [cmd, ...resto] = process.argv.slice(2);
const opt = {};
for (let i = 0; i < resto.length; i++) if (resto[i].startsWith('--')) opt[resto[i].slice(2)] = resto[i + 1] && !resto[i + 1].startsWith('--') ? resto[++i] : true;

const sair = (m) => { console.error(`✗ ${m}`); process.exit(1); };
if (!token) sair('Defina SUPABASE_ACCESS_TOKEN só para este comando.');
if (!senha || senha.length < 16) sair('Defina BACKUP_SENHA (no mínimo 16 caracteres) só para este comando.');

async function sql(query) {
  for (let tentativa = 1; ; tentativa++) {
    const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
    });
    const text = await res.text();
    if (res.ok) return JSON.parse(text);
    if (tentativa < 3 && res.status >= 500) { await new Promise((r) => setTimeout(r, 2000 * tentativa)); continue; }
    let msg = text; try { msg = JSON.parse(text).message ?? text; } catch { /* */ }
    throw new Error(msg);
  }
}
const lit = (s) => { let t; do t = `b${randomBytes(4).toString('hex')}`; while (s.includes(`$${t}$`)); return `$${t}$${s}$${t}$`; };
const sha = (buf) => createHash('sha256').update(buf).digest('hex');

const MAGIC = Buffer.from('IARABK1');
function cifrar(dados) {
  const sal = randomBytes(16), iv = randomBytes(12);
  const chave = scryptSync(senha, sal, 32, { N: 2 ** 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
  const c = createCipheriv('aes-256-gcm', chave, iv);
  const corpo = Buffer.concat([c.update(dados), c.final()]);
  return Buffer.concat([MAGIC, sal, iv, c.getAuthTag(), corpo]);
}
function decifrar(buf) {
  if (!buf.subarray(0, 7).equals(MAGIC)) throw new Error('Arquivo não é um backup do IARA Educa.');
  const sal = buf.subarray(7, 23), iv = buf.subarray(23, 35), tag = buf.subarray(35, 51);
  const chave = scryptSync(senha, sal, 32, { N: 2 ** 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });
  const d = createDecipheriv('aes-256-gcm', chave, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(buf.subarray(51)), d.final()]); // senha errada ou arquivo alterado: erro aqui
}

async function tabelas() {
  return await sql(`
    select t.table_schema s, t.table_name t,
           coalesce((select string_agg(quote_ident(a.attname), ', ' order by k.ord) from pg_index i
                     cross join unnest(i.indkey) with ordinality k(attnum, ord)
                     join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
                     where i.indrelid = (quote_ident(t.table_schema) || '.' || quote_ident(t.table_name))::regclass and i.indisprimary), 'ctid') pk
    from information_schema.tables t
    where t.table_schema in ('iara', 'carga') and t.table_type = 'BASE TABLE' and t.table_name not in ('limites_taxa')
    order by 1, 2`);
}

async function exportar() {
  const base = opt.saida || sair('Informe --saida <pasta fora do repositório>.');
  if (!relative(REPO, resolve(base)).startsWith('..')) sair('A pasta de backup não pode ficar dentro do repositório.');
  const carimbo = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '').replace(/^(\d{8})(\d{4})$/, '$1-$2');
  const pasta = join(base, `iara-${carimbo}`);
  mkdirSync(pasta, { recursive: true });
  const cabeca = (await sql('select seq, hash from iara.audit_chain_head where id = 1'))[0];
  const manifesto = { formato: 'IARABK1 (NDJSON → gzip → AES-256-GCM; chave scrypt N=2^15 da BACKUP_SENHA)', projeto: ref,
    gerado_em: new Date().toISOString(), commit: (() => { try { return execSync('git rev-parse HEAD', { cwd: REPO }).toString().trim(); } catch { return null; } })(),
    migracoes: readdirSync(join(REPO, 'supabase', 'migrations')).filter((f) => f.endsWith('.sql')),
    auditoria: cabeca, tabelas: [] };
  const PAGINA = 4000;
  for (const { s, t, pk } of await tabelas()) {
    const linhas = [];
    for (let off = 0; ; off += PAGINA) {
      const r = await sql(`select coalesce(json_agg(x), '[]') j from (select * from ${s}.${t} order by ${pk} limit ${PAGINA} offset ${off}) x`);
      const lote = r[0].j;
      for (const l of lote) linhas.push(JSON.stringify(l));
      if (lote.length < PAGINA) break;
    }
    const plano = Buffer.from(linhas.join('\n'), 'utf8');
    const cifrado = cifrar(gzipSync(plano, { level: 9 }));
    const arq = `${s}.${t}.ndjson.gz.enc`;
    writeFileSync(join(pasta, arq), cifrado);
    manifesto.tabelas.push({ tabela: `${s}.${t}`, linhas: linhas.length, arquivo: arq, sha256_conteudo: sha(plano), sha256_arquivo: sha(cifrado) });
    process.stdout.write(`\r  ${`${s}.${t}`.padEnd(40)} ${String(linhas.length).padStart(8)} linha(s)`);
  }
  writeFileSync(join(pasta, 'manifesto.json'), JSON.stringify(manifesto, null, 2));
  const total = manifesto.tabelas.reduce((a, x) => a + x.linhas, 0);
  console.log(`\n✓ Backup em ${pasta}: ${manifesto.tabelas.length} tabelas, ${total} linhas; auditoria até o registro ${cabeca.seq}.`);
  console.log('  Copie a pasta para o armazenamento externo (com versionamento e bloqueio contra exclusão).');
}

async function restaurarTeste() {
  const pasta = opt.pasta || sair('Informe --pasta do backup.');
  const m = JSON.parse(readFileSync(join(pasta, 'manifesto.json'), 'utf8'));
  const esquema = 'restauro_teste';
  const t0 = Date.now();
  await sql(`drop schema if exists ${esquema} cascade; create schema ${esquema};`);
  const resultado = [];
  try {
    for (const tb of m.tabelas) {
      const cifrado = readFileSync(join(pasta, tb.arquivo));
      if (sha(cifrado) !== tb.sha256_arquivo) throw new Error(`${tb.tabela}: arquivo alterado (hash não confere).`);
      const plano = gunzipSync(decifrar(cifrado));
      if (sha(plano) !== tb.sha256_conteudo) throw new Error(`${tb.tabela}: conteúdo não confere com o manifesto.`);
      const [s, t] = tb.tabela.split('.');
      await sql(`create table ${esquema}.${t} (like ${s}.${t})`);
      const linhas = plano.length ? plano.toString('utf8').split('\n') : [];
      // lotes de até ~1,5 MB (limite de tamanho da API de gerenciamento)
      for (let i = 0; i < linhas.length;) {
        const parte = [];
        let bytes = 0;
        while (i < linhas.length && (parte.length === 0 || bytes + linhas[i].length < 1_500_000)) { bytes += linhas[i].length + 1; parte.push(linhas[i++]); }
        await sql(`insert into ${esquema}.${t} select * from jsonb_populate_recordset(null::${esquema}.${t}, ${lit('[' + parte.join(',') + ']')}::jsonb)`);
      }
      // confere a quantidade; e mostra quantas linhas diferem da base atual (o que mudou depois do backup)
      const [c] = await sql(`select (select count(*)::int from ${esquema}.${t}) n,
        (select count(*)::int from (select to_jsonb(x) j from ${esquema}.${t} x except select to_jsonb(y) from ${s}.${t} y) d) dif`);
      resultado.push({ tabela: tb.tabela, linhas_backup: tb.linhas, linhas_restauradas: c.n, diferentes_da_base_atual: c.dif, confere: c.n === tb.linhas });
      process.stdout.write(`\r  ${tb.tabela.padEnd(40)} ${String(c.n).padStart(8)}/${tb.linhas}`);
    }
  } finally {
    await sql(`drop schema if exists ${esquema} cascade`);
  }
  const falhas = resultado.filter((r) => !r.confere);
  const seg = Math.round((Date.now() - t0) / 1000);
  console.log(`\n${falhas.length ? '✗' : '✓'} Restauração de teste: ${resultado.length} tabelas, ${resultado.reduce((a, r) => a + r.linhas_restauradas, 0)} linhas em ${seg} s; ${falhas.length} divergência(s).`);
  for (const f of falhas) console.log(`  ✗ ${f.tabela}: backup ${f.linhas_backup}, restauradas ${f.linhas_restauradas}`);
  writeFileSync(join(pasta, `restauracao-teste-${new Date().toISOString().slice(0, 10)}.json`), JSON.stringify({ em: new Date().toISOString(), segundos: seg, resultado }, null, 2));
  if (falhas.length) process.exit(1);
}

function decifrarPasta() {
  const pasta = opt.pasta || sair('Informe --pasta do backup.');
  const saida = opt.saida || sair('Informe --saida para os arquivos NDJSON abertos (pasta protegida).');
  mkdirSync(saida, { recursive: true });
  for (const f of readdirSync(pasta).filter((x) => x.endsWith('.enc'))) {
    writeFileSync(join(saida, f.replace(/\.gz\.enc$/, '')), gunzipSync(decifrar(readFileSync(join(pasta, f)))));
  }
  console.log(`✓ Arquivos abertos em ${saida}. Apague-os assim que terminar.`);
}

const acoes = { exportar, 'restaurar-teste': restaurarTeste, decifrar: decifrarPasta };
(acoes[cmd] ?? (() => console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).join('\n'))))()
  .catch?.((e) => sair(e.message));
