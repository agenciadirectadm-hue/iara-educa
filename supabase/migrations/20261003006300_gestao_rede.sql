-- IARA Educa — 063 · Gestão da rede: organograma, guarda e restrições, suporte técnico, catálogo de serviços, critérios e jornada
-- Pedido de Rob (07/10/2026): itens 23, 24, 25 e 27 das pendências.
--  · Organograma: setores em árvore, importação por texto (CSV) com validação e vinculação de pessoas (com chefia).
--  · Guarda e restrições: guarda, tutela, acolhimento, medida protetiva e proibição de retirada; efeito na retirada e no portal
--    da família. O que é público e o que é privado está PENDENTE de decisão da SEDUC: até lá vale o mais restrito (detalhe só para
--    direção e secretaria; professor vê apenas o alerta).
--  · Suporte técnico: demandas com protocolo e prazo, “fale com o master” e cadastro do AnyDesk das unidades (nunca senha).
--  · Catálogo de serviços: inclusão, alteração e exclusão (prazo, plantão, alçada, equipe e ação da IARA).
--  · Critérios: nova versão com justificativa e vigência; critério novo entra como proposto, sem efeito no cálculo até a implementação.
--  · Jornada e matriz: aulas por dia, duração, intervalo e hora-atividade (Lei 11.738/2008) por série e turno, adotados pelas turmas
--    e pelas disciplinas da matriz; a turma pode ter jornada própria.
-- Toda alteração fica no histórico (gestao_hist); a limpeza da demonstração desfaz o que foi mexido ao vivo.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('gestao.organograma', 'Cadastrar, importar e vincular o organograma', false),
  ('gestao.servicos', 'Incluir, alterar e excluir serviços do catálogo', false),
  ('gestao.jornada', 'Definir jornada, hora-atividade e matriz curricular padrão', false),
  ('guarda.read', 'Consultar guarda e restrições judiciais dos alunos', true),
  ('guarda.write', 'Registrar e encerrar guarda e restrições judiciais', true),
  ('suporte.atender', 'Atender as demandas de suporte técnico', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('SECRETARIO', 'gestao.organograma'), ('SUPERINTENDENCIA', 'gestao.organograma'), ('INOVACAO', 'gestao.organograma'),
  ('SECRETARIO', 'gestao.servicos'), ('SUPERINTENDENCIA', 'gestao.servicos'), ('INOVACAO', 'gestao.servicos'),
  ('SUPERINTENDENCIA', 'rules.manage'),
  ('SECRETARIO', 'gestao.jornada'), ('SUPERINTENDENCIA', 'gestao.jornada'), ('GERENCIA_EI', 'gestao.jornada'),
  ('DIRETOR_UNIDADE', 'guarda.read'), ('DIRETOR_UNIDADE', 'guarda.write'), ('SECRETARIA_ESCOLAR', 'guarda.read'), ('SECRETARIA_ESCOLAR', 'guarda.write'),
  ('SECRETARIO', 'guarda.read'), ('SUPERINTENDENCIA', 'guarda.read'),
  ('INOVACAO', 'suporte.atender'), ('SUPERINTENDENCIA', 'suporte.atender')
) v(r, p)
on conflict do nothing;

create or replace function iara.e_servidor() returns boolean
language sql stable security definer set search_path = iara, public
as $$ select iara.my_guardian() is null and coalesce(iara.my_role(), 'CIDADAO') not in ('CIDADAO', 'CIDADAO_NOVO', 'CONTROLE_EXTERNO') $$;

-- 0. Histórico das alterações (também desfaz o que foi feito ao vivo na demonstração) ---------------------------------------------
create table if not exists iara.gestao_hist (
  id bigserial primary key,
  tabela text not null,
  chave jsonb not null,
  acao text not null check (acao in ('INSERT', 'UPDATE', 'DELETE')),
  antes jsonb,
  depois jsonb,
  por_label text,
  em timestamptz not null default now()
);
create index if not exists gestao_hist_idx on iara.gestao_hist (tabela, em desc);
alter table iara.gestao_hist enable row level security;

create or replace function iara.gestao_hist_trg() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
  v_chave jsonb := '{}'::jsonb;
  k text;
begin
  if coalesce(current_setting('iara.gestao_restaurando', true), '') = 'on' then return null; end if;
  foreach k in array tg_argv loop v_chave := v_chave || jsonb_build_object(k, v_row -> k); end loop;
  insert into iara.gestao_hist (tabela, chave, acao, antes, depois, por_label)
  values (tg_table_name, v_chave, tg_op, case when tg_op <> 'INSERT' then to_jsonb(old) end, case when tg_op <> 'DELETE' then to_jsonb(new) end, iara.my_label());
  return null;
end $$;

-- desfaz a alteração: volta ao “antes” (ou apaga o que foi incluído)
create or replace function iara.gestao_restaurar(p_tabela text, p_chave jsonb, p_antes jsonb) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cols text;
  v_exc text;
  v_conf text;
begin
  perform set_config('iara.gestao_restaurando', 'on', true);
  if p_antes is null then
    execute format('delete from iara.%I t where to_jsonb(t) @> $1', p_tabela) using p_chave;
  else
    select string_agg(format('%I', column_name), ', ' order by ordinal_position), string_agg(format('excluded.%I', column_name), ', ' order by ordinal_position)
    into v_cols, v_exc from information_schema.columns where table_schema = 'iara' and table_name = p_tabela and is_generated = 'NEVER';
    select string_agg(format('%I', k), ', ') into v_conf from jsonb_object_keys(p_chave) k;
    execute format('insert into iara.%1$I (%2$s) select %2$s from jsonb_populate_record(null::iara.%1$I, $1) on conflict (%3$s) do update set (%2$s) = row(%4$s)',
                   p_tabela, v_cols, v_conf, v_exc) using p_antes;
  end if;
  perform set_config('iara.gestao_restaurando', 'off', true);
end $$;

-- 1. Organograma --------------------------------------------------------------------------------------------------------------------
create table if not exists iara.org_setores (
  id uuid primary key default gen_random_uuid(),
  sigla text not null unique,
  nome text not null,
  tipo text not null check (tipo in ('SECRETARIA', 'GABINETE', 'SUPERINTENDENCIA', 'DIRETORIA', 'GERENCIA', 'DIVISAO', 'COORDENACAO', 'NUCLEO', 'ASSESSORIA', 'CONSELHO')),
  superior_id uuid references iara.org_setores(id) on delete restrict,
  competencias text,
  email text,
  telefone text,
  ordem smallint not null default 0,
  ativo boolean not null default true,
  fonte text not null default 'A_VALIDAR' check (fonte in ('OFICIAL', 'A_VALIDAR', 'DEMONSTRACAO')),
  criado_em timestamptz not null default now()
);
create table if not exists iara.org_vinculos (
  id uuid primary key default gen_random_uuid(),
  setor_id uuid not null references iara.org_setores(id) on delete cascade,
  staff_id uuid references iara.staff(id) on delete set null,
  pessoa_nome text not null,
  funcao text not null,
  chefia boolean not null default false,
  inicio date not null default current_date,
  fim date,
  criado_em timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists org_vinculos_setor_idx on iara.org_vinculos (setor_id) where fim is null;
alter table iara.org_setores enable row level security;
alter table iara.org_vinculos enable row level security;

-- estrutura inicial a validar pela SEDUC (montada a partir dos perfis do sistema; não é o organograma oficial)
insert into iara.org_setores (sigla, nome, tipo, ordem, fonte, competencias) values
  ('SEDUC', 'Secretaria Municipal de Educação', 'SECRETARIA', 0, 'A_VALIDAR', 'Política municipal de educação infantil e ensino fundamental.')
on conflict (sigla) do nothing;
insert into iara.org_setores (sigla, nome, tipo, superior_id, ordem, fonte, competencias)
select v.sigla, v.nome, v.tipo, (select id from iara.org_setores where sigla = v.sup), v.ordem, 'A_VALIDAR', v.comp
from (values
  ('GAB', 'Gabinete da Secretaria', 'GABINETE', 'SEDUC', 1, 'Agenda, expediente e comunicação da Secretaria.'),
  ('OUV', 'Ouvidoria da Educação', 'ASSESSORIA', 'SEDUC', 2, 'Reclamações, denúncias e elogios; 2ª instância das ocorrências quando designada.'),
  ('SUP', 'Superintendência', 'SUPERINTENDENCIA', 'SEDUC', 3, 'Coordenação das diretorias e acompanhamento da rede.'),
  ('DIGE', 'Diretoria de Gestão Educacional', 'DIRETORIA', 'SUP', 1, 'Vagas, matrículas, atendimento e vida escolar.'),
  ('CV', 'Central de Vagas', 'DIVISAO', 'DIGE', 1, 'Fila de espera on-line, ofertas e matrículas (IN 023 e 025/2025).'),
  ('CA', 'Central de Atendimento', 'DIVISAO', 'DIGE', 2, 'Atendimento ao cidadão (portal, WhatsApp e balcão).'),
  ('DIEN', 'Diretoria de Ensino', 'DIRETORIA', 'SUP', 2, 'Proposta pedagógica, avaliação e formação.'),
  ('GEI', 'Gerência de Educação Infantil', 'GERENCIA', 'DIEN', 1, 'CMEIs e pré-escola.'),
  ('GEF', 'Gerência de Ensino Fundamental', 'GERENCIA', 'DIEN', 2, 'Anos iniciais e EJA.'),
  ('GEE', 'Gerência de Educação Especial e Inclusão', 'GERENCIA', 'DIEN', 3, 'AEE, salas de recursos e apoio.'),
  ('GINT', 'Gerência de Educação Integral', 'GERENCIA', 'DIEN', 4, 'Tempo integral e contraturno.'),
  ('DINF', 'Diretoria de Infraestrutura', 'DIRETORIA', 'SUP', 3, 'Prédios, manutenção, transporte, merenda e suprimentos.'),
  ('GTE', 'Gerência de Transporte Escolar', 'GERENCIA', 'DINF', 1, 'Rotas, frota e motoristas.'),
  ('GME', 'Gerência da Merenda Escolar', 'GERENCIA', 'DINF', 2, 'Cardápios, nutrição e cozinhas.'),
  ('GSA', 'Gerência de Suprimentos e Almoxarifado', 'GERENCIA', 'DINF', 3, 'Estoque, pedidos e entregas às unidades.'),
  ('DMAN', 'Divisão de Manutenção', 'DIVISAO', 'DINF', 4, 'Chamados de manutenção predial.'),
  ('DINOV', 'Diretoria de Inovação Educacional', 'DIRETORIA', 'SUP', 4, 'Sistemas, dados, IARA e suporte técnico.'),
  ('UNID', 'Unidades escolares (escolas e CMEIs)', 'NUCLEO', 'SUP', 5, 'Direção, secretaria escolar e equipe pedagógica de cada unidade.')
) v(sigla, nome, tipo, sup, ordem, comp)
on conflict (sigla) do nothing;
-- 2ª passada: superiores incluídos no mesmo comando ainda não eram visíveis
select set_config('iara.gestao_restaurando', 'on', true);
update iara.org_setores s set superior_id = (select x.id from iara.org_setores x where x.sigla = v.sup)
from (values ('DIGE', 'SUP'), ('CV', 'DIGE'), ('CA', 'DIGE'), ('DIEN', 'SUP'), ('GEI', 'DIEN'), ('GEF', 'DIEN'), ('GEE', 'DIEN'), ('GINT', 'DIEN'),
             ('DINF', 'SUP'), ('GTE', 'DINF'), ('GME', 'DINF'), ('GSA', 'DINF'), ('DMAN', 'DINF'), ('DINOV', 'SUP'), ('UNID', 'SUP')) v(sigla, sup)
where s.sigla = v.sigla and s.superior_id is null;
select set_config('iara.gestao_restaurando', 'off', true);

create or replace function iara.org_json(s iara.org_setores) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(s) || jsonb_build_object('superior', (select x.sigla from iara.org_setores x where x.id = s.superior_id),
    'pessoas', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'nome', v.pessoa_nome, 'funcao', v.funcao, 'chefia', v.chefia, 'staff_id', v.staff_id,
                  'inicio', v.inicio, 'is_demo', v.is_demo) order by v.chefia desc, v.pessoa_nome), '[]') from iara.org_vinculos v where v.setor_id = s.id and v.fim is null))
