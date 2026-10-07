#!/usr/bin/env node
// Recria os dados FICTÍCIOS do Sprint 2 (notas dos bimestres encerrados, pareceres da educação infantil, sondagens de
// alfabetização, planos de intervenção, planos e atendimentos do AEE e as declarações da família da Maria), em etapas.
// Depende do Sprint 1 (frequência e pessoal): rode scripts/seed/sprint1_demo.mjs antes, se for recriar tudo.
// Só roda com o modo demonstração ligado. Os lançamentos feitos ao vivo (is_demo = false) não são tocados.
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/seed/sprint2_demo.mjs [--so=notas,pareceres,alfabetizacao,planos,aee,declaracoes]
// Para tirar a demonstração destes módulos: select iara.demo_limpar_sprint2();   (o token nunca é gravado em disco)
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
// notas: um bimestre encerrado por chamada (≈180 mil linhas cada)
if (quer('notas')) {
  const bims = await q(`select numero from iara.bimestres where ano = 2026 and fim < current_date order by numero`);
  for (const { numero } of bims) await q(`select iara.demo_gerar_notas_bimestre(${Number(numero)}::smallint) n`);
}
if (quer('pareceres')) await q(`select iara.demo_gerar_pareceres() n`);
if (quer('alfabetizacao')) await q(`select iara.demo_gerar_alfabetizacao() n`);
// os planos de intervenção dependem das notas, da frequência e das sondagens (risco calculado)
if (quer('planos')) await q(`select iara.demo_gerar_planos() r`);
if (quer('aee')) await q(`select iara.demo_gerar_aee() r`);
if (quer('declaracoes')) await q(`select iara.demo_gerar_declaracoes() n`);
console.log('Pronto.');
