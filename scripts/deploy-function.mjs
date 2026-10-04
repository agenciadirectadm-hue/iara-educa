#!/usr/bin/env node
// Publica uma Edge Function via Management API (sem Docker/CLI).
// Uso: SUPABASE_ACCESS_TOKEN=... node scripts/deploy-function.mjs api [--verify-jwt]
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || 'fqpjbyhewzngutbyydig';
const slug = process.argv[2] || 'api';
const verifyJwt = process.argv.includes('--verify-jwt');
if (!token) {
  console.error('Defina SUPABASE_ACCESS_TOKEN.');
  process.exit(1);
}

const dir = join(process.cwd(), 'supabase', 'functions', slug);
const files = [];
(function walk(d) {
  for (const name of readdirSync(d)) {
    const full = join(d, name);
    if (statSync(full).isDirectory()) walk(full);
    else if (/\.(ts|js|json|mjs)$/.test(name)) files.push(full);
  }
})(dir);

const form = new FormData();
form.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: slug, verify_jwt: verifyJwt }));
for (const f of files) {
  const rel = relative(dir, f).replace(/\\/g, '/');
  form.append('file', new Blob([readFileSync(f)], { type: 'application/typescript' }), rel);
}

const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/functions/deploy?slug=${encodeURIComponent(slug)}`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}` },
  body: form,
});
const text = await res.text();
if (!res.ok) {
  console.error(`✗ deploy ${slug}: ${res.status}\n${text.slice(0, 3000)}`);
  process.exitCode = 2;
} else {
  const j = JSON.parse(text);
  console.log(`✓ ${slug} publicada — versão ${j.version}, status ${j.status}, verify_jwt=${j.verify_jwt}`);
  console.log(`  URL: https://${ref}.supabase.co/functions/v1/${slug}`);
}