$$;

create or replace function api.org_arvore(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  return jsonb_build_object('pode_editar', iara.has_perm('gestao.organograma'),
    'setores', (select coalesce(jsonb_agg(iara.org_json(s) order by s.ordem, s.nome), '[]') from iara.org_setores s
                where s.ativo or coalesce((p ->> 'inativos')::boolean, false)),
    'unidades', (select count(*) from iara.education_units where status = 'ATIVA'));
end $$;

create or replace function api.org_setor_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_sup uuid := nullif(p ->> 'superior_id', '')::uuid;
  v_sigla text := upper(btrim(coalesce(p ->> 'sigla', '')));
  s iara.org_setores;
begin
  perform iara.require_perm('gestao.organograma');
  if v_sigla !~ '^[A-Z0-9][A-Z0-9_-]{1,15}$' then raise exception 'Sigla de 2 a 16 letras ou números.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'nome', ''))) < 3 then raise exception 'Informe o nome do setor.' using errcode = '22023'; end if;
  if v_id is not null and v_sup is not null and (v_sup = v_id or exists (
       with recursive acima as (select id, superior_id from iara.org_setores where id = v_sup
                                union all select o3.id, o3.superior_id from iara.org_setores o3 join acima a on o3.id = a.superior_id)
       select 1 from acima where id = v_id)) then
    raise exception 'O setor não pode ficar abaixo dele mesmo.' using errcode = '22023';
  end if;
  if v_sup is null and exists (select 1 from iara.org_setores where superior_id is null and id is distinct from v_id) then
    raise exception 'Escolha o setor superior (só a Secretaria fica no topo).' using errcode = '22023';
  end if;
  if v_id is null then
    insert into iara.org_setores (sigla, nome, tipo, superior_id, competencias, email, telefone, ordem, fonte)
    values (v_sigla, btrim(p ->> 'nome'), coalesce(p ->> 'tipo', 'DIVISAO'), v_sup, nullif(btrim(coalesce(p ->> 'competencias', '')), ''),
            nullif(btrim(coalesce(p ->> 'email', '')), ''), nullif(btrim(coalesce(p ->> 'telefone', '')), ''), coalesce((p ->> 'ordem')::smallint, 0),
            coalesce(nullif(p ->> 'fonte', ''), 'A_VALIDAR'))
    returning * into s;
  else
    update iara.org_setores set sigla = v_sigla, nome = btrim(p ->> 'nome'), tipo = coalesce(p ->> 'tipo', tipo), superior_id = v_sup,
           competencias = nullif(btrim(coalesce(p ->> 'competencias', '')), ''), email = nullif(btrim(coalesce(p ->> 'email', '')), ''),
           telefone = nullif(btrim(coalesce(p ->> 'telefone', '')), ''), ordem = coalesce((p ->> 'ordem')::smallint, ordem),
           fonte = coalesce(nullif(p ->> 'fonte', ''), fonte), ativo = coalesce((p ->> 'ativo')::boolean, ativo)
    where id = v_id returning * into s;
    if s.id is null then raise exception 'Setor não encontrado.' using errcode = 'P0002'; end if;
  end if;
  perform iara.audit_event('ORGANOGRAMA', 'org_setor', s.sigla, null, format('Setor %s (%s) salvo.', s.sigla, s.nome));
  return iara.org_json(s);
exception when unique_violation then
  raise exception 'Já existe um setor com a sigla %.', v_sigla using errcode = '22023';
end $$;

-- exclusão: só setor sem subordinados e sem pessoas vinculadas; com histórico, vira inativo
create or replace function api.org_setor_excluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  s iara.org_setores;
begin
  perform iara.require_perm('gestao.organograma');
  select * into s from iara.org_setores where id = (p ->> 'id')::uuid;
  if s.id is null then raise exception 'Setor não encontrado.' using errcode = 'P0002'; end if;
  if s.superior_id is null then raise exception 'A Secretaria (topo) não pode ser excluída.' using errcode = '22023'; end if;
  if exists (select 1 from iara.org_setores where superior_id = s.id and ativo) then raise exception 'Mova ou exclua antes os setores subordinados.' using errcode = '22023'; end if;
  if exists (select 1 from iara.org_vinculos where setor_id = s.id and fim is null) then raise exception 'Desvincule antes as pessoas do setor.' using errcode = '22023'; end if;
  if exists (select 1 from iara.org_vinculos where setor_id = s.id) or exists (select 1 from iara.org_setores where superior_id = s.id) then
    update iara.org_setores set ativo = false where id = s.id;
  else
    delete from iara.org_setores where id = s.id;
  end if;
  perform iara.audit_event('ORGANOGRAMA', 'org_setor', s.sigla, null, format('Setor %s excluído.', s.sigla));
  return jsonb_build_object('ok', true);
end $$;

-- importação: uma linha por setor — SIGLA;Nome;Tipo;SIGLA do superior[;e-mail;telefone]. “validar” só confere; “confirmar” grava.
create or replace function api.org_importar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_linhas text[] := regexp_split_to_array(replace(coalesce(p ->> 'texto', ''), E'\r', ''), E'\n');
  v_conf boolean := coalesce((p ->> 'confirmar')::boolean, false);
  l text;
  c text[];
  i integer := 0;
  v_err jsonb := '[]';
  v_ok jsonb := '[]';
  v_siglas text[] := array(select sigla from iara.org_setores);
  v_novas text[] := '{}';
  n_ins integer := 0;
  n_upd integer := 0;
  x record;
begin
  perform iara.require_perm('gestao.organograma');
  if array_length(v_linhas, 1) > 500 then raise exception 'No máximo 500 linhas por importação.' using errcode = '22023'; end if;
  create temp table if not exists tmp_org_imp (n integer, sigla text, nome text, tipo text, sup text, email text, telefone text) on commit drop;
  truncate tmp_org_imp;
  foreach l in array v_linhas loop
    i := i + 1;
    continue when btrim(l) = '' or upper(btrim(l)) like 'SIGLA%';
    c := regexp_split_to_array(l, '\s*[;\t]\s*');
    if array_length(c, 1) < 4 then v_err := v_err || jsonb_build_object('linha', i, 'erro', 'Use: SIGLA;Nome;Tipo;SIGLA do superior'); continue; end if;
    c[1] := upper(btrim(c[1])); c[3] := upper(btrim(c[3])); c[4] := upper(btrim(c[4]));
    if c[1] !~ '^[A-Z0-9][A-Z0-9_-]{1,15}$' then v_err := v_err || jsonb_build_object('linha', i, 'erro', 'Sigla inválida: ' || c[1]); continue; end if;
    if c[3] not in ('SECRETARIA', 'GABINETE', 'SUPERINTENDENCIA', 'DIRETORIA', 'GERENCIA', 'DIVISAO', 'COORDENACAO', 'NUCLEO', 'ASSESSORIA', 'CONSELHO') then
      v_err := v_err || jsonb_build_object('linha', i, 'erro', 'Tipo desconhecido: ' || c[3]); continue;
    end if;
    if c[1] = any (v_novas) then v_err := v_err || jsonb_build_object('linha', i, 'erro', 'Sigla repetida no arquivo: ' || c[1]); continue; end if;
    v_novas := v_novas || c[1];
    insert into tmp_org_imp values (i, c[1], btrim(c[2]), c[3], nullif(c[4], ''), nullif(btrim(coalesce(c[5], '')), ''), nullif(btrim(coalesce(c[6], '')), ''));
  end loop;
  for x in select * from tmp_org_imp loop
    if x.sup is null and x.sigla <> 'SEDUC' then v_err := v_err || jsonb_build_object('linha', x.n, 'erro', 'Informe o superior de ' || x.sigla);
    elsif x.sup is not null and not (x.sup = any (v_siglas) or x.sup = any (v_novas)) then v_err := v_err || jsonb_build_object('linha', x.n, 'erro', 'Superior não encontrado: ' || x.sup);
    elsif x.sup = x.sigla then v_err := v_err || jsonb_build_object('linha', x.n, 'erro', 'O setor não pode ser superior dele mesmo.');
    else v_ok := v_ok || jsonb_build_object('linha', x.n, 'sigla', x.sigla, 'nome', x.nome, 'acao', case when x.sigla = any (v_siglas) then 'alterar' else 'incluir' end);
    end if;
  end loop;
  if v_conf and jsonb_array_length(v_err) = 0 then
    -- inclui sem superior e depois liga os superiores (a ordem das linhas não importa)
    insert into iara.org_setores (sigla, nome, tipo, email, telefone, fonte)
    select sigla, nome, tipo, email, telefone, 'A_VALIDAR' from tmp_org_imp where not (sigla = any (v_siglas));
    get diagnostics n_ins = row_count;
    update iara.org_setores s set nome = t.nome, tipo = t.tipo, email = coalesce(t.email, s.email), telefone = coalesce(t.telefone, s.telefone), ativo = true
    from tmp_org_imp t where t.sigla = s.sigla and t.sigla = any (v_siglas);
    get diagnostics n_upd = row_count;
    update iara.org_setores s set superior_id = (select o2.id from iara.org_setores o2 where o2.sigla = t.sup) from tmp_org_imp t where t.sigla = s.sigla and t.sup is not null;
    if exists (with recursive c(id, sup, caminho, ciclo) as (
                 select id, superior_id, array[id], false from iara.org_setores
                 union all select c.id, s.superior_id, c.caminho || s.id, s.id = any (c.caminho) from c join iara.org_setores s on s.id = c.sup where not c.ciclo)
               select 1 from c where ciclo) then
      raise exception 'A importação criaria um ciclo no organograma (um setor acima dele mesmo).' using errcode = '22023';
    end if;
    perform iara.audit_event('ORGANOGRAMA', 'org_setor', 'importacao', null, format('Importação do organograma: %s incluído(s), %s alterado(s).', n_ins, n_upd));
  end if;
  return jsonb_build_object('validas', v_ok, 'erros', v_err, 'gravado', v_conf and jsonb_array_length(v_err) = 0, 'incluidos', n_ins, 'alterados', n_upd);
end $$;

create or replace function api.org_pessoas_busca(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_q text := iara.norm(btrim(coalesce(p ->> 'q', '')));
begin
  perform iara.require_perm('gestao.organograma');
  if length(v_q) < 3 then return '[]'::jsonb; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.full_name, 'cargo', coalesce(s.cargo, s.role), 'unidade', u.short_name)), '[]')
          from (select * from iara.staff s where iara.norm(s.full_name) like '%' || v_q || '%' order by s.full_name limit 15) s
          left join iara.education_units u on u.id = s.unit_id);
