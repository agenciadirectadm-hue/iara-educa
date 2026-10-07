-- IARA Educa — 064 · Conselho de classe, resultado final e histórico escolar (Sprint 4)
-- Conselho de classe por bimestre (análise da turma, deliberação e encaminhamentos por aluno, ata) e conselho final, que fecha o
-- resultado do ano. Regras propostas (item 32 das pendências, a validar com a SEDUC):
--  · educação infantil: progressão, sem retenção (LDB, art. 31, I);
--  · 1º e 2º ano: progressão — bloco pedagógico do 1º ao 3º ano (Res. CNE/CEB nº 7/2010, art. 30, §1º); frequência abaixo de 75% vai ao conselho;
--  · 3º ao 5º ano e EJA: aprovado com média anual ≥ média mínima em todos os componentes e frequência ≥ 75% (LDB, art. 24, VI);
--    caso contrário, o conselho delibera (aprovado pelo conselho ou retido), sempre com justificativa.
-- Histórico escolar com os anos cursados (na rede ou fora dela) e o ano em curso; emitido como documento com código e QR (tipo HISTORICO).
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('conselho.manage', 'Conduzir o conselho de classe e fechar o resultado final da turma', true)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, 'conselho.manage' from (values ('DIRETOR_UNIDADE'), ('SECRETARIA_ESCOLAR')) v(r)
on conflict do nothing;

-- 1. Estrutura ----------------------------------------------------------------------------------------------------------------------
create table if not exists iara.conselhos_classe (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references iara.classes(id) on delete cascade,
  unit_id integer,
  ano smallint not null,
  etapa smallint not null check (etapa between 1 and 5),   -- 1 a 4: bimestre; 5: conselho final
  data date not null default current_date,
  participantes text,
  ata text,
  situacao text not null default 'ABERTO' check (situacao in ('ABERTO', 'CONCLUIDO')),
  registrado_por_label text,
  concluido_por_label text,
  concluido_em timestamptz,
  reaberto_motivo text,
  created_at timestamptz not null default now(),
  alterado_em timestamptz,
  is_demo boolean not null default false,
  unique (class_id, ano, etapa)
);
create table if not exists iara.conselho_deliberacoes (
  conselho_id uuid not null references iara.conselhos_classe(id) on delete cascade,
  student_id uuid not null references iara.students(id) on delete cascade,
  situacao_calculada text,
  situacao text check (situacao in ('APROVADO', 'APROVADO_CONSELHO', 'PROGRESSAO', 'RETIDO')),
  justificativa text,
  encaminhamentos text[] not null default '{}',
  observacao text,
  comunicar_familia boolean not null default true,
  atualizado_por_label text,
  atualizado_em timestamptz not null default now(),
  is_demo boolean not null default false,
  primary key (conselho_id, student_id)
);
alter table iara.conselho_deliberacoes drop constraint if exists conselho_encaminhamentos_validos;
alter table iara.conselho_deliberacoes add constraint conselho_encaminhamentos_validos check (encaminhamentos <@ array['REFORCO', 'CONVERSA_FAMILIA', 'PLANO_INTERVENCAO',
  'AVALIACAO_AEE', 'BUSCA_ATIVA', 'APOIO_PSICOPEDAGOGICO', 'ELOGIO', 'REDE_APOIO']::text[]);

create table if not exists iara.resultados_finais (
  student_id uuid not null references iara.students(id) on delete cascade,
  ano smallint not null,
  grade_code text not null,
  serie text not null,
  unit_id integer references iara.education_units(id),
  unidade_nome text not null,
  rede text not null default 'MUNICIPAL' check (rede in ('MUNICIPAL', 'ESTADUAL', 'PARTICULAR', 'OUTRO_MUNICIPIO')),
  turma text,
  carga_horaria integer,
  dias_letivos integer,
  frequencia_pct numeric(5, 1),
  componentes jsonb not null default '[]',
  parecer text,
  situacao text not null check (situacao in ('APROVADO', 'APROVADO_CONSELHO', 'PROGRESSAO', 'RETIDO', 'TRANSFERIDO')),
  observacao text,
  conselho_id uuid references iara.conselhos_classe(id) on delete set null,
  fechado_por_label text,
  fechado_em timestamptz not null default now(),
  is_demo boolean not null default false,
  primary key (student_id, ano)
);
create index if not exists resultados_finais_unit_idx on iara.resultados_finais (unit_id, ano);
alter table iara.conselhos_classe enable row level security;
alter table iara.conselho_deliberacoes enable row level security;
alter table iara.resultados_finais enable row level security;

alter table iara.declaracoes drop constraint if exists declaracoes_tipo_check;
alter table iara.declaracoes add constraint declaracoes_tipo_check check (tipo in ('MATRICULA', 'FREQUENCIA', 'INSCRICAO_FILA', 'HISTORICO'));

-- 2. Regras ------------------------------------------------------------------------------------------------------------------------
create or replace function iara.grade_ordem(p text) returns integer
language sql immutable as $$ select array_position(array['CRECHE', 'PRE', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], p) $$;

-- situação calculada do ano (prévia enquanto houver bimestre sem nota)
create or replace function iara.situacao_calculada(p_student uuid, p_ano smallint default 2026) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_grade text;
  v_min numeric := iara.media_minima();
  v_freq numeric;
  v_fmin numeric;
  v_medias jsonb;
  v_abaixo text[];
  v_completo boolean;
  v_sit text;
  v_mot text[] := '{}';
