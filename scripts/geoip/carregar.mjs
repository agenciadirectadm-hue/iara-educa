#!/usr/bin/env node
// Carrega no banco a base gratuita de localização por IP da DB-IP (IP to City Lite e IP to ASN Lite, licença CC BY 4.0), usada
// pelo registro de entradas no portal (migração 099.22) para mostrar cidade, estado e provedor de quem abriu o portal.
// O Brasil fica com estado (UF) e cidade; fora do Brasil, só o país. Faixas vizinhas iguais viram uma só.
// A carga vai para tabelas de carga e só no fim troca a base (iara.geoip_trocar), numa transação: a consulta nunca fica vazia.
//
// Uso: node scripts/geoip/carregar.mjs [--pasta <pasta com os .csv.gz>] [--mes 2026-11]
//   sem --pasta, baixa os dois arquivos do mês para %TEMP%\iara-geoip. A DB-IP atualiza a base no dia 1º de cada mês.
// Token: SUPABASE_ACCESS_TOKEN do ambiente ou a variável do usuário no Windows (como scripts/deploy-function.mjs).
import { spawnSync } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { createGunzip } from 'node:zlib';

const REF = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
const arg = (nome) => { const i = process.argv.indexOf(nome); return i > 0 ? process.argv[i + 1] : null; };
const mes = arg('--mes') || new Date().toISOString().slice(0, 7);
const pasta = arg('--pasta') || join(tmpdir(), 'iara-geoip');
const ARQ_LOCAL = `dbip-city-lite-${mes}.csv.gz`;
const ARQ_ASN = `dbip-asn-lite-${mes}.csv.gz`;

const token = process.env.SUPABASE_ACCESS_TOKEN || (process.platform === 'win32'
  ? (spawnSync('powershell', ['-NoProfile', '-Command', "[Environment]::GetEnvironmentVariable('SUPABASE_ACCESS_TOKEN','User')"], { encoding: 'utf8' }).stdout ?? '').trim()
  : '');
if (!token) { console.error('Defina SUPABASE_ACCESS_TOKEN.'); process.exit(1); }

async function consulta(query) {
  for (let tentativa = 1; ; tentativa++) {
    const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ query }),
    });
    const texto = await res.text();
    if (res.ok) return JSON.parse(texto);
    if (res.status === 401) throw new Error('O Supabase recusou o token (401). Nada foi trocado.');
    if (tentativa >= 3 || res.status < 500) throw new Error(`${res.status}: ${texto.slice(0, 400)}`);
    await new Promise((r) => setTimeout(r, 2000 * tentativa));
  }
}

async function baixar(nome) {
  const destino = join(pasta, nome);
  if (existsSync(destino) && statSync(destino).size > 1_000_000) return destino;
  mkdirSync(pasta, { recursive: true });
  console.log(`baixando ${nome}…`);
  const res = await fetch(`https://download.db-ip.com/free/${nome}`);
  if (!res.ok) throw new Error(`download de ${nome}: ${res.status} (a base do mês sai no dia 1º; use --mes AAAA-MM)`);
  writeFileSync(destino, Buffer.from(await res.arrayBuffer()));
  return destino;
}

// CSV simples com aspas (as cidades podem ter vírgula)
function campos(linha) {
  const out = [];
  let atual = '';
  let aspas = false;
  for (let i = 0; i < linha.length; i++) {
    const c = linha[i];
    if (aspas) {
      if (c === '"' && linha[i + 1] === '"') { atual += '"'; i++; } else if (c === '"') aspas = false; else atual += c;
    } else if (c === '"') aspas = true;
    else if (c === ',') { out.push(atual); atual = ''; } else atual += c;
  }
  out.push(atual);
  return out;
}

async function* linhas(arquivo) {
  const rl = createInterface({ input: createReadStream(arquivo).pipe(createGunzip()), crlfDelay: Infinity });
  for await (const l of rl) if (l) yield campos(l);
}

const UF = {
  Acre: 'AC', Alagoas: 'AL', 'Amapá': 'AP', Amazonas: 'AM', Bahia: 'BA', 'Ceará': 'CE', 'Federal District': 'DF', 'Distrito Federal': 'DF',
  'Espírito Santo': 'ES', 'Goiás': 'GO', 'Maranhão': 'MA', 'Mato Grosso': 'MT', 'Mato Grosso do Sul': 'MS', 'Minas Gerais': 'MG', 'Pará': 'PA',
  'Paraíba': 'PB', 'Paraná': 'PR', Pernambuco: 'PE', 'Piauí': 'PI', 'Rio de Janeiro': 'RJ', 'Rio Grande do Norte': 'RN',
  'Rio Grande do Sul': 'RS', 'Rondônia': 'RO', Roraima: 'RR', 'Santa Catarina': 'SC', 'São Paulo': 'SP', Sergipe: 'SE', Tocantins: 'TO',
};
const v6 = (ip) => ip.includes(':');
const q = (s) => (s == null || s === '' ? 'null' : `'${String(s).replace(/'/g, "''")}'`);

/** Junta faixas vizinhas com a mesma chave (e a mesma família de IP) e manda em lotes para a tabela de carga. */
async function carregar(fonte, tabela, colunas, chaveDe, valoresDe) {
  await consulta(`truncate iara.${tabela}`);
  let lote = [];
  let atual = null;
  let total = 0;
  const enviar = async () => {
    if (!lote.length) return;
    await consulta(`insert into iara.${tabela} (${colunas}) values ${lote.join(',')}`);
    total += lote.length;
    lote = [];
    process.stdout.write(`\r${tabela}: ${total.toLocaleString('pt-BR')} faixas`);
  };
  const fechar = async () => {
    if (!atual) return;
    lote.push(`(${q(atual.ini)}::inet,${q(atual.fim)}::inet,${valoresDe(atual.f)})`);
    atual = null;
    if (lote.length >= 8000) await enviar();
  };
  for await (const f of linhas(fonte)) {
    const chave = chaveDe(f);
    if (chave == null) { await fechar(); continue; }
    const k = `${v6(f[0]) ? 6 : 4}|${chave}`;
    if (atual && atual.k === k) { atual.fim = f[1]; continue; }
    await fechar();
    atual = { k, ini: f[0], fim: f[1], f };
  }
  await fechar();
  await enviar();
  process.stdout.write('\n');
  return total;
}

const local = await baixar(ARQ_LOCAL);
const asn = await baixar(ARQ_ASN);

// city lite: ip_ini, ip_fim, continente, país, estado, cidade, lat, lng
const nLocal = await carregar(local, 'geoip_local_carga', 'ip_ini, ip_fim, pais, estado, cidade',
  (f) => (f[3] === 'ZZ' ? null : f[3] === 'BR' ? `BR|${f[4]}|${f[5]}` : f[3]),
  (f) => (f[3] === 'BR' ? `'BR',${q(UF[f[4]] ?? f[4])},${q(f[5])}` : `${q(f[3])},null,null`));
// asn lite: ip_ini, ip_fim, asn, organização
const nAsn = await carregar(asn, 'geoip_provedor_carga', 'ip_ini, ip_fim, asn, provedor',
  (f) => (f[2] ? `${f[2]}|${f[3]}` : null),
  (f) => `${Number(f[2]) || 'null'},${q(f[3])}`);

const r = await consulta(`select iara.geoip_trocar('DB-IP Lite (CC BY 4.0)', '${mes}') as r`);
console.log(`Base trocada: ${nLocal.toLocaleString('pt-BR')} faixas de local e ${nAsn.toLocaleString('pt-BR')} de provedor.`, JSON.stringify(r[0]?.r ?? r));
