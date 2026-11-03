-- IARA Educa — 088 · Oráculo do Prefeito: qualquer número consolidado do município, por texto ou áudio
-- Exclusivo do Prefeito. As "ferramentas" do Oráculo são consultas agregadas (api.oraculo_dados): visão geral, matrículas,
-- fila, vagas, creche, frequência, ocorrências, profissionais, transporte, alfabetização, busca ativa, unidades e cadastros,
-- na cidade, numa unidade ou numa região (área de ponderação). São as mesmas que o servidor MCP do gateway (/mcp) expõe e
-- que o Claude Opus 5.5 usa quando a chave da Anthropic estiver configurada; sem a chave, api.oraculo_perguntar responde por
-- regras (palavras da pergunta → consulta). Só números agregados: nenhum nome nem identificador de pessoa.
-- Cada pergunta fica registrada (pergunta, modo, resposta) para o próprio Prefeito e para a auditoria.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive)
values ('oraculo.prefeito', 'Perguntar ao Oráculo do Prefeito (números consolidados do município, por texto ou áudio)', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code) values ('PREFEITO', 'oraculo.prefeito') on conflict do nothing;

create table if not exists iara.oraculo_perguntas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references iara.app_users(id) on delete set null,
  criado_em timestamptz not null default clock_timestamp(),
  pergunta text not null,
  canal text not null default 'TEXTO' check (canal in ('TEXTO', 'AUDIO')),
  modo text not null check (modo in ('REGRAS', 'CLAUDE')),
  resposta text not null,
  ferramentas jsonb not null default '[]'::jsonb,
  is_demo boolean not null default true
);
alter table iara.oraculo_perguntas alter column criado_em set default clock_timestamp();
create index if not exists oraculo_perguntas_user_idx on iara.oraculo_perguntas (user_id, criado_em desc);
alter table iara.oraculo_perguntas enable row level security;

-- número no padrão brasileiro (1.234 ou 93,4)
create or replace function iara.num_br(p numeric, p_casas integer default 0) returns text
language sql immutable
as $$
  select case when p is null then '—' else
    replace(replace(replace(to_char(round(p, p_casas), 'FM999,999,999,990' || case when p_casas > 0 then '.' || repeat('0', p_casas) else '' end), ',', '#'), '.', ','), '#', '.') end
$$;

-- texto só com letras e números separados por um espaço ("Odette A. Rosa?" → "odette a rosa")
create or replace function iara.oraculo_palavras(p text) returns text
language sql immutable
as $$ select btrim(regexp_replace(iara.norm(p), '[^a-z0-9]+', ' ', 'g')) $$;

-- unidade e região citadas na pergunta (a de nome mais longo, para não confundir "Jardim" com "Jardim Alvorada")
create or replace function iara.oraculo_recorte(p_texto text) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_n text := ' ' || iara.oraculo_palavras(p_texto) || ' ';
  v_unit integer;
  v_area integer;
  v_ap text := (regexp_match(v_n, ' (?:ap|area|regiao) 0*([0-9]{1,3}) '))[1];
begin
  select u.id into v_unit from iara.education_units u
  where length(iara.oraculo_palavras(u.short_name)) >= 5 and v_n like '% ' || iara.oraculo_palavras(u.short_name) || ' %'
  order by length(u.short_name) desc limit 1;
  if v_ap is not null then
    select t.id into v_area from iara.territories t where t.kind = 'AREA_PONDERACAO' and t.name ilike 'AP ' || lpad(v_ap, 3, '0') || '%' limit 1;
  elsif v_unit is null then
    -- região pelo nome de um dos bairros ("AP 001 · Iguatemi, Floriano e área rural" → "iguatemi", "floriano", "area rural")
    select t.id into v_area from iara.territories t
    cross join lateral regexp_split_to_table(split_part(t.name, '·', 2), ' *(/|,| e ) *') pedaco
    where t.kind = 'AREA_PONDERACAO' and length(iara.oraculo_palavras(pedaco)) >= 6
      and v_n like '% ' || iara.oraculo_palavras(pedaco) || ' %'
    order by length(pedaco) desc limit 1;
  end if;
  return jsonb_build_object('unidade', v_unit, 'area', v_area);
end $$;

-- os números de um tópico, na cidade, numa unidade ou numa região (unidades da região)
create or replace function iara.oraculo_numeros(p_topico text, p_unit integer, p_area integer) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_units integer[];
  v_nome text;
  n jsonb := '[]';
  v_presenca numeric;
