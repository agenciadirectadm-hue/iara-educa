// Carga dos dados reais — operador da carga (seção 9 do documento de estrutura).
// Fluxo, domínio por domínio, na ordem: UNIDADES → TURMAS → SERVIDORES → RESPONSAVEIS → ALUNOS → VINCULOS → MATRICULAS → FILA
//   node scripts/carga/carga.mjs receber   --dominio ALUNOS --arquivo D:\cargas\alunos.csv --origem "Sistema X" --referencia 2026-10-01 --responsavel "Nome"
//   node scripts/carga/carga.mjs validar   --lote <código>
//   node scripts/carga/carga.mjs conciliar --lote <código>
//   node scripts/carga/carga.mjs promover  --lote <código> [--parcial]
//   node scripts/carga/carga.mjs reverter  --lote <código>
//   node scripts/carga/carga.mjs descartar --lote <código> --motivo "arquivo errado"
//   node scripts/carga/carga.mjs situacao  [--lote <código>]
//   node scripts/carga/carga.mjs layouts   --saida <pasta>          (modelos CSV e dicionário para a SEDUC)
//   node scripts/carga/carga.mjs ensaio    --pasta <pasta>          (arquivos fictícios: valida, promove e DESFAZ tudo)
// Segurança: token só por variável de ambiente (SUPABASE_ACCESS_TOKEN), nunca em arquivo; arquivos de dados nunca dentro do
// repositório; dados reais nunca no projeto de demonstração (a produção é um projeto novo: defina SUPABASE_PROJECT_REF).
import { createHash, randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const DEMO_REF = 'fqpjbyhewzngutbyydig';
const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || DEMO_REF;
const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DOMINIOS = ['UNIDADES', 'TURMAS', 'SERVIDORES', 'RESPONSAVEIS', 'ALUNOS', 'VINCULOS', 'MATRICULAS', 'FILA'];

const [cmd, ...resto] = process.argv.slice(2);
const opt = {};
for (let i = 0; i < resto.length; i++) {
  if (resto[i].startsWith('--')) {
    const k = resto[i].slice(2);
    opt[k] = resto[i + 1] && !resto[i + 1].startsWith('--') ? resto[++i] : true;
  }
}

function sair(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

async function sql(query) {
  if (!token) sair('Defina SUPABASE_ACCESS_TOKEN (token pessoal do Supabase) só para este comando.');
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) {
    let msg = text;
    try { msg = JSON.parse(text).message ?? text; } catch { /* texto puro */ }
    const e = new Error(msg);
    e.status = res.status;
    throw e;
  }
  return JSON.parse(text);
}

// JSON dentro do SQL com uma etiqueta de dólar que não aparece no conteúdo
function lit(obj) {
  const s = JSON.stringify(obj);
  let tag;
  do tag = `c${randomBytes(4).toString('hex')}`; while (s.includes(`$${tag}$`));
  return `$${tag}$${s}$${tag}$::jsonb`;
}

// texto puro dentro do SQL (sem aspas do JSON)
function litTexto(s) {
  const v = String(s ?? '');
  let tag;
  do tag = `t${randomBytes(4).toString('hex')}`; while (v.includes(`$${tag}$`));
  return `$${tag}$${v}$${tag}$`;
}

async function chamar(fn, args) {
  const r = await sql(`select carga.${fn}(${lit(args)}) as r`);
  return r[0]?.r;
}

// CSV: separador , ou ; (detectado no cabeçalho), aspas duplas, UTF-8 (com ou sem BOM) ou Windows-1252
function lerCsv(caminho) {
  const buf = readFileSync(caminho);
  let texto;
  try {
    texto = new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    texto = new TextDecoder('windows-1252').decode(buf);
  }
  texto = texto.replace(/^\uFEFF/, '');
  const primeira = texto.split(/\r?\n/, 1)[0];
  const sep = (primeira.match(/;/g)?.length ?? 0) > (primeira.match(/,/g)?.length ?? 0) ? ';' : ',';
  const linhas = [];
  let campo = '';
  let linha = [];
  let aspas = false;
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (aspas) {
      if (c === '"' && texto[i + 1] === '"') { campo += '"'; i++; }
      else if (c === '"') aspas = false;
      else campo += c;
    } else if (c === '"') aspas = true;
    else if (c === sep) { linha.push(campo); campo = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && texto[i + 1] === '\n') i++;
      linha.push(campo); campo = '';
      if (linha.some((v) => v.trim() !== '')) linhas.push(linha);
      linha = [];
    } else campo += c;
  }
  linha.push(campo);
  if (linha.some((v) => v.trim() !== '')) linhas.push(linha);
  const [cab, ...dados] = linhas;
  if (!cab) sair('Arquivo vazio.');
  return { cabecalho: cab.map((h) => h.trim()), linhas: dados.map((l) => Object.fromEntries(cab.map((h, k) => [h.trim(), (l[k] ?? '').trim()]))) };
}

