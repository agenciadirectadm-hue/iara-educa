-- IARA Educa — 087 · Públicos do Prefeito: contagens por filtros e envio pelo WhatsApp oficial
-- Exclusivo do Prefeito. Ele monta públicos de profissionais e de responsáveis com os filtros do IARA (unidade, região,
-- tipo de unidade, função, vínculo, situação, formação; e, para responsáveis, unidade, série, turno e situação dos filhos,
-- fila, transporte, AEE, alerta de frequência, CadÚnico e região de moradia) e vê só contagens: nenhum nome, telefone ou
-- identificador sai daqui; recortes com menos de 3 pessoas ficam em sigilo. O envio usa um modelo aprovado e o WhatsApp
-- oficial, respeita quem pediu para não receber, fica auditado e é bloqueado no período eleitoral (Lei 9.504/97, art. 73:
-- publicidade institucional restrita nos 3 meses antes da eleição). Na demonstração, o envio só é registrado (simulado).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive)
values ('publicos.prefeito', 'Montar públicos de profissionais e responsáveis (só contagens) e enviar comunicados oficiais', true)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code) values ('PREFEITO', 'publicos.prefeito') on conflict do nothing;

-- modelos de mensagem aprovados (categoria da Meta: define a tarifa)
create table if not exists iara.publicos_modelos (
  codigo text primary key,
  nome text not null,
  publico text not null check (publico in ('PROFISSIONAIS', 'RESPONSAVEIS', 'TODOS')),
  categoria text not null check (categoria in ('MARKETING', 'UTILIDADE')),
  corpo text not null,  -- {texto} é o que o prefeito escreve
  ativo boolean not null default true
);
insert into iara.publicos_modelos (codigo, nome, publico, categoria, corpo) values
  ('COMUNICADO', 'Comunicado da Prefeitura', 'TODOS', 'MARKETING', 'Prefeitura de Maringá · Secretaria de Educação: {texto}'),
  ('CONVITE', 'Convite para evento', 'TODOS', 'MARKETING', 'Prefeitura de Maringá convida: {texto} Responda SAIR para não receber mais.'),
  ('MATRICULA', 'Campanha de matrícula e rematrícula', 'RESPONSAVEIS', 'UTILIDADE', 'Matrícula e rematrícula na rede municipal: {texto}'),
  ('SERVIDORES', 'Aviso aos profissionais da rede', 'PROFISSIONAIS', 'UTILIDADE', 'Aviso da Secretaria de Educação aos profissionais da rede: {texto}')
on conflict (codigo) do update set nome = excluded.nome, publico = excluded.publico, categoria = excluded.categoria, corpo = excluded.corpo;

create table if not exists iara.publicos_envios (
  id uuid primary key default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  autor_label text,
  publico text not null check (publico in ('PROFISSIONAIS', 'RESPONSAVEIS')),
  filtros jsonb not null default '{}'::jsonb,
  modelo text not null references iara.publicos_modelos(codigo),
  texto text not null,
  total integer not null,
  com_contato integer not null,
  sem_contato integer not null,
  nao_querem integer not null,
  enviados integer not null,
  situacao text not null check (situacao in ('SIMULADO', 'ENFILEIRADO', 'BLOQUEADO_ELEITORAL')),
  is_demo boolean not null default true
);
create index if not exists publicos_envios_criado_idx on iara.publicos_envios (criado_em desc);
alter table iara.publicos_modelos enable row level security;
alter table iara.publicos_envios enable row level security;

-- quem forma o público, com o telefone normalizado (só dígitos) para conferir o bloqueio; nunca sai desta função
create or replace function iara.publicos_alvo(p_publico text, f jsonb)
returns table (pessoa uuid, unit_id integer, area integer, telefone text)
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_unid integer[] := array(select jsonb_array_elements_text(coalesce(f -> 'unidades', '[]'))::int);
  v_areas integer[] := array(select jsonb_array_elements_text(coalesce(f -> 'areas', '[]'))::int);
  v_tipos text[] := array(select jsonb_array_elements_text(coalesce(f -> 'tipos', '[]')));
