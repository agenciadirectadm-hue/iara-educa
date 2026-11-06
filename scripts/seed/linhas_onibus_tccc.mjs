#!/usr/bin/env node
// Atualiza as linhas de ônibus da TCCC a partir do que ela publica no Na Hora Maringá (relatório público da Bus2/Mobilibus):
// linhas, variantes de trajeto, paradas com coordenada e partidas de dia útil. Substitui tudo de uma vez, numa só transação.
// Rode de novo quando a TCCC mudar linhas ou horários (cerca de 5 min: uma consulta a cada 0,8 s, para não pesar na fonte).
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/seed/linhas_onibus_tccc.mjs [--sem-gravar]
// Outro projeto (produção): SUPABASE_PROJECT_REF=...   (o token nunca é gravado em disco)
const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
const API = 'https://mobilibus.com/api';
const PROJETO = '43wpt';
const UA = 'IARA-Educa/1.0 (+https://agenciadirectadm-hue.github.io/iara-educa/)';
const semGravar = process.argv.includes('--sem-gravar');
if (!token && !semGravar) {
  console.error('Defina SUPABASE_ACCESS_TOKEN (token pessoal do Supabase).');
  process.exit(1);
}
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

async function consulta(caminho) {
  let erro;
  for (let tentativa = 1; tentativa <= 4; tentativa++) {
    await espera(800);
    try {
      const res = await fetch(`${API}/${caminho}`, { headers: { 'User-Agent': UA, Accept: 'application/json' }, signal: AbortSignal.timeout(40_000) });
      if (res.ok) return await res.json();
      erro = `HTTP ${res.status}`;
    } catch (e) {
      erro = e.message;
    }
    console.error(`  ${caminho}: ${erro} (tentativa ${tentativa})`);
    await espera(5000 * tentativa);
  }
  throw new Error(`Fonte indisponível em ${caminho}: ${erro}. Nada foi alterado no banco.`);
}

const hoje = new Date(Date.now() - 3 * 3600_000).toISOString().slice(0, 10); // horário de Maringá
const consultadoEm = new Date().toISOString();
const linhas = [];
const viagens = [];
const paradas = new Map();
const viagemParadas = [];

for (const r of await consulta(`routes?project_hash=${PROJETO}`)) {
  const { timetable } = await consulta(`timetable?v=2&route_hash=${r.routeId}`);
  // partidas de dia útil, em quadros válidos hoje, por sentido + variante do trajeto
  const partidas = new Map();
  for (const d of timetable.directions) {
    for (const s of d.services) {
      if (!s.days.slice(1, 6).some(Boolean) || s.start > hoje || s.end < hoje) continue;
      for (const p of s.departures) {
        const k = `${d.directionId}/${p.seq}`;
        partidas.set(k, (partidas.get(k) ?? 0) + 1);
      }
    }
  }
  linhas.push({ id: r.routeId, codigo: r.shortName, nome: r.longName, cor: r.color });
  for (const v of timetable.trips) {
    const det = await consulta(`trip-details?v=2&trip_hash=${v.tripId}`);
    if (!det.stops?.length) throw new Error(`Viagem ${v.tripId} da linha ${r.shortName} sem paradas. Nada foi alterado no banco.`);
    viagens.push({ id: v.tripId, linha_id: r.routeId, sentido: v.directionId, descricao: (v.tripDesc ?? '').replace(/\s+/g, ' ').trim(), partidas_dia_util: partidas.get(`${v.directionId}/${v.seq}`) ?? 0 });
    det.stops.forEach((s, i) => {
      paradas.set(s.stopId, { id: s.stopId, nome: s.name, lat: s.lat, lng: s.lng });
      viagemParadas.push({ viagem_id: v.tripId, ordem: i + 1, parada_id: s.stopId });
    });
  }
  console.log(`${r.shortName} ${r.longName}`);
}

console.log(`${linhas.length} linhas, ${viagens.length} viagens, ${paradas.size} paradas.`);
// Trava contra fonte fora do ar ou em outro formato: um retorno pela metade não pode apagar o que já existe.
if (linhas.length < 50 || viagens.length < 150 || paradas.size < 1500) {
  throw new Error('Retorno muito menor que o esperado. Nada foi alterado no banco.');
}
const foraDaCidade = [...paradas.values()].filter((p) => p.lat < -23.7 || p.lat > -23.1 || p.lng < -52.3 || p.lng > -51.6);
if (foraDaCidade.length) throw new Error(`${foraDaCidade.length} paradas fora da região de Maringá. Nada foi alterado no banco.`);

if (semGravar) {
  console.log('--sem-gravar: nada foi alterado no banco.');
  process.exit(0);
}

const json = (x) => `$dados$${JSON.stringify(x)}$dados$::jsonb`;
const sql = `begin;
delete from iara.onibus_viagem_paradas;
delete from iara.onibus_viagens;
delete from iara.onibus_paradas;
delete from iara.onibus_linhas;
insert into iara.onibus_linhas (id, codigo, nome, cor, atualizado_em)
  select id, codigo, nome, cor, '${consultadoEm}'::timestamptz from jsonb_to_recordset(${json(linhas)}) as x(id text, codigo text, nome text, cor text);
insert into iara.onibus_viagens (id, linha_id, sentido, descricao, partidas_dia_util)
  select * from jsonb_to_recordset(${json(viagens)}) as x(id text, linha_id text, sentido int, descricao text, partidas_dia_util int);
insert into iara.onibus_paradas (id, nome, lat, lng, location)
  select id, nome, lat, lng, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography
  from jsonb_to_recordset(${json([...paradas.values()])}) as x(id text, nome text, lat double precision, lng double precision);
insert into iara.onibus_viagem_paradas (viagem_id, ordem, parada_id)
  select * from jsonb_to_recordset(${json(viagemParadas)}) as x(viagem_id text, ordem int, parada_id text);
commit;
select (select count(*) from iara.onibus_linhas) linhas, (select count(*) from iara.onibus_viagens) viagens,
       (select count(*) from iara.onibus_paradas) paradas, (select count(*) from iara.onibus_viagem_paradas) passagens;`;

const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql }),
});
const texto = await res.text();
if (!res.ok) throw new Error(`Falha ao gravar (${res.status}): ${texto.slice(0, 500)}`);
console.log('Gravado:', texto);
