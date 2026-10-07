-- IARA Educa — 068 · Sprint 4: rotina da demonstração e limpeza da apresentação
-- Rotina semanal: a biblioteca fictícia é refeita para os empréstimos em aberto continuarem coerentes com a data de hoje.
-- “Limpar depois da apresentação” passa a desfazer também conselho de classe/histórico, biblioteca, patrimônio e peso e medidas.
begin;

create or replace function iara.demo_rotina_sprint4() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_base date := nullif(iara.setting('demo_bib_base'), '')::date;
begin
  if not iara.demo_mode() then return null; end if;
  if v_base is null or v_base <= iara.hoje_local() - 7 then
    if not pg_try_advisory_xact_lock(hashtext('iara.demo_rotina_sprint4')) then return null; end if;
    perform set_config('iara.skip_audit', 'on', true);
    update iara.tenants set settings = settings || jsonb_build_object('demo_bib_base', iara.hoje_local()::text) where id = 1;
    perform set_config('iara.skip_audit', 'off', true);
    return jsonb_build_object('biblioteca', iara.demo_gerar_biblioteca());
  end if;
  return null;
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
  v_rotina4 jsonb;
  v_ba jsonb;
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
    begin
      v_rotina4 := iara.demo_rotina_sprint4();
    exception when others then
      v_rotina4 := jsonb_build_object('erro', sqlerrm);
    end;
  end if;
  -- busca ativa: níveis, agendados e limite legal (vale também na produção)
  begin
    v_ba := iara.demo_rotina_busca_ativa();
  exception when others then
    v_ba := jsonb_build_object('erro', sqlerrm);
  end;
  return jsonb_build_object('timeshift', v_shift::text, 'expired_offers', v_expired, 'rotina', v_rotina, 'rotina_sprint2', v_rotina2, 'rotina_sprint3', v_rotina3,
    'rotina_sprint4', v_rotina4, 'busca_ativa', v_ba);
end $$;

create or replace function iara.demo_purge_sprint4(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  return jsonb_build_object('conselhos', iara.demo_purge_conselhos(p_desde), 'biblioteca', iara.demo_purge_biblioteca(p_desde),
    'patrimonio', iara.demo_purge_patrimonio(p_desde), 'antropometria', iara.demo_purge_antropometria(p_desde));
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
                               'sprint4', iara.demo_purge_sprint4(null), 'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_rotina_sprint4(), iara.demo_purge_sprint4(timestamptz) from public;

update iara.tenants set settings = settings || jsonb_build_object('demo_bib_base', iara.hoje_local()::text) where id = 1 and iara.demo_mode();

commit;
