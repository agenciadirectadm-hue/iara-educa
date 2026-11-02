#!/usr/bin/env node
// Gera supabase/seed/11_areas_ponderacao.sql: as 29 áreas de ponderação de Maringá (recorte territorial do IARA), os 793
// setores censitários com os agregados do Censo Demográfico 2022 (camada de demanda) e o limite oficial dos distritos de
// Iguatemi e Floriano (união dos setores de cada distrito). Fonte: GeoJSON do levantamento de setores e áreas de ponderação
// (malha IBGE 2022 simplificada, WGS84, 5 casas) — pasta iara-geo do projeto setores-censitarios-dados.
// Uso: node scripts/seed/gerar_areas_ponderacao.mjs [pasta-iara-geo]   (padrão: ../setores-censitarios-dados/iara-geo)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const pasta = resolve(process.argv[2] ?? join(raiz, '../setores-censitarios-dados/iara-geo'));
const saida = join(raiz, 'supabase/seed/11_areas_ponderacao.sql');

const aponds = JSON.parse(readFileSync(join(pasta, 'maringa-aponds.geojson'), 'utf8')).features;
const setores = JSON.parse(readFileSync(join(pasta, 'maringa-setores.geojson'), 'utf8')).features;

// O IBGE só numera as áreas. O nome soma os bairros com mais endereços na área (CNEFE 2022), revisado à mão.
const NOMES = {
  '4115200001': 'Iguatemi, Floriano e área rural',
  '4115200002': 'Jardim Alvorada',
  '4115200003': 'Cidade Nova / Vila Esperança',
  '4115200004': 'Jardim Liberdade / Jardim América',
  '4115200005': 'Zona 01 / Centro',
  '4115200006': 'Zona 08 / Jardim Aclimação',
  '4115200007': 'Vila Morangueira / Vila Santo Antônio',
  '4115200008': 'Jardim Diamante / Parque das Palmeiras',
  '4115200009': 'Zona 06 / Jardim Olímpico',
  '4115200010': 'Zona 05 / Zona 04',
  '4115200012': 'Parque Tarumã / Cidade Alta',
  '4115200013': 'Vila Bosque / Jardim Novo Horizonte',
  '4115200015': 'Parque das Grevíleas / Parque Avenida',
  '4115200016': 'Jardim Paris / Parque das Laranjeiras',
  '4115200017': 'Zona 20 / Jardim Universo',
  '4115200018': 'Vila Santa Isabel / Jardim São Jorge',
  '4115200020': 'Jardim Oásis / Novo Oásis',
  '4115200021': 'Jardim Universitário / Zona 07',
  '4115200023': 'Zona 02 (sem moradores)',
  '4115200024': 'Zona 02 (sem moradores)',
  '4115200025': 'Zona 01 (sem moradores)',
  '4115200026': 'Área sem moradores',
  '4115200027': 'Zona 03 / Zona 09',
  '4115200029': 'Jardim São Silvestre / Sol Nascente',
  '4115200032': 'Jardim Paulista / Ebenezer',
  '4115200037': 'Conjunto Ney Braga / Jardim Guairacá',
  '4115200038': 'Zona 07',
  '4115200039': 'Conjunto Requião / Conjunto Guaiapó',
  '4115200040': 'Parque Itaipu / Jardim das Estações',
};
const CORES = ['#7A24C5', '#1594D2', '#00A983', '#F28C38', '#D94C7A', '#086DB6', '#8C6A3F', '#4F7D2B'];
const MUNICIPIO = 100;
const FONTE_AP = 'IBGE — Censo Demográfico 2022: área de ponderação (malha e agregados por setor)';
const FONTE_SETOR = 'IBGE — Censo Demográfico 2022: setor censitário (malha e agregados)';
const FONTE_DISTRITO = 'IBGE — Censo Demográfico 2022: limite do distrito (união dos setores censitários)';
const DISTRITOS = [['IGUATEMI', 'Iguatemi'], ['FLORIANO', 'Floriano']];

const q = (s) => (s == null || s === '' ? 'null' : `'${String(s).replace(/'/g, "''")}'`);
const n = (v) => (v == null || Number.isNaN(Number(v)) ? 'null' : String(v));
const geom = (g) => `extensions.st_multi(extensions.st_setsrid(extensions.st_geomfromgeojson(${q(JSON.stringify(g))}), 4326))::extensions.geography`;
const ponto = ([lng, lat]) => `iara.point(${lat}, ${lng})`;
const idAp = (cd) => 200 + Number(cd.slice(-3));

const faltam = aponds.map((f) => f.properties.cd).filter((cd) => !NOMES[cd]);
if (faltam.length) throw new Error(`Área sem nome revisado: ${faltam.join(', ')}`);
const semArea = setores.filter((f) => !aponds.some((a) => a.properties.cd === f.properties.apond));
if (semArea.length) throw new Error(`${semArea.length} setor(es) sem área de ponderação conhecida`);

