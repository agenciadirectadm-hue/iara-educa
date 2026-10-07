#!/usr/bin/env node
// Recria os dados FICTÍCIOS do Sprint 3: transporte escolar (rotas a partir dos endereços dos alunos que precisam de transporte,
// pontos, horários, frota, motoristas e as viagens do ano) e almoxarifado (catálogo, fornecedores fictícios, estoque central,
// alimentos nas unidades com lote e validade, pedidos de agosto até hoje). Depende do Sprint 1 (refeições servidas e frequência).
// Só roda com o modo demonstração ligado. Os lançamentos feitos ao vivo (is_demo = false) não são tocados.
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/seed/sprint3_demo.mjs [--so=transporte,almoxarifado]
// Para tirar a demonstração destes módulos: select iara.demo_limpar_sprint3();   (o token nunca é gravado em disco)
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
if (quer('transporte')) await q(`select iara.demo_gerar_transporte() r`);
if (quer('almoxarifado')) {
  await q(`select iara.demo_gerar_almoxarifado() r`);
  await q(`update iara.tenants set settings = settings || jsonb_build_object('demo_almox_base', iara.hoje_local()) where id = 1 returning 1 ok`);
}
console.log('Pronto.');
