-- IARA Educa — 057 · Sprint 3: rotina e limpeza da demonstração (transporte e almoxarifado)
-- A rotina diária completa as viagens dos dias que passaram e renova o almoxarifado fictício toda semana (pedidos e validades
-- acompanham o calendário). “Limpar depois da apresentação” apaga o que foi lançado ao vivo e devolve o que era de demonstração.
begin;

alter table iara.transporte_alunos add column if not exists created_at timestamptz not null default now();
alter table iara.transporte_alunos add column if not exists encerrado_em timestamptz;

create or replace function api.transporte_aluno_remover(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.transporte_alunos;
begin
  perform iara.require_perm('transporte.manage');
  if length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update iara.transporte_alunos set fim = current_date, encerrado_em = now(), observacao = coalesce(observacao || ' · ', '') || 'Saída: ' || btrim(p ->> 'motivo')
  where id = (p ->> 'id')::uuid and fim is null returning * into a;
  if a.id is null then raise exception 'Vínculo não encontrado.' using errcode = 'P0002'; end if;
  update iara.students set school_transport_status = 'ENCERRADO' where id = a.student_id;
  perform iara.audit_event('TRANSPORTE_ALUNO_REMOVIDO', 'student', a.student_id::text, null, 'Aluno retirado da rota: ' || left(btrim(p ->> 'motivo'), 120) || '.');
  return jsonb_build_object('ok', true);
end $$;

create or replace function iara.demo_limpar_sprint3() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  update iara.frequencia_faltas f set tipo = 'FALTA', justificativa = null
  from iara.transporte_abonos ab, iara.frequencia_registros fr
  where fr.id = f.registro_id and ab.student_id = f.student_id and ab.data = fr.data and ab.is_demo and f.justificativa = ab.motivo;
  delete from iara.transporte_abonos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_abonos', n);
  delete from iara.transporte_ocorrencias where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_ocorrencias', n);
  delete from iara.transporte_viagens where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_viagens', n);
  delete from iara.transporte_alunos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_alunos', n);
  delete from iara.transporte_rotas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_rotas', n);
  delete from iara.transporte_veiculos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_veiculos', n);
  delete from iara.transporte_motoristas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('transporte_motoristas', n);
  update iara.students set school_transport_status = null where school_transport_status in ('ATENDIDO', 'AGUARDANDO') and is_demo;
  if v_ana is not null then update iara.students set transport_need = false where id = v_ana; end if;
  delete from iara.pedidos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('pedidos', n);
  delete from iara.estoque_lotes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('estoque_lotes', n);
  delete from iara.materiais where is_demo and (categoria = 'ALIMENTO' or unit_id is null); get diagnostics n = row_count; v := v || jsonb_build_object('materiais_alimentos_central', n);
  delete from iara.fornecedores where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('fornecedores', n);
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_MODULO', 'demo', 'sprint3', null, 'Dados de demonstração do Sprint 3 apagados: ' || v::text || '.');
  return v;
end $$;

create or replace function iara.demo_purge_sprint3(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  v_regen boolean;
begin
  if not iara.demo_mode() then raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501'; end if;
  perform set_config('iara.skip_audit', 'on', true);
  -- transporte: o que foi lançado ao vivo sai (e a falta abonada por ele volta a ser falta)
  update iara.frequencia_faltas f set tipo = 'FALTA', justificativa = null
  from iara.transporte_abonos ab, iara.frequencia_registros fr
  where fr.id = f.registro_id and ab.student_id = f.student_id and ab.data = fr.data and not ab.is_demo and ab.created_at >= d and f.justificativa = ab.motivo;
  delete from iara.transporte_abonos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('abonos', n);
  delete from iara.transporte_ocorrencias where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('ocorrencias', n);
  delete from iara.transporte_viagens where not is_demo and registrado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('viagens', n);
  delete from iara.transporte_embarques where registrado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('embarques', n);
  delete from iara.transporte_avisos where created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('avisos_familia', n);
  with x as (delete from iara.transporte_alunos where not is_demo and created_at >= d returning student_id)
  update iara.students s set school_transport_status = 'AGUARDANDO' from x
  where s.id = x.student_id and not exists (select 1 from iara.transporte_alunos a where a.student_id = s.id and a.fim is null and a.is_demo);
  get diagnostics n = row_count; v := v || jsonb_build_object('inclusoes', n);
  update iara.transporte_alunos set fim = null, encerrado_em = null where is_demo and encerrado_em >= d;
  update iara.students s set school_transport_status = 'ATENDIDO' where exists (select 1 from iara.transporte_alunos a where a.student_id = s.id and a.fim is null and a.is_demo)
    and s.school_transport_status is distinct from 'ATENDIDO';
  delete from iara.notifications where created_at >= d and event_type like 'TRANSPORTE\_%';
  -- almoxarifado: devolve o saldo dos materiais de demonstração movimentados ao vivo; se o ciclo de pedidos ou os lotes mudaram, recria
  v_regen := exists (select 1 from iara.pedidos where not is_demo and solicitado_em >= d)
          or exists (select 1 from iara.pedidos where is_demo and greatest(decidido_em, despachado_em, recebido_em) >= d and greatest(decidido_em, despachado_em, recebido_em) > solicitado_em + interval '6 days')
          or exists (select 1 from iara.materiais_movimentos mv join iara.materiais m on m.id = mv.material_id
                     where not mv.is_demo and mv.created_at >= d and m.is_demo and (m.unit_id is null or m.categoria = 'ALIMENTO'));
  update iara.materiais m set quantidade = greatest(m.quantidade - z.delta, 0)
  from (select mv.material_id, sum(case mv.tipo when 'ENTRADA' then mv.quantidade when 'SAIDA' then -mv.quantidade else mv.quantidade end) delta
        from iara.materiais_movimentos mv where not mv.is_demo and mv.created_at >= d group by 1) z
  where m.id = z.material_id and m.is_demo and m.unit_id is not null and m.categoria <> 'ALIMENTO';
  delete from iara.estoque_lotes where not is_demo and entrada_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('lotes', n);
  delete from iara.pedidos where not is_demo and solicitado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('pedidos', n);
  if v_regen then
    delete from iara.materiais_movimentos where not is_demo and created_at >= d;
    v := v || jsonb_build_object('almoxarifado_recriado', iara.demo_gerar_almoxarifado());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_SPRINT3', 'demo', 'sprint3', null, 'Lançamentos ao vivo do Sprint 3 apagados: ' || v::text || '.');
  return v;
end $$;

create or replace function iara.demo_rotina_sprint3() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ult date := (select max(data) from iara.transporte_viagens where is_demo);
  v_out jsonb := '{}'::jsonb;
  v_base date := nullif(iara.setting('demo_almox_base'), '')::date;
begin
  if v_ult is not null and v_ult < iara.hoje_local() - 1 then
    v_out := v_out || jsonb_build_object('viagens', iara.demo_gerar_viagens(v_ult + 1, iara.hoje_local() - 1));
  end if;
  if exists (select 1 from iara.pedidos where is_demo) and (v_base is null or v_base <= iara.hoje_local() - 7) then
    v_out := v_out || jsonb_build_object('almoxarifado', iara.demo_gerar_almoxarifado());
    perform set_config('iara.skip_audit', 'on', true);
    update iara.tenants set settings = settings || jsonb_build_object('demo_almox_base', iara.hoje_local()) where id = 1;
    perform set_config('iara.skip_audit', 'off', true);
  end if;
  return case when v_out = '{}'::jsonb then null else v_out end;
end $$;

create or replace function iara.housekeeping() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_shift interval;
  v_expired integer;
  v_rotina jsonb;
  v_rotina2 jsonb;
  v_rotina3 jsonb;
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
    begin
      v_rotina3 := iara.demo_rotina_sprint3();
    exception when others then
      v_rotina3 := jsonb_build_object('erro', sqlerrm);
    end;
  end if;
  return jsonb_build_object('timeshift', v_shift::text, 'expired_offers', v_expired, 'rotina', v_rotina, 'rotina_sprint2', v_rotina2, 'rotina_sprint3', v_rotina3);
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
                               'transporte_almoxarifado', iara.demo_purge_sprint3(null), 'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

update iara.tenants set settings = settings || jsonb_build_object('demo_almox_base', iara.hoje_local()) where id = 1 and exists (select 1 from iara.pedidos where is_demo);

revoke all on function iara.demo_limpar_sprint3(), iara.demo_purge_sprint3(timestamptz), iara.demo_rotina_sprint3() from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('transporte_alunos', 'motivo', 'SENSIVEL', 'elegibilidade (pode indicar deficiência)', 'transporte escolar', 'gerência de transporte e unidade'),
  ('transporte_rotas', 'nome', 'INTERNO', 'operação', 'identificação da rota', null)
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
                         'notas', 'pareceres', 'alfabetizacao_sondagens', 'planos_intervencao', 'aee_planos', 'aee_atendimentos', 'declaracoes',
                         'transporte_motoristas', 'transporte_rotas', 'transporte_pontos', 'transporte_alunos', 'transporte_viagens', 'transporte_embarques',
                         'transporte_ocorrencias', 'transporte_avisos', 'transporte_abonos', 'pedidos', 'pedido_itens', 'fornecedores')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo|providencias|providencia|texto|conteudo|objetivo|objetivos|resultado|atividade|avaliacao_inicial|orientacoes_sala|divergencia|lat|lng)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

commit;
