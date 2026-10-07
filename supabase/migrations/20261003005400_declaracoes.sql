-- IARA Educa — 054 · Sprint 2: declarações com verificação pública e limpeza da demonstração do Sprint 2
-- Declaração de matrícula, de frequência e de inscrição na fila: a família emite no portal ou pela IARA, a escola emite
-- no balcão. Cada declaração guarda o texto emitido (snapshot) e o hash, tem validade e um código de verificação
-- impossível de adivinhar (60 bits) impresso com QR code. Quem recebe o papel confere em /verificar sem login:
-- a página mostra se é autêntica, válida, expirada ou revogada, com o nome abreviado (não expõe o documento inteiro).
-- Transferência continua como protocolo (exige análise da secretaria).
begin;

create table if not exists iara.declaracoes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  tipo text not null check (tipo in ('MATRICULA', 'FREQUENCIA', 'INSCRICAO_FILA')),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  conteudo jsonb not null,
  hash text not null,
  emitida_em timestamptz not null default now(),
  valida_ate date not null,
  canal text not null check (canal in ('PORTAL', 'IARA', 'WHATSAPP', 'UNIDADE')),
  emitida_por_label text,
  emitida_por_guardian uuid references iara.guardians(id) on delete set null,
  revogada_em timestamptz,
  motivo_revogacao text,
  revogada_por_label text,
  verificacoes integer not null default 0,
  ultima_verificacao timestamptz,
  is_demo boolean not null default false
);
create index if not exists declaracoes_student_idx on iara.declaracoes (student_id, emitida_em desc);
alter table iara.declaracoes enable row level security;

-- código: 12 caracteres sem ambíguos (sem 0/O e 1/I), em 3 blocos — 60 bits aleatórios
create or replace function iara.declaracao_codigo() returns text
language plpgsql volatile as $$
declare
  a constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea := decode(md5(gen_random_uuid()::text || clock_timestamp()::text || random()::text), 'hex');
  r text := '';
begin
  for i in 0..11 loop
    r := r || substr(a, 1 + get_byte(b, i) % 32, 1);
    if i in (3, 7) then r := r || '-'; end if;
  end loop;
  return r;
end $$;

create or replace function iara.nome_abreviado(p text) returns text
language sql immutable as $$
  select split_part(btrim(p), ' ', 1) || coalesce(' ' || string_agg(left(w, 1) || '.', ' ' order by o), '')
  from unnest((string_to_array(btrim(p), ' '))[2:]) with ordinality t(w, o) where length(w) > 2
$$;

create or replace function iara.declaracao_json(d iara.declaracoes, p_completa boolean) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', d.id, 'codigo', d.codigo, 'tipo', d.tipo, 'emitida_em', d.emitida_em, 'valida_ate', d.valida_ate,
      'situacao', case when d.revogada_em is not null then 'REVOGADA' when d.valida_ate < current_date then 'EXPIRADA' else 'VALIDA' end,
      'hash', left(d.hash, 16), 'canal', d.canal, 'is_demo', d.is_demo)
    || case when p_completa then jsonb_build_object('conteudo', d.conteudo, 'emitida_por', d.emitida_por_label, 'student_id', d.student_id,
         'revogada_em', d.revogada_em, 'motivo_revogacao', d.motivo_revogacao, 'verificacoes', d.verificacoes)
       else jsonb_build_object('aluno', iara.nome_abreviado(d.conteudo ->> 'aluno'), 'nascimento_ano', left(d.conteudo ->> 'nascimento', 4),
         'unidade', d.conteudo ->> 'unidade', 'resumo', d.conteudo ->> 'resumo', 'revogada_em', d.revogada_em) end
$$;

