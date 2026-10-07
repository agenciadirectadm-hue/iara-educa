#!/usr/bin/env node
// Traça cada rota do transporte pelas ruas no motor de rotas (OSRM sobre o OpenStreetMap) e grava o trajeto por trecho:
// do ponto k ao ponto k+1 e do último ponto até a escola. Com ele, os quilômetros e os horários dos pontos passam a vir do
// caminho real. Só coordenadas saem para o motor (nunca nome ou endereço). Servidor público: uma consulta por segundo.
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/seed/trajetos_transporte.mjs [--todas] [--rota=R-234]
// Motor próprio (produção): ROTAS_OSRM_CARRO=https://... (mesma API).   (o token nunca é gravado em disco)
const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
const OSRM = (process.env.ROTAS_OSRM_CARRO ?? 'https://routing.openstreetmap.de/routed-car').replace(/\/$/, '');
const UA = 'IARA-Educa/1.0 (+https://agenciadirectadm-hue.github.io/iara-educa/)';
if (!token) {
  console.error('Defina SUPABASE_ACCESS_TOKEN (token pessoal do Supabase).');
  process.exit(1);
}
const todas = process.argv.includes('--todas');
const so = (process.argv.find((a) => a.startsWith('--rota=')) ?? '').slice(7);

async function q(sql) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${sql.slice(0, 80)} → ${res.status}: ${text.slice(0, 400)}`);
  return JSON.parse(text);
}
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

/** Douglas-Peucker em graus (≈ 6 m), para guardar só os vértices que mudam o desenho. */
function simplificar(pts, eps = 0.00006) {
  if (pts.length < 3) return pts;
  const [a, b] = [pts[0], pts[pts.length - 1]];
  let iMax = 0;
  let dMax = 0;
  for (let i = 1; i < pts.length - 1; i++) {
    const [x, y] = pts[i];
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const t = dx || dy ? Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy))) : 0;
    const d = Math.hypot(x - (a[0] + t * dx), y - (a[1] + t * dy));
    if (d > dMax) { dMax = d; iMax = i; }
  }
  if (dMax <= eps) return [a, b];
  return [...simplificar(pts.slice(0, iMax + 1), eps).slice(0, -1), ...simplificar(pts.slice(iMax), eps)];
}
const r5 = (c) => [Math.round(c[0] * 1e5) / 1e5, Math.round(c[1] * 1e5) / 1e5];

const rotas = await q(`select r.id, r.codigo, json_agg(json_build_array(p.lng, p.lat) order by p.ordem) pts, json_agg(p.id order by p.ordem) ids, u.lng ulng, u.lat ulat
  from iara.transporte_rotas r join iara.transporte_pontos p on p.rota_id = r.id join iara.education_units u on u.id = r.unit_id
  where r.situacao = 'ATIVA' ${todas || so ? '' : 'and r.trajeto is null'} ${so ? `and r.codigo = '${so.replace(/[^A-Z0-9-]/g, '')}'` : ''}
  group by r.id, r.codigo, u.lng, u.lat order by r.codigo`);
console.log(`${rotas.length} rota(s) a traçar pelo ${OSRM}`);

let lote = [];
let ok = 0;
let falhas = 0;
const gravar = async () => {
  if (!lote.length) return;
  const json = JSON.stringify(lote);
  const r = await q(`select x.id, iara.rota_aplicar_trajeto(x.id::uuid, x.trechos, 'OSRM · OpenStreetMap (ordem otimizada)', x.ordem) r
                     from jsonb_to_recordset($j$${json}$j$::jsonb) x(id text, trechos jsonb, ordem uuid[])`);
  for (const l of r) console.log(`  ✓ ${l.r.rota}: ${String(l.r.km).replace('.', ',')} km, ${l.r.minutos} min até a escola`);
  lote = [];
};
for (const rota of rotas) {
  // serviço trip: o motor escolhe a melhor ordem dos pontos, terminando na escola (último ponto da lista)
  const coords = [...rota.pts, [rota.ulng, rota.ulat]];
  const url = `${OSRM}/trip/v1/driving/${coords.map((c) => `${c[0].toFixed(5)},${c[1].toFixed(5)}`).join(';')}?roundtrip=false&source=any&destination=last&steps=true&geometries=geojson&overview=false`;
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(25_000) });
    const j = await res.json();
    if (j.code !== 'Ok') throw new Error(j.code ?? res.status);
    // waypoints[i].waypoint_index = posição do ponto i no percurso otimizado
    const ordem = rota.ids.map((id, i) => ({ id, pos: j.waypoints[i].waypoint_index })).sort((a, b) => a.pos - b.pos).map((x) => x.id);
    const trechos = j.trips[0].legs.map((leg) => {
      const linha = leg.steps.flatMap((s, i) => (i === 0 ? s.geometry.coordinates : s.geometry.coordinates.slice(1)));
      return { c: simplificar(linha).map(r5), m: Math.round(leg.distance), s: Math.round(leg.duration) };
    });
    lote.push({ id: rota.id, trechos, ordem });
    ok++;
  } catch (e) {
    falhas++;
    console.log(`  ✗ ${rota.codigo}: ${e.message} (fica em linha reta)`);
  }
  if (lote.length >= 8) await gravar();
  await espera(1100);
}
await gravar();
console.log(`Pronto: ${ok} rota(s) traçada(s) pelas ruas, ${falhas} falha(s).`);