begin
  select gl.code into v_grade from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  where e.student_id = p_student and e.status = 'ACTIVE' limit 1;
  if v_grade is null then return null; end if;
  v_freq := (iara.frequencia_resumo(p_student, null, null) ->> 'percentual')::numeric;
  v_fmin := iara.freq_minima(v_grade);
  select coalesce(jsonb_object_agg(z.componente, z.media), '{}'), coalesce(array_agg(z.componente) filter (where z.media < v_min), '{}'), coalesce(bool_and(z.n = 4), false)
  into v_medias, v_abaixo, v_completo
  from (select m.componente, round(avg(iara.nota_final(n.nota, n.recuperacao)), 1) media, count(n.nota) n
        from iara.matriz_curricular m left join iara.notas n on n.student_id = p_student and n.ano = p_ano and n.componente = m.componente
        where m.grade_code = v_grade group by m.componente) z;
  if v_grade in ('CRECHE', 'PRE') then
    v_sit := 'PROGRESSAO'; v_mot := array['Educação infantil: avaliação sem retenção (LDB, art. 31, I)'];
    v_completo := true;
  elsif v_freq is not null and v_freq < v_fmin then
    v_sit := 'CONSELHO'; v_mot := array[format('Frequência de %s%% abaixo de %s%% (LDB, art. 24, VI)', replace(v_freq::text, '.', ','), v_fmin::int)];
  elsif v_grade in ('EF1', 'EF2') then
    v_sit := 'PROGRESSAO'; v_mot := array['Bloco pedagógico do 1º ao 3º ano (Res. CNE/CEB nº 7/2010, art. 30, §1º)'];
  elsif cardinality(v_abaixo) = 0 then
    v_sit := 'APROVADO';
  else
    v_sit := 'CONSELHO'; v_mot := array[format('Média anual abaixo de %s em: %s', replace(v_min::text, '.', ','), array_to_string(v_abaixo, ', '))];
  end if;
  return jsonb_build_object('grade', v_grade, 'situacao', v_sit, 'motivos', to_jsonb(v_mot), 'medias', v_medias, 'abaixo', to_jsonb(v_abaixo),
    'frequencia', v_freq, 'frequencia_minima', v_fmin, 'completo', v_completo, 'media_minima', v_min);
end $$;

create or replace function iara.conselho_acesso(p_class uuid, p_conduzir boolean) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select case when p_conduzir then iara.has_perm('conselho.manage') and iara.my_scope() = 'UNIT' and exists (select 1 from iara.classes c where c.id = p_class and c.unit_id = iara.my_unit())
              else iara.has_perm('notas.read') and ((iara.my_role() not in ('PROFESSOR', 'PROFESSOR_AEE') and exists (select 1 from iara.classes c where c.id = p_class and iara.can_access_unit(c.unit_id)))
                                                    or p_class = any (iara.minhas_turmas())) end
$$;

-- 3. Conselho de classe -------------------------------------------------------------------------------------------------------------
create or replace function api.conselho_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
  v_etapa smallint := coalesce(nullif(p ->> 'etapa', '')::smallint, greatest(iara.bimestre_atual() - 1, 1)::smallint);
  v_min numeric := iara.media_minima();
  b iara.bimestres;
  k iara.conselhos_classe;
  v_grade text;
  v_alunos jsonb;
begin
  if not iara.conselho_acesso(v_class, false) then raise exception 'Turma fora do seu escopo.' using errcode = '42501'; end if;
  if v_etapa not between 1 and 5 then raise exception 'Etapa inválida.' using errcode = '22023'; end if;
  select * into b from iara.bimestres where ano = 2026 and numero = least(v_etapa, 4);
  select * into k from iara.conselhos_classe where class_id = v_class and ano = 2026 and etapa = v_etapa;
  select gl.code into v_grade from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id where c.id = v_class;
  select coalesce(jsonb_agg(x order by x ->> 'nome'), '[]') into v_alunos from (
    select jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'aee', s.aee_status,
      'medias', (select coalesce(jsonb_object_agg(m.componente, (select case when v_etapa = 5 then round(avg(iara.nota_final(n.nota, n.recuperacao)), 1)
                                                                             else max(iara.nota_final(n.nota, n.recuperacao)) end
                                                                  from iara.notas n where n.student_id = s.id and n.ano = 2026 and n.componente = m.componente
                                                                    and (v_etapa = 5 or n.bimestre = v_etapa))), '{}')
                 from iara.matriz_curricular m where m.grade_code = v_grade),
      'frequencia', (iara.frequencia_resumo(s.id, case when v_etapa < 5 then b.inicio end, case when v_etapa < 5 then least(b.fim, iara.hoje_local()) end) ->> 'percentual')::numeric,
      'alfabetizacao', (select a.nivel from iara.alfabetizacao_sondagens a where a.student_id = s.id and a.ano = 2026 order by a.data desc limit 1),
      'plano', exists (select 1 from iara.planos_intervencao pl where pl.student_id = s.id and pl.ano = 2026 and pl.situacao = 'ATIVO'),
      'ocorrencias', (select count(*) from iara.ocorrencias o where o.student_id = s.id and o.situacao <> 'ENCERRADA' and o.tipo <> 'ELOGIO'),
      'busca_ativa', exists (select 1 from iara.busca_ativa_casos bc where bc.student_id = s.id and bc.situacao <> 'ENCERRADO'),
      'calculada', case when v_etapa = 5 then iara.situacao_calculada(s.id, 2026::smallint) end,
      'deliberacao', (select to_jsonb(d) - 'conselho_id' - 'student_id' from iara.conselho_deliberacoes d where d.conselho_id = k.id and d.student_id = s.id)) x
    from iara.enrollments e join iara.students s on s.id = e.student_id where e.class_id = v_class and e.status = 'ACTIVE') z(x);
  -- abaixo da média no recorte (bimestre ou ano)
  select coalesce(jsonb_agg(a || jsonb_build_object('abaixo', (select count(*) from jsonb_each_text(a -> 'medias') m where m.value::numeric < v_min))), '[]')
  into v_alunos from jsonb_array_elements(v_alunos) a;
  return jsonb_build_object('class_id', v_class, 'etapa', v_etapa, 'ano', 2026, 'grade', v_grade, 'media_minima', v_min,
    'turma', (select c.class_name || ' · ' || u.short_name from iara.classes c join iara.education_units u on u.id = c.unit_id where c.id = v_class),
    'bimestre', case when v_etapa < 5 then jsonb_build_object('inicio', b.inicio, 'fim', b.fim, 'encerrado', b.fim < iara.hoje_local()) end,
    'conselho', case when k.id is not null then to_jsonb(k) end,
    'componentes', (select coalesce(jsonb_agg(jsonb_build_object('nome', m.componente,
        'media_turma', (select round(avg((a -> 'medias' ->> m.componente)::numeric), 1) from jsonb_array_elements(v_alunos) a),
        'abaixo', (select count(*) from jsonb_array_elements(v_alunos) a where (a -> 'medias' ->> m.componente)::numeric < v_min)) order by m.ordem), '[]')
      from iara.matriz_curricular m where m.grade_code = v_grade),
    'alunos', v_alunos,
    'pode_conduzir', iara.conselho_acesso(v_class, true) and coalesce(k.situacao, 'ABERTO') = 'ABERTO',
    'pode_reabrir', iara.conselho_acesso(v_class, true) and k.situacao = 'CONCLUIDO',
    'pode_observar', v_class = any (iara.minhas_turmas()) or iara.conselho_acesso(v_class, true),
    'final_liberado', v_etapa < 5 or (select fim from iara.bimestres where ano = 2026 and numero = 4) < iara.hoje_local(),
    'regras', 'Proposta a validar (item 32): educação infantil e 1º/2º ano em progressão; do 3º ano em diante, média anual e frequência de 75% (LDB, art. 24, VI).');
