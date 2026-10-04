#!/usr/bin/env node
// Executa arquivos .sql no projeto Supabase via Management API.
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/sql.mjs arquivo1.sql [arquivo2.sql ...]
//      SUPABASE_ACCESS_TOKEN=... node scripts/sql.mjs -e "select 1"
// O token nunca é gravado em disco; o ref padrão é o projeto iara-educa.
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
if (!token) {
  console.error('Defina SUPABASE_ACCESS_TOKEN (token pessoal do Supabase).');
  process.exit(1);
}

const args = process.argv.slice(2);
const jobs = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '-e') jobs.push({ name: 'inline', query: args[++i] });
  else jobs.push({ name: basename(args[i]), query: readFileSync(args[i], 'utf8') });
}

for (const job of jobs) {
  const started = Date.now();
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: job.query }),
  });
  const text = await res.text();
  const ms = Date.now() - started;
  if (!res.ok) {
    // testes revertidos devolvem o resultado no erro (RESULTADO: ...): SQL_OUT_LIMIT amplia a saída
    console.error(`✗ ${job.name} (${res.status}, ${ms} ms)\n${text.slice(0, Number(process.env.SQL_OUT_LIMIT || 4000))}`);
    process.exitCode = 2;
    break;
  }
  let out = text;
  try {
    const parsed = JSON.parse(text);
    out = JSON.stringify(parsed, null, 1);
  } catch {
    /* resposta não-JSON */
  }
  const limit = Number(process.env.SQL_OUT_LIMIT || 6000);
  console.log(`✓ ${job.name} (${ms} ms)${out && out !== '[]' ? '\n' + out.slice(0, limit) : ''}`);
}
