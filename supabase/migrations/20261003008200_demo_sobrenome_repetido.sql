-- IARA Educa — 082 · Demonstração: nenhum nome com o mesmo sobrenome duas vezes ("Raquel Siqueira Siqueira")
-- O gerador antigo sorteava os dois sobrenomes sem impedir a repetição (o novo, seed 20, já impede). Aqui o primeiro dos dois
-- vira outro sobrenome da lista e o último fica: mãe, pai e filhos continuam com o mesmo sobrenome no fim do nome.
-- A troca depende só do nome (a palavra antes e o sobrenome), então toda cópia do nome muda igual: filiação, conversas,
-- mensagens, rótulos de quem registrou, documentos emitidos. Só conta como repetição um sobrenome da lista do gerador.
-- Ficam de fora os dados públicos reais e a trilha de auditoria (imutável), como na 081. Os selos são recalculados.
begin;

create or replace function iara.desrepetir_sobrenome(p text) returns text
language plpgsql immutable set search_path = iara, public
as $$
declare
  v_lista text[] := array['Silva','Santos','Oliveira','Souza','Rodrigues','Ferreira','Alves','Pereira','Lima','Gomes','Costa','Ribeiro',
    'Martins','Carvalho','Almeida','Lopes','Soares','Fernandes','Vieira','Barbosa','Rocha','Dias','Nascimento','Andrade','Moreira',
    'Nunes','Marques','Machado','Mendes','Freitas','Cardoso','Ramos','Gonçalves','Santana','Teixeira','Araújo','Moraes','Alencar','Silvino',
    'Correia','Batista','Campos','Monteiro','Cavalcanti','Miranda','Castro','Reis','Rezende','Toledo','Mazzaro','Tanaka','Yamamoto',
    'Kobayashi','Nakamura','Watanabe','Zanetti','Bertoli','Rossi','Ferrari','Romano','Colombo','Ricci','Bianchi','Marchetti',
    'Pagliari','Kowalski','Nowak','Schmidt','Becker','Hoffmann','Wagner','Prado','Siqueira','Brandão','Bueno','Camargo','Fonseca',
    'Guimarães','Pires','Sato','Ito'];
  v text := p;
  m text[];
  v_antes text;
  v_sob text;
  v_opcoes text[];
  v_novo text;
begin
  if p is null or p !~ '\m(\w+) \1\M' then
    return p;
  end if;
  -- m[1] = palavra antes (com o espaço), m[2] = o sobrenome repetido
  for m in select regexp_matches(p, '\m(\w+ )?(\w+) \2\M', 'g') loop
    v_antes := coalesce(m[1], '');
    v_sob := m[2];
    continue when lower(v_sob) <> all (select lower(x) from unnest(v_lista) x);
    v_opcoes := array(select x from unnest(v_lista) x where lower(x) not in (lower(v_sob), lower(trim(v_antes))) order by x);
    v_novo := v_opcoes[(1 + abs(hashtext(lower(v_antes || v_sob))::bigint) % cardinality(v_opcoes))::int];
    if v_sob = upper(v_sob) then
      v_novo := upper(v_novo);
    elsif v_sob = lower(v_sob) then
      v_novo := lower(v_novo);
    end if;
    v := replace(v, v_antes || v_sob || ' ' || v_sob, v_antes || v_novo || ' ' || v_sob);
  end loop;
  return v;
end $$;

do $$
declare
  c record;
  n bigint;
  v_total jsonb := '{}'::jsonb;
  v_fora text[] := array['audit_log', 'audit_chain_head', 'education_units', 'territories', 'setores_censitarios', 'tenants', 'import_batches',
                         'classificacao_dados', 'rules', 'service_catalog', 'unit_offers', 'unit_grade_stats', 'unit_shift_stats', 'knowledge_articles',
                         'data_quality_issues', 'demo_metrics', 'feature_flags', 'organizational_roles', 'education_stages', 'grade_levels',
                         'permissions', 'role_permissions'];
begin
  perform set_config('iara.skip_audit', 'on', true);
  for c in
    select cl.table_name, cl.column_name, cl.data_type
    from information_schema.columns cl join information_schema.tables t on t.table_schema = cl.table_schema and t.table_name = cl.table_name
    where cl.table_schema = 'iara' and t.table_type = 'BASE TABLE' and cl.is_generated = 'NEVER'
      and cl.data_type in ('text', 'character varying', 'jsonb') and cl.table_name <> all (v_fora)
  loop
    execute format('update iara.%I set %I = %s where %I::text ~ %L and %I::text is distinct from iara.desrepetir_sobrenome(%I::text)',
      c.table_name, c.column_name,
      case when c.data_type = 'jsonb' then format('iara.desrepetir_sobrenome(%I::text)::jsonb', c.column_name) else format('iara.desrepetir_sobrenome(%I)', c.column_name) end,
      c.column_name, '\m(\w+) \1\M', c.column_name, c.column_name);
    get diagnostics n = row_count;
    if n > 0 then
      v_total := v_total || jsonb_build_object(c.table_name || '.' || c.column_name, n);
    end if;
  end loop;

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
  perform iara.audit_event('DEMO_NOMES', 'demo', 'sobrenome_repetido', null,
    'Demonstração: nomes com o mesmo sobrenome duas vezes passaram a ter dois sobrenomes diferentes (o último fica); selos recalculados.', v_total);
  raise notice 'Trocas: %', v_total;
end $$;

revoke all on function iara.desrepetir_sobrenome(text) from public;

commit;