end $$;

create or replace function api.conselho_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
  v_etapa smallint := (p ->> 'etapa')::smallint;
  v_conduzir boolean := iara.conselho_acesso(v_class, true);
  v_prof boolean := v_class = any (iara.minhas_turmas());
  k iara.conselhos_classe;
  d jsonb;
  x record;
  v_calc jsonb;
  v_sit text;
  v_grade text;
  v_n integer := 0;
  v_unit integer;
begin
  if not (v_conduzir or v_prof) then raise exception 'Só a direção, a secretaria escolar e os professores da turma registram no conselho.' using errcode = '42501'; end if;
  if v_etapa not between 1 and 5 then raise exception 'Etapa inválida.' using errcode = '22023'; end if;
  select c.unit_id, gl.code into v_unit, v_grade from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id where c.id = v_class;
  select * into k from iara.conselhos_classe where class_id = v_class and ano = 2026 and etapa = v_etapa for update;
  if coalesce((p ->> 'reabrir')::boolean, false) then
    if not v_conduzir or k.situacao <> 'CONCLUIDO' then raise exception 'Só a direção reabre um conselho concluído.' using errcode = '42501'; end if;
    if length(btrim(coalesce(p ->> 'motivo', ''))) < 10 then raise exception 'Informe o motivo da reabertura (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    update iara.conselhos_classe set situacao = 'ABERTO', reaberto_motivo = btrim(p ->> 'motivo'), concluido_em = null, alterado_em = now() where id = k.id;
    if v_etapa = 5 then delete from iara.resultados_finais where conselho_id = k.id; end if;
    perform iara.audit_event('CONSELHO_CLASSE', 'class', v_class::text, v_unit, format('Conselho de classe (%s) reaberto: %s', case when v_etapa = 5 then 'final' else v_etapa || 'º bimestre' end, btrim(p ->> 'motivo')));
    return api.conselho_turma(jsonb_build_object('class_id', v_class, 'etapa', v_etapa));
  end if;
  if k.situacao = 'CONCLUIDO' then raise exception 'Conselho concluído: para alterar, a direção reabre com motivo.' using errcode = '22023'; end if;
  if k.id is null then
    insert into iara.conselhos_classe (class_id, unit_id, ano, etapa, registrado_por_label) values (v_class, v_unit, 2026, v_etapa, iara.my_label()) returning * into k;
  end if;
  if v_conduzir then
    update iara.conselhos_classe set data = coalesce(nullif(p ->> 'data', '')::date, data), participantes = coalesce(nullif(btrim(coalesce(p ->> 'participantes', '')), ''), participantes),
           ata = coalesce(nullif(btrim(coalesce(p ->> 'ata', '')), ''), ata), alterado_em = now()
    where id = k.id returning * into k;
  end if;
  for d in select * from jsonb_array_elements(coalesce(p -> 'deliberacoes', '[]')) loop
    if not exists (select 1 from iara.enrollments e where e.student_id = (d ->> 'student_id')::uuid and e.class_id = v_class and e.status = 'ACTIVE') then
      raise exception 'Aluno fora da turma.' using errcode = '22023';
    end if;
    v_sit := nullif(d ->> 'situacao', '');
    if v_sit is not null and not v_conduzir then raise exception 'A situação final é deliberada pela direção no conselho.' using errcode = '42501'; end if;
    if v_sit is not null then
      if v_etapa <> 5 then raise exception 'Situação final só no conselho final.' using errcode = '22023'; end if;
      v_calc := iara.situacao_calculada((d ->> 'student_id')::uuid, 2026::smallint);
      if v_sit not in ('APROVADO', 'APROVADO_CONSELHO', 'PROGRESSAO', 'RETIDO') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
      if v_sit = 'RETIDO' and v_grade in ('CRECHE', 'PRE') then raise exception 'Na educação infantil não há retenção (LDB, art. 31, I).' using errcode = '22023'; end if;
      if v_sit = 'RETIDO' and v_grade in ('EF1', 'EF2') and coalesce((v_calc ->> 'frequencia')::numeric, 100) >= 75 then
        raise exception 'No 1º e no 2º ano (bloco pedagógico) a retenção só cabe por frequência abaixo de 75%%.' using errcode = '22023';
      end if;
      if v_sit = 'APROVADO' and v_calc ->> 'situacao' = 'CONSELHO' then raise exception 'Com pendência de nota ou frequência, use “aprovado pelo conselho”, com justificativa.' using errcode = '22023'; end if;
      if v_sit in ('APROVADO_CONSELHO', 'RETIDO') and length(btrim(coalesce(d ->> 'justificativa', ''))) < 15 then
        raise exception 'Justifique a deliberação (mínimo de 15 caracteres).' using errcode = '22023';
      end if;
    end if;
    insert into iara.conselho_deliberacoes (conselho_id, student_id, situacao_calculada, situacao, justificativa, encaminhamentos, observacao, comunicar_familia, atualizado_por_label)
    values (k.id, (d ->> 'student_id')::uuid, case when v_etapa = 5 then iara.situacao_calculada((d ->> 'student_id')::uuid, 2026::smallint) ->> 'situacao' end,
            v_sit, nullif(btrim(coalesce(d ->> 'justificativa', '')), ''),
            coalesce((select array_agg(distinct y) from jsonb_array_elements_text(coalesce(d -> 'encaminhamentos', '[]')) y), '{}'),
            nullif(btrim(coalesce(d ->> 'observacao', '')), ''), coalesce((d ->> 'comunicar_familia')::boolean, true), iara.my_label())
    on conflict (conselho_id, student_id) do update set
      situacao = case when v_conduzir then excluded.situacao else iara.conselho_deliberacoes.situacao end,
      justificativa = case when v_conduzir then excluded.justificativa else iara.conselho_deliberacoes.justificativa end,
      encaminhamentos = case when v_conduzir then excluded.encaminhamentos else iara.conselho_deliberacoes.encaminhamentos end,
      comunicar_familia = case when v_conduzir then excluded.comunicar_familia else iara.conselho_deliberacoes.comunicar_familia end,
      situacao_calculada = coalesce(excluded.situacao_calculada, iara.conselho_deliberacoes.situacao_calculada),
      observacao = coalesce(excluded.observacao, iara.conselho_deliberacoes.observacao), atualizado_por_label = excluded.atualizado_por_label, atualizado_em = now();
  end loop;

  if coalesce((p ->> 'concluir')::boolean, false) then
    if not v_conduzir then raise exception 'Só a direção e a secretaria escolar concluem o conselho.' using errcode = '42501'; end if;
    if length(btrim(coalesce(k.participantes, ''))) < 5 or length(btrim(coalesce(k.ata, ''))) < 20 then
      raise exception 'Registre os participantes e a ata (síntese da análise da turma) antes de concluir.' using errcode = '22023';
    end if;
    if v_etapa < 5 and (select fim from iara.bimestres where ano = 2026 and numero = v_etapa) >= iara.hoje_local() then
      raise exception 'O bimestre ainda não terminou.' using errcode = '22023';
    end if;
    if v_etapa = 5 then
      if (select fim from iara.bimestres where ano = 2026 and numero = 4) >= iara.hoje_local() then
        raise exception 'O conselho final só fecha depois do 4º bimestre; até lá, use a prévia do resultado.' using errcode = '22023';
      end if;
      -- todos os alunos com situação: calculada ou deliberada
      for x in select e.student_id, iara.situacao_calculada(e.student_id, 2026::smallint) calc, d2.situacao deliberada, d2.justificativa
               from iara.enrollments e left join iara.conselho_deliberacoes d2 on d2.conselho_id = k.id and d2.student_id = e.student_id
               where e.class_id = v_class and e.status = 'ACTIVE' loop
        if not coalesce((x.calc ->> 'completo')::boolean, false) then raise exception 'Há notas do ano por lançar nesta turma.' using errcode = '22023'; end if;
        if x.deliberada is null and x.calc ->> 'situacao' = 'CONSELHO' then raise exception 'Delibere todos os alunos indicados ao conselho.' using errcode = '22023'; end if;
        insert into iara.resultados_finais (student_id, ano, grade_code, serie, unit_id, unidade_nome, rede, turma, carga_horaria, dias_letivos, frequencia_pct,
                                            componentes, parecer, situacao, observacao, conselho_id, fechado_por_label)
        select x.student_id, 2026, gl.code, gl.name, c.unit_id, u.name, 'MUNICIPAL', c.class_name, 800, 200, (x.calc ->> 'frequencia')::numeric,
               (select coalesce(jsonb_agg(jsonb_build_object('nome', m.componente, 'media', (x.calc -> 'medias' ->> m.componente)::numeric, 'aulas_semana', m.aulas_semana) order by m.ordem), '[]')
                from iara.matriz_curricular m where m.grade_code = gl.code),
               case when gl.code in ('CRECHE', 'PRE') then (select pa.texto from iara.pareceres pa where pa.student_id = x.student_id and pa.ano = 2026 order by pa.bimestre desc limit 1) end,
               coalesce(x.deliberada, x.calc ->> 'situacao'), x.justificativa, k.id, iara.my_label()
        from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id join iara.education_units u on u.id = c.unit_id where c.id = v_class
        on conflict (student_id, ano) do update set situacao = excluded.situacao, componentes = excluded.componentes, frequencia_pct = excluded.frequencia_pct,
           observacao = excluded.observacao, conselho_id = excluded.conselho_id, fechado_por_label = excluded.fechado_por_label, fechado_em = now();
        v_n := v_n + 1;
      end loop;
    else
      -- encaminhamentos do bimestre: plano de intervenção aberto e aviso à família
      for x in select d2.*, s.full_name from iara.conselho_deliberacoes d2 join iara.students s on s.id = d2.student_id where d2.conselho_id = k.id loop
        if 'PLANO_INTERVENCAO' = any (x.encaminhamentos) and not exists (select 1 from iara.planos_intervencao pl where pl.student_id = x.student_id and pl.ano = 2026 and pl.situacao = 'ATIVO') then
          insert into iara.planos_intervencao (student_id, class_id, unit_id, ano, motivos, objetivo, acoes, responsavel_label, inicio, reavaliar_em, situacao, criado_por_label, is_demo)
          values (x.student_id, v_class, v_unit, 2026, array['Conselho de classe do ' || v_etapa || 'º bimestre'], 'Recuperar as aprendizagens apontadas no conselho de classe.',
                  coalesce(x.observacao, 'Ações definidas no conselho de classe.'), 'Professor(a) regente', iara.hoje_local(), iara.hoje_local() + 45, 'ATIVO', iara.my_label(), false);
        end if;
        if x.comunicar_familia and cardinality(x.encaminhamentos) > 0 then
          insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
          select 1, sg.guardian_id, x.student_id, 'PORTAL', 'CONSELHO_CLASSE', 'Conselho de classe do ' || v_etapa || 'º bimestre',
                 format('O conselho de classe acompanhou %s: %s. Em caso de dúvida, fale com a escola.', split_part(x.full_name, ' ', 1),
                        (select string_agg(case e when 'REFORCO' then 'participação no reforço escolar' when 'CONVERSA_FAMILIA' then 'a escola vai chamar a família para conversar'
                                                when 'PLANO_INTERVENCAO' then 'plano de apoio às aprendizagens' when 'AVALIACAO_AEE' then 'avaliação da equipe de inclusão (AEE)'
                                                when 'BUSCA_ATIVA' then 'acompanhamento da frequência' when 'APOIO_PSICOPEDAGOGICO' then 'apoio psicopedagógico'
                                                when 'ELOGIO' then 'parabéns pelo desempenho no bimestre' else 'apoio da rede' end, '; ') from unnest(x.encaminhamentos) e)),
                 'ENVIADA'
          from iara.student_guardians sg where sg.student_id = x.student_id and sg.end_date is null and coalesce(sg.can_receive_notifications, true)
            and not exists (select 1 from iara.guarda_restricoes r where r.student_id = x.student_id and r.guardian_id = sg.guardian_id and r.bloquear_portal and r.situacao = 'ATIVA');
        end if;
      end loop;
    end if;
    update iara.conselhos_classe set situacao = 'CONCLUIDO', concluido_por_label = iara.my_label(), concluido_em = now(), alterado_em = now() where id = k.id;
    perform iara.audit_event('CONSELHO_CLASSE', 'class', v_class::text, v_unit, format('Conselho de classe (%s) concluído%s.',
      case when v_etapa = 5 then 'final' else v_etapa || 'º bimestre' end, case when v_etapa = 5 then format('; resultado final de %s aluno(s)', v_n) else '' end));
  end if;
  return api.conselho_turma(jsonb_build_object('class_id', v_class, 'etapa', v_etapa));
