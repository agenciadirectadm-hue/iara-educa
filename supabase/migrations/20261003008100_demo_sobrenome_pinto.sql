-- IARA Educa — 081 · Demonstração: o sobrenome "Pinto" vira Alencar (e "Pinto Pinto", Alencar Silvino)
-- Pedido para as apresentações (ex.: a professora "Amanda Pinto Pinto"). Vale para alunos, responsáveis, professores,
-- auxiliares e funcionários e para toda cópia do nome (filiação, conversas, mensagens, rótulos de quem registrou,
-- documentos emitidos). Mãe, pai e filhos continuam com o mesmo sobrenome. Ficam de fora os dados públicos reais
-- (unidades, territórios, setores do Censo, catálogos) e a trilha de auditoria, que é imutável.
-- Os selos das declarações e dos certificados são recalculados, para a verificação continuar valendo.
-- O gerador da demonstração (seed 20) já não usa "Pinto" e não repete sobrenome ("Silva Silva").
begin;

create or replace function iara.trocar_pinto(p text) returns text
language sql immutable set search_path = iara, public
as $$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(p,
           '\mPinto Pinto\M', 'Alencar Silvino', 'g'), '\mPinto\M', 'Alencar', 'g'),
           '\mPINTO PINTO\M', 'ALENCAR SILVINO', 'g'), '\mPINTO\M', 'ALENCAR', 'g'),
           '\mpinto pinto\M', 'alencar silvino', 'g'), '\mpinto\M', 'alencar', 'g')
$$;

do $$
declare
  c record;
  n bigint;
  v_total jsonb := '{}'::jsonb;
  -- dados públicos reais, configuração e a trilha de auditoria (imutável): não mexe
  v_fora text[] := array['audit_log', 'audit_chain_head', 'education_units', 'territories', 'setores_censitarios', 'tenants', 'import_batches',
                         'classificacao_dados', 'rules', 'service_catalog', 'unit_offers', 'unit_grade_stats', 'unit_shift_stats', 'knowledge_articles',
                         'data_quality_issues', 'demo_metrics', 'feature_flags', 'organizational_roles', 'education_stages', 'grade_levels',
                         'permissions', 'role_permissions'];
begin
  -- correção em massa da demonstração: um evento de auditoria resume tudo
  perform set_config('iara.skip_audit', 'on', true);
  for c in
    select cl.table_name, cl.column_name, cl.data_type
    from information_schema.columns cl join information_schema.tables t on t.table_schema = cl.table_schema and t.table_name = cl.table_name
    where cl.table_schema = 'iara' and t.table_type = 'BASE TABLE' and cl.is_generated = 'NEVER'
      and cl.data_type in ('text', 'character varying', 'jsonb') and cl.table_name <> all (v_fora)
  loop
    execute format('update iara.%I set %I = %s where %I::text ~ %L',
      c.table_name, c.column_name,
      case when c.data_type = 'jsonb' then format('iara.trocar_pinto(%I::text)::jsonb', c.column_name) else format('iara.trocar_pinto(%I)', c.column_name) end,
      c.column_name, '\m(Pinto|PINTO|pinto)\M');
    get diagnostics n = row_count;
    if n > 0 then
      v_total := v_total || jsonb_build_object(c.table_name || '.' || c.column_name, n);
    end if;
  end loop;

  -- selos: o texto da declaração e o nome no certificado mudaram
  update iara.declaracoes set hash = encode(sha256(convert_to(conteudo::text, 'UTF8')), 'hex')
  where hash is distinct from encode(sha256(convert_to(conteudo::text, 'UTF8')), 'hex');
  get diagnostics n = row_count;
  v_total := v_total || jsonb_build_object('selos_declaracoes', n);
  update iara.evento_participantes ep set certificado_hash = encode(sha256(convert_to(ep.id::text || ep.nome || e.titulo || e.carga_horaria::text, 'UTF8')), 'hex')
  from iara.eventos e
  where e.id = ep.evento_id and ep.certificado_hash is not null
    and ep.certificado_hash is distinct from encode(sha256(convert_to(ep.id::text || ep.nome || e.titulo || e.carga_horaria::text, 'UTF8')), 'hex');
  get diagnostics n = row_count;
  v_total := v_total || jsonb_build_object('selos_certificados', n);

  perform set_config('iara.skip_audit', '', true);
  perform iara.audit_event('DEMO_NOMES', 'demo', 'sobrenome', null,
    'Demonstração: sobrenome "Pinto" trocado por Alencar ("Pinto Pinto" por Alencar Silvino) em pessoas e cópias do nome; selos recalculados.', v_total);
  raise notice 'Trocas: %', v_total;
end $$;

revoke all on function iara.trocar_pinto(text) from public;

commit;
