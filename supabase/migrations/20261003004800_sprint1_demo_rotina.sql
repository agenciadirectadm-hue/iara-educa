-- IARA Educa — 048 · Sprint 1: rotina diária da demonstração, limpeza por módulo e classificação dos dados novos
-- 1. Rotina diária (só com demo_mode): completa a chamada e as refeições dos dias letivos que passaram, detecta os alertas,
--    publica os cardápios das próximas semanas e desloca as datas dos chamados de manutenção. Roda pelo housekeeping do
--    gateway, uma vez por dia, no máximo 7 dias por vez. O que foi lançado ao vivo (is_demo = false) nunca é apagado.
-- 2. Limpeza por módulo: apaga só o que é de demonstração (is_demo) — o lugar fica livre para os dados reais. A limpeza
--    total continua sendo o Marco A do documento, só a pedido expresso de Rob.
-- 3. Classificação: as tabelas novas com dado de pessoa entram no catálogo e na verificação de pendências.
begin;

-- 1. Rotina diária ------------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_rotina_diaria() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ult date;
  v_ate date;
  v_ref date;
  v_base date;
  v_out jsonb := '{}'::jsonb;
  d integer;
begin
  if not iara.demo_mode() or coalesce(iara.setting('demo_rotina_dia'), '') = current_date::text then
    return null;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('iara.demo_rotina_diaria')) then return null; end if;

  -- chamada: do último dia gerado (completa as turmas que ficaram sem chamada) até ontem, 7 dias por vez
  v_ult := (select max(data) from iara.frequencia_registros where is_demo);
  if v_ult is not null and v_ult < current_date - 1 then
    v_ate := least(current_date - 1, v_ult + 7);
    v_out := v_out || jsonb_build_object('frequencia', iara.demo_gerar_frequencia_periodo(v_ult, v_ate, false),
                                         'alertas', iara.frequencia_detectar_alertas(null));
    v_ref := (select max(data) from iara.refeicoes_servidas where is_demo);
    if v_ref is not null then
      v_out := v_out || jsonb_build_object('refeicoes', iara.demo_gerar_refeicoes_periodo(v_ref, v_ate));
    end if;
  end if;

  v_out := v_out || jsonb_build_object('cardapios', iara.demo_gerar_cardapios(current_date));

  -- manutenção: as datas acompanham o calendário (prazos, atrasos e concluídos dos últimos 30 dias continuam coerentes)
  v_base := nullif(iara.setting('demo_manutencao_base'), '')::date;
  d := current_date - v_base;
  if d > 0 then
    perform set_config('iara.skip_audit', 'on', true);
    update iara.manutencao_chamados set aberto_em = aberto_em + make_interval(days => d), prazo = prazo + make_interval(days => d),
           concluido_em = concluido_em + make_interval(days => d), validado_em = validado_em + make_interval(days => d)
    where is_demo;
    update iara.manutencao_eventos set created_at = created_at + make_interval(days => d) where is_demo;
    v_out := v_out || jsonb_build_object('manutencao_dias', d);
  end if;

  perform set_config('iara.skip_audit', 'on', true);
  update iara.tenants set settings = settings || jsonb_build_object('demo_rotina_dia', current_date::text)
         || case when d > 0 then jsonb_build_object('demo_manutencao_base', current_date) else '{}'::jsonb end
  where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
  return v_out;
end $$;

create or replace function iara.housekeeping() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_shift interval;
  v_expired integer;
  v_rotina jsonb;
begin
  v_shift := iara.demo_timeshift();
  v_expired := iara.expire_due_offers();
  begin
    v_rotina := iara.demo_rotina_diaria();
  exception when others then
    -- a rotina da demonstração nunca derruba o housekeeping
    v_rotina := jsonb_build_object('erro', sqlerrm);
  end;
  return jsonb_build_object('timeshift', v_shift::text, 'expired_offers', v_expired, 'rotina', v_rotina);
end $$;

