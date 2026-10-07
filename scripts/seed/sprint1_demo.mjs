#!/usr/bin/env node
// Recria os dados FICTÍCIOS do Sprint 1 (pessoal, calendário, frequência, cardápio e nutrição, manutenção, mural)
// em etapas — a frequência e as refeições vão mês a mês para caber no tempo máximo de cada chamada.
// Só roda com o modo demonstração ligado. Os lançamentos feitos ao vivo (is_demo = false) não são tocados.
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/seed/sprint1_demo.mjs [--so=frequencia,nutricao,...]
// Para tirar a demonstração destes módulos: select iara.demo_limpar_sprint1();   (o token nunca é gravado em disco)
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
  console.log(`✓ ${sql.slice(0, 90).padEnd(90)} ${String(Date.now() - t0).padStart(6)} ms  ${JSON.stringify(linhas[0] ?? {}).slice(0, 140)}`);
  return linhas;
}

const [{ demo }] = await q(`select iara.demo_mode() as demo`);
if (!demo) {
  console.error('Modo demonstração desligado: nada a fazer.');
  process.exit(1);
}
const meses = (await q(`select to_char(m, 'YYYY-MM-DD') de, to_char(least((m + interval '1 month - 1 day')::date, current_date - 1), 'YYYY-MM-DD') ate
  from generate_series(date_trunc('month', (iara.setting('ano_letivo_inicio'))::date), date_trunc('month', current_date - 1), interval '1 month') m`));

if (quer('pessoal')) await q(`select iara.demo_gerar_pessoal() r`);
if (quer('calendario')) await q(`select iara.demo_gerar_calendario() r`);
if (quer('frequencia')) {
  for (const m of meses) await q(`select iara.demo_gerar_frequencia_periodo('${m.de}', '${m.ate}') r`);
  await q(`select iara.demo_frequencia_sequencias() r`);
  await q(`select iara.demo_gerar_alertas_frequencia() r`);
}
if (quer('nutricao')) {
  await q(`select iara.demo_gerar_nutricao() r`);
  for (const m of meses) await q(`select iara.demo_gerar_refeicoes_periodo('${m.de}', '${m.ate}') r`);
}
if (quer('manutencao')) await q(`select iara.demo_gerar_manutencao() r`);
if (quer('mural')) await q(`select iara.demo_gerar_mural() r`);
await q(`select iara.demo_reforcar_cenario() r`);
await q(`update iara.tenants set settings = settings || jsonb_build_object('demo_rotina_dia', current_date::text) where id = 1 returning settings ->> 'demo_rotina_dia' as rotina`);
console.log('Pronto. A rotina diária (housekeeping do gateway) completa os próximos dias letivos sozinha.');