end $$;

-- prévia do resultado final da unidade: quem vai ao conselho (frequência ou média) — dá tempo de agir antes do fim do ano
create or replace function api.resultado_previa(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('notas.read');
  if iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE') then raise exception 'Disponível para a direção e a SEDUC.' using errcode = '42501'; end if;
  if v_unit is null then raise exception 'Escolha a unidade.' using errcode = '22023'; end if;
  if not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  return (with al as (
      select e.class_id, c.class_name, gl.code, s.id, s.full_name, iara.situacao_calculada(s.id, 2026::smallint) calc
      from iara.enrollments e join iara.students s on s.id = e.student_id join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
      where e.unit_id = v_unit and e.status = 'ACTIVE')
    select jsonb_build_object('unit_id', v_unit, 'unidade', (select short_name from iara.education_units where id = v_unit),
      'resumo', (select jsonb_object_agg(sit, n) from (select calc ->> 'situacao' sit, count(*) n from al group by 1) z),
      'turmas', (select coalesce(jsonb_agg(jsonb_build_object('class_id', class_id, 'turma', class_name, 'alunos', n, 'conselho', nc,
                    'conselhos', (select jsonb_agg(jsonb_build_object('etapa', k.etapa, 'situacao', k.situacao) order by k.etapa) from iara.conselhos_classe k where k.class_id = z.class_id and k.ano = 2026))
                    order by class_name), '[]')
                 from (select class_id, class_name, count(*) n, count(*) filter (where calc ->> 'situacao' = 'CONSELHO') nc from al group by 1, 2) z),
      'conselho', (select coalesce(jsonb_agg(jsonb_build_object('student_id', id, 'nome', full_name, 'turma', class_name, 'class_id', class_id, 'motivos', calc -> 'motivos',
                     'frequencia', calc -> 'frequencia', 'abaixo', calc -> 'abaixo') order by class_name, full_name), '[]')
                   from al where calc ->> 'situacao' = 'CONSELHO'),
      'regras', 'Prévia com as notas lançadas até agora; regras propostas a validar (item 32).'));
end $$;

-- 4. Histórico escolar ------------------------------------------------------------------------------------------------------------
create or replace function iara.historico_json(p_student uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('aluno', s.full_name, 'nascimento', s.birth_date, 'registro', s.student_registry_number,
    'anos', (select coalesce(jsonb_agg(jsonb_build_object('ano', r.ano, 'serie', r.serie, 'grade', r.grade_code, 'unidade', r.unidade_nome, 'rede', r.rede, 'turma', r.turma,
                'carga_horaria', r.carga_horaria, 'dias_letivos', r.dias_letivos, 'frequencia', r.frequencia_pct, 'componentes', r.componentes, 'parecer', r.parecer,
                'situacao', r.situacao, 'observacao', r.observacao, 'is_demo', r.is_demo) order by r.ano), '[]')
             from iara.resultados_finais r where r.student_id = s.id),
    'em_curso', (select jsonb_build_object('ano', 2026, 'serie', gl.name, 'grade', gl.code, 'unidade', u.name, 'turma', c.class_name,
                   'calculada', iara.situacao_calculada(s.id, 2026::smallint))
                 from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id join iara.education_units u on u.id = e.unit_id
                 where e.student_id = s.id and e.status = 'ACTIVE' and not exists (select 1 from iara.resultados_finais r where r.student_id = s.id and r.ano = 2026) limit 1))
  from iara.students s where s.id = p_student
$$;

create or replace function api.historico_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v jsonb;
begin
  if not ((v_fam and v_student in (select iara.my_student_ids())) or iara.aluno_acesso(v_student, 'notas.read')) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  v := iara.historico_json(v_student);
  if v_fam and v -> 'em_curso' is not null then
    -- a família vê a situação do ano só como “em curso” (sem a prévia de conselho)
    v := jsonb_set(v, '{em_curso,calculada}', (v -> 'em_curso' -> 'calculada') - 'situacao' - 'motivos');
  end if;
  return v;
end $$;

create or replace function api.familia_historico(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(api.historico_aluno(jsonb_build_object('student_id', s.id)) || jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1))
            order by s.full_name), '[]')
          from iara.students s where s.id in (select iara.my_student_ids()));