end $$;

create or replace function api.org_vincular(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_setor uuid := (p ->> 'setor_id')::uuid;
  v_staff uuid := nullif(p ->> 'staff_id', '')::uuid;
  v_nome text := coalesce((select full_name from iara.staff where id = v_staff), nullif(btrim(coalesce(p ->> 'nome', '')), ''));
  v_id uuid;
begin
  perform iara.require_perm('gestao.organograma');
  if coalesce((p ->> 'desvincular')::boolean, false) then
    update iara.org_vinculos set fim = current_date where id = (p ->> 'id')::uuid and fim is null returning id into v_id;
    if v_id is null then raise exception 'Vínculo não encontrado.' using errcode = 'P0002'; end if;
    return jsonb_build_object('ok', true);
  end if;
  if not exists (select 1 from iara.org_setores where id = v_setor and ativo) then raise exception 'Setor não encontrado.' using errcode = 'P0002'; end if;
  if v_nome is null or length(v_nome) < 3 then raise exception 'Escolha a pessoa (servidor) ou digite o nome.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'funcao', ''))) < 3 then raise exception 'Informe a função no setor.' using errcode = '22023'; end if;
  if coalesce((p ->> 'chefia')::boolean, false) then update iara.org_vinculos set chefia = false where setor_id = v_setor and fim is null and chefia; end if;
  insert into iara.org_vinculos (setor_id, staff_id, pessoa_nome, funcao, chefia)
  values (v_setor, v_staff, v_nome, btrim(p ->> 'funcao'), coalesce((p ->> 'chefia')::boolean, false)) returning id into v_id;
  perform iara.audit_event('ORGANOGRAMA', 'org_vinculo', v_id::text, null, format('%s vinculado(a) ao setor como %s.', v_nome, btrim(p ->> 'funcao')));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- 2. Guarda e restrições ------------------------------------------------------------------------------------------------------------
create table if not exists iara.guarda_restricoes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer,
  tipo text not null check (tipo in ('GUARDA_UNILATERAL', 'GUARDA_COMPARTILHADA', 'TUTELA', 'ACOLHIMENTO', 'MEDIDA_PROTETIVA', 'PROIBICAO_RETIRADA',
                                     'PROIBICAO_CONTATO', 'VISITA_SUPERVISIONADA', 'AUTORIZACAO_RETIRADA', 'OUTRA')),
  pessoa_nome text,
  guardian_id uuid references iara.guardians(id) on delete set null,
  efeito_retirada text not null default 'SEM_EFEITO' check (efeito_retirada in ('NAO_PODE', 'PODE', 'SEM_EFEITO')),
  bloquear_portal boolean not null default false,
  descricao text not null,
  documento text,
  orgao text,
  vigencia_inicio date not null default current_date,
  vigencia_fim date,
  situacao text not null default 'ATIVA' check (situacao in ('ATIVA', 'ENCERRADA')),
  retirada_anterior boolean,
  registrado_por_label text,
  created_at timestamptz not null default now(),
  encerrado_em timestamptz,
  encerramento_motivo text,
  is_demo boolean not null default false
);
create index if not exists guarda_student_idx on iara.guarda_restricoes (student_id) where situacao = 'ATIVA';
alter table iara.guarda_restricoes enable row level security;

create or replace function iara.guarda_ativa(r iara.guarda_restricoes) returns boolean
language sql stable as $$ select r.situacao = 'ATIVA' and r.vigencia_inicio <= iara.hoje_local() and (r.vigencia_fim is null or r.vigencia_fim >= iara.hoje_local()) $$;

-- o responsável com bloqueio judicial deixa de ver a criança no portal e na IARA
create or replace function iara.my_student_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_scope() = 'GUARDIAN' then
    return query select sg.student_id from iara.student_guardians sg where sg.guardian_id = iara.my_guardian() and sg.end_date is null
      and not exists (select 1 from iara.guarda_restricoes r where r.student_id = sg.student_id and r.guardian_id = sg.guardian_id and r.bloquear_portal
                      and r.situacao = 'ATIVA' and (r.vigencia_fim is null or r.vigencia_fim >= iara.hoje_local()));
  elsif iara.my_scope() = 'UNIT' and iara.has_perm('students.read') then
    return query select iara.unidade_alunos(iara.my_unit());
  end if;
end $$;

create or replace function iara.guarda_json(r iara.guarda_restricoes) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(r) - 'retirada_anterior' || jsonb_build_object('aluno', s.full_name, 'unidade', u.short_name, 'vigente', iara.guarda_ativa(r),
    'responsavel', (select g.full_name from iara.guardians g where g.id = r.guardian_id))
  from iara.students s left join iara.education_units u on u.id = r.unit_id where s.id = r.student_id
$$;

create or replace function api.guarda_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
begin
  perform iara.require_perm('guarda.read');
  return jsonb_build_object('pode_registrar', iara.has_perm('guarda.write'), 'visibilidade', 'RESTRITA',
    'contagem', (select jsonb_build_object('ativas', count(*) filter (where iara.guarda_ativa(r)), 'retirada', count(*) filter (where iara.guarda_ativa(r) and r.efeito_retirada = 'NAO_PODE'),
                  'portal', count(*) filter (where iara.guarda_ativa(r) and r.bloquear_portal), 'vencendo', count(*) filter (where iara.guarda_ativa(r) and r.vigencia_fim <= iara.hoje_local() + 30))
                 from iara.guarda_restricoes r where v_unit is null or r.unit_id = v_unit),
    'itens', (select coalesce(jsonb_agg(iara.guarda_json(r) order by (r.situacao = 'ENCERRADA'), r.created_at desc), '[]') from (
                select r.* from iara.guarda_restricoes r join iara.students s on s.id = r.student_id
                where (v_unit is null or r.unit_id = v_unit) and (v_q is null or iara.norm(s.full_name) like '%' || v_q || '%')
                  and (coalesce((p ->> 'encerradas')::boolean, false) or r.situacao = 'ATIVA')
                order by r.created_at desc limit 300) r));
end $$;

-- na ficha do aluno: detalhe para quem tem guarda.read; os demais servidores com acesso ao aluno veem só o alerta
create or replace function api.guarda_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_n integer;
  v_ret boolean;
begin
  if not (iara.e_servidor() and (iara.can_access_student(v_student) or exists (select 1 from iara.enrollments e where e.student_id = v_student and e.status = 'ACTIVE'
                                                                              and e.class_id = any (iara.minhas_turmas())))) then
    raise exception 'Aluno fora do seu acesso.' using errcode = '42501';
  end if;
  select count(*), bool_or(efeito_retirada = 'NAO_PODE') into v_n, v_ret from iara.guarda_restricoes r where r.student_id = v_student and iara.guarda_ativa(r);
  if not iara.has_perm('guarda.read') then
    return jsonb_build_object('detalhe', false, 'tem_restricao', v_n > 0, 'restricao_retirada', coalesce(v_ret, false),
      'aviso', case when v_n > 0 then 'Há registro judicial ou de guarda para este aluno. Antes de entregar a criança ou passar informações, consulte a direção ou a secretaria.' end);
  end if;
  return jsonb_build_object('detalhe', true, 'tem_restricao', v_n > 0, 'restricao_retirada', coalesce(v_ret, false), 'pode_registrar', iara.has_perm('guarda.write'),
    'itens', (select coalesce(jsonb_agg(iara.guarda_json(r) order by (r.situacao = 'ENCERRADA'), r.created_at desc), '[]') from iara.guarda_restricoes r where r.student_id = v_student),
    'responsaveis', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'nome', g.full_name, 'parentesco', sg.relationship, 'pode_buscar', sg.can_pick_up)), '[]')
                     from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id where sg.student_id = v_student and sg.end_date is null));
end $$;

create or replace function api.guarda_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_guardian uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_unit integer;
  r iara.guarda_restricoes;
begin
  perform iara.require_perm('guarda.write');
  if not iara.can_access_student(v_student) then raise exception 'Aluno fora do seu acesso.' using errcode = '42501'; end if;
  if coalesce((p ->> 'encerrar')::boolean, false) then
    select * into r from iara.guarda_restricoes where id = (p ->> 'id')::uuid and student_id = v_student and situacao = 'ATIVA' for update;
    if r.id is null then raise exception 'Registro não encontrado.' using errcode = 'P0002'; end if;
    if length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Informe o motivo do encerramento (ex.: decisão revogada).' using errcode = '22023'; end if;
    update iara.guarda_restricoes set situacao = 'ENCERRADA', encerrado_em = now(), encerramento_motivo = btrim(p ->> 'motivo') where id = r.id;
    if r.efeito_retirada = 'NAO_PODE' and r.guardian_id is not null and r.retirada_anterior is not null
       and not exists (select 1 from iara.guarda_restricoes x where x.student_id = r.student_id and x.guardian_id = r.guardian_id and x.id <> r.id and x.situacao = 'ATIVA' and x.efeito_retirada = 'NAO_PODE') then
      update iara.student_guardians set can_pick_up = r.retirada_anterior where student_id = r.student_id and guardian_id = r.guardian_id;
    end if;
    perform iara.audit_event('GUARDA_RESTRICAO', 'student', v_student::text, r.unit_id, 'Registro de guarda/restrição encerrado.');
    return api.guarda_aluno(jsonb_build_object('student_id', v_student));
  end if;
  if coalesce(p ->> 'tipo', '') not in ('GUARDA_UNILATERAL', 'GUARDA_COMPARTILHADA', 'TUTELA', 'ACOLHIMENTO', 'MEDIDA_PROTETIVA', 'PROIBICAO_RETIRADA',
                                        'PROIBICAO_CONTATO', 'VISITA_SUPERVISIONADA', 'AUTORIZACAO_RETIRADA', 'OUTRA') then
    raise exception 'Tipo inválido.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p ->> 'descricao', ''))) < 10 then raise exception 'Descreva o que a decisão determina (mínimo de 10 caracteres).' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'documento', ''))) < 3 then raise exception 'Informe o documento de referência (processo, termo, ofício).' using errcode = '22023'; end if;
  if v_guardian is not null and not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = v_guardian) then
    raise exception 'Responsável não vinculado a este aluno.' using errcode = '22023';
  end if;
  if v_guardian is null and nullif(btrim(coalesce(p ->> 'pessoa_nome', '')), '') is null and p ->> 'tipo' in ('PROIBICAO_RETIRADA', 'PROIBICAO_CONTATO', 'MEDIDA_PROTETIVA') then
    raise exception 'Indique a pessoa a quem a restrição se aplica.' using errcode = '22023';
  end if;
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  insert into iara.guarda_restricoes (student_id, unit_id, tipo, pessoa_nome, guardian_id, efeito_retirada, bloquear_portal, descricao, documento, orgao,
                                      vigencia_inicio, vigencia_fim, registrado_por_label, retirada_anterior)
  values (v_student, v_unit, p ->> 'tipo', coalesce(nullif(btrim(coalesce(p ->> 'pessoa_nome', '')), ''), (select full_name from iara.guardians where id = v_guardian)), v_guardian,
          coalesce(nullif(p ->> 'efeito_retirada', ''), case when p ->> 'tipo' in ('PROIBICAO_RETIRADA', 'MEDIDA_PROTETIVA', 'PROIBICAO_CONTATO') then 'NAO_PODE' else 'SEM_EFEITO' end),
          v_guardian is not null and coalesce((p ->> 'bloquear_portal')::boolean, false), btrim(p ->> 'descricao'), btrim(p ->> 'documento'),
          nullif(btrim(coalesce(p ->> 'orgao', '')), ''), coalesce(nullif(p ->> 'vigencia_inicio', '')::date, iara.hoje_local()), nullif(p ->> 'vigencia_fim', '')::date,
          iara.my_label(), (select can_pick_up from iara.student_guardians where student_id = v_student and guardian_id = v_guardian))
  returning * into r;
  if r.efeito_retirada = 'NAO_PODE' and r.guardian_id is not null then
    update iara.student_guardians set can_pick_up = false where student_id = r.student_id and guardian_id = r.guardian_id;
  end if;
  perform iara.audit_event('GUARDA_RESTRICAO', 'student', v_student::text, v_unit, format('Registro de %s.', lower(replace(r.tipo, '_', ' '))));
  return api.guarda_aluno(jsonb_build_object('student_id', v_student));