function exigirForaDoRepositorio(caminho) {
  const rel = relative(REPO, resolve(caminho));
  if (!rel.startsWith('..') && !resolve(caminho).startsWith('\\\\')) {
    sair(`O arquivo está dentro do repositório (${rel}). Dados não podem ficar na pasta do projeto: mova para uma pasta protegida fora dele.`);
  }
}

function imprimirResumo(r) {
  if (!r) return;
  console.log(`\nLote ${r.lote} · ${r.dominio} · ${r.situacao}${r.ensaio ? ' · ENSAIO' : ''}`);
  console.log(`  linhas ${r.linhas} · ok ${r.ok ?? '-'} · aviso ${r.aviso ?? '-'} · erro ${r.erro ?? '-'} · promovidas ${r.promovidas ?? 0}`);
  for (const m of r.mensagens ?? []) console.log(`  ${m.tipo === 'erro' ? '✗' : '!'} ${m.mensagem} (${m.linhas} linha(s))`);
  if (r.resultado) console.log(`  resultado: ${JSON.stringify(r.resultado)}`);
  if (r.conciliacao) console.log(`  conciliação: ${JSON.stringify(r.conciliacao)}`);
}

async function receber({ dominio, arquivo, lote, origem, referencia, responsavel, ensaio, observacoes }) {
  if (!DOMINIOS.includes(String(dominio).toUpperCase())) sair(`Informe --dominio (${DOMINIOS.join(', ')}).`);
  if (!arquivo) sair('Informe --arquivo.');
  exigirForaDoRepositorio(arquivo);
  if (!ensaio && ref === DEMO_REF) {
    sair('Este é o projeto de DEMONSTRAÇÃO: dados reais não entram aqui. Defina SUPABASE_PROJECT_REF com o projeto de produção (ou use --ensaio com arquivos fictícios).');
  }
  if (!ensaio && (!origem || !referencia || !responsavel)) sair('Carga real exige --origem, --referencia (AAAA-MM-DD) e --responsavel.');
  const hash = createHash('sha256').update(readFileSync(arquivo)).digest('hex');
  const { linhas } = lerCsv(arquivo);
  const codigo = lote || `${String(dominio).toUpperCase()}-${new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '')}${ensaio ? '-ENSAIO' : ''}`;
  const PARTE = 1000;
  let r;
  for (let i = 0; i < linhas.length; i += PARTE) {
    r = await chamar('receber', {
      lote: codigo, dominio: String(dominio).toUpperCase(), arquivo: basename(arquivo), hash, origem: origem || 'Ensaio (fictício)',
      data_referencia: referencia || new Date().toISOString().slice(0, 10), responsavel: responsavel || 'ensaio', ensaio: !!ensaio,
      observacoes, linhas: linhas.slice(i, i + PARTE),
    });
    process.stdout.write(`\r  recebidas ${r.total}/${linhas.length}`);
  }
  console.log(`\n✓ Lote ${codigo}: ${linhas.length} linha(s) · sha256 ${hash.slice(0, 16)}…`);
  return codigo;
}

async function emPartes(fn, lote, extra = {}) {
  let r;
  do {
    r = await chamar(fn, { lote, limite: 3000, ...extra });
    if (r?.restam) process.stdout.write(`\r  ${fn}: restam ${r.restam}   `);
  } while (r?.restam);
  return r;
}