-- 2. Limpeza por módulo ------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_limpar_modulo(p_modulo text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  case p_modulo
    when 'mural' then
      delete from iara.mural_leituras where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mural_leituras', n);
      delete from iara.mural_enquete_respostas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mural_enquete_respostas', n);
      delete from iara.mural_publicacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mural_publicacoes', n);
    when 'manutencao' then
      delete from iara.manutencao_chamados where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_chamados', n);
      delete from iara.manutencao_eventos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_eventos', n);
    when 'nutricao' then
      delete from iara.refeicoes_servidas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('refeicoes_servidas', n);
      delete from iara.aluno_restricoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('aluno_restricoes', n);
      delete from iara.cardapios where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('cardapios', n);
    when 'frequencia' then
      delete from iara.frequencia_alertas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_alertas', n);
      delete from iara.frequencia_justificativas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_justificativas', n);
      delete from iara.frequencia_faltas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_faltas', n);
      delete from iara.frequencia_registros r where r.is_demo and not exists (select 1 from iara.frequencia_faltas f where f.registro_id = r.id);
      get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_registros', n);
    when 'calendario' then
      -- eventos fictícios da rede e das unidades; os feriados de lei (fonte LEI) ficam até a SEDUC publicar o calendário oficial
      delete from iara.calendario_eventos where is_demo and fonte <> 'LEI'; get diagnostics n = row_count; v := v || jsonb_build_object('calendario_eventos', n);
    when 'pessoal' then
      delete from iara.horarios_turma where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('horarios_turma', n);
      delete from iara.mediacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mediacoes', n);
      delete from iara.staff_formacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('staff_formacoes', n);
      delete from iara.staff_lotacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('staff_lotacoes', n);
      update iara.staff set matricula_funcional = null, cargo = null, carga_horaria_semanal = null, data_admissao = null,
             escolaridade = null, formacao = null, area_atuacao = null
      where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('staff_ficha_limpa', n);
    else
      raise exception 'Módulo desconhecido: % (mural, manutencao, nutricao, frequencia, calendario, pessoal).', p_modulo using errcode = '22023';
  end case;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_MODULO', 'demo', p_modulo, null,
    'Dados de demonstração do módulo ' || p_modulo || ' apagados: ' || v::text || '.');
  return jsonb_build_object('modulo', p_modulo, 'apagados', v);
end $$;

create or replace function iara.demo_limpar_sprint1() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  return jsonb_build_array(iara.demo_limpar_modulo('mural'), iara.demo_limpar_modulo('manutencao'), iara.demo_limpar_modulo('nutricao'),
                           iara.demo_limpar_modulo('frequencia'), iara.demo_limpar_modulo('calendario'), iara.demo_limpar_modulo('pessoal'));
end $$;

-- cenário da apresentação: a unidade da família Maria/Ana (demo_unit_maria) sempre com o que mostrar — restrições
-- validadas na cozinha, duas aguardando a nutrição, alunos com faltas seguidas (alerta) e justificativas a avaliar;
-- na rede, parte das faltas da última semana com justificativa enviada pela família. Tudo is_demo.
create or replace function iara.demo_reforcar_cenario() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := nullif(iara.setting('demo_unit_maria'), '')::int;
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_r integer; v_s integer; v_j integer; v_a integer;
begin
  if v_unit is null then return null; end if;
  perform set_config('iara.skip_audit', 'on', true);
  -- 1. restrições na unidade da apresentação (a Ana fica de fora: a família informa ao vivo); só se ainda não houver
  if (select count(*) from iara.aluno_restricoes ar join iara.enrollments e on e.student_id = ar.student_id and e.status = 'ACTIVE'
      where e.unit_id = v_unit and ar.is_demo) < 6 then
  insert into iara.aluno_restricoes (student_id, restricao_codigo, detalhe, inicio, situacao, validada_por_label, validada_em, origem, is_demo)
  select x.student_id, (array['APLV', 'CELIACA', 'VEGETARIANO', 'PORCO_RELIGIAO', 'OVO_TOTAL', 'LACTOSE', 'DIABETES', 'FRUTA_LAUDO'])[x.n],
         case when x.n = 8 then 'banana' end, date '2026-02-09' + (x.n * 7)::int,
         case when x.n <= 6 then 'VALIDADA' else 'INFORMADA' end,
         case when x.n <= 6 then 'Nutrição escolar (demonstração)' end, case when x.n <= 6 then now() - make_interval(days => 20 + x.n::int) end, 'DEMO', true
  from (select e.student_id, row_number() over (order by md5(e.student_id::text || 'cena')) n
        from iara.enrollments e where e.unit_id = v_unit and e.status = 'ACTIVE' and e.student_id is distinct from v_ana
          and not exists (select 1 from iara.aluno_restricoes ar where ar.student_id = e.student_id)) x
  where x.n <= 8;
  get diagnostics v_r = row_count;
  end if;
  -- 2. dois alunos com faltas seguidas nos últimos dias letivos (vira alerta para a busca ativa)
  insert into iara.frequencia_faltas (registro_id, student_id, tipo, is_demo)
  select r.id, x.student_id, 'FALTA', true
  from (select e.student_id, e.class_id from iara.enrollments e
        where e.unit_id = v_unit and e.status = 'ACTIVE' and e.student_id is distinct from v_ana
        order by md5(e.student_id::text || 'seq') limit 2) x
  join lateral (select r2.id from iara.frequencia_registros r2 where r2.class_id = x.class_id order by r2.data desc limit 6) r on true
  on conflict do nothing;
  get diagnostics v_s = row_count;
  v_a := iara.frequencia_detectar_alertas(v_unit);
  -- 3. justificativas enviadas pelas famílias e ainda não avaliadas: ~12% das faltas da última semana na unidade, ~4% na rede
  insert into iara.frequencia_justificativas (student_id, data, motivo, atestado, canal, situacao, created_at, is_demo)
  select f.student_id, r.data,
         (array['Consulta médica marcada no posto', 'Febre e dor de garganta', 'Viagem por falecimento na família', 'Criança com virose', 'Exame de vista'])[1 + abs(hashtext(f.student_id::text)) % 5],
         abs(hashtext(f.student_id::text)) % 3 = 0, (array['PORTAL', 'IARA', 'IARA'])[1 + abs(hashtext(r.data::text || f.student_id::text)) % 3],
         'ENVIADA', r.data + interval '1 day 9 hours', true
  from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id join iara.classes c on c.id = r.class_id
  where f.tipo = 'FALTA' and r.data >= current_date - 7
    and abs(hashtext(f.student_id::text || r.data::text)) % 100 < case when c.unit_id = v_unit then 12 else 4 end
    and not exists (select 1 from iara.frequencia_justificativas j where j.student_id = f.student_id and j.data = r.data);
  get diagnostics v_j = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('restricoes_unidade', v_r, 'faltas_seguidas', v_s, 'alertas', v_a, 'justificativas', v_j);
