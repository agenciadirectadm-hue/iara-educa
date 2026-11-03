-- IARA Educa — 084 · Simulador de preços para o perfil Comercial (demonstração)
-- Consulta detalhada do preço de implantação e mensal de cada agente, por município, mais os custos adicionais cobrados
-- diretamente pela Meta, pela Anthropic e pela Groq (não somam ao preço). Só o perfil Comercial (permissão precos.simular) vê;
-- os perfis da prefeitura não veem preços. Esta migration traz só a estrutura: os preços e as prefeituras ficam em
-- supabase/privado/simulador_dados.sql, gerado da calculadora por scripts/simulador/extrai_sim.py e fora do repositório
-- público (.gitignore). Só os preços finais vão ao banco: o divisor e os valores de referência ficam na planilha.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive)
values ('precos.simular', 'Consultar a tabela de preços e simular a proposta de cada prefeitura (perfil Comercial)', true)
on conflict (code) do update set description = excluded.description;

insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('COMERCIAL', 1, 'Comercial IARA Educa', 'Comercial', 'Equipe comercial da IARA Educa: simula o preço da solução para cada prefeitura. Não vê dados de pessoas.',
   'AGGREGATE', null, 'Quanto custa para esta prefeitura?', 'IARA Educa', true, 99)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona, sort = excluded.sort;

insert into iara.role_permissions (role_code, permission_code) values ('COMERCIAL', 'precos.simular')
on conflict do nothing;

create table if not exists iara.sim_agentes (
  num smallint primary key,
  nome text not null unique,
  assuntos text not null,
  tipo smallint not null check (tipo between 1 and 3),
  criticidade text not null,
  dimensao text not null,
  situacao text not null,
  cobranca text not null check (cobranca in ('agente', 'vaga', 'profissional', 'fila', 'disparador')),
  disparador boolean not null default false,
  implantacao numeric not null default 0,  -- preço final por unidade de cobrança (R$), com a precisão da planilha
  mensal numeric not null default 0
);
create table if not exists iara.sim_municipios (
  id smallint primary key,
  nome text not null,
  uf text,
  unidades integer, ocupadas integer, creche integer, fila_informada integer, docentes integer, outros integer,
  filas_centrais integer not null default 3, filas_setor integer not null default 5, conveniadas integer,
  redutor numeric(6, 4) not null default 0,
  observacao text
);
create table if not exists iara.sim_parametros (
  chave text primary key,
  valor numeric not null
);
alter table iara.sim_agentes alter column implantacao type numeric, alter column mensal type numeric;
alter table iara.sim_agentes enable row level security;
alter table iara.sim_municipios enable row level security;
alter table iara.sim_parametros enable row level security;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('sim_agentes', 'implantacao', 'INTERNO', 'comercial', 'tabela de preços da solução', 'só o perfil Comercial'),
  ('sim_municipios', 'redutor', 'INTERNO', 'comercial', 'desconto proposto a cada prefeitura', 'só o perfil Comercial')
on conflict (tabela, coluna) do nothing;

-- tudo o que a tela precisa: a conta é feita na tela, para marcar e desmarcar agentes na hora
create or replace function api.simulador_precos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('precos.simular');
  return jsonb_build_object(
    'agentes', (select coalesce(jsonb_agg(to_jsonb(a) order by a.num), '[]') from iara.sim_agentes a),
    'municipios', (select coalesce(jsonb_agg(to_jsonb(m) order by m.id), '[]') from iara.sim_municipios m),
    'parametros', (select coalesce(jsonb_object_agg(chave, valor), '{}') from iara.sim_parametros),
    'fonte', 'Calculadora IARA Educa (preços finais). Volumes: Censo Escolar 2025 (INEP), rede municipal. Custos adicionais: tarifas da Meta, da Anthropic e da Groq.');
end $$;

commit;