async function main() {
  switch (cmd) {
    case 'receber':
      await receber(opt);
      break;
    case 'validar':
      imprimirResumo(await emPartes('validar', opt.lote, opt.refazer ? { refazer: true } : {}));
      break;
    case 'conciliar':
      console.log(JSON.stringify((await sql(`select carga.conciliar(${litTexto(opt.lote)}) as r`))[0]?.r, null, 2));
      break;
    case 'promover':
      imprimirResumo(await emPartes('promover', opt.lote, opt.parcial ? { parcial: true } : {}));
      break;
    case 'reverter':
      imprimirResumo(await chamar('reverter', { lote: opt.lote }));
      break;
    case 'descartar':
      console.log(await chamar('descartar', { lote: opt.lote, motivo: opt.motivo }));
      break;
    case 'situacao': {
      if (opt.lote) imprimirResumo((await sql(`select carga.resumo(${litTexto(opt.lote)}) as r`))[0]?.r);
      else for (const l of await sql(`select codigo, dominio, situacao, ensaio, linhas, linhas_erro, recebido_em from carga.lotes where situacao <> 'DESCARTADO' order by id desc limit 30`))
        console.log(`${l.codigo.padEnd(34)} ${l.dominio.padEnd(13)} ${l.situacao.padEnd(10)} ${String(l.linhas).padStart(7)} linhas ${l.linhas_erro ? `(${l.linhas_erro} com erro)` : ''}${l.ensaio ? ' · ensaio' : ''}`);
      break;
    }
    case 'layouts': {
      const saida = opt.saida || sair('Informe --saida <pasta>.');
      mkdirSync(saida, { recursive: true });
      const campos = await sql('select dominio, campo, tipo, obrigatorio, chave, valores, descricao, exemplo from carga.layouts order by dominio, ordem');
      let md = '# IARA Educa — layouts dos arquivos de carga\n\nCSV em UTF-8 (ou Windows-1252), separador `;` ou `,`, uma linha de cabeçalho com os nomes abaixo.\n' +
        'Datas: AAAA-MM-DD ou DD/MM/AAAA. Sim/não: S ou N. Códigos (chaves) estáveis: não mudam de uma carga para outra.\n' +
        'Ordem de envio: ' + DOMINIOS.join(' → ') + '.\n';
      for (const d of DOMINIOS) {
        const cs = campos.filter((c) => c.dominio === d);
        writeFileSync(join(saida, `${d.toLowerCase()}.csv`), '\uFEFF' + cs.map((c) => c.campo).join(';') + '\n' + cs.map((c) => (c.exemplo ?? '').replace(/;/g, ',')).join(';') + '\n');
        md += `\n## ${d}\n\n| Campo | Tipo | Obrigatório | Descrição | Exemplo |\n|---|---|---|---|---|\n` +
          cs.map((c) => `| \`${c.campo}\`${c.chave ? ' (chave)' : ''} | ${c.tipo}${c.valores ? `: ${c.valores.join(', ')}` : ''} | ${c.obrigatorio ? 'sim' : 'não'} | ${c.descricao} | ${c.exemplo ?? ''} |`).join('\n') + '\n';
      }
      writeFileSync(join(saida, 'LAYOUTS.md'), md);
      console.log(`✓ Modelos e dicionário em ${resolve(saida)}`);
      break;
    }
    case 'ensaio': {
      const pasta = opt.pasta || sair('Informe --pasta com os CSVs fictícios (nome do arquivo = domínio, ex.: alunos.csv).');
      const arquivos = readdirSync(pasta).filter((f) => f.toLowerCase().endsWith('.csv'));
      const lotes = [];
      const marca = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
      for (const d of DOMINIOS) {
        const f = arquivos.find((a) => a.toLowerCase() === `${d.toLowerCase()}.csv`);
        if (f) lotes.push(await receber({ dominio: d, arquivo: join(pasta, f), lote: `ENSAIO-${marca}-${d}`, ensaio: true }));
      }
      try {
        await sql(`select carga.ensaiar(${lit({ lotes })})`);
      } catch (e) {
        const m = /ENSAIO: (\[.*\])/s.exec(e.message);
        if (!m) throw e;
        for (const r of JSON.parse(m[1])) imprimirResumo(r);
        console.log('\n✓ Ensaio concluído: tudo foi desfeito (nada ficou na base); os lotes de ensaio ficam registrados como DESCARTADO.');
        for (const l of lotes) await chamar('descartar', { lote: l, motivo: 'ensaio concluído' });
      }
      break;
    }
    default:
      console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).join('\n'));
  }
}

main().catch((e) => sair(e.message));