begin
  if p_unit is not null then
    v_units := array[p_unit];
    select short_name into v_nome from iara.education_units where id = p_unit;
  elsif p_area is not null then
    v_units := array(select id from iara.education_units where macro_territory_id = p_area);
    select name into v_nome from iara.territories where id = p_area;
  else
    v_units := array(select id from iara.education_units);
    v_nome := 'Maringá';
  end if;

  case p_topico
  when 'matriculas' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Alunos matriculados', 'valor', (select count(*) from iara.enrollments where status = 'ACTIVE' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Turmas', 'valor', (select count(*) from iara.classes where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Matrículas no Censo Escolar 2025', 'valor', (select sum(public_enrollments) from iara.education_units where id = any (v_units))));
  when 'fila' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Crianças na fila de espera', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Na fila da creche', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and grade_level_id = 1 and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Com oferta de vaga em aberto', 'valor', (select count(*) from iara.waiting_list_entries where status = 'OFFERED' and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Espera média (dias)', 'valor', (select round(avg(v_hoje - entered_at::date)) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any (v_units))));
  when 'vagas' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Vagas que podem ser oferecidas', 'valor', (select sum(offerable_vacancies_count) from iara.classes where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Turmas com vaga', 'valor', (select count(*) from iara.classes where offerable_vacancies_count > 0 and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Vagas de creche', 'valor', (select sum(offerable_vacancies_count) from iara.classes where grade_level_id = 1 and unit_id = any (v_units))));
  when 'creche' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Vagas de creche', 'valor', (select coalesce(sum(offerable_vacancies_count), 0) from iara.classes where grade_level_id = 1 and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Crianças esperando creche', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and grade_level_id = 1 and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Matriculados na creche', 'valor', (select count(*) from iara.enrollments e join iara.classes c on c.id = e.class_id where e.status = 'ACTIVE' and c.grade_level_id = 1 and e.unit_id = any (v_units))));
  when 'frequencia' then
    with reg as (select r.id, r.class_id from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data >= v_hoje - 30 and c.unit_id = any (v_units)),
         poss as (select sum((select count(*) from iara.enrollments e where e.class_id = reg.class_id and e.status = 'ACTIVE')) n from reg),
         fal as (select count(*) n from iara.frequencia_faltas f join reg on reg.id = f.registro_id)
    select round(100.0 - 100.0 * fal.n / nullif(poss.n, 0), 1) into v_presenca from poss, fal;
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Presença nos últimos 30 dias', 'valor', v_presenca, 'sufixo', '%', 'casas', 1),
      jsonb_build_object('rotulo', 'Alunos em alerta de frequência', 'valor', (select count(*) from iara.frequencia_alertas where situacao <> 'RESOLVIDO' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Casos de busca ativa abertos', 'valor', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and unit_id = any (v_units))));
  when 'ocorrencias' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Ocorrências nos últimos 90 dias', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Graves', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and gravidade = 'GRAVE' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Com violência', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and cardinality(violencia) > 0 and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Em aberto', 'valor', (select count(*) from iara.ocorrencias where situacao <> 'ENCERRADA' and tipo <> 'ELOGIO' and unit_id = any (v_units))));
  when 'profissionais' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Profissionais', 'valor', (select count(*) from iara.staff where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Professores', 'valor', (select count(*) from iara.staff where role = 'PROFESSOR' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Educadores infantis', 'valor', (select count(*) from iara.staff where role = 'EDUCADOR' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Auxiliares e AEE', 'valor', (select count(*) from iara.staff where role in ('AUXILIAR', 'AEE') and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Com pós-graduação', 'valor', (select round(100.0 * count(*) filter (where iara.formacao_nivel(escolaridade) >= 4) / nullif(count(*) filter (where iara.formacao_nivel(escolaridade) is not null), 0))
                                                                  from iara.staff where role in ('PROFESSOR', 'EDUCADOR', 'AEE') and unit_id = any (v_units)), 'sufixo', '%'));
  when 'transporte' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Rotas ativas', 'valor', (select count(*) from iara.transporte_rotas where situacao = 'ATIVA' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Alunos transportados', 'valor', (select count(*) from iara.transporte_alunos ta join iara.transporte_rotas r on r.id = ta.rota_id where ta.fim is null and r.unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Viagens não realizadas (30 dias)', 'valor', (select count(*) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id
                                                                                where v.situacao = 'NAO_REALIZADA' and v.data >= v_hoje - 30 and r.unit_id = any (v_units))));
  when 'alfabetizacao' then
    n := (with so as (select distinct on (x.student_id) x.student_id, x.nivel, x.class_id,
                             ((extract(year from age(x.data, s.birth_date)) * 12 + extract(month from age(x.data, s.birth_date))))::int meses
                      from iara.alfabetizacao_sondagens x join iara.students s on s.id = x.student_id
                      join iara.classes c on c.id = x.class_id
                      where x.ano = extract(year from v_hoje)::int and c.unit_id = any (v_units) order by x.student_id, x.data desc),
               sx as (select iara.alfa_situacao_idade(nivel, meses) sit from so)
          select jsonb_build_array(
            jsonb_build_object('rotulo', 'Crianças avaliadas', 'valor', count(*)),
            jsonb_build_object('rotulo', 'No nível esperado ou acima', 'valor', round(100.0 * count(*) filter (where sit <> 'ABAIXO') / nullif(count(*), 0)), 'sufixo', '%'),
            jsonb_build_object('rotulo', 'Abaixo do esperado para a idade', 'valor', count(*) filter (where sit = 'ABAIXO')))
          from sx);
  when 'busca_ativa' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Casos de busca ativa abertos', 'valor', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Urgentes', 'valor', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and urgente and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Crianças que voltaram à escola', 'valor', (select count(*) from iara.busca_ativa_casos where situacao = 'RETORNOU' and unit_id = any (v_units))));
  when 'unidades' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Unidades', 'valor', cardinality(v_units)),
      jsonb_build_object('rotulo', 'CMEIs', 'valor', (select count(*) from iara.education_units where unit_type = 'CMEI' and id = any (v_units))),
      jsonb_build_object('rotulo', 'Escolas', 'valor', (select count(*) from iara.education_units where unit_type = 'ESCOLA' and id = any (v_units))));
  when 'cadastros' then
    n := (with al as (select cardinality(iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null))) = 0 ok
                      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = any (v_units))
          select jsonb_build_array(
            jsonb_build_object('rotulo', 'Cadastros de alunos completos', 'valor', round(100.0 * count(*) filter (where ok) / nullif(count(*), 0), 1), 'sufixo', '%', 'casas', 1),
            jsonb_build_object('rotulo', 'Cadastros a completar', 'valor', count(*) filter (where not ok)))
          from al);
  else  -- visão geral
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Unidades', 'valor', cardinality(v_units)),
      jsonb_build_object('rotulo', 'Alunos matriculados', 'valor', (select count(*) from iara.enrollments where status = 'ACTIVE' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Crianças na fila de espera', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Vagas que podem ser oferecidas', 'valor', (select sum(offerable_vacancies_count) from iara.classes where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Profissionais', 'valor', (select count(*) from iara.staff where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Ocorrências nos últimos 90 dias', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any (v_units))));
    p_topico := 'visao_geral';
  end case;
  return jsonb_build_object('topico', p_topico, 'recorte', v_nome, 'unidade', p_unit, 'area', p_area, 'numeros', n,
    'nota', 'Dados da demonstração do IARA Educa (Censo Escolar 2025 para as matrículas oficiais). Só números agregados.');