-- o que cada criança pode pedir agora
create or replace function iara.declaracoes_disponiveis(p_student uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_array()
    || case when exists (select 1 from iara.enrollments where student_id = p_student and status = 'ACTIVE')
            then jsonb_build_array('MATRICULA', 'FREQUENCIA') else '[]' end
    || case when exists (select 1 from iara.waiting_list_entries where student_id = p_student and status in ('WAITING', 'OFFERED', 'SUSPENDED'))
            then jsonb_build_array('INSCRICAO_FILA') else '[]' end
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
      else 'Tipo de declaração inválido.' end using errcode = '22023';
  end if;
  if (select count(*) from iara.declaracoes where student_id = v_student and emitida_em > now() - interval '1 day') >= 10 then
    raise exception 'Limite de 10 declarações por dia para esta criança.' using errcode = '22023';
  end if;
  select * into s from iara.students where id = v_student;
  v_nasc := to_char(s.birth_date, 'DD/MM/YYYY');
  c := jsonb_build_object('aluno', s.full_name, 'nascimento', s.birth_date, 'ano', v_ano, 'municipio', 'Maringá — PR',
                          'orgao', 'Secretaria Municipal de Educação de Maringá');
  if v_tipo in ('MATRICULA', 'FREQUENCIA') then
    select en.unit_id, en.start_date, c2.class_name, c2.shift, gl.name serie, u.name unidade, u.inep_code, u.address_line, u.director_name into e
    from iara.enrollments en join iara.classes c2 on c2.id = en.class_id join iara.grade_levels gl on gl.id = c2.grade_level_id
    join iara.education_units u on u.id = en.unit_id where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
    v_unit := e.unit_id;
    c := c || jsonb_build_object('unidade', e.unidade, 'inep', e.inep_code, 'endereco_unidade', e.address_line, 'turma', e.class_name, 'serie', e.serie,
                                 'turno', initcap(lower(e.shift)), 'diretor', e.director_name);
    if v_tipo = 'MATRICULA' then
      c := c || jsonb_build_object('titulo', 'Declaração de matrícula', 'resumo', format('Matrícula ativa em %s — %s, turno %s (%s).', e.unidade, e.serie, lower(e.shift), v_ano),
        'texto', format('Declaramos, para os devidos fins, que %s, nascido(a) em %s, está regularmente matriculado(a) no(a) %s, na turma %s (%s), turno %s, no ano letivo de %s.',
                        s.full_name, v_nasc, e.unidade, e.class_name, e.serie, lower(case e.shift when 'MANHA' then 'manhã' else e.shift end), v_ano));
    else
      f := iara.frequencia_resumo(v_student);
      c := c || jsonb_build_object('titulo', 'Declaração de frequência', 'frequencia', f,
        'resumo', format('Frequência de %s%% em %s dias letivos registrados (%s).', coalesce(f ->> 'percentual', '—'), f ->> 'dias', e.unidade),
        'texto', format('Declaramos, para os devidos fins, que %s, nascido(a) em %s, matriculado(a) no(a) %s, na turma %s (%s), apresenta frequência de %s%% no ano letivo de %s, '
                        || 'considerados %s dias letivos registrados até %s, com %s falta(s), das quais %s justificada(s).',
                        s.full_name, v_nasc, e.unidade, e.class_name, e.serie, coalesce(f ->> 'percentual', '—'), v_ano, f ->> 'dias',
                        to_char(coalesce((f ->> 'ultimo_dia')::date, current_date), 'DD/MM/YYYY'), f ->> 'faltas', f ->> 'justificadas'));
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
          current_date + case v_tipo when 'MATRICULA' then 90 else 30 end, v_canal, iara.my_label(), iara.my_guardian(), false)
  returning * into d;
  perform iara.audit_event('DECLARACAO_EMITIDA', 'student', v_student::text, v_unit, 'Declaração emitida: ' || lower(v_tipo) || ' (' || d.codigo || ').');
  return iara.declaracao_json(d, true);
end $$;

create or replace function api.declaracao_ver(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  d iara.declaracoes;
begin
  select * into d from iara.declaracoes where id = nullif(p ->> 'id', '')::uuid;
  if d.id is null or not ((iara.my_guardian() is not null and d.student_id in (select iara.my_student_ids()))
                          or (iara.my_guardian() is null and iara.has_perm('students.read') and iara.can_access_student(d.student_id))) then
    raise exception 'Declaração não encontrada.' using errcode = 'P0002';
  end if;
  return iara.declaracao_json(d, true);
end $$;

create or replace function api.declaracoes_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
begin
  if not ((v_fam and v_student in (select iara.my_student_ids())) or (not v_fam and iara.has_perm('students.read') and iara.can_access_student(v_student))) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  return jsonb_build_object('disponiveis', iara.declaracoes_disponiveis(v_student),
    'pode_emitir', v_fam or iara.my_role() not in ('PROFESSOR', 'PROFESSOR_AEE'),
    'pode_revogar', not v_fam and iara.has_perm('students.write'),
    'itens', (select coalesce(jsonb_agg(iara.declaracao_json(d, true) order by d.emitida_em desc), '[]')
              from (select * from iara.declaracoes where student_id = v_student order by emitida_em desc limit 30) d));
end $$;

create or replace function api.familia_declaracoes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1),
      'disponiveis', iara.declaracoes_disponiveis(s.id),
      'itens', (select coalesce(jsonb_agg(iara.declaracao_json(d, true) order by d.emitida_em desc), '[]')
                from (select * from iara.declaracoes where student_id = s.id order by emitida_em desc limit 10) d))
      order by s.full_name), '[]')
    from iara.students s where s.id in (select iara.my_student_ids()));