end $$;

-- 3. Suporte técnico ----------------------------------------------------------------------------------------------------------------
create sequence if not exists iara.suporte_seq;
create table if not exists iara.suporte_chamados (
  id uuid primary key default gen_random_uuid(),
  protocolo text not null unique default 'SUP-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('iara.suporte_seq')::text, 5, '0'),
  canal text not null default 'DEMANDA' check (canal in ('DEMANDA', 'MASTER')),
  categoria text not null check (categoria in ('ACESSO_SENHA', 'SISTEMA_IARA', 'WHATSAPP', 'EQUIPAMENTO', 'REDE_INTERNET', 'IMPRESSORA', 'DADOS_CADASTRO', 'MELHORIA', 'OUTRO')),
  prioridade text not null default 'NORMAL' check (prioridade in ('BAIXA', 'NORMAL', 'ALTA', 'URGENTE')),
  titulo text not null,
  descricao text not null,
  unit_id integer,
  setor text,
  solicitante_user uuid,
  solicitante_label text,
  contato text,
  anydesk_id text,
  situacao text not null default 'ABERTO' check (situacao in ('ABERTO', 'EM_ATENDIMENTO', 'AGUARDANDO_SOLICITANTE', 'RESOLVIDO', 'CANCELADO')),
  atendente_label text,
  prazo timestamptz,
  resolvido_em timestamptz,
  solucao text,
  avaliacao smallint check (avaliacao between 1 and 5),
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create table if not exists iara.suporte_mensagens (
  id uuid primary key default gen_random_uuid(),
  chamado_id uuid not null references iara.suporte_chamados(id) on delete cascade,
  autor_label text,
  do_suporte boolean not null default false,
  interno boolean not null default false,
  texto text not null,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create table if not exists iara.suporte_anydesk (
  id uuid primary key default gen_random_uuid(),
  unit_id integer,
  setor text,
  equipamento text not null,
  anydesk_id text not null,
  local text,
  responsavel text,
  observacao text,
  ativo boolean not null default true,
  atualizado_por_label text,
  atualizado_em timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists suporte_chamados_idx on iara.suporte_chamados (situacao, created_at desc);
alter table iara.suporte_chamados enable row level security;
alter table iara.suporte_mensagens enable row level security;
alter table iara.suporte_anydesk enable row level security;

create or replace function iara.suporte_prazo(p_prioridade text, p_de timestamptz default now()) returns timestamptz
language sql immutable as $$
  select p_de + case p_prioridade when 'URGENTE' then interval '4 hours' when 'ALTA' then interval '1 day' when 'BAIXA' then interval '5 days' else interval '3 days' end
$$;
create or replace function iara.texto_tem_senha(p text) returns boolean
language sql immutable as $$ select coalesce(p, '') ~* '(senha|password|pwd)\s*(:|=|é|e\s)' $$;

create or replace function iara.suporte_ve(c iara.suporte_chamados) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('suporte.atender') or c.solicitante_user = auth.uid()
      or (c.canal = 'DEMANDA' and iara.my_scope() = 'UNIT' and c.unit_id = iara.my_unit() and iara.my_role() in ('DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR'))
$$;

create or replace function iara.suporte_json(c iara.suporte_chamados, p_msgs boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(c) - 'solicitante_user' || jsonb_build_object('unidade', (select short_name from iara.education_units where id = c.unit_id),
    'vencido', c.situacao not in ('RESOLVIDO', 'CANCELADO') and c.prazo < now(), 'meu', c.solicitante_user = auth.uid(),
    'mensagens', case when p_msgs then (select coalesce(jsonb_agg(jsonb_build_object('autor', m.autor_label, 'do_suporte', m.do_suporte, 'interno', m.interno,
                   'texto', m.texto, 'em', m.created_at) order by m.created_at), '[]') from iara.suporte_mensagens m
                   where m.chamado_id = c.id and (not m.interno or iara.has_perm('suporte.atender'))) end)
$$;

create or replace function api.suporte_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_atende boolean := iara.has_perm('suporte.atender');
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  return (with base as (select c.* from iara.suporte_chamados c where iara.suporte_ve(c)
                          and (nullif(p ->> 'canal', '') is null or c.canal = p ->> 'canal'))
    select jsonb_build_object('atende', v_atende,
      'contagem', (select jsonb_build_object('abertos', count(*) filter (where situacao in ('ABERTO', 'EM_ATENDIMENTO', 'AGUARDANDO_SOLICITANTE')),
                     'novos', count(*) filter (where situacao = 'ABERTO'), 'vencidos', count(*) filter (where situacao not in ('RESOLVIDO', 'CANCELADO') and prazo < now()),
                     'master', count(*) filter (where canal = 'MASTER' and situacao not in ('RESOLVIDO', 'CANCELADO')),
                     'resolvidos_30d', count(*) filter (where resolvido_em >= now() - interval '30 days'),
                     'avaliacao', round(avg(avaliacao) filter (where avaliacao is not null), 1)) from base),
      'itens', (select coalesce(jsonb_agg(iara.suporte_json(b) order by (b.situacao in ('RESOLVIDO', 'CANCELADO')), b.prioridade = 'URGENTE' desc, b.created_at desc), '[]')
                from (select * from base where coalesce((p ->> 'todos')::boolean, false) or situacao not in ('RESOLVIDO', 'CANCELADO') or resolvido_em >= now() - interval '15 days'
                      order by created_at desc limit 200) b),
      'anydesk_unidade', case when iara.my_scope() = 'UNIT' then (select coalesce(jsonb_agg(to_jsonb(a) order by a.equipamento), '[]')
                                from iara.suporte_anydesk a where a.unit_id = iara.my_unit() and a.ativo) end));
end $$;

create or replace function api.suporte_abrir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.suporte_chamados;
  v_desc text := btrim(coalesce(p ->> 'descricao', ''));
  v_any text := nullif(regexp_replace(coalesce(p ->> 'anydesk_id', ''), '[^0-9a-zA-Z@._-]', '', 'g'), '');
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  if coalesce(p ->> 'categoria', '') not in ('ACESSO_SENHA', 'SISTEMA_IARA', 'WHATSAPP', 'EQUIPAMENTO', 'REDE_INTERNET', 'IMPRESSORA', 'DADOS_CADASTRO', 'MELHORIA', 'OUTRO') then
    raise exception 'Escolha a categoria.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p ->> 'titulo', ''))) < 5 or length(v_desc) < 15 then raise exception 'Dê um título e descreva o problema (mínimo de 15 caracteres).' using errcode = '22023'; end if;
  if iara.texto_tem_senha(v_desc) or iara.texto_tem_senha(p ->> 'titulo') then
    raise exception 'Não escreva senhas no chamado. O suporte nunca pede senha; no AnyDesk, você aceita a conexão na tela.' using errcode = '22023';
  end if;
  if v_any is not null and v_any !~ '^([0-9]{9,10}|[a-z0-9._-]+@ad)$' then raise exception 'Código do AnyDesk inválido (9 ou 10 números).' using errcode = '22023'; end if;
  insert into iara.suporte_chamados (canal, categoria, prioridade, titulo, descricao, unit_id, setor, solicitante_user, solicitante_label, contato, anydesk_id, prazo)
  values (case when p ->> 'canal' = 'MASTER' then 'MASTER' else 'DEMANDA' end, p ->> 'categoria',
          case when p ->> 'prioridade' in ('BAIXA', 'NORMAL', 'ALTA', 'URGENTE') then p ->> 'prioridade' else 'NORMAL' end,
          btrim(p ->> 'titulo'), v_desc, case when iara.my_scope() = 'UNIT' then iara.my_unit() end,
          coalesce(nullif(btrim(coalesce(p ->> 'setor', '')), ''), (select org_unit from iara.organizational_roles where code = iara.my_role())),
          auth.uid(), iara.my_label(), nullif(btrim(coalesce(p ->> 'contato', '')), ''), v_any,
          iara.suporte_prazo(case when p ->> 'prioridade' in ('BAIXA', 'NORMAL', 'ALTA', 'URGENTE') then p ->> 'prioridade' else 'NORMAL' end))
  returning * into c;
  perform iara.audit_event('SUPORTE', 'suporte', c.protocolo, c.unit_id, format('Demanda de suporte aberta (%s, %s).', lower(c.categoria), lower(c.canal)));
  return iara.suporte_json(c, true);
end $$;

create or replace function api.suporte_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.suporte_chamados;
begin
  select * into c from iara.suporte_chamados where id = (p ->> 'id')::uuid;
  if c.id is null or not iara.suporte_ve(c) then raise exception 'Chamado não encontrado.' using errcode = 'P0002'; end if;
  return iara.suporte_json(c, true) || jsonb_build_object('pode_atender', iara.has_perm('suporte.atender'), 'pode_avaliar', c.solicitante_user = auth.uid() and c.situacao = 'RESOLVIDO' and c.avaliacao is null);
end $$;

-- mensagens e andamento: o suporte assume, pede informação, resolve; quem abriu responde, reabre ou avalia
create or replace function api.suporte_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.suporte_chamados;
  v_sup boolean := iara.has_perm('suporte.atender');
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  v_sit text := nullif(p ->> 'situacao', '');
begin
  select * into c from iara.suporte_chamados where id = (p ->> 'id')::uuid for update;
  if c.id is null or not iara.suporte_ve(c) then raise exception 'Chamado não encontrado.' using errcode = 'P0002'; end if;
  if iara.texto_tem_senha(v_txt) then raise exception 'Não escreva senhas nas mensagens.' using errcode = '22023'; end if;
  if (p ->> 'avaliacao') is not null then
    if c.solicitante_user is distinct from auth.uid() or c.situacao <> 'RESOLVIDO' then raise exception 'A avaliação é de quem abriu, depois de resolvido.' using errcode = '22023'; end if;
    update iara.suporte_chamados set avaliacao = greatest(1, least(5, (p ->> 'avaliacao')::int)) where id = c.id;
  end if;
  if not v_sup then
    if v_sit is not null and not (v_sit = 'ABERTO' and c.situacao in ('RESOLVIDO', 'AGUARDANDO_SOLICITANTE')) and not (v_sit = 'CANCELADO' and c.solicitante_user = auth.uid()) then
      raise exception 'Você pode responder, reabrir ou cancelar o seu chamado.' using errcode = '42501';
    end if;
  elsif v_sit is not null and v_sit not in ('ABERTO', 'EM_ATENDIMENTO', 'AGUARDANDO_SOLICITANTE', 'RESOLVIDO', 'CANCELADO') then
    raise exception 'Situação inválida.' using errcode = '22023';
  end if;
  if v_sit = 'RESOLVIDO' and length(v_txt) < 10 then raise exception 'Descreva a solução (mínimo de 10 caracteres).' using errcode = '22023'; end if;
  if length(v_txt) < 2 and v_sit is null and (p ->> 'avaliacao') is null then raise exception 'Escreva a mensagem.' using errcode = '22023'; end if;
  if length(v_txt) >= 2 then
    insert into iara.suporte_mensagens (chamado_id, autor_label, do_suporte, interno, texto)
    values (c.id, iara.my_label(), v_sup and c.solicitante_user is distinct from auth.uid(), v_sup and coalesce((p ->> 'interno')::boolean, false), v_txt);
  end if;
  update iara.suporte_chamados set situacao = coalesce(v_sit, case when v_sup and situacao = 'ABERTO' and length(v_txt) >= 2 and not coalesce((p ->> 'interno')::boolean, false) then 'EM_ATENDIMENTO'
                                                              when not v_sup and situacao = 'AGUARDANDO_SOLICITANTE' then 'EM_ATENDIMENTO' else situacao end),
         atendente_label = case when v_sup then coalesce(atendente_label, iara.my_label()) else atendente_label end,
         resolvido_em = case when v_sit = 'RESOLVIDO' then now() when v_sit = 'ABERTO' then null else resolvido_em end,
         solucao = case when v_sit = 'RESOLVIDO' then v_txt else solucao end,
         prazo = case when v_sit = 'ABERTO' and c.situacao = 'RESOLVIDO' then iara.suporte_prazo(prioridade) else prazo end
  where id = c.id;
  return api.suporte_detalhe(jsonb_build_object('id', c.id));
end $$;

create or replace function api.suporte_anydesk(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_gestor boolean := iara.has_perm('suporte.atender') or iara.my_role() in ('DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR');
  v_id text := nullif(regexp_replace(coalesce(p ->> 'anydesk_id', ''), '[^0-9a-zA-Z@._-]', '', 'g'), '');
  a iara.suporte_anydesk;
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  if coalesce(p ->> 'acao', 'LISTAR') = 'LISTAR' then
    return jsonb_build_object('pode_editar', v_gestor, 'itens', (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('unidade', u.short_name) order by u.short_name, x.equipamento), '[]')
             from iara.suporte_anydesk x left join iara.education_units u on u.id = x.unit_id where x.ativo and (v_unit is null or x.unit_id = v_unit)
               and (iara.has_perm('suporte.atender') or x.unit_id = iara.my_unit())));
  end if;
  if not v_gestor then raise exception 'O cadastro do AnyDesk é feito pela direção, pela secretaria da unidade ou pelo suporte.' using errcode = '42501'; end if;
  if p ->> 'acao' = 'EXCLUIR' then
    update iara.suporte_anydesk set ativo = false, atualizado_por_label = iara.my_label(), atualizado_em = now()
    where id = (p ->> 'id')::uuid and (iara.has_perm('suporte.atender') or unit_id = iara.my_unit());
    return jsonb_build_object('ok', true);
  end if;
  if v_id is null or v_id !~ '^([0-9]{9,10}|[a-z0-9._-]+@ad)$' then raise exception 'Código do AnyDesk inválido (9 ou 10 números). Nunca cadastre a senha.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'equipamento', ''))) < 3 then raise exception 'Identifique o equipamento (ex.: computador da secretaria).' using errcode = '22023'; end if;
  if iara.texto_tem_senha(p ->> 'observacao') then raise exception 'Não cadastre senhas.' using errcode = '22023'; end if;
  if nullif(p ->> 'id', '') is null then
    insert into iara.suporte_anydesk (unit_id, setor, equipamento, anydesk_id, local, responsavel, observacao, atualizado_por_label)
    values (coalesce(v_unit, nullif(p ->> 'unit_id', '')::int), nullif(btrim(coalesce(p ->> 'setor', '')), ''), btrim(p ->> 'equipamento'), v_id,
            nullif(btrim(coalesce(p ->> 'local', '')), ''), nullif(btrim(coalesce(p ->> 'responsavel', '')), ''), nullif(btrim(coalesce(p ->> 'observacao', '')), ''), iara.my_label())
    returning * into a;
  else
    update iara.suporte_anydesk set equipamento = btrim(p ->> 'equipamento'), anydesk_id = v_id, local = nullif(btrim(coalesce(p ->> 'local', '')), ''),
           responsavel = nullif(btrim(coalesce(p ->> 'responsavel', '')), ''), observacao = nullif(btrim(coalesce(p ->> 'observacao', '')), ''),
           atualizado_por_label = iara.my_label(), atualizado_em = now()
    where id = (p ->> 'id')::uuid and (iara.has_perm('suporte.atender') or unit_id = iara.my_unit()) returning * into a;
    if a.id is null then raise exception 'Equipamento não encontrado.' using errcode = 'P0002'; end if;
  end if;
  return to_jsonb(a);
end $$;

-- 4. Catálogo de serviços -----------------------------------------------------------------------------------------------------------
alter table iara.service_catalog add column if not exists ativo boolean not null default true;
alter table iara.service_catalog add column if not exists plantao text;
alter table iara.service_catalog add column if not exists canais text[] not null default '{PORTAL,IARA,PRESENCIAL}';
alter table iara.service_catalog add column if not exists atualizado_por_label text;
alter table iara.service_catalog add column if not exists atualizado_em timestamptz;

create or replace function api.service_catalog(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'description', description,
         'requirements', requirements, 'documents', required_documents, 'sector', sector, 'sla_days', sla_days, 'source', source,
         'level', resolution_level, 'team', team, 'team_label', iara.team_label(team), 'iara_action', iara_action, 'escalation', escalation,
         'plantao', plantao, 'canais', canais) order by sort), '[]'::jsonb))
  from iara.service_catalog where ativo