end $$;

-- ferramenta do Oráculo e do servidor MCP. p: topico, unidade (id ou nome), regiao (id, "AP 017" ou nome)
create or replace function api.oraculo_dados(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer;
  v_area integer;
begin
  perform iara.require_perm('oraculo.prefeito');
  if coalesce(p ->> 'unidade', '') ~ '^\d+$' then
    v_unit := (p ->> 'unidade')::int;
  elsif coalesce(p ->> 'unidade', '') <> '' then
    v_unit := (iara.oraculo_recorte(p ->> 'unidade') ->> 'unidade')::int;
  end if;
  if coalesce(p ->> 'regiao', '') ~ '^\d+$' then
    v_area := (p ->> 'regiao')::int;
  elsif coalesce(p ->> 'regiao', '') <> '' then
    v_area := coalesce((iara.oraculo_recorte(p ->> 'regiao') ->> 'area')::int,
                       (select id from iara.territories where kind = 'AREA_PONDERACAO' and iara.norm(name) like '%' || iara.norm(p ->> 'regiao') || '%' limit 1));
  end if;
  return iara.oraculo_numeros(coalesce(nullif(p ->> 'topico', ''), 'visao_geral'), v_unit, v_area);
end $$;

-- sem a chave da Anthropic: palavras da pergunta → tópico e recorte → números → resposta em português
create or replace function api.oraculo_perguntar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  v_n text := iara.norm(coalesce(p ->> 'pergunta', ''));
  v_topico text;
  v_rec jsonb := iara.oraculo_recorte(p ->> 'pergunta');
  r jsonb;
  v_texto text;
  x jsonb;
  v_partes text[] := '{}';
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then
    raise exception 'Faça uma pergunta.' using errcode = '22023';
  end if;
  v_topico := case
    when v_n ~ 'creche|bercario' then 'creche'
    when v_n ~ 'fila|espera|aguard' then 'fila'
    when v_n ~ 'vaga' then 'vagas'
    when v_n ~ 'frequenc|presenc|falta|ausen' then 'frequencia'
    when v_n ~ 'ocorrenc|violenc|bullying|briga|acidente|indisciplina' then 'ocorrencias'
    when v_n ~ 'professor|profissiona|servidor|educador|auxiliar|docente|funcionari' then 'profissionais'
    when v_n ~ 'transporte|onibus|rota|van|veicul|motorista' then 'transporte'
    when v_n ~ 'alfabetiz|leitura|escrita|sondagem|ler e escrever' then 'alfabetizacao'
    when v_n ~ 'busca ativa|evasao|abandono' then 'busca_ativa'
    when v_n ~ 'cadastr|documento' then 'cadastros'
    when v_n ~ 'matricul|aluno|estudante' then 'matriculas'
    when v_n ~ 'unidade|escola|cmei' then 'unidades'
    else 'visao_geral' end;
  r := iara.oraculo_numeros(v_topico, (v_rec ->> 'unidade')::int, (v_rec ->> 'area')::int);
  for x in select * from jsonb_array_elements(r -> 'numeros') loop
    v_partes := v_partes || ((x ->> 'rotulo') || ': '
                 || iara.num_br((x ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', ''));
  end loop;
  v_texto := 'Em ' || (r ->> 'recorte') || ' — ' || array_to_string(v_partes, '; ') || '.';
  insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
  values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', v_texto,
          jsonb_build_array(jsonb_build_object('topico', v_topico, 'unidade', v_rec -> 'unidade', 'area', v_rec -> 'area')), iara.demo_mode());
  return r || jsonb_build_object('pergunta', v_perg, 'resposta', v_texto, 'modo', 'REGRAS');
end $$;

-- o gateway registra as respostas do Claude (modo CLAUDE)
create or replace function api.oraculo_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
  values (iara.current_user_id(), left(coalesce(p ->> 'pergunta', ''), 2000), coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'CLAUDE',
          left(coalesce(p ->> 'resposta', ''), 8000), coalesce(p -> 'ferramentas', '[]'), iara.demo_mode());
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.oraculo_historico(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'criado_em', criado_em, 'pergunta', pergunta, 'canal', canal, 'modo', modo, 'resposta', resposta)
                    order by criado_em desc), '[]')
          from (select * from iara.oraculo_perguntas where user_id = iara.current_user_id() order by criado_em desc limit 20) q);