end $$;

create or replace function api.declaracao_revogar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d iara.declaracoes;
begin
  select * into d from iara.declaracoes where id = (p ->> 'id')::uuid for update;
  if d.id is null or iara.my_guardian() is not null or not iara.has_perm('students.write') or not iara.can_access_student(d.student_id) then
    raise exception 'Declaração não encontrada.' using errcode = 'P0002';
  end if;
  if d.revogada_em is not null then raise exception 'Declaração já revogada.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'motivo', ''))) < 10 then raise exception 'Informe o motivo da revogação.' using errcode = '22023'; end if;
  update iara.declaracoes set revogada_em = now(), motivo_revogacao = btrim(p ->> 'motivo'), revogada_por_label = iara.my_label() where id = d.id returning * into d;
  perform iara.audit_event('DECLARACAO_REVOGADA', 'student', d.student_id::text, d.unit_id, 'Declaração revogada (' || d.codigo || ').');
  return iara.declaracao_json(d, true);
end $$;

-- verificação pública (sem login; o gateway limita as tentativas por IP)
create or replace function api.declaracao_verificar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cod text := upper(regexp_replace(coalesce(p ->> 'codigo', ''), '[^A-Za-z0-9]', '', 'g'));
  d iara.declaracoes;
begin
  if length(v_cod) <> 12 then return jsonb_build_object('encontrada', false, 'mensagem', 'O código tem 12 letras e números (ex.: ABCD-EFGH-JK23).'); end if;
  v_cod := substr(v_cod, 1, 4) || '-' || substr(v_cod, 5, 4) || '-' || substr(v_cod, 9, 4);
  update iara.declaracoes set verificacoes = verificacoes + 1, ultima_verificacao = now() where codigo = v_cod returning * into d;
  if d.id is null then
    return jsonb_build_object('encontrada', false, 'mensagem', 'Nenhuma declaração com este código. Confira as letras e os números; se persistir, o documento não é autêntico.');
  end if;
  return jsonb_build_object('encontrada', true) || iara.declaracao_json(d, false)
    || jsonb_build_object('tipo_rotulo', d.conteudo ->> 'titulo', 'orgao', d.conteudo ->> 'orgao');
end $$;

-- 2. Demonstração e limpeza do Sprint 2 ---------------------------------------------------------------------------------------------
-- algumas declarações já emitidas pela família da Maria (a plateia emite novas ao vivo)
create or replace function iara.demo_gerar_declaracoes() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_maria uuid := nullif(iara.setting('demo_guardian_maria'), '')::uuid;
  c jsonb;
  e record;