end $$;

-- o que as sessões de demonstração lançaram ao vivo nos módulos do Sprint 1 (is_demo = false), desde um instante:
-- chamadas, justificativas, restrições informadas, chamados, publicações, leituras e respostas. Só no modo demonstração.
-- Uso: select iara.demo_purge_sprint1(now() - interval '2 hours');   -- sem argumento: tudo o que foi lançado ao vivo
create or replace function iara.demo_purge_sprint1(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
begin
  if not iara.demo_mode() then
    raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.mural_enquete_respostas where not is_demo and respondido_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('enquete_respostas', n);
  delete from iara.mural_leituras where not is_demo and lido_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('mural_leituras', n);
  delete from iara.calendario_eventos where not is_demo and fonte = 'MURAL' and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('calendario_eventos', n);
  delete from iara.mural_publicacoes where not is_demo and publicado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('mural_publicacoes', n);
  delete from iara.manutencao_chamados where not is_demo and aberto_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_chamados', n);
  delete from iara.manutencao_eventos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_eventos', n);
  delete from iara.aluno_restricoes where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('aluno_restricoes', n);
  delete from iara.frequencia_justificativas where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_justificativas', n);
  delete from iara.frequencia_registros where not is_demo and registrado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_registros', n);
  if p_desde is null then
    delete from iara.refeicoes_servidas where not is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('refeicoes_servidas', n);
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_SPRINT1', 'demo', 'sprint1', null, 'Lançamentos ao vivo da demonstração apagados: ' || v::text || '.');
  return v;
end $$;

-- "Limpar depois da apresentação" (Rotina de apresentação) passa a levar também os lançamentos ao vivo do Sprint 1
create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_rotina_diaria(), iara.demo_limpar_modulo(text), iara.demo_limpar_sprint1(), iara.demo_purge_sprint1(timestamptz),
  iara.demo_reforcar_cenario() from public;

-- 3. Classificação dos dados novos -------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('staff', 'matricula_funcional', 'PESSOAL', 'identificador funcional', 'gestão de pessoal', 'só perfis com pessoal.read'),
  ('staff', 'cargo', 'INTERNO', 'vínculo funcional', 'lotação e turmas', null),
  ('staff', 'carga_horaria_semanal', 'INTERNO', 'vínculo funcional', 'distribuição de aulas (Lei 11.738/2008)', null),
  ('staff', 'data_admissao', 'PESSOAL', 'vínculo funcional', 'gestão de pessoal', 'só perfis com pessoal.read'),
  ('staff', 'escolaridade', 'PESSOAL', 'formação', 'habilitação para o componente', 'só perfis com pessoal.read'),
  ('staff', 'formacao', 'PESSOAL', 'formação', 'habilitação para o componente', 'só perfis com pessoal.read'),
  ('staff_formacoes', 'titulo', 'PESSOAL', 'formação', 'formação continuada', 'só perfis com pessoal.read'),
  ('staff_lotacoes', 'motivo', 'PESSOAL', 'vínculo funcional', 'histórico de lotação', 'só perfis com pessoal.read'),
  ('mediacoes', 'student_id', 'SENSIVEL', 'deficiência (art. 11)', 'mediação escolar do aluno', 'escopo da unidade; agregados fora dela'),
  ('frequencia_faltas', 'justificativa', 'SENSIVEL', 'saúde (art. 11)', 'abono e acompanhamento da frequência', 'escopo família/unidade/professor da turma'),
  ('frequencia_faltas', 'atestado', 'SENSIVEL', 'saúde (art. 11)', 'abono de faltas', 'escopo família/unidade'),
  ('frequencia_justificativas', 'motivo', 'SENSIVEL', 'saúde (art. 11)', 'justificativa enviada pela família', 'escopo família/unidade'),
  ('frequencia_justificativas', 'atestado', 'SENSIVEL', 'saúde (art. 11)', 'abono de faltas', 'escopo família/unidade'),
  ('frequencia_justificativas', 'avaliada_por_label', 'PESSOAL', 'identificação', 'auditoria (quem avaliou)', null),
  ('staff_formacoes', 'carga_horaria', 'INTERNO', 'formação', 'formação continuada', null),
  ('frequencia_justificativas', 'observacao', 'PESSOAL', 'texto livre', 'avaliação da justificativa', 'escopo família/unidade'),
  ('frequencia_alertas', 'acao', 'PESSOAL', 'texto livre', 'busca ativa e acompanhamento', 'escopo da unidade e da SEDUC'),
  ('frequencia_alertas', 'tratado_por_label', 'PESSOAL', 'identificação', 'auditoria (quem tratou)', null),
  ('aluno_restricoes', 'restricao_codigo', 'SENSIVEL', 'saúde/convicção religiosa (art. 11)', 'alimentação adequada da criança', 'cozinha vê só a instrução de preparo; nunca o laudo'),
  ('aluno_restricoes', 'detalhe', 'SENSIVEL', 'saúde (art. 11)', 'alimentação adequada da criança', 'nutrição e unidade'),
  ('aluno_restricoes', 'observacao', 'SENSIVEL', 'saúde (art. 11)', 'validação pela nutrição', 'nutrição'),
  ('aluno_restricoes', 'validada_por_label', 'PESSOAL', 'identificação', 'auditoria (quem validou)', null),
  ('manutencao_chamados', 'aberto_por_label', 'PESSOAL', 'identificação', 'auditoria (quem abriu)', null),
  ('manutencao_chamados', 'responsavel_label', 'PESSOAL', 'identificação', 'responsável pela execução', null),
  ('manutencao_chamados', 'descricao', 'INTERNO', 'texto livre', 'manutenção predial (sem dado de pessoa)', 'orientação: não citar alunos'),
  ('mural_leituras', 'guardian_id', 'PESSOAL', 'comportamento (leitura)', 'confirmação de ciência dos avisos', 'só contagens para a escola'),
  ('mural_enquete_respostas', 'opcao', 'PESSOAL', 'opinião', 'enquete da escola', 'só totais para a escola')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade,
  protecao = excluded.protecao;

create or replace function iara.classificacao_pendente() returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name), '[]'::jsonb)
  from information_schema.columns c
  where c.table_schema = 'iara'
    and c.table_name in ('students', 'student_sensitive', 'guardians', 'household_members', 'student_guardians', 'addresses',
                         'messages', 'conversations', 'whatsapp_contacts', 'service_cases', 'documents', 'waiting_list_entries', 'staff',
                         'staff_formacoes', 'staff_lotacoes', 'mediacoes', 'frequencia_faltas', 'frequencia_justificativas',
                         'frequencia_alertas', 'aluno_restricoes', 'manutencao_chamados', 'mural_leituras', 'mural_enquete_respostas')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

commit;