const L = [];
L.push(
  '-- IARA Educa — áreas de ponderação e setores censitários de Maringá (IBGE, Censo Demográfico 2022)',
  '-- GERADO por scripts/seed/gerar_areas_ponderacao.mjs — não editar à mão. Idempotente.',
  '-- Aplicar depois de supabase/seed/10_dados_publicos.sql e da migration 20261003007500_areas_ponderacao.sql:',
  '-- carrega as áreas, os setores e o limite dos distritos e reorganiza unidades, bairros, endereços e fila por área',
  '-- (iara.aplicar_areas_ponderacao), retirando as macrorregiões de demonstração.',
  'begin;',
  '',
  '-- trava: os ids 201–240 (200 + número da área) não podem estar em uso por outro tipo de território',
  'do $$ begin',
  "  if exists (select 1 from iara.territories where id between 201 and 240 and kind <> 'AREA_PONDERACAO') then",
  "    raise exception 'Ids 201–240 já usados por outro território: áreas de ponderação não carregadas.';",
  '  end if;',
  'end $$;',
  '',
  `-- ${aponds.length} áreas de ponderação: o recorte territorial do IARA`,
  'insert into iara.territories (id, tenant_id, code, name, kind, parent_id, center, geom, color, sort, source, confidence_status) values',
);
const ordenadas = [...aponds].sort((a, b) => a.properties.cd.localeCompare(b.properties.cd));
L.push(ordenadas.map((f, i) => {
  const p = f.properties;
  const num = p.cd.slice(-3);
  return `(${idAp(p.cd)}, 1, ${q(p.cd)}, ${q(`AP ${num} · ${NOMES[p.cd]}`)}, 'AREA_PONDERACAO', ${MUNICIPIO}, ${ponto(p.centro)}, ${geom(f.geometry)}, `
    + `${q(CORES[i % CORES.length])}, ${Number(num)}, ${q(FONTE_AP)}, 'PUBLIC_OFFICIAL')`;
}).join(',\n'));
L.push(
  'on conflict (id) do update set code = excluded.code, name = excluded.name, kind = excluded.kind, parent_id = excluded.parent_id,',
  '  center = excluded.center, geom = excluded.geom, color = excluded.color, sort = excluded.sort, source = excluded.source,',
  '  confidence_status = excluded.confidence_status;',
  '',
  `-- ${setores.length} setores censitários (camada de demanda): agregados do Censo 2022; crianças de 0 a 4 anos nulas = sigilo do IBGE`,
  'insert into iara.setores_censitarios (code, tenant_id, area_ponderacao_id, distrito, situacao, bairro, area_km2, pessoas, domicilios,',
  '                                      criancas_0a4, center, geom, source) values',
);
const setoresOrd = [...setores].sort((a, b) => a.properties.cd.localeCompare(b.properties.cd));
L.push(setoresOrd.map((f) => {
  const p = f.properties;
  return `(${q(p.cd)}, 1, ${idAp(p.apond)}, ${q(p.distrito)}, ${q(p.situacao?.toUpperCase())}, ${q(p.bairro)}, ${n(p.area_km2)}, ${n(p.pessoas)}, `
    + `${n(p.domicilios)}, ${n(p.criancas_0a4)}, ${ponto(p.centro)}, ${geom(f.geometry)}, ${q(FONTE_SETOR)})`;
}).join(',\n'));
L.push(
  'on conflict (code) do update set area_ponderacao_id = excluded.area_ponderacao_id, distrito = excluded.distrito, situacao = excluded.situacao,',
  '  bairro = excluded.bairro, area_km2 = excluded.area_km2, pessoas = excluded.pessoas, domicilios = excluded.domicilios,',
  '  criancas_0a4 = excluded.criancas_0a4, center = excluded.center, geom = excluded.geom, source = excluded.source;',
  `delete from iara.setores_censitarios where code <> all (array[${setoresOrd.map((f) => q(f.properties.cd)).join(', ')}]);`,
  '',
  '-- distritos: limite oficial (união dos setores do distrito), dentro da área de ponderação que os contém',
);
for (const [code, distrito] of DISTRITOS) {
  const ap = setores.find((f) => f.properties.distrito === distrito)?.properties.apond;
  if (!ap) throw new Error(`Distrito sem setores: ${distrito}`);
  L.push(
    `update iara.territories set parent_id = ${idAp(ap)}, source = ${q(FONTE_DISTRITO)}, confidence_status = 'PUBLIC_OFFICIAL',`,
    '  geom = (select extensions.st_multi(extensions.st_collectionextract(extensions.st_union(extensions.st_buffer(s.geom::extensions.geometry, 0)), 3))::extensions.geography',
    `          from iara.setores_censitarios s where s.distrito = ${q(distrito)})`,
    `where tenant_id = 1 and code = ${q(code)} and kind = 'DISTRITO';`,
  );
}
L.push('', 'select iara.aplicar_areas_ponderacao();', '', 'commit;', '');
writeFileSync(saida, L.join('\n'));

const pessoas = aponds.reduce((a, f) => a + f.properties.pessoas, 0);
console.log(`${aponds.length} áreas · ${setores.length} setores · ${pessoas.toLocaleString('pt-BR')} pessoas → ${saida}`);