$$;

create or replace function api.servicos_gestao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  return jsonb_build_object('pode_editar', iara.has_perm('gestao.servicos'),
    'equipes', (select jsonb_agg(jsonb_build_object('code', t, 'label', iara.team_label(t))) from unnest(array['CENTRAL_VAGAS', 'SECRETARIA_ESCOLAR', 'TRANSPORTE', 'AEE',
                 'INTEGRAL', 'ALIMENTACAO', 'OUVIDORIA', 'GESTAO', 'ATENDIMENTO']) t),
    'itens', (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('team_label', iara.team_label(s.team),
                 'casos_abertos', (select count(*) from iara.service_cases c where c.case_type = s.code and c.status <> 'ENCERRADO')) order by s.ativo desc, s.sort), '[]')
              from iara.service_catalog s where s.ativo or coalesce((p ->> 'inativos')::boolean, false)));
end $$;

create or replace function api.servico_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_code text := upper(regexp_replace(iara.norm(btrim(coalesce(nullif(p ->> 'code', ''), p ->> 'name', ''))), '[^a-z0-9]+', '_', 'g'));
  v_novo boolean;
  s iara.service_catalog;
begin
  perform iara.require_perm('gestao.servicos');
  v_code := btrim(v_code, '_');
  v_novo := not exists (select 1 from iara.service_catalog where code = v_code);
  if coalesce((p ->> 'excluir')::boolean, false) then
    if v_novo then raise exception 'Serviço não encontrado.' using errcode = 'P0002'; end if;
    if exists (select 1 from iara.service_cases c where c.case_type = v_code and c.status <> 'ENCERRADO') then
      raise exception 'Há atendimentos em aberto deste serviço: conclua-os antes de excluir.' using errcode = '22023';
    end if;
    update iara.service_catalog set ativo = false, atualizado_por_label = iara.my_label(), atualizado_em = now() where code = v_code returning * into s;
    perform iara.audit_event('CATALOGO_SERVICO', 'service_catalog', v_code, null, format('Serviço %s excluído do catálogo.', v_code));
    return to_jsonb(s);
  end if;
  if length(btrim(coalesce(p ->> 'name', ''))) < 5 or length(btrim(coalesce(p ->> 'description', ''))) < 15 then
    raise exception 'Informe o nome e a descrição do serviço.' using errcode = '22023';
  end if;
  if coalesce((p ->> 'sla_days')::int, 0) not between 1 and 120 then raise exception 'Prazo de 1 a 120 dias.' using errcode = '22023'; end if;
  if coalesce(p ->> 'resolution_level', 'SECRETARIA') not in ('IARA', 'UNIDADE', 'SECRETARIA') then raise exception 'Alçada inválida.' using errcode = '22023'; end if;
  if coalesce(p ->> 'team', 'CENTRAL_VAGAS') not in ('CENTRAL_VAGAS', 'SECRETARIA_ESCOLAR', 'TRANSPORTE', 'AEE', 'INTEGRAL', 'ALIMENTACAO', 'OUVIDORIA', 'GESTAO', 'ATENDIMENTO') then
    raise exception 'Equipe inválida.' using errcode = '22023';
  end if;
  insert into iara.service_catalog (code, tenant_id, name, description, audience, requirements, required_documents, sector, sla_days, actions, source, is_demo, sort,
                                    resolution_level, team, iara_action, escalation, plantao, canais, ativo, atualizado_por_label, atualizado_em)
  values (v_code, 1, btrim(p ->> 'name'), btrim(p ->> 'description'), coalesce(nullif(p ->> 'audience', ''), 'CIDADAO'), nullif(btrim(coalesce(p ->> 'requirements', '')), ''),
          coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p -> 'documents', '[]')) x), '{}'),
          coalesce(nullif(btrim(coalesce(p ->> 'sector', '')), ''), iara.team_label(coalesce(p ->> 'team', 'CENTRAL_VAGAS'))), (p ->> 'sla_days')::smallint, '{}',
          coalesce(nullif(btrim(coalesce(p ->> 'source', '')), ''), 'Cadastro da SEDUC no IARA Educa (a validar)'), false,
          coalesce((select max(sort) + 1 from iara.service_catalog), 1), coalesce(p ->> 'resolution_level', 'SECRETARIA'), coalesce(p ->> 'team', 'CENTRAL_VAGAS'),
          nullif(btrim(coalesce(p ->> 'iara_action', '')), ''), nullif(btrim(coalesce(p ->> 'escalation', '')), ''), nullif(btrim(coalesce(p ->> 'plantao', '')), ''),
          coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'canais') x where x in ('PORTAL', 'IARA', 'WHATSAPP', 'PRESENCIAL', 'TELEFONE')), '{PORTAL,IARA,PRESENCIAL}'),
          true, iara.my_label(), now())
  on conflict (code) do update set name = excluded.name, description = excluded.description, requirements = excluded.requirements,
     required_documents = excluded.required_documents, sector = excluded.sector, sla_days = excluded.sla_days, source = excluded.source,
     resolution_level = excluded.resolution_level, team = excluded.team, iara_action = excluded.iara_action, escalation = excluded.escalation,
     plantao = excluded.plantao, canais = excluded.canais, ativo = true, atualizado_por_label = excluded.atualizado_por_label, atualizado_em = now()
  returning * into s;
  perform iara.audit_event('CATALOGO_SERVICO', 'service_catalog', v_code, null, format('Serviço %s %s no catálogo.', v_code, case when v_novo then 'incluído' else 'alterado' end));
  return to_jsonb(s);