begin
  delete from iara.declaracoes where is_demo;
  if v_ana is null then return 0; end if;
  select s.full_name, s.birth_date, u.name unidade, u.inep_code, c2.class_name, c2.shift, gl.name serie into e
  from iara.students s join iara.enrollments en on en.student_id = s.id and en.status = 'ACTIVE' join iara.classes c2 on c2.id = en.class_id
  join iara.grade_levels gl on gl.id = c2.grade_level_id join iara.education_units u on u.id = en.unit_id where s.id = v_ana;
  if e.full_name is null then return 0; end if;
  c := jsonb_build_object('aluno', e.full_name, 'nascimento', e.birth_date, 'ano', '2026', 'municipio', 'Maringá — PR', 'orgao', 'Secretaria Municipal de Educação de Maringá',
    'unidade', e.unidade, 'inep', e.inep_code, 'turma', e.class_name, 'serie', e.serie, 'turno', initcap(lower(e.shift)), 'titulo', 'Declaração de matrícula',
    'resumo', format('Matrícula ativa em %s — %s, turno %s (2026).', e.unidade, e.serie, lower(e.shift)),
    'texto', format('Declaramos, para os devidos fins, que %s, nascido(a) em %s, está regularmente matriculado(a) no(a) %s, na turma %s (%s), turno %s, no ano letivo de 2026.',
                    e.full_name, to_char(e.birth_date, 'DD/MM/YYYY'), e.unidade, e.class_name, e.serie, lower(e.shift)));
  insert into iara.declaracoes (codigo, tipo, student_id, unit_id, conteudo, hash, emitida_em, valida_ate, canal, emitida_por_label, emitida_por_guardian,
                                verificacoes, ultima_verificacao, is_demo)
  select iara.declaracao_codigo(), 'MATRICULA', v_ana, (select unit_id from iara.enrollments where student_id = v_ana and status = 'ACTIVE' limit 1), c,
         encode(sha256(convert_to(c::text, 'UTF8')), 'hex'), x.em, (x.em + interval '90 days')::date, x.canal, (select full_name from iara.guardians where id = v_maria),
         v_maria, x.v, case when x.v > 0 then x.em + interval '2 days' end, true
  from (values (now() - interval '120 days', 'PORTAL', 1), (now() - interval '18 days', 'WHATSAPP', 2)) x(em, canal, v);
  return 2;
end $$;

create or replace function iara.demo_limpar_sprint2() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.declaracoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('declaracoes', n);
  delete from iara.aee_atendimentos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('aee_atendimentos', n);
  delete from iara.aee_planos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('aee_planos', n);
  delete from iara.planos_intervencao where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('planos_intervencao', n);
  delete from iara.alfabetizacao_sondagens where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('alfabetizacao_sondagens', n);
  delete from iara.pareceres where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('pareceres', n);
  delete from iara.notas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('notas', n);
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_MODULO', 'demo', 'sprint2', null, 'Dados de demonstração do Sprint 2 apagados: ' || v::text || '.');
  return v;
end $$;

