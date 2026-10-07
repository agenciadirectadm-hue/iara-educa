#!/usr/bin/env node
// Recria os dados FICTÍCIOS do Sprint 5: conteúdos ministrados dos últimos dias letivos (diário de classe), rematrícula do ano
// seguinte e transferências entre unidades, salas de cada unidade (ensalamento) e eventos com participantes e certificados.
// Só roda com o modo demonstração ligado; o que foi lançado ao vivo não é tocado.
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/seed/sprint5_demo.mjs [--so=aulas,rematricula,salas,eventos]
// Para desfazer o que foi feito ao vivo: select iara.demo_purge_sprint5('<início>');   (o token nunca é gravado em disco)
const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
if (!token) {
  console.error('Defina SUPABASE_ACCESS_TOKEN (token pessoal do Supabase).');
  process.exit(1);
}
const so = (process.argv.find((a) => a.startsWith('--so=')) ?? '').slice(5).split(',').filter(Boolean);
const quer = (m) => !so.length || so.includes(m);

async function q(sql) {
  const t0 = Date.now();
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${sql.slice(0, 80)} → ${res.status}: ${text.slice(0, 400)}`);
  const linhas = JSON.parse(text);
  console.log(`✓ ${sql.slice(0, 90).padEnd(90)} ${String(Date.now() - t0).padStart(6)} ms  ${JSON.stringify(linhas[0] ?? {}).slice(0, 160)}`);
  return linhas;
}

const [{ demo }] = await q(`select iara.demo_mode() as demo`);
if (!demo) {
  console.error('Modo demonstração desligado: nada a fazer.');
  process.exit(1);
}
if (quer('aulas')) await q(`select iara.demo_gerar_aulas() r`);
if (quer('rematricula')) await q(`select iara.demo_gerar_rematricula() r`);
if (quer('salas')) await q(`select iara.demo_gerar_salas() r`);
if (quer('eventos')) await q(`select iara.demo_gerar_eventos() r`);
console.log('Pronto.');