end $$;

-- 5. Critérios (regras versionadas) -------------------------------------------------------------------------------------------------
alter table iara.rules add column if not exists criado_em timestamptz not null default now();
alter table iara.rules add column if not exists criado_por_label text;
alter table iara.rules add column if not exists no_calculo boolean not null default true;

create or replace function api.criterios_gestao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  return jsonb_build_object('pode_editar', iara.has_perm('rules.manage'), 'versao', iara.rule_version(),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'code', r.rule_code, 'version', r.version, 'name', r.name, 'description', r.description,
                 'type', r.rule_type, 'weight', r.weight, 'condition', r.condition, 'source', r.source, 'source_kind', r.source_kind, 'justification', r.justification,
                 'valid_from', r.valid_from, 'valid_to', r.valid_to, 'active', r.is_active, 'no_calculo', r.no_calculo, 'criado_em', r.criado_em, 'criado_por', r.criado_por_label,
                 'vigente', r.id = (iara.rule(r.rule_code)).id) order by r.rule_type, r.sort, r.rule_code, r.valid_from desc, r.id desc), '[]')
              from iara.rules r where r.tenant_id = 1));
end $$;

-- alteração = nova versão (a anterior vale até a véspera); critério novo entra proposto, fora do cálculo, até a implementação técnica
create or replace function api.criterio_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_code text := upper(regexp_replace(iara.norm(btrim(coalesce(p ->> 'code', ''))), '[^a-z0-9]+', '_', 'g'));
  v_atual iara.rules;
  v_de date := coalesce(nullif(p ->> 'valid_from', '')::date, iara.hoje_local());
  v_just text := btrim(coalesce(p ->> 'justification', ''));
  v_ver text;
  v_n integer;
  r iara.rules;
begin
  perform iara.require_perm('rules.manage');
  v_code := btrim(v_code, '_');
  if length(v_code) < 3 then raise exception 'Informe o código do critério.' using errcode = '22023'; end if;
  if length(v_just) < 10 then raise exception 'Registre a justificativa (decisão, norma ou ofício).' using errcode = '22023'; end if;
  if v_de < iara.hoje_local() then raise exception 'A vigência começa hoje ou depois (não retroage).' using errcode = '22023'; end if;
  v_atual := iara.rule(v_code);
  if v_atual.id is null then select * into v_atual from iara.rules where rule_code = v_code order by valid_from desc, id desc limit 1; end if;
  if coalesce((p ->> 'desativar')::boolean, false) then
    if v_atual.id is null then raise exception 'Critério não encontrado.' using errcode = 'P0002'; end if;
    if v_atual.rule_type = 'ELIMINATORIA' then raise exception 'As eliminatórias da busca de vaga não são desativadas por aqui.' using errcode = '22023'; end if;
    update iara.rules set valid_to = v_de - 1, justification = coalesce(justification || ' | ', '') || 'Desativado: ' || v_just where id = v_atual.id;
    perform iara.audit_event('RULE_VERSION', 'rules', v_code, null, format('Critério %s desativado a partir de %s: %s', v_code, to_char(v_de, 'DD/MM/YYYY'), v_just));
    return jsonb_build_object('ok', true);
  end if;
  if length(btrim(coalesce(p ->> 'name', v_atual.name, ''))) < 3 or length(btrim(coalesce(p ->> 'description', v_atual.description, ''))) < 10 then
    raise exception 'Informe o nome e a descrição do critério.' using errcode = '22023';
  end if;
  if coalesce(p ->> 'type', v_atual.rule_type) not in ('ELIMINATORIA', 'PONTUACAO_UNIDADE', 'PRIORIDADE_FILA', 'PRIORIDADE_ANALISE', 'DESEMPATE', 'PARAMETRO') then
    raise exception 'Tipo inválido.' using errcode = '22023';
  end if;
  if coalesce((p ->> 'weight')::numeric, v_atual.weight, 0) not between 0 and 100 then raise exception 'Peso de 0 a 100.' using errcode = '22023'; end if;
  if coalesce(p ->> 'type', v_atual.rule_type) = 'PRIORIDADE_FILA' and (
       select coalesce(sum(x.weight), 0) from iara.rules x where x.rule_type = 'PRIORIDADE_FILA' and x.is_active and x.no_calculo and x.rule_code <> v_code
         and (x.valid_to is null or x.valid_to >= v_de) and x.valid_from <= v_de) + coalesce((p ->> 'weight')::numeric, v_atual.weight, 0) > 100
     and coalesce(v_atual.no_calculo, false) then
    raise exception 'A soma dos pontos da fila passaria de 100 (IN 025/2025, Anexo I).' using errcode = '22023';
  end if;
  v_ver := to_char(v_de, 'YYYY.MM.DD');
  select count(*) into v_n from iara.rules where rule_code = v_code and version like v_ver || '%';
  if v_n > 0 then v_ver := v_ver || '-' || (v_n + 1); end if;
  if v_atual.id is not null then
    update iara.rules set valid_to = v_de - 1 where id = v_atual.id and (valid_to is null or valid_to >= v_de);
  end if;
  insert into iara.rules (tenant_id, rule_code, version, name, description, rule_type, condition, weight, source, justification, valid_from, is_active, sort,
                          source_kind, source_url, criado_por_label, no_calculo)
  values (1, v_code, v_ver, btrim(coalesce(p ->> 'name', v_atual.name)), btrim(coalesce(p ->> 'description', v_atual.description)), coalesce(p ->> 'type', v_atual.rule_type),
          coalesce(v_atual.condition, '{}'), coalesce((p ->> 'weight')::numeric, v_atual.weight, 0), coalesce(nullif(btrim(coalesce(p ->> 'source', '')), ''), v_atual.source, 'A definir'),
          v_just, v_de, true, coalesce(v_atual.sort, (select max(sort) + 1 from iara.rules)),
          case when v_atual.id is null then 'PENDENTE' else coalesce(nullif(p ->> 'source_kind', ''), v_atual.source_kind) end, v_atual.source_url, iara.my_label(),
          v_atual.id is not null and v_atual.no_calculo)
  returning * into r;
  -- pesos da fila mudaram hoje: recalcula a fila para todos verem a nova ordem
  if r.no_calculo and r.rule_type in ('PRIORIDADE_FILA', 'DESEMPATE') and v_de = iara.hoje_local() then
    perform iara.compute_queue_priority(id) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED');
    perform iara.recalculate_all_queues();
  end if;
  perform iara.audit_event('RULE_VERSION', 'rules', v_code, null, format('Critério %s, versão %s (vigente a partir de %s)%s: %s', v_code, v_ver, to_char(v_de, 'DD/MM/YYYY'),
    case when r.no_calculo then '' else ' — proposto, fora do cálculo até a implementação' end, v_just));
  return jsonb_build_object('ok', true, 'id', r.id, 'version', r.version, 'no_calculo', r.no_calculo);
end $$;

-- 6. Jornada e matriz curricular ----------------------------------------------------------------------------------------------------
create table if not exists iara.jornada_padrao (
  id uuid primary key default gen_random_uuid(),
  grade_code text not null,
  turno text not null check (turno in ('MANHA', 'TARDE', 'NOITE', 'INTEGRAL')),
  inicio time not null,
  aulas_dia smallint not null check (aulas_dia between 1 and 10),
  duracao_aula_min smallint not null check (duracao_aula_min between 30 and 120),
  intervalo_min smallint not null default 15 check (intervalo_min between 0 and 60),
  intervalo_apos smallint not null default 3,
  dias_semana smallint not null default 5 check (dias_semana between 1 and 6),
  hora_atividade_pct numeric(5,2) not null default 33.33 check (hora_atividade_pct between 0 and 50),
  situacao text not null default 'PROPOSTO' check (situacao in ('CONFIRMADO', 'PROPOSTO')),
  fundamento text,
  versao integer not null default 1,
  ativo boolean not null default true,
  alterado_por_label text,
  alterado_em timestamptz not null default now(),
  unique (grade_code, turno, versao)
);
alter table iara.jornada_padrao enable row level security;
alter table iara.classes add column if not exists jornada_propria jsonb;
alter table iara.matriz_curricular add column if not exists duracao_min smallint;
alter table iara.matriz_curricular add column if not exists cobre_hora_atividade boolean not null default false;
alter table iara.horarios_turma drop constraint if exists horarios_turma_aula_check;
alter table iara.horarios_turma add constraint horarios_turma_aula_check check (aula between 1 and 10);

-- padrão inicial (proposta a validar): 5 aulas de 50 min (833 h/ano) + 20 min de intervalo após a 3ª, 5 dias — cabe a matriz de 25 aulas;
-- hora-atividade de 1/3 (Lei 11.738/2008)
insert into iara.jornada_padrao (grade_code, turno, inicio, aulas_dia, duracao_aula_min, intervalo_min, intervalo_apos, hora_atividade_pct, situacao, fundamento, alterado_por_label, alterado_em)
select g.code, t.turno, case t.turno when 'MANHA' then time '07:30' when 'TARDE' then time '13:00' else time '19:00' end,
       5, 50, 20, 3, 33.33, 'PROPOSTO',
       'Proposta inicial: LDB art. 24 (800 h e 200 dias letivos) e Lei 11.738/2008 art. 2º §4º (no máximo 2/3 da jornada com os alunos). Validar com a SEDUC.',
       'SEDUC (padrão inicial — validar)', '2026-10-01'
from iara.grade_levels g cross join (values ('MANHA'), ('TARDE'), ('NOITE')) t(turno)
where (t.turno <> 'NOITE' or g.code like 'EJA%') and (t.turno = 'NOITE' or g.code not like 'EJA%')
on conflict (grade_code, turno, versao) do nothing;
select set_config('iara.gestao_restaurando', 'on', true);
update iara.jornada_padrao set aulas_dia = 5, duracao_aula_min = 50, inicio = case turno when 'TARDE' then time '13:00' else inicio end
where versao = 1 and alterado_por_label = 'SEDUC (padrão inicial — validar)' and (aulas_dia, duracao_aula_min) <> (5, 50);
update iara.matriz_curricular set cobre_hora_atividade = true where quem = 'ESPECIALISTA' and not cobre_hora_atividade;
select set_config('iara.gestao_restaurando', 'off', true);

create or replace function iara.jornada_vigente(p_grade text, p_turno text) returns iara.jornada_padrao
language sql stable security definer set search_path = iara, public
as $$ select * from iara.jornada_padrao where grade_code = p_grade and turno = p_turno and ativo order by versao desc limit 1 $$;