-- o que a plateia e os testes lançaram ao vivo sai; o que foi alterado em dado de demonstração volta ao original
create or replace function iara.demo_purge_sprint2(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  x record;
  v_planos uuid[];
  v_aee uuid[];
begin
  if not iara.demo_mode() then raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501'; end if;
  -- turmas e bimestres mexidos (para devolver as notas, pareceres e sondagens de demonstração)
  create temp table tmp_turmas on commit drop as
    select distinct class_id, bimestre::smallint b, 'N' k from iara.notas where not is_demo and lancado_em >= d and class_id is not null
    union select distinct class_id, bimestre, 'P' from iara.pareceres where not is_demo and created_at >= d and class_id is not null
    union select distinct class_id, 0::smallint, 'A' from iara.alfabetizacao_sondagens where not is_demo and registrado_em >= d and class_id is not null;
  v_planos := array(select student_id from iara.planos_intervencao where is_demo and alterado_em >= d);
  v_aee := array(select student_id from iara.aee_planos where (is_demo and alterado_em >= d) or (not is_demo and created_at >= d)
                 union select student_id from iara.aee_atendimentos where not is_demo and registrado_em >= d);
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.notas where not is_demo and lancado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('notas', n);
  delete from iara.pareceres where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('pareceres', n);
  delete from iara.alfabetizacao_sondagens where not is_demo and registrado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('sondagens', n);
  delete from iara.planos_intervencao where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('planos_intervencao', n);
  delete from iara.aee_atendimentos where not is_demo and registrado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('aee_atendimentos', n);
  delete from iara.aee_planos where (not is_demo and created_at >= d) or (is_demo and alterado_em >= d); get diagnostics n = row_count; v := v || jsonb_build_object('aee_planos', n);
  update iara.aee_planos set familia_ciente_em = null, familia_ciente_label = null where is_demo and familia_ciente_em >= d and familia_ciente_em > created_at + interval '7 days';
  delete from iara.declaracoes where not is_demo and emitida_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('declaracoes', n);
  update iara.declaracoes set revogada_em = null, motivo_revogacao = null, revogada_por_label = null where is_demo and revogada_em >= d;
  delete from iara.notifications where created_at >= d and event_type in ('PLANO_APOIO', 'AEE_PLANO');
  for x in select * from tmp_turmas loop
    -- só bimestres encerrados têm notas de demonstração (o bimestre em andamento começa vazio)
    if x.k = 'N' then
      if exists (select 1 from iara.bimestres where ano = 2026 and numero = x.b and fim < current_date) then perform iara.demo_gerar_notas_bimestre(x.b, x.class_id); end if;
    elsif x.k = 'P' then perform iara.demo_gerar_pareceres(x.class_id);
    else perform iara.demo_gerar_alfabetizacao(x.class_id); end if;
  end loop;
  if cardinality(v_planos) > 0 then
    delete from iara.planos_intervencao where is_demo and student_id = any (v_planos);
    v := v || jsonb_build_object('planos_restaurados', cardinality(v_planos));
    perform iara.demo_gerar_planos_alunos(v_planos);
  end if;
  if cardinality(v_aee) > 0 then
    perform iara.demo_gerar_aee(v_aee);
    v := v || jsonb_build_object('aee_restaurados', cardinality(v_aee));
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_SPRINT2', 'demo', 'sprint2', null, 'Lançamentos ao vivo do Sprint 2 apagados: ' || v::text || '.');
  return v;
end $$;

-- planos de intervenção de demonstração de alguns alunos (restauração depois da apresentação)
create or replace function iara.demo_gerar_planos_alunos(p_students uuid[]) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  insert into iara.planos_intervencao (student_id, class_id, unit_id, motivos, indicadores, objetivo, acoes, responsavel_label, inicio, reavaliar_em,
                                       situacao, criado_por_label, created_at, is_demo)
  select r.student_id, r.class_id, r.unit_id, r.motivos, r.indicadores,
         case when 'ALFABETIZACAO' = any (r.motivos) then 'Avançar na hipótese de escrita e na leitura de palavras e frases simples.'
              when 'FREQUENCIA' = any (r.motivos) then 'Recuperar a frequência e as aprendizagens perdidas nas ausências.'
              else 'Recuperar as aprendizagens de ' || coalesce((r.indicadores -> 'componentes_abaixo' ->> 0), 'Português e Matemática') || '.' end,
         'Recuperação paralela no contraturno; atividades diferenciadas em sala; devolutiva quinzenal à família.',
         'Coordenação pedagógica (demonstração)', current_date - 20, current_date + 25, 'ATIVO', 'Coordenação pedagógica (demonstração)', now() - interval '20 days', true
  from (select distinct on (e.student_id) e.student_id, e.unit_id, e.class_id from iara.enrollments e where e.status = 'ACTIVE' and e.student_id = any (p_students)) a
  cross join lateral (select * from iara.risco_alunos(a.unit_id, a.class_id) r where r.student_id = a.student_id) r;
  get diagnostics v_n = row_count;
  return v_n;
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
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

-- atendimentos do AEE acompanham o calendário (a rotina diária completa até ontem)
create or replace function iara.demo_rotina_sprint2() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ult date := (select max(data) from iara.aee_atendimentos where is_demo);
  n integer := 0;
begin
  if v_ult is null or v_ult >= current_date - 1 then return null; end if;
  perform set_config('iara.skip_audit', 'on', true);
  insert into iara.aee_atendimentos (plano_id, student_id, data, presenca, atividade, registrado_por_label, registrado_em, is_demo)
  select pl.id, pl.student_id, d::date,
         case when abs(hashtext(pl.id::text || d::date)) % 100 < 86 then 'PRESENTE' when abs(hashtext(pl.id::text || d::date)) % 100 < 93 then 'FALTA'
              when abs(hashtext(pl.id::text || d::date)) % 100 < 98 then 'FALTA_JUSTIFICADA' else 'CANCELADO' end,
         case when abs(hashtext(pl.id::text || d::date)) % 100 < 86 then
           (array['Jogo de alfabeto móvel', 'Material dourado: quantidades até 20', 'Sequência lógica com figuras', 'Rotina visual do dia',
                  'Leitura com apoio de imagens'])[1 + abs(hashtext(pl.id::text || d::date || 'a')) % 5] end,
         'Professor(a) do AEE (demonstração)', d::date + interval '17 hours', true
  from iara.aee_planos pl cross join generate_series(greatest(v_ult + 1, pl.inicio), current_date - 1, interval '1 day') d
  where pl.is_demo and pl.situacao in ('ATIVO', 'EM_REVISAO')
    and (array['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB'])[extract(dow from d)::int + 1] = any (pl.dias)
    and iara.dia_letivo(d::date, pl.unit_id)
  on conflict (plano_id, data) do nothing;
  get diagnostics n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('aee_atendimentos', n);
end $$;

create or replace function iara.housekeeping() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_shift interval;
  v_expired integer;
  v_rotina jsonb;
  v_rotina2 jsonb;
begin
  v_shift := iara.demo_timeshift();
  v_expired := iara.expire_due_offers();
  begin
    v_rotina := iara.demo_rotina_diaria();
  exception when others then
    -- a rotina da demonstração nunca derruba o housekeeping
    v_rotina := jsonb_build_object('erro', sqlerrm);
  end;
  if iara.demo_mode() then
    begin
      v_rotina2 := iara.demo_rotina_sprint2();
    exception when others then
      v_rotina2 := jsonb_build_object('erro', sqlerrm);
    end;
  end if;
  return jsonb_build_object('timeshift', v_shift::text, 'expired_offers', v_expired, 'rotina', v_rotina, 'rotina_sprint2', v_rotina2);
end $$;

revoke all on function iara.declaracao_codigo(), iara.demo_gerar_declaracoes(), iara.demo_limpar_sprint2(), iara.demo_purge_sprint2(timestamptz),
  iara.demo_gerar_planos_alunos(uuid[]), iara.demo_rotina_sprint2() from public;

-- 3. Classificação ----------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('declaracoes', 'conteudo', 'PESSOAL', 'identificação e vida escolar', 'declaração emitida (snapshot)', 'família/unidade; verificação pública mostra só o nome abreviado'),
  ('declaracoes', 'codigo', 'INTERNO', 'código de verificação', 'conferir autenticidade', '60 bits aleatórios; tentativas limitadas por IP'),
  ('declaracoes', 'emitida_por_label', 'PESSOAL', 'identificação', 'auditoria (quem emitiu)', null),
  ('declaracoes', 'revogada_por_label', 'PESSOAL', 'identificação', 'auditoria (quem revogou)', null),
  ('declaracoes', 'motivo_revogacao', 'PESSOAL', 'texto livre', 'revogação', 'unidade'),
  ('notas', 'nota', 'PESSOAL', 'desempenho escolar', 'avaliação', 'escopo família/unidade/professor da turma'),
  ('notas', 'recuperacao', 'PESSOAL', 'desempenho escolar', 'avaliação', 'escopo família/unidade/professor da turma'),
  ('alfabetizacao_sondagens', 'nivel', 'PESSOAL', 'desempenho escolar', 'acompanhamento da alfabetização', 'escopo família/unidade/professor da turma'),
  ('planos_intervencao', 'indicadores', 'PESSOAL', 'desempenho escolar', 'plano de intervenção', 'escopo unidade (família não vê os indicadores)')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

create or replace function iara.classificacao_pendente() returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name), '[]'::jsonb)
  from information_schema.columns c
  where c.table_schema = 'iara'
    and c.table_name in ('students', 'student_sensitive', 'guardians', 'household_members', 'student_guardians', 'addresses',
                         'messages', 'conversations', 'whatsapp_contacts', 'service_cases', 'documents', 'waiting_list_entries', 'staff',
                         'staff_formacoes', 'staff_lotacoes', 'mediacoes', 'frequencia_faltas', 'frequencia_justificativas',
                         'frequencia_alertas', 'aluno_restricoes', 'manutencao_chamados', 'mural_leituras', 'mural_enquete_respostas',
                         'ocorrencias', 'ocorrencia_eventos', 'agenda_escolar', 'agenda_ciencia',
                         'notas', 'pareceres', 'alfabetizacao_sondagens', 'planos_intervencao', 'aee_planos', 'aee_atendimentos', 'declaracoes')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo|providencias|texto|conteudo|objetivo|objetivos|resultado|atividade|avaliacao_inicial|orientacoes_sala)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

commit;
