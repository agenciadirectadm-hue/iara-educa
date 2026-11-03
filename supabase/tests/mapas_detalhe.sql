-- Mapas: detalhamento de todo quesito (api.mapa_detalhe) — cidade → unidade → turma e região → microrregião, os números
-- batendo com o mapa, o sigilo pela casa e quem não pode ver.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/mapas_detalhe.sql
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

create or replace function pg_temp.as_anon(p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  execute 'set local role anon';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  r2 jsonb;
  rr jsonb;
  c text;
  v_t0 timestamptz;
  v_tempos jsonb := '{}';
  v_falhas jsonb := '[]';
  v_unit text;
  v_turma text;
  v_ap017 integer := (select id from iara.territories where kind = 'AREA_PONDERACAO' and code = '4115200017');
  v_setor text;
begin
  perform iara.session_create('PREFEITO', null, 'md-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'md-sec', 'teste');
  perform iara.session_create('CIDADAO', null, 'md-cid', 'teste');

  -- D1: os quesitos com detalhamento respondem na cidade, com quebras e unidades
  foreach c in array array['unidades', 'vagas', 'matriculas', 'fila', 'deficit', 'criancas_0a4', 'pessoas', 'fila_casa',
                           'transporte_necessidade', 'transporte_oferta', 'transporte_efetividade',
                           'frequencia', 'faltas', 'ocorrencias', 'alfa_esperado', 'alfa_precoce', 'alfa_abaixo', 'cadastros', 'formacao'] loop
    v_t0 := clock_timestamp();
    r := pg_temp.as_call('md-pref', 'mapa_detalhe', jsonb_build_object('camada', c));
    v_tempos := v_tempos || jsonb_build_object(c, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
    if r ->> 'erro' is not null or jsonb_typeof(r -> 'quebras') <> 'array' or jsonb_array_length(r -> 'quebras') = 0 then
      v_falhas := v_falhas || jsonb_build_object('quesito', c, 'erro', coalesce(r ->> 'erro', 'sem quebras'));
    end if;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'D1. Os 19 quesitos com detalhamento respondem na cidade', 'ok', v_falhas = '[]', 'falhas', v_falhas, 'ms', v_tempos);

  -- D2: ocorrências — a unidade com mais ocorrências: o valor dela bate com a lista da cidade e com o mapa de calor
  r := pg_temp.as_call('md-pref', 'mapa_detalhe', '{"camada": "ocorrencias"}');
  v_unit := r -> 'filhos' -> 'itens' -> 0 ->> 'id';
  r2 := pg_temp.as_call('md-pref', 'mapa_detalhe', jsonb_build_object('camada', 'ocorrencias', 'nivel', 'unidade', 'id', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'D2. Ocorrências: a unidade do topo tem o mesmo valor na cidade, no detalhe e no mapa', 'ok',
    (r2 ->> 'valor')::numeric = (r -> 'filhos' -> 'itens' -> 0 ->> 'valor')::numeric
    and (r2 ->> 'valor')::numeric = (select count(*) from iara.ocorrencias o where o.unit_id = v_unit::int and o.ocorrida_em >= now() - interval '90 days' and o.tipo <> 'ELOGIO')
    and (r2 -> 'posicao' ->> 'posicao')::int = 1 and r2 -> 'pai' ->> 'nivel' = 'cidade',
    'unidade', r2 ->> 'nome', 'valor', r2 ->> 'valor', 'media', r2 ->> 'media', 'posicao', r2 -> 'posicao',
    'quebras', (select jsonb_object_agg(q ->> 'titulo', jsonb_array_length(q -> 'itens')) from jsonb_array_elements(r2 -> 'quebras') q),
    'tipos', r2 -> 'quebras' -> 0 -> 'itens');

  -- D3: descer para a turma: a soma das turmas não passa da unidade, e a turma volta para a unidade
  v_turma := r2 -> 'filhos' -> 'itens' -> 0 ->> 'id';
  rr := pg_temp.as_call('md-pref', 'mapa_detalhe', jsonb_build_object('camada', 'ocorrencias', 'nivel', 'turma', 'id', v_turma));
  v_out := v_out || jsonb_build_object('passo', 'D3. Turma: responde, volta para a unidade e as turmas somam no máximo a unidade', 'ok',
    rr ->> 'erro' is null and rr -> 'pai' ->> 'id' = v_unit and rr -> 'filhos' = 'null'::jsonb
    and (select sum((x ->> 'valor')::numeric) from jsonb_array_elements(r2 -> 'filhos' -> 'itens') x) <= (r2 ->> 'valor')::numeric,
    'turma', rr ->> 'nome', 'valor', rr ->> 'valor', 'erro', rr ->> 'erro');

  -- D4: região: o valor bate com o mapa por região (faltas e presença, pela casa)
  r := pg_temp.as_call('md-pref', 'mapa_detalhe', jsonb_build_object('camada', 'faltas', 'nivel', 'area', 'id', v_ap017));
  r2 := pg_temp.as_call('md-pref', 'mapa_recorte', '{"camada": "faltas", "recorte": "area"}');
  rr := pg_temp.as_call('md-pref', 'mapa_detalhe', jsonb_build_object('camada', 'frequencia', 'nivel', 'area', 'id', v_ap017));
  v_out := v_out || jsonb_build_object('passo', 'D4. Região AP 017: faltas e presença batem com o mapa por região', 'ok',
    (r ->> 'valor')::numeric = (select (x ->> 'valor')::numeric from jsonb_array_elements(r2 -> 'itens') x where x ->> 'chave' = v_ap017::text)
    and (rr ->> 'valor')::numeric = (select (x ->> 'valor')::numeric from jsonb_array_elements(pg_temp.as_call('md-pref', 'mapa_recorte', '{"camada": "frequencia", "recorte": "area"}') -> 'itens') x
                                     where x ->> 'chave' = v_ap017::text),
    'faltas', r ->> 'valor', 'presenca', rr ->> 'valor', 'onde_estudam', jsonb_array_length(r -> 'filhos' -> 'itens'), 'pai', r -> 'pai');

  -- D5: microrregião em sigilo no mapa (pela casa) também fica em sigilo no detalhe
  select x ->> 'chave' into v_setor from jsonb_array_elements(pg_temp.as_call('md-pref', 'mapa_recorte', '{"camada": "ocorrencias", "recorte": "setor"}') -> 'itens') x
  where (x ->> 'oculto')::boolean limit 1;
  r := pg_temp.as_call('md-pref', 'mapa_detalhe', jsonb_build_object('camada', 'ocorrencias', 'nivel', 'setor', 'id', v_setor));
  v_out := v_out || jsonb_build_object('passo', 'D5. Microrregião em sigilo no mapa: o detalhe também não mostra número', 'ok',
    v_setor is not null and (r ->> 'sigilo')::boolean and r -> 'valor' is null and r -> 'quebras' is null, 'setor', v_setor, 'pai', r -> 'pai');

  -- D6: nenhum dado pessoal sai (nem o identificador das pessoas)
  r := pg_temp.as_call('md-sec', 'mapa_detalhe', jsonb_build_object('camada', 'cadastros', 'nivel', 'unidade', 'id', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'D6. Sem dado pessoal: nenhum nome nem identificador de aluno no detalhe', 'ok',
    r ->> 'erro' is null and not r ? 'pessoa' and not r ? 'pessoas'
    and not exists (select 1 from iara.enrollments e join iara.students s on s.id = e.student_id
                    where e.unit_id = v_unit::int and e.status = 'ACTIVE' and (r::text like '%' || s.id::text || '%' or r::text like '%' || s.full_name || '%')),
    'o_que_falta', r -> 'quebras' -> 1 -> 'itens');

  -- D7: quem não pode: visitante e perfil sem a visão da rede
  r := pg_temp.as_anon('mapa_detalhe', '{"camada": "vagas"}');
  r2 := pg_temp.as_call('md-cid', 'mapa_detalhe', '{"camada": "ocorrencias"}');
  rr := pg_temp.as_call('md-cid', 'mapa_detalhe', '{"camada": "vagas"}');
  v_out := v_out || jsonb_build_object('passo', 'D7. Visitante não detalha; cidadão não vê ocorrências, mas vê as vagas', 'ok',
    r ->> 'erro' is not null and r2 ->> 'codigo' = '42501' and rr ->> 'erro' is null,
    'visitante', r ->> 'erro', 'cidadao_ocorrencias', r2 ->> 'erro');

  -- D8: pedido inválido
  r := pg_temp.as_call('md-pref', 'mapa_detalhe', '{"camada": "rotas"}');
  r2 := pg_temp.as_call('md-pref', 'mapa_detalhe', '{"camada": "faltas", "nivel": "unidade"}');
  v_out := v_out || jsonb_build_object('passo', 'D8. Quesito sem detalhamento ou nível sem id: erro claro', 'ok',
    r ->> 'codigo' = '22023' and r2 ->> 'codigo' = '22023');

  -- D9: Secretaria: frequência de uma unidade e da turma pior
  r := pg_temp.as_call('md-sec', 'mapa_detalhe', jsonb_build_object('camada', 'frequencia', 'nivel', 'unidade', 'id', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'D9. Presença da unidade: taxa, referência da rede e turmas', 'ok',
    r ->> 'erro' is null and r ->> 'tipo' = 'taxa' and r ->> 'referencia' = 'Rede' and jsonb_array_length(r -> 'filhos' -> 'itens') > 0,
    'valor', r ->> 'valor', 'rede', r ->> 'rede', 'turma_pior', r -> 'filhos' -> 'itens' -> 0, 'faixas', r -> 'quebras' -> 2 -> 'itens');

  raise exception 'RESULTADO: %', v_out;
end $$;