create or replace function api.jornada_gestao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_dias integer := coalesce((select count(*) from iara.calendario_eventos where false), 0) + 200;
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  return jsonb_build_object('pode_editar', iara.has_perm('gestao.jornada'), 'dias_letivos', v_dias, 'minimo_ldb_horas', 800,
    'series', (select coalesce(jsonb_agg(jsonb_build_object('code', g.code, 'nome', g.name,
        'jornadas', (select coalesce(jsonb_agg(to_jsonb(j) || jsonb_build_object(
              'horas_dia', round(j.aulas_dia * j.duracao_aula_min / 60.0, 2),
              'horas_ano', round(j.aulas_dia * j.duracao_aula_min / 60.0 * v_dias),
              'termino', (j.inicio + make_interval(mins => j.aulas_dia * j.duracao_aula_min + j.intervalo_min))::time,
              'turmas', (select count(*) from iara.classes c where c.grade_level_id = g.id and c.shift = j.turno and c.status = 'ATIVA'),
              'turmas_proprias', (select count(*) from iara.classes c where c.grade_level_id = g.id and c.shift = j.turno and c.status = 'ATIVA' and c.jornada_propria is not null),
              'historico', (select count(*) from iara.jornada_padrao h where h.grade_code = j.grade_code and h.turno = j.turno)) order by j.turno), '[]')
            from iara.jornada_padrao j where j.grade_code = g.code and j.ativo and j.versao = (select max(versao) from iara.jornada_padrao x where x.grade_code = j.grade_code and x.turno = j.turno)),
        'matriz', (select coalesce(jsonb_agg(to_jsonb(m) order by m.ordem), '[]') from iara.matriz_curricular m where m.grade_code = g.code),
        'aulas_semana', (select coalesce(sum(aulas_semana), 0) from iara.matriz_curricular m where m.grade_code = g.code),
        'aulas_especialista', (select coalesce(sum(aulas_semana), 0) from iara.matriz_curricular m where m.grade_code = g.code and (m.quem = 'ESPECIALISTA' or m.cobre_hora_atividade)))
      order by g.code), '[]') from iara.grade_levels g));
end $$;

create or replace function api.jornada_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_atual iara.jornada_padrao;
  j iara.jornada_padrao;
  v_min integer;
begin
  perform iara.require_perm('gestao.jornada');
  if coalesce(p ->> 'turno', '') not in ('MANHA', 'TARDE', 'NOITE', 'INTEGRAL') or not exists (select 1 from iara.grade_levels where code = p ->> 'grade_code') then
    raise exception 'Série ou turno inválidos.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p ->> 'fundamento', ''))) < 10 then raise exception 'Registre o fundamento da alteração (mínimo de 10 caracteres).' using errcode = '22023'; end if;
  v_atual := iara.jornada_vigente(p ->> 'grade_code', p ->> 'turno');
  v_min := (p ->> 'aulas_dia')::int * (p ->> 'duracao_aula_min')::int;
  if v_min * 200 / 60 < 800 then raise exception 'Abaixo do mínimo legal: % h por ano (LDB, art. 24: 800 h em 200 dias).', v_min * 200 / 60 using errcode = '22023'; end if;
  if coalesce((p ->> 'hora_atividade_pct')::numeric, 33.33) < 33.33 then
    raise exception 'A hora-atividade não pode ser menor que 1/3 da jornada (Lei 11.738/2008, art. 2º, §4º).' using errcode = '22023';
  end if;
  insert into iara.jornada_padrao (grade_code, turno, inicio, aulas_dia, duracao_aula_min, intervalo_min, intervalo_apos, dias_semana, hora_atividade_pct, situacao, fundamento,
                                   versao, alterado_por_label)
  values (p ->> 'grade_code', p ->> 'turno', (p ->> 'inicio')::time, (p ->> 'aulas_dia')::smallint, (p ->> 'duracao_aula_min')::smallint,
          coalesce((p ->> 'intervalo_min')::smallint, 15), coalesce((p ->> 'intervalo_apos')::smallint, 3), coalesce((p ->> 'dias_semana')::smallint, 5),
          coalesce((p ->> 'hora_atividade_pct')::numeric, 33.33), case when p ->> 'situacao' = 'CONFIRMADO' then 'CONFIRMADO' else 'PROPOSTO' end, btrim(p ->> 'fundamento'),
          coalesce(v_atual.versao, 0) + 1, iara.my_label())
  returning * into j;
  perform iara.audit_event('JORNADA', 'jornada_padrao', j.grade_code || ':' || j.turno, null, format('Jornada padrão %s/%s, versão %s.', j.grade_code, j.turno, j.versao));
  return to_jsonb(j);
end $$;

create or replace function api.matriz_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_comp text := btrim(coalesce(p ->> 'componente', ''));
  v_total integer;
  v_cap integer;
  j iara.jornada_padrao;
begin
  perform iara.require_perm('gestao.jornada');
  if not exists (select 1 from iara.grade_levels where code = p ->> 'grade_code') or length(v_comp) < 3 then raise exception 'Série ou disciplina inválidas.' using errcode = '22023'; end if;
  if coalesce((p ->> 'excluir')::boolean, false) then
    if exists (select 1 from iara.horarios_turma h join iara.classes c on c.id = h.class_id join iara.grade_levels g on g.id = c.grade_level_id
               where g.code = p ->> 'grade_code' and h.componente = v_comp) then
      raise exception 'A disciplina está nos horários das turmas: tire-a dos horários antes de excluir.' using errcode = '22023';
    end if;
    delete from iara.matriz_curricular where grade_code = p ->> 'grade_code' and componente = v_comp;
    return jsonb_build_object('ok', true);
  end if;
  if coalesce((p ->> 'aulas_semana')::int, 0) not between 1 and 30 or coalesce(p ->> 'quem', '') not in ('REGENTE', 'ESPECIALISTA') then
    raise exception 'Aulas por semana (1 a 30) e quem leciona (regente ou especialista).' using errcode = '22023';
  end if;
  insert into iara.matriz_curricular (grade_code, componente, aulas_semana, quem, ordem, duracao_min, cobre_hora_atividade)
  values (p ->> 'grade_code', v_comp, (p ->> 'aulas_semana')::smallint, p ->> 'quem',
          coalesce((p ->> 'ordem')::smallint, (select coalesce(max(ordem), 0) + 1 from iara.matriz_curricular where grade_code = p ->> 'grade_code')),
          nullif(p ->> 'duracao_min', '')::smallint, coalesce((p ->> 'cobre_hora_atividade')::boolean, p ->> 'quem' = 'ESPECIALISTA'))
  on conflict (grade_code, componente) do update set aulas_semana = excluded.aulas_semana, quem = excluded.quem, duracao_min = excluded.duracao_min,
     cobre_hora_atividade = excluded.cobre_hora_atividade, ordem = coalesce((p ->> 'ordem')::smallint, iara.matriz_curricular.ordem);
  select coalesce(sum(aulas_semana), 0) into v_total from iara.matriz_curricular where grade_code = p ->> 'grade_code';
  select max(aulas_dia * dias_semana) into v_cap from iara.jornada_padrao x where x.grade_code = p ->> 'grade_code' and x.ativo
    and x.versao = (select max(versao) from iara.jornada_padrao y where y.grade_code = x.grade_code and y.turno = x.turno);
  if v_cap is not null and v_total > v_cap then
    raise exception 'A matriz somaria % aulas por semana, mais que a jornada comporta (%).', v_total, v_cap using errcode = '22023';
  end if;
  perform iara.audit_event('JORNADA', 'matriz_curricular', (p ->> 'grade_code') || ':' || v_comp, null, format('Matriz %s: %s.', p ->> 'grade_code', v_comp));
  return jsonb_build_object('ok', true, 'aulas_semana', v_total);
end $$;