end $$;

create or replace function iara.declaracoes_disponiveis(p_student uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_array()
    || case when exists (select 1 from iara.enrollments where student_id = p_student and status = 'ACTIVE')
            then jsonb_build_array('MATRICULA', 'FREQUENCIA') else '[]' end
    || case when exists (select 1 from iara.waiting_list_entries where student_id = p_student and status in ('WAITING', 'OFFERED', 'SUSPENDED'))
            then jsonb_build_array('INSCRICAO_FILA') else '[]' end
    || case when exists (select 1 from iara.resultados_finais where student_id = p_student) then jsonb_build_array('HISTORICO') else '[]' end
$$;

create or replace function api.declaracao_emitir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_tipo text := upper(coalesce(p ->> 'tipo', ''));
  v_fam boolean := iara.my_guardian() is not null;
  v_canal text := case when v_fam then coalesce(nullif(upper(p ->> 'canal'), ''), 'PORTAL') else 'UNIDADE' end;
  s iara.students;
  e record;
  w record;
  f jsonb;
  c jsonb;
  h jsonb;
  d iara.declaracoes;
  v_ano text := to_char(current_date, 'YYYY');
  v_nasc text;
  v_unit integer;
begin
  if not ((v_fam and v_student in (select iara.my_student_ids())) or (not v_fam and iara.has_perm('students.read') and iara.can_access_student(v_student)
          and iara.my_role() not in ('PROFESSOR', 'PROFESSOR_AEE'))) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  if v_canal not in ('PORTAL', 'IARA', 'WHATSAPP', 'UNIDADE') then v_canal := 'PORTAL'; end if;
  if not iara.declaracoes_disponiveis(v_student) ? v_tipo then
    raise exception '%', case v_tipo when 'INSCRICAO_FILA' then 'A criança não está na fila de espera.'
      when 'MATRICULA' then 'A criança não tem matrícula ativa na rede.' when 'FREQUENCIA' then 'A criança não tem matrícula ativa na rede.'
      when 'HISTORICO' then 'Ainda não há ano concluído para o histórico escolar.'
      else 'Tipo de declaração inválido.' end using errcode = '22023';
  end if;
  if (select count(*) from iara.declaracoes where student_id = v_student and emitida_em > now() - interval '1 day') >= 10 then
    raise exception 'Limite de 10 declarações por dia para esta criança.' using errcode = '22023';
  end if;
  select * into s from iara.students where id = v_student;
  v_nasc := to_char(s.birth_date, 'DD/MM/YYYY');
  c := jsonb_build_object('aluno', s.full_name, 'nascimento', s.birth_date, 'ano', v_ano, 'municipio', 'Maringá — PR',
                          'orgao', 'Secretaria Municipal de Educação de Maringá');
  if v_tipo in ('MATRICULA', 'FREQUENCIA', 'HISTORICO') then
    select en.unit_id, en.start_date, c2.class_name, c2.shift, gl.name serie, u.name unidade, u.inep_code, u.address_line, u.director_name into e
    from iara.enrollments en join iara.classes c2 on c2.id = en.class_id join iara.grade_levels gl on gl.id = c2.grade_level_id
    join iara.education_units u on u.id = en.unit_id where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
    v_unit := e.unit_id;
    if e.unidade is not null then
      c := c || jsonb_build_object('unidade', e.unidade, 'inep', e.inep_code, 'endereco_unidade', e.address_line, 'turma', e.class_name, 'serie', e.serie,
                                   'turno', initcap(lower(e.shift)), 'diretor', e.director_name);
    end if;
    if v_tipo = 'MATRICULA' then
      c := c || jsonb_build_object('titulo', 'Declaração de matrícula', 'resumo', format('Matrícula ativa em %s — %s, turno %s (%s).', e.unidade, e.serie, lower(e.shift), v_ano),
        'texto', format('Declaramos, para os devidos fins, que %s, nascido(a) em %s, está regularmente matriculado(a) no(a) %s, na turma %s (%s), turno %s, no ano letivo de %s.',
                        s.full_name, v_nasc, e.unidade, e.class_name, e.serie, lower(case e.shift when 'MANHA' then 'manhã' else e.shift end), v_ano));
    elsif v_tipo = 'FREQUENCIA' then
      f := iara.frequencia_resumo(v_student);
      c := c || jsonb_build_object('titulo', 'Declaração de frequência', 'frequencia', f,
        'resumo', format('Frequência de %s%% em %s dias letivos registrados (%s).', coalesce(f ->> 'percentual', '—'), f ->> 'dias', e.unidade),
        'texto', format('Declaramos, para os devidos fins, que %s, nascido(a) em %s, matriculado(a) no(a) %s, na turma %s (%s), apresenta frequência de %s%% no ano letivo de %s, '
                        || 'considerados %s dias letivos registrados até %s, com %s falta(s), das quais %s justificada(s).',
                        s.full_name, v_nasc, e.unidade, e.class_name, e.serie, coalesce(f ->> 'percentual', '—'), v_ano, f ->> 'dias',
                        to_char(coalesce((f ->> 'ultimo_dia')::date, current_date), 'DD/MM/YYYY'), f ->> 'faltas', f ->> 'justificadas'));
    else
      h := iara.historico_json(v_student);
      c := c || jsonb_build_object('titulo', 'Histórico escolar', 'historico', h -> 'anos', 'em_curso', (h -> 'em_curso') - 'calculada', 'registro', h ->> 'registro',
        'resumo', format('Histórico escolar com %s ano(s) concluído(s)%s.', jsonb_array_length(h -> 'anos'),
                         case when h -> 'em_curso' is not null then format('; cursando %s em %s', h -> 'em_curso' ->> 'serie', h -> 'em_curso' ->> 'unidade') else '' end),
        'texto', format('Certificamos que %s, nascido(a) em %s, apresenta a vida escolar abaixo, conforme os registros da rede municipal de ensino de Maringá '
                        || 'e os históricos recebidos de outras redes. Os resultados seguem a Lei nº 9.394/1996 (LDB) e as normas da rede.',
                        s.full_name, v_nasc));
    end if;
  else
    select we.entered_at, we.position, we.status, gl.name serie, u.name unidade, sc.protocol_number into w
    from iara.waiting_list_entries we join iara.grade_levels gl on gl.id = we.grade_level_id join iara.education_units u on u.id = we.preferred_unit_id
    left join iara.service_cases sc on sc.id = we.case_id
    where we.student_id = v_student and we.status in ('WAITING', 'OFFERED', 'SUSPENDED') order by we.entered_at limit 1;
    c := c || jsonb_build_object('titulo', 'Declaração de inscrição na fila de espera', 'unidade', 'Central de Vagas', 'unidade_preferencia', w.unidade,
      'serie', w.serie, 'inscrita_em', w.entered_at, 'protocolo', w.protocol_number, 'posicao', w.position,
      'resumo', format('Inscrição na fila de espera para %s desde %s (Central de Vagas).', w.serie, to_char(w.entered_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')),
      'texto', format('Declaramos, para os devidos fins, que %s, nascido(a) em %s, está inscrito(a) na fila de espera da Central de Vagas da Secretaria Municipal de Educação '
                      || 'para %s desde %s%s, com preferência pela unidade %s, aguardando oferta de vaga%s. A posição na fila pode mudar conforme os critérios da IN nº 025/2025.',
                      s.full_name, v_nasc, w.serie, to_char(w.entered_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
                      coalesce(' (protocolo ' || w.protocol_number || ')', ''), w.unidade,
                      coalesce(format(' — posição %s na data desta declaração', w.position), '')));
  end if;
  insert into iara.declaracoes (codigo, tipo, student_id, unit_id, conteudo, hash, valida_ate, canal, emitida_por_label, emitida_por_guardian, is_demo)
  values (iara.declaracao_codigo(), v_tipo, v_student, v_unit, c, encode(sha256(convert_to(c::text, 'UTF8')), 'hex'),
          current_date + case v_tipo when 'MATRICULA' then 90 when 'HISTORICO' then 1825 else 30 end, v_canal, iara.my_label(), iara.my_guardian(), false)
  returning * into d;
  perform iara.audit_event('DECLARACAO_EMITIDA', 'student', v_student::text, v_unit, 'Declaração emitida: ' || lower(v_tipo) || ' (' || d.codigo || ').');
  return iara.declaracao_json(d, true);
end $$;

-- 5. Demonstração --------------------------------------------------------------------------------------------------------------------
-- histórico dos anos anteriores (fictício): a série de cada ano anterior segue a atual; a maioria na mesma unidade, alguns em outra rede
create or replace function iara.demo_gerar_historicos() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.resultados_finais where is_demo;
  insert into iara.resultados_finais (student_id, ano, grade_code, serie, unit_id, unidade_nome, rede, turma, carga_horaria, dias_letivos, frequencia_pct, componentes,
                                      parecer, situacao, observacao, fechado_por_label, fechado_em, is_demo)
  select x.student_id, 2026 - x.k, gp.code, gp.name,
         case when x.rede = 'MUNICIPAL' then x.unidade_id end,
         case x.rede when 'MUNICIPAL' then (select name from iara.education_units where id = x.unidade_id)
                     when 'ESTADUAL' then 'Colégio Estadual do Paraná — unidade de demonstração' when 'PARTICULAR' then 'Escola particular de demonstração'
                     else 'Rede municipal de Sarandi — PR (demonstração)' end,
         x.rede, gp.name || ' ' || chr(65 + abs(hashtext(x.student_id::text || x.k)) % 4), case when gp.code in ('CRECHE', 'PRE') then 800 else 800 end, 200,
         round((86 + (abs(hashtext(x.student_id::text || x.k || 'f')) % 135) / 10.0)::numeric, 1),
         case when gp.code in ('CRECHE', 'PRE') then '[]'::jsonb else
           (select coalesce(jsonb_agg(jsonb_build_object('nome', m.componente,
                     'media', least(10, round((x.base + (abs(hashtext(x.student_id::text || x.k || m.componente)) % 21 - 6) / 10.0)::numeric, 1)), 'aulas_semana', m.aulas_semana) order by m.ordem), '[]')
            from iara.matriz_curricular m where m.grade_code = gp.code) end,
         case when gp.code in ('CRECHE', 'PRE') then 'Desenvolvimento acompanhado por parecer descritivo: participa das propostas, amplia o vocabulário e a autonomia nas rotinas.' end,
         case when gp.code in ('CRECHE', 'PRE', 'EF1', 'EF2') then 'PROGRESSAO' when x.h % 100 < 3 then 'APROVADO_CONSELHO' else 'APROVADO' end,
         case when gp.code not in ('CRECHE', 'PRE', 'EF1', 'EF2') and x.h % 100 < 3 then 'Aprovado pelo conselho de classe com plano de acompanhamento no ano seguinte.' end,
         'Secretaria escolar (demonstração)', make_date(2026 - x.k, 12, 18)::timestamptz, true
  from (select e.student_id, e.unit_id, k, iara.grade_ordem(gl.code) - k ord, abs(hashtext(e.student_id::text || 'hist')) h,
               7.0 + (abs(hashtext(e.student_id::text || 'base')) % 22) / 10.0 base,
               case when abs(hashtext(e.student_id::text || k || 'r')) % 100 < 86 then 'MUNICIPAL' when abs(hashtext(e.student_id::text || k || 'r')) % 100 < 92 then 'ESTADUAL'
                    when abs(hashtext(e.student_id::text || k || 'r')) % 100 < 96 then 'PARTICULAR' else 'OUTRO_MUNICIPIO' end rede,
               case when abs(hashtext(e.student_id::text || k || 'u')) % 100 < 80 then e.unit_id
                    else (select u2.id from iara.education_units u2 where u2.status = 'ATIVA' order by abs(hashtext(u2.id::text || e.student_id::text)) limit 1) end unidade_id
        from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
        cross join generate_series(1, 3) k
        where e.status = 'ACTIVE' and gl.code like 'EF%') x
  join iara.grade_levels gp on iara.grade_ordem(gp.code) = x.ord
  where x.ord >= 2   -- a partir da pré-escola
  on conflict (student_id, ano) do nothing;
  get diagnostics n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return n;
end $$;

-- conselhos dos bimestres encerrados (fictícios): ata, participantes e deliberação de quem ficou abaixo da média, com encaminhamentos
create or replace function iara.demo_gerar_conselhos() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_min numeric := iara.media_minima();
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.conselhos_classe where is_demo;
  insert into iara.conselhos_classe (class_id, unit_id, ano, etapa, data, participantes, ata, situacao, registrado_por_label, concluido_por_label, concluido_em, created_at, is_demo)
  select c.id, c.unit_id, 2026, b.numero, least(b.fim + 6, iara.hoje_local() - 1),
         'Direção, coordenação pedagógica, professora regente e professores especialistas (demonstração)',
         format('Conselho do %sº bimestre: a turma avançou em leitura e cálculo; os alunos com média abaixo de %s seguem para o reforço e conversa com a família. '
                || 'Combinado acompanhamento quinzenal pela coordenação.', b.numero, replace(v_min::text, '.', ',')),
         'CONCLUIDO', 'Coordenação pedagógica (demonstração)', 'Direção da unidade (demonstração)', (least(b.fim + 6, iara.hoje_local() - 1))::timestamptz + interval '17 hours',
         (least(b.fim + 6, iara.hoje_local() - 1))::timestamptz + interval '14 hours', true
  from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
  join iara.bimestres b on b.ano = 2026 and b.fim < iara.hoje_local()
  where c.status = 'ATIVA' and gl.code like 'EF%' and abs(hashtext(c.id::text || b.numero)) % 100 < 90;
  insert into iara.conselho_deliberacoes (conselho_id, student_id, encaminhamentos, observacao, comunicar_familia, atualizado_por_label, atualizado_em, is_demo)
  select k.id, z.student_id,
         case when z.abaixo >= 3 then array['REFORCO', 'CONVERSA_FAMILIA', 'PLANO_INTERVENCAO'] when z.abaixo = 2 then array['REFORCO', 'CONVERSA_FAMILIA']
              when z.abaixo = 1 then array['REFORCO'] else array['ELOGIO'] end,
         case when z.abaixo >= 1 then format('Abaixo da média em %s componente(s) no bimestre.', z.abaixo) else 'Destaque da turma no bimestre.' end,
         true, 'Coordenação pedagógica (demonstração)', k.concluido_em, true
  from iara.conselhos_classe k
  join lateral (select n.student_id, count(*) filter (where iara.nota_final(n.nota, n.recuperacao) < v_min) abaixo, avg(iara.nota_final(n.nota, n.recuperacao)) media
                from iara.notas n join iara.enrollments e on e.student_id = n.student_id and e.class_id = k.class_id and e.status = 'ACTIVE'
                where n.ano = 2026 and n.bimestre = k.etapa group by n.student_id) z on z.abaixo > 0 or z.media >= 9.3
  where k.is_demo;
  get diagnostics n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return n;
end $$;

create or replace function iara.demo_purge_conselhos(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
  v jsonb := '{}'::jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.resultados_finais where not is_demo and fechado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('resultados', n);
  delete from iara.conselho_deliberacoes where not is_demo and atualizado_em >= d;
  delete from iara.conselhos_classe where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('conselhos', n);
  delete from iara.notifications where created_at >= d and event_type = 'CONSELHO_CLASSE';
  if exists (select 1 from iara.conselhos_classe where is_demo and alterado_em >= d) or exists (select 1 from iara.conselho_deliberacoes where is_demo and atualizado_em >= d and atualizado_por_label not like '%(demonstração)%') then
    v := v || jsonb_build_object('conselhos_refeitos', iara.demo_gerar_conselhos());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
end $$;

revoke all on function iara.demo_gerar_historicos(), iara.demo_gerar_conselhos(), iara.demo_purge_conselhos(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('conselhos_classe', 'ata', 'PESSOAL', 'registro pedagógico', 'conselho de classe', 'escola e SEDUC'),
  ('conselhos_classe', 'participantes', 'PESSOAL', 'identificação', 'conselho de classe', null),
  ('conselho_deliberacoes', 'justificativa', 'SENSIVEL', 'vida escolar da criança', 'resultado final', 'escola e SEDUC'),
  ('conselho_deliberacoes', 'observacao', 'SENSIVEL', 'vida escolar da criança', 'acompanhamento', 'escola e SEDUC'),
  ('resultados_finais', 'componentes', 'PESSOAL', 'vida escolar', 'histórico escolar', 'aluno, família, escola e SEDUC'),
  ('resultados_finais', 'parecer', 'PESSOAL', 'vida escolar', 'histórico escolar', 'aluno, família, escola e SEDUC'),
  ('resultados_finais', 'observacao', 'PESSOAL', 'vida escolar', 'histórico escolar', 'aluno, família, escola e SEDUC')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_historicos() where iara.demo_mode();
select iara.demo_gerar_conselhos() where iara.demo_mode();

commit;