begin
  if p_publico = 'PROFISSIONAIS' then
    return query
      select st.id, st.unit_id, u.macro_territory_id, null::text
      from iara.staff st left join iara.education_units u on u.id = st.unit_id
      where (cardinality(v_unid) = 0 or st.unit_id = any (v_unid))
        and (cardinality(v_areas) = 0 or u.macro_territory_id = any (v_areas))
        and (cardinality(v_tipos) = 0 or u.unit_type = any (v_tipos))
        and (not f ? 'funcoes' or jsonb_array_length(f -> 'funcoes') = 0 or st.role in (select jsonb_array_elements_text(f -> 'funcoes')))
        and (not f ? 'vinculos' or jsonb_array_length(f -> 'vinculos') = 0 or st.bond in (select jsonb_array_elements_text(f -> 'vinculos')))
        and (not f ? 'situacoes' or jsonb_array_length(f -> 'situacoes') = 0 or coalesce(st.situacao, 'ATIVO') in (select jsonb_array_elements_text(f -> 'situacoes')))
        and (not f ? 'formacao' or jsonb_array_length(f -> 'formacao') = 0
             or coalesce(iara.formacao_nivel(st.escolaridade), 0)::text in (select jsonb_array_elements_text(f -> 'formacao')))
        and (not f ? 'carga' or jsonb_array_length(f -> 'carga') = 0 or st.carga_horaria_semanal::text in (select jsonb_array_elements_text(f -> 'carga')));
  elsif p_publico = 'RESPONSAVEIS' then
    return query
      with filhos as (
        select s.id, s.status, s.aee_status, e.unit_id, c.grade_level_id, c.shift, a.territory_id area_casa
        from iara.students s
        left join lateral (select e2.unit_id, e2.class_id from iara.enrollments e2
                           where e2.student_id = s.id and e2.status = 'ACTIVE' order by e2.start_date desc nulls last limit 1) e on true
        left join iara.classes c on c.id = e.class_id
        left join iara.addresses a on a.id = s.address_id
        where (cardinality(v_unid) = 0 or e.unit_id = any (v_unid)
               or exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED') and w.preferred_unit_id = any (v_unid)))
          and (cardinality(v_tipos) = 0 or exists (select 1 from iara.education_units u where u.id = e.unit_id and u.unit_type = any (v_tipos)))
          and (cardinality(v_areas) = 0 or a.territory_id = any (v_areas))
          and (not f ? 'series' or jsonb_array_length(f -> 'series') = 0 or c.grade_level_id::text in (select jsonb_array_elements_text(f -> 'series'))
               or exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED')
                            and w.grade_level_id::text in (select jsonb_array_elements_text(f -> 'series'))))
          and (not f ? 'turnos' or jsonb_array_length(f -> 'turnos') = 0 or c.shift in (select jsonb_array_elements_text(f -> 'turnos')))
          and (not f ? 'situacoes_aluno' or jsonb_array_length(f -> 'situacoes_aluno') = 0 or s.status in (select jsonb_array_elements_text(f -> 'situacoes_aluno')))
          and (coalesce((f ->> 'fila')::boolean, false) = false
               or exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED')))
          and (coalesce((f ->> 'transporte')::boolean, false) = false
               or exists (select 1 from iara.transporte_alunos ta where ta.student_id = s.id and ta.fim is null))
          and (coalesce((f ->> 'aee')::boolean, false) = false or s.aee_status)
          and (coalesce((f ->> 'alerta_frequencia')::boolean, false) = false
               or exists (select 1 from iara.frequencia_alertas fa where fa.student_id = s.id and fa.situacao <> 'RESOLVIDO')))
      select distinct on (g.id) g.id, fi.unit_id, fi.area_casa,
             nullif(regexp_replace(coalesce(g.whatsapp_phone, g.primary_phone, ''), '\D', '', 'g'), '')
      from filhos fi
      join iara.student_guardians sg on sg.student_id = fi.id and sg.end_date is null
      join iara.guardians g on g.id = sg.guardian_id
      where (coalesce((f ->> 'cadunico')::boolean, false) = false or g.cadunico_status)
        and coalesce(sg.can_receive_notifications, true)
      order by g.id, sg.is_primary desc;
  else
    raise exception 'Público inválido: use PROFISSIONAIS ou RESPONSAVEIS.' using errcode = '22023';
  end if;
end $$;

-- quem pediu para não receber (bloqueio do canal da IARA), pelo telefone só com dígitos
create or replace function iara.publicos_nao_quer(p_tel text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select p_tel is not null and exists (select 1 from iara.whatsapp_avisos_bloqueio b
                                       where regexp_replace(b.telefone_e164, '\D', '', 'g') in (p_tel, '55' || p_tel))
$$;

-- período eleitoral: 3 meses antes da eleição municipal (data em tenants.settings.eleicao_municipal; padrão: 1º/10/2028)
create or replace function iara.publicos_periodo_eleitoral() returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with e as (select coalesce(nullif(iara.setting('eleicao_municipal'), '')::date, date '2028-10-01') d)
  select jsonb_build_object('eleicao', d, 'inicio_restricao', (d - interval '3 months')::date,
                            'restrito', iara.hoje_local() between (d - interval '3 months')::date and d)
  from e
$$;

create or replace function api.publicos_opcoes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('publicos.prefeito');
  return jsonb_build_object(
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', short_name, 'tipo', unit_type, 'area', macro_territory_id) order by short_name), '[]')
                 from iara.education_units),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', name) order by name), '[]') from iara.territories where kind = 'AREA_PONDERACAO'),
    'funcoes', (select coalesce(jsonb_agg(distinct role), '[]') from iara.staff),
    'vinculos', (select coalesce(jsonb_agg(distinct bond), '[]') from iara.staff where bond is not null),
    'situacoes', (select coalesce(jsonb_agg(distinct coalesce(situacao, 'ATIVO')), '[]') from iara.staff),
    'cargas', (select coalesce(jsonb_agg(distinct carga_horaria_semanal order by carga_horaria_semanal), '[]') from iara.staff where carga_horaria_semanal is not null),
    'series', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', short_name) order by sort), '[]') from iara.grade_levels),
    'situacoes_aluno', (select coalesce(jsonb_agg(distinct status), '[]') from iara.students),
    'modelos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome, 'publico', publico, 'categoria', categoria, 'corpo', corpo) order by nome), '[]')
                from iara.publicos_modelos where ativo),
    'periodo_eleitoral', iara.publicos_periodo_eleitoral());