-- turma com jornada própria (ou volta ao padrão)
create or replace function api.jornada_turma(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
begin
  if not (iara.has_perm('gestao.jornada') or (iara.my_role() = 'DIRETOR_UNIDADE' and exists (select 1 from iara.classes where id = v_class and unit_id = iara.my_unit()))) then
    raise exception 'Sem permissão para a jornada desta turma.' using errcode = '42501';
  end if;
  if p -> 'jornada' is null or jsonb_typeof(p -> 'jornada') = 'null' then
    update iara.classes set jornada_propria = null where id = v_class;
  else
    if coalesce((p -> 'jornada' ->> 'aulas_dia')::int, 0) not between 1 and 10 or coalesce((p -> 'jornada' ->> 'duracao_aula_min')::int, 0) not between 30 and 120
       or length(btrim(coalesce(p -> 'jornada' ->> 'motivo', ''))) < 10 then
      raise exception 'Informe aulas por dia, duração e o motivo da jornada própria.' using errcode = '22023';
    end if;
    update iara.classes set jornada_propria = (p -> 'jornada') || jsonb_build_object('por', iara.my_label(), 'em', now()) where id = v_class;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 7. Histórico, limpeza e demonstração ----------------------------------------------------------------------------------------------
drop trigger if exists gestao_hist on iara.org_setores;
create trigger gestao_hist after insert or update or delete on iara.org_setores for each row execute function iara.gestao_hist_trg('id');
drop trigger if exists gestao_hist on iara.org_vinculos;
create trigger gestao_hist after insert or update or delete on iara.org_vinculos for each row execute function iara.gestao_hist_trg('id');
drop trigger if exists gestao_hist on iara.service_catalog;
create trigger gestao_hist after insert or update or delete on iara.service_catalog for each row execute function iara.gestao_hist_trg('code');
drop trigger if exists gestao_hist on iara.rules;
create trigger gestao_hist after insert or update or delete on iara.rules for each row execute function iara.gestao_hist_trg('id');
drop trigger if exists gestao_hist on iara.jornada_padrao;
create trigger gestao_hist after insert or update or delete on iara.jornada_padrao for each row execute function iara.gestao_hist_trg('id');
drop trigger if exists gestao_hist on iara.matriz_curricular;
create trigger gestao_hist after insert or update or delete on iara.matriz_curricular for each row execute function iara.gestao_hist_trg('grade_code', 'componente');
drop trigger if exists gestao_hist_turma on iara.classes;
create trigger gestao_hist_turma after update of jornada_propria on iara.classes for each row execute function iara.gestao_hist_trg('id');

create or replace function api.gestao_historico(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not iara.e_servidor() then raise exception 'Disponível para servidores.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('acao', h.acao, 'por', h.por_label, 'em', h.em, 'antes', h.antes, 'depois', h.depois) order by h.em desc), '[]')
          from (select * from iara.gestao_hist where tabela = p ->> 'tabela' and chave @> coalesce(p -> 'chave', '{}') order by em desc limit 50) h);
end $$;

create or replace function iara.demo_gerar_gestao() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  perform set_config('iara.gestao_restaurando', 'on', true);
  -- guarda e restrições fictícias (nunca a família da apresentação)
  update iara.student_guardians sg set can_pick_up = r.retirada_anterior from iara.guarda_restricoes r
  where r.is_demo and r.guardian_id = sg.guardian_id and r.student_id = sg.student_id and r.retirada_anterior is not null;
  delete from iara.guarda_restricoes where is_demo;
  insert into iara.guarda_restricoes (student_id, unit_id, tipo, pessoa_nome, guardian_id, efeito_retirada, bloquear_portal, descricao, documento, orgao,
                                      vigencia_inicio, vigencia_fim, registrado_por_label, retirada_anterior, created_at, is_demo)
  select x.student_id, x.unit_id, t.tipo, case when t.com_resp then g.full_name else t.pessoa end, case when t.com_resp then g.id end, t.efeito, t.portal and t.com_resp,
         t.descr, 'Processo nº 00' || (1000000 + abs(hashtext(x.student_id::text)) % 8999999) || '-' || (10 + abs(hashtext(x.student_id::text)) % 89) || '.2026.8.16.0017 (demonstração)',
         t.orgao, iara.hoje_local() - (abs(hashtext(x.student_id::text)) % 300), case when t.tipo = 'MEDIDA_PROTETIVA' then iara.hoje_local() + (abs(hashtext(x.student_id::text)) % 90) end,
         'Secretaria escolar (demonstração)', sg.can_pick_up, now() - make_interval(days => abs(hashtext(x.student_id::text)) % 200), true
  from (select e.student_id, e.unit_id, abs(hashtext(e.student_id::text || 'guarda')) % 5 k from iara.enrollments e
        where e.status = 'ACTIVE' and e.student_id is distinct from v_ana and abs(hashtext(e.student_id::text || 'guarda')) % 1000 < 3) x
  join lateral (select * from iara.student_guardians s where s.student_id = x.student_id and s.end_date is null and not s.is_primary limit 1) sg on true
  join iara.guardians g on g.id = sg.guardian_id
  join (values
    (0, 'GUARDA_UNILATERAL', false, null, 'SEM_EFEITO', false, 'Guarda unilateral com a mãe; o pai tem visitas em fins de semana alternados, sem retirada na escola.', 'Vara de Família de Maringá'),
    (1, 'PROIBICAO_RETIRADA', true, null, 'NAO_PODE', false, 'O responsável indicado não pode retirar a criança da escola nem levá-la para fora do horário.', 'Vara de Família de Maringá'),
    (2, 'MEDIDA_PROTETIVA', true, null, 'NAO_PODE', true, 'Medida protetiva: afastamento do responsável indicado; não pode se aproximar da criança nem receber informações escolares.', 'Vara da Infância e Juventude de Maringá'),
    (3, 'GUARDA_COMPARTILHADA', false, null, 'SEM_EFEITO', false, 'Guarda compartilhada; residência fixa com a mãe. Os dois responsáveis recebem as informações escolares.', 'Vara de Família de Maringá'),
    (4, 'AUTORIZACAO_RETIRADA', false, 'Avó materna (demonstração)', 'PODE', false, 'Termo de autorização: a avó materna pode retirar a criança às terças e quintas.', 'Conselho Tutelar (termo)')
  ) t(k, tipo, com_resp, pessoa, efeito, portal, descr, orgao) on t.k = x.k;
  update iara.student_guardians sg set can_pick_up = false from iara.guarda_restricoes r
  where r.is_demo and r.efeito_retirada = 'NAO_PODE' and r.guardian_id = sg.guardian_id and r.student_id = sg.student_id;

  -- suporte: demandas e AnyDesk fictícios
  delete from iara.suporte_chamados where is_demo;
  delete from iara.suporte_anydesk where is_demo;
  insert into iara.suporte_anydesk (unit_id, setor, equipamento, anydesk_id, local, responsavel, atualizado_por_label, atualizado_em, is_demo)
  select u.id, 'Secretaria escolar', e.eq, (100000000 + abs(hashtext(u.id::text || e.eq)) % 899999999)::text, e.loc, 'Secretaria escolar (demonstração)',
         'Suporte (demonstração)', now() - make_interval(days => abs(hashtext(u.id::text)) % 120), true
  from iara.education_units u cross join (values ('Computador da secretaria', 'Secretaria'), ('Computador da direção', 'Sala da direção')) e(eq, loc)
  where u.status = 'ATIVA' and abs(hashtext(u.id::text || 'any')) % 100 < 45;
  insert into iara.suporte_chamados (canal, categoria, prioridade, titulo, descricao, unit_id, setor, solicitante_label, anydesk_id, situacao, atendente_label, prazo,
                                     resolvido_em, solucao, avaliacao, created_at, is_demo)
  select case when t.k = 7 then 'MASTER' else 'DEMANDA' end, t.cat, t.pri, t.tit, t.descr, u.id, 'Secretaria escolar', 'Secretaria escolar (demonstração)',
         (select a.anydesk_id from iara.suporte_anydesk a where a.unit_id = u.id and a.is_demo limit 1),
         case when x.idade > 6 then 'RESOLVIDO' when x.idade > 3 then (array['EM_ATENDIMENTO', 'AGUARDANDO_SOLICITANTE', 'RESOLVIDO'])[1 + x.h % 3] else (array['ABERTO', 'EM_ATENDIMENTO'])[1 + x.h % 2] end,
         case when x.idade > 0 then 'Suporte · Inovação (demonstração)' end, iara.suporte_prazo(t.pri, now() - make_interval(days => x.idade, hours => x.h % 8)),
         case when x.idade > 6 or (x.idade > 3 and x.h % 3 = 2) then now() - make_interval(days => greatest(x.idade - 2, 0)) end,
         case when x.idade > 6 or (x.idade > 3 and x.h % 3 = 2) then t.sol end,
         case when x.idade > 6 and x.h % 4 <> 0 then 4 + x.h % 2 end, now() - make_interval(days => x.idade, hours => x.h % 8), true
  from (select u.id, abs(hashtext(u.id::text || 'sup')) h, abs(hashtext(u.id::text || 'sup')) % 20 idade from iara.education_units u
        where u.status = 'ATIVA' and abs(hashtext(u.id::text || 'sup')) % 100 < 35) x
  join iara.education_units u on u.id = x.id
  join (values
    (0, 'ACESSO_SENHA', 'ALTA', 'Professora nova sem acesso ao diário', 'A professora que assumiu a turma do 3º ano não consegue entrar no diário de classe.', 'Perfil de professor liberado e turma vinculada.'),
    (1, 'IMPRESSORA', 'NORMAL', 'Impressora da secretaria não imprime', 'A impressora da secretaria parou de imprimir depois da troca do toner.', 'Driver reinstalado por acesso remoto (AnyDesk).'),
    (2, 'REDE_INTERNET', 'URGENTE', 'Sem internet na unidade', 'A escola está sem internet desde a manhã; o diário não sincroniza.', 'Chamado aberto com a operadora; link restabelecido.'),
    (3, 'SISTEMA_IARA', 'NORMAL', 'Chamada não aparece no portal da família', 'Uma família diz que a falta de ontem não aparece no portal.', 'A chamada estava como rascunho; o professor confirmou.'),
    (4, 'EQUIPAMENTO', 'BAIXA', 'Computador da direção lento', 'O computador da direção demora muito para abrir o sistema.', 'Limpeza de inicialização e atualização do navegador.'),
    (5, 'DADOS_CADASTRO', 'NORMAL', 'Aluno com data de nascimento errada', 'Um aluno aparece com a data de nascimento trocada no cadastro.', 'Cadastro corrigido com a certidão apresentada.'),
    (6, 'WHATSAPP', 'ALTA', 'Família não recebe mensagens da IARA', 'Uma família informa que não recebe os avisos pelo WhatsApp.', 'Telefone conferido e contato vinculado novamente.'),
    (7, 'MELHORIA', 'NORMAL', 'Sugestão: relatório de faltas por turma', 'Gostaríamos de um relatório mensal de faltas por turma para a reunião pedagógica.', 'Sugestão registrada no planejamento da Diretoria de Inovação.')
  ) t(k, cat, pri, tit, descr, sol) on t.k = x.h % 8;
  insert into iara.suporte_mensagens (chamado_id, autor_label, do_suporte, texto, created_at, is_demo)
  select c.id, 'Suporte · Inovação (demonstração)', true, case when c.situacao = 'AGUARDANDO_SOLICITANTE' then 'Pode deixar o AnyDesk aberto amanhã às 9h para acessarmos?'
                                                          else 'Recebemos sua demanda e já estamos verificando.' end, c.created_at + interval '40 minutes', true
  from iara.suporte_chamados c where c.is_demo and c.situacao <> 'ABERTO';
  perform set_config('iara.gestao_restaurando', 'off', true);
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('guarda', (select count(*) from iara.guarda_restricoes where is_demo), 'chamados', (select count(*) from iara.suporte_chamados where is_demo),
    'anydesk', (select count(*) from iara.suporte_anydesk where is_demo));
end $$;

-- limpeza: desfaz alterações feitas ao vivo no catálogo, critérios, organograma, jornada e matriz; apaga registros novos
create or replace function iara.demo_purge_gestao(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  h record;
  n integer := 0;
  v jsonb := '{}'::jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  for h in select * from iara.gestao_hist where em >= d order by id desc loop
    perform iara.gestao_restaurar(h.tabela, h.chave, h.antes);
    n := n + 1;
  end loop;
  delete from iara.gestao_hist where em >= d;
  v := v || jsonb_build_object('alteracoes_desfeitas', n);
  update iara.student_guardians sg set can_pick_up = r.retirada_anterior from iara.guarda_restricoes r
  where not r.is_demo and r.created_at >= d and r.guardian_id = sg.guardian_id and r.student_id = sg.student_id and r.retirada_anterior is not null;
  delete from iara.guarda_restricoes where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('guarda', n);
  update iara.guarda_restricoes set situacao = 'ATIVA', encerrado_em = null, encerramento_motivo = null where is_demo and encerrado_em >= d;
  delete from iara.suporte_mensagens where not is_demo and created_at >= d;
  delete from iara.suporte_chamados where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('suporte', n);
  delete from iara.suporte_anydesk where not is_demo and atualizado_em >= d;
  if exists (select 1 from iara.suporte_chamados where is_demo and (avaliacao is not null and resolvido_em >= d))
     or exists (select 1 from iara.suporte_anydesk where is_demo and atualizado_em >= d and atualizado_por_label not like '%(demonstração)%') then
    perform iara.demo_gerar_gestao();
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
end $$;

create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null), 'pedagogico', iara.demo_purge_sprint2(null),
                               'transporte_almoxarifado', iara.demo_purge_sprint3(null), 'busca_ativa', iara.demo_purge_busca_ativa(null),
                               'ocorrencias', iara.demo_purge_ocorrencias(null), 'gestao', iara.demo_purge_gestao(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.gestao_restaurar(text, jsonb, jsonb), iara.demo_gerar_gestao(), iara.demo_purge_gestao(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('guarda_restricoes', 'descricao', 'SENSIVEL', 'decisão judicial / proteção da criança', 'retirada segura e sigilo', 'direção e secretaria (visibilidade pendente de decisão da SEDUC)'),
  ('guarda_restricoes', 'pessoa_nome', 'SENSIVEL', 'identificação de pessoa com restrição', 'retirada segura', 'direção e secretaria'),
  ('guarda_restricoes', 'documento', 'SENSIVEL', 'referência processual', 'comprovação', 'direção e secretaria'),
  ('guarda_restricoes', 'encerramento_motivo', 'SENSIVEL', 'decisão judicial', 'histórico', 'direção e secretaria'),
  ('guarda_restricoes', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('org_vinculos', 'pessoa_nome', 'PESSOAL', 'identificação funcional', 'organograma', null),
  ('suporte_chamados', 'descricao', 'INTERNO', 'demanda técnica', 'suporte', 'sem senhas (bloqueado)'),
  ('suporte_chamados', 'solicitante_label', 'PESSOAL', 'identificação', 'suporte', null),
  ('suporte_chamados', 'contato', 'PESSOAL', 'contato funcional', 'suporte', null),
  ('suporte_anydesk', 'anydesk_id', 'INTERNO', 'acesso remoto', 'suporte', 'só o código; nunca a senha')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_gestao() where iara.demo_mode();

commit;