end $$;

-- segunda ferramenta: nomes das unidades e das regiões, para o Claude achar a unidade citada (busca opcional)
create or replace function api.oraculo_unidades(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_b text := iara.norm(coalesce(p ->> 'busca', ''));
begin
  perform iara.require_perm('oraculo.prefeito');
  return jsonb_build_object(
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.short_name, 'tipo', u.unit_type, 'regiao', t.name) order by u.short_name), '[]')
                 from (select * from iara.education_units where v_b = '' or iara.norm(short_name || ' ' || name) like '%' || v_b || '%' order by short_name limit 60) u
                 left join iara.territories t on t.id = u.macro_territory_id),
    'regioes', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.name) order by t.sort), '[]')
                from iara.territories t where t.kind = 'AREA_PONDERACAO' and (v_b = '' or iara.norm(t.name) like '%' || v_b || '%')),
    'total_unidades', (select count(*) from iara.education_units));
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('oraculo_perguntas', 'pergunta', 'INTERNO', 'gestão', 'perguntas do Prefeito ao Oráculo', 'só o próprio Prefeito vê; respostas só com números agregados')
on conflict (tabela, coluna) do nothing;

revoke all on function iara.oraculo_palavras(text), iara.oraculo_recorte(text), iara.oraculo_numeros(text, integer, integer) from public;

commit;