end $$;

-- p: publico, filtros. Só contagens; recortes com menos de 3 pessoas ficam em sigilo.
create or replace function api.publicos_contar(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_pub text := coalesce(p ->> 'publico', 'RESPONSAVEIS');
  v_f jsonb := coalesce(p -> 'filtros', '{}'::jsonb);
begin
  perform iara.require_perm('publicos.prefeito');
  return (
    with a as (select * from iara.publicos_alvo(v_pub, v_f)),
    b as (select a.*, iara.publicos_nao_quer(a.telefone) nao_quer from a)
    select jsonb_build_object(
      'publico', v_pub,
      'total', (select count(*) from b),
      'com_contato', (select count(*) from b where telefone is not null and not nao_quer),
      'sem_contato', (select count(*) from b where telefone is null),
      'nao_querem', (select count(*) from b where nao_quer),
      'por_unidade', (select coalesce(jsonb_agg(jsonb_build_object('nome', u.short_name, 'n', q.n) order by q.n desc), '[]') from (
                        select unit_id, count(*) n from b where unit_id is not null group by unit_id having count(*) >= 3 order by count(*) desc limit 10) q
                      join iara.education_units u on u.id = q.unit_id),
      'por_regiao', (select coalesce(jsonb_agg(jsonb_build_object('nome', t.name, 'n', q.n) order by q.n desc), '[]') from (
                       select area, count(*) n from b where area is not null group by area having count(*) >= 3 order by count(*) desc limit 10) q
                     join iara.territories t on t.id = q.area),
      'nota', 'Só contagens: nenhum nome, telefone ou identificador. Recortes com menos de 3 pessoas ficam em sigilo.'));
end $$;

-- p: publico, filtros, modelo, texto. Registra o envio (simulado na demonstração) e audita; bloqueia no período eleitoral.
create or replace function api.publicos_enviar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_pub text := coalesce(p ->> 'publico', 'RESPONSAVEIS');
  v_f jsonb := coalesce(p -> 'filtros', '{}'::jsonb);
  v_modelo iara.publicos_modelos;
  v_texto text := btrim(coalesce(p ->> 'texto', ''));
  v_total integer; v_com integer; v_sem integer; v_nao integer;
  v_situacao text;
  v_id uuid;
  v_ele jsonb := iara.publicos_periodo_eleitoral();
begin
  perform iara.require_perm('publicos.prefeito');
  select * into v_modelo from iara.publicos_modelos where codigo = p ->> 'modelo' and ativo;
  if v_modelo.codigo is null then
    raise exception 'Escolha um modelo de mensagem aprovado.' using errcode = '22023';
  end if;
  if v_modelo.publico <> 'TODOS' and v_modelo.publico <> v_pub then
    raise exception 'Este modelo não serve para este público.' using errcode = '22023';
  end if;
  if length(v_texto) < 10 or length(v_texto) > 700 then
    raise exception 'Escreva a mensagem (de 10 a 700 caracteres).' using errcode = '22023';
  end if;
  select count(*), count(*) filter (where telefone is not null and not iara.publicos_nao_quer(telefone)),
         count(*) filter (where telefone is null), count(*) filter (where iara.publicos_nao_quer(telefone))
    into v_total, v_com, v_sem, v_nao
  from iara.publicos_alvo(v_pub, v_f);
  if v_total = 0 then
    raise exception 'Ninguém neste público.' using errcode = '22023';
  end if;
  v_situacao := case when (v_ele ->> 'restrito')::boolean then 'BLOQUEADO_ELEITORAL' when iara.demo_mode() then 'SIMULADO' else 'ENFILEIRADO' end;
  insert into iara.publicos_envios (autor_label, publico, filtros, modelo, texto, total, com_contato, sem_contato, nao_querem, enviados, situacao, is_demo)
  values (iara.my_label(), v_pub, v_f, v_modelo.codigo, v_texto, v_total, v_com, v_sem, v_nao,
          case when v_situacao = 'BLOQUEADO_ELEITORAL' then 0 else v_com end, v_situacao, iara.demo_mode())
  returning id into v_id;
  perform iara.audit_event('PUBLICO_ENVIO', 'publicos_envios', v_id::text, null,
    format('Envio aos %s (%s pessoas, %s com contato): %s', lower(v_pub), v_total, v_com, v_situacao),
    jsonb_build_object('publico', v_pub, 'filtros', v_f, 'modelo', v_modelo.codigo, 'total', v_total, 'situacao', v_situacao));
  -- produção: aqui entram as mensagens na fila do WhatsApp oficial (modelo aprovado pela Meta), um por pessoa com contato
  return jsonb_build_object('id', v_id, 'situacao', v_situacao, 'total', v_total, 'enviados', case when v_situacao = 'BLOQUEADO_ELEITORAL' then 0 else v_com end,
    'sem_contato', v_sem, 'nao_querem', v_nao, 'periodo_eleitoral', v_ele,
    'mensagem', replace(v_modelo.corpo, '{texto}', v_texto));
end $$;

create or replace function api.publicos_historico(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('publicos.prefeito');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'criado_em', e.criado_em, 'autor', e.autor_label, 'publico', e.publico, 'modelo', m.nome,
                    'texto', e.texto, 'total', e.total, 'enviados', e.enviados, 'sem_contato', e.sem_contato, 'nao_querem', e.nao_querem, 'situacao', e.situacao)
                    order by e.criado_em desc), '[]')
          from (select * from iara.publicos_envios order by criado_em desc limit 30) e join iara.publicos_modelos m on m.codigo = e.modelo);
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('publicos_envios', 'filtros', 'INTERNO', 'comunicação', 'públicos dos comunicados do Prefeito', 'só contagens; auditado')
on conflict (tabela, coluna) do nothing;

revoke all on function iara.publicos_alvo(text, jsonb), iara.publicos_nao_quer(text), iara.publicos_periodo_eleitoral() from public;

commit;
