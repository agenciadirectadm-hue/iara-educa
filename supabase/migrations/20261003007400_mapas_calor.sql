-- IARA Educa — 074 · Sprint 5: mapas de calor da visão do prefeito
-- Uma função agregada por camada (transporte, frequência, ocorrências, alfabetização na idade esperada, cadastros e formação dos professores).
-- Privacidade: nada sai por pessoa. O que depende da casa da criança vira célula de ~400 m e só aparece com 3 ou mais crianças;
-- o resto é por unidade (ponto da escola) ou por ponto/rota do transporte.
begin;

-- formação do professor: o campo é texto livre (carga, formulário e demonstração usam vocabulários diferentes) → nível de 1 a 6
create or replace function iara.formacao_nivel(p text) returns smallint
language sql stable set search_path = iara, public
as $$
  select (case
    when p is null or btrim(p) = '' then null
    when iara.norm(p) ~ 'doutor' then 6
    when iara.norm(p) ~ 'mestr' then 5
    when iara.norm(p) ~ '(especializ|pos.?gradua|mba)' then 4
    when iara.norm(p) ~ 'superior incompleto' then 2
    when iara.norm(p) ~ '(superior|graduac|licenciat|pedagog)' then 3
    when iara.norm(p) ~ '(magisterio|medio|normal)' then 1
  end)::smallint
$$;

-- alfabetização esperada para a idade (meses na data da sondagem) — proposta a validar com a equipe pedagógica:
-- até 6a5m pré-silábico já é esperado; 6a6m silábico sem valor; 7a silábico com valor; 7a6m silábico-alfabético; 8a alfabético
create or replace function iara.alfa_esperado(p_meses integer) returns smallint
language sql immutable
as $$ select (case when p_meses < 78 then 1 when p_meses < 84 then 2 when p_meses < 90 then 3 when p_meses < 96 then 4 else 5 end)::smallint $$;

-- 'PRECOCE' (já alfabético antes dos 7 anos, ou silábico-alfabético antes dos 6 anos e meio), 'ESPERADO' ou 'ABAIXO'
create or replace function iara.alfa_situacao_idade(p_nivel text, p_meses integer) returns text
language sql immutable
as $$
  select case
    when iara.nivel_ordem(p_nivel) = 5 and p_meses < 84 or iara.nivel_ordem(p_nivel) >= 4 and p_meses < 78 then 'PRECOCE'
    when iara.nivel_ordem(p_nivel) < iara.alfa_esperado(p_meses) then 'ABAIXO'
    else 'ESPERADO' end
$$;

create or replace function api.mapa_calor(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_camada text := coalesce(nullif(p ->> 'camada', ''), 'transporte_necessidade');
  v_hoje date := iara.hoje_local();
  v_raio double precision := coalesce(nullif(iara.setting('default_radius_m'), '')::numeric, 2000) / 1000.0;
  v_cel numeric := 0.004;  -- ~440 m × 410 m em Maringá
  v_min integer := 3;      -- célula com menos de 3 crianças não aparece
  v_ano integer := extract(year from iara.hoje_local())::int;
  r jsonb;
begin
  perform iara.require_perm('kpi.network');

  if v_camada = 'transporte_necessidade' then
    -- onde mais precisa: mora a mais de 2 km (linha reta) da escola, ou pediu transporte, e não está em nenhuma rota
    with al as (
      select s.id, e.unit_id uid, s.school_transport_status st, extensions.st_y(a.location::extensions.geometry) lat, extensions.st_x(a.location::extensions.geometry) lng,
             u.lat ulat, u.lng ulng, g.code grade
      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
      join iara.classes c on c.id = e.class_id join iara.grade_levels g on g.id = c.grade_level_id
      join iara.addresses a on a.id = s.address_id join iara.education_units u on u.id = e.unit_id
      where a.location is not null),
    pr as (select al.*, iara.km_entre(al.lat, al.lng, al.ulat, al.ulng) km from al
           where not exists (select 1 from iara.transporte_alunos ta where ta.student_id = al.id and ta.fim is null)
             and (al.st = 'AGUARDANDO' or iara.km_entre(al.lat, al.lng, al.ulat, al.ulng) > v_raio)),
    cel as (select round(lat::numeric / v_cel) * v_cel clat, round(lng::numeric / v_cel) * v_cel clng, count(*) n, count(*) filter (where st = 'AGUARDANDO') pedidos,
                   round(avg(km)::numeric, 1) km from pr group by 1, 2)
    select jsonb_build_object('modo', 'densidade', 'sufixo', ' criança(s)',
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', clat, 'lng', clng, 'valor', n,
                   'titulo', format('%s criança(s) sem transporte a %s km da escola, em média%s', n, replace(km::text, '.', ','),
                                    case when pedidos > 0 then format(' · %s pedido(s) aguardando rota', pedidos) else '' end))), '[]') from cel where n >= v_min),
      'max', (select max(n) from cel where n >= v_min),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Sem transporte a mais de ' || replace(v_raio::text, '.', ',') || ' km', 'valor', (select count(*) from pr)),
        jsonb_build_object('rotulo', 'Pedidos aguardando rota', 'valor', (select count(*) from pr where st = 'AGUARDANDO')),
        jsonb_build_object('rotulo', 'Na creche e na pré-escola', 'valor', (select count(*) from pr where grade in ('CRECHE', 'PRE'))),
        jsonb_build_object('rotulo', 'Já atendidos pelo transporte', 'valor', (select count(*) from iara.transporte_alunos where fim is null))),
      'ranking', jsonb_build_object('titulo', 'Escolas com mais crianças longe e sem transporte', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', u.short_name, 'valor', count(*), 'detalhe', format('%s km em média', replace(round(avg(pr.km)::numeric, 1)::text, '.', ','))) z
                   from pr join iara.education_units u on u.id = pr.uid
                   group by u.short_name order by count(*) desc limit 8) q)),
      'nota', format('Casas a mais de %s km da escola em linha reta (raio padrão da rede) ou com pedido de transporte, sem rota hoje. Células de ~400 m; menos de %s crianças não aparece.',
                     replace(v_raio::text, '.', ','), v_min)) into r;

  elsif v_camada = 'transporte_oferta' then
    -- onde mais tem: os pontos de parada, pelo número de alunos que embarcam em cada um
    with pt as (select p2.lat, p2.lng, p2.nome, r2.codigo, u.short_name unidade, count(ta.id) n
                from iara.transporte_pontos p2 join iara.transporte_rotas r2 on r2.id = p2.rota_id and r2.situacao = 'ATIVA'
                join iara.education_units u on u.id = r2.unit_id
                left join iara.transporte_alunos ta on ta.ponto_id = p2.id and ta.fim is null
                group by p2.id, p2.lat, p2.lng, p2.nome, r2.codigo, u.short_name)
    select jsonb_build_object('modo', 'densidade', 'sufixo', ' aluno(s)',
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', n, 'titulo', format('%s · rota %s (%s): %s aluno(s)', nome, codigo, unidade, n))), '[]') from pt where n > 0),
      'max', (select max(n) from pt),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Alunos atendidos', 'valor', (select count(*) from iara.transporte_alunos where fim is null)),
        jsonb_build_object('rotulo', 'Rotas ativas', 'valor', (select count(*) from iara.transporte_rotas where situacao = 'ATIVA')),
        jsonb_build_object('rotulo', 'Pontos de parada', 'valor', (select count(*) from pt)),
        jsonb_build_object('rotulo', 'Km rodados por dia', 'valor', (select round(coalesce(sum(km), 0) * 2) from iara.transporte_rotas where situacao = 'ATIVA'))),
      'ranking', jsonb_build_object('titulo', 'Escolas com mais alunos no transporte', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', u.short_name, 'valor', count(ta.id), 'detalhe', format('%s rota(s)', count(distinct r2.id))) z
                   from iara.transporte_rotas r2 join iara.education_units u on u.id = r2.unit_id
                   left join iara.transporte_alunos ta on ta.rota_id = r2.id and ta.fim is null where r2.situacao = 'ATIVA'
                   group by u.short_name order by count(ta.id) desc limit 8) q)),
      'nota', 'Cada ponto de parada pesa pelo número de alunos que embarcam nele.') into r;

  elsif v_camada = 'transporte_efetividade' then
    -- onde é mais efetivo: alunos transportados ÷ previstos nas viagens dos últimos 30 dias (viagem não realizada conta zero), por rota, nos pontos dela
    with ef as (select r2.id, r2.codigo, r2.km, u.short_name unidade, sum(v.alunos_previstos) prev, sum(coalesce(v.alunos_transportados, 0)) transp, count(v.id) viagens,
                       count(v.id) filter (where v.situacao = 'CONCLUIDA' and coalesce(v.atraso_min, 0) <= 10) no_horario,
                       count(v.id) filter (where v.situacao = 'NAO_REALIZADA') falhas,
                       (select count(*) from iara.transporte_alunos ta where ta.rota_id = r2.id and ta.fim is null) alunos
                from iara.transporte_rotas r2 join iara.education_units u on u.id = r2.unit_id
                join iara.transporte_viagens v on v.rota_id = r2.id and v.data >= v_hoje - 30 and v.data < v_hoje
                where r2.situacao = 'ATIVA' group by r2.id, r2.codigo, r2.km, u.short_name),
         ev as (select ef.*, round(100.0 * transp / nullif(prev, 0)) valor, round(100.0 * no_horario / nullif(viagens, 0)) pont from ef)
    select jsonb_build_object('modo', 'taxa', 'sufixo', '%',
      'escala', jsonb_build_array(jsonb_build_array(70, '#dc2626'), jsonb_build_array(80, '#f97316'), jsonb_build_array(88, '#facc15'), jsonb_build_array(94, '#22c55e'), jsonb_build_array(100, '#1d4ed8')),
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', p2.lat, 'lng', p2.lng, 'valor', ev.valor,
                   'titulo', format('Rota %s (%s): %s%% dos alunos previstos transportados · %s%% das viagens no horário · %s aluno(s) por km', ev.codigo, ev.unidade, ev.valor,
                                    coalesce(ev.pont, 0), replace(round(ev.alunos / nullif(ev.km * 2, 0), 2)::text, '.', ',')))), '[]')
                 from ev join iara.transporte_pontos p2 on p2.rota_id = ev.id where ev.valor is not null),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Alunos transportados ÷ previstos', 'valor', (select round(100.0 * sum(transp) / nullif(sum(prev), 0)) from ef), 'sufixo', '%'),
        jsonb_build_object('rotulo', 'Viagens no horário (até 10 min)', 'valor', (select round(100.0 * sum(no_horario) / nullif(sum(viagens), 0)) from ef), 'sufixo', '%'),
        jsonb_build_object('rotulo', 'Viagens não realizadas', 'valor', (select sum(falhas) from ef)),
        jsonb_build_object('rotulo', 'Viagens em 30 dias', 'valor', (select sum(viagens) from ef))),
      'ranking', jsonb_build_object('titulo', 'Rotas menos efetivas', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', 'Rota ' || codigo || ' · ' || unidade, 'valor', valor, 'sufixo', '%', 'detalhe', format('%s%% no horário · %s falha(s)', coalesce(pont, 0), falhas)) z
                   from ev where valor is not null order by valor, pont limit 8) q)),
      'nota', 'Efetividade = alunos transportados ÷ alunos previstos nas viagens dos últimos 30 dias (viagem não realizada conta zero). Cada rota colore os seus pontos de parada.') into r;

  elsif v_camada = 'transporte_veiculos' then
    -- onde estão os veículos agora: posição simulada pelo horário planejado (sem GPS integrado)
    with ro as (select r2.id, r2.codigo, u.short_name unidade, u.lat ulat, u.lng ulng, ve.placa, ve.tipo,
                       iara.transporte_estado(r2.id, 'IDA') ida, iara.transporte_estado(r2.id, 'VOLTA') volta,
                       (select jsonb_build_object('lat', p2.lat, 'lng', p2.lng) from iara.transporte_pontos p2 where p2.rota_id = r2.id order by p2.ordem limit 1) inicio
                from iara.transporte_rotas r2 join iara.education_units u on u.id = r2.unit_id left join iara.transporte_veiculos ve on ve.id = r2.veiculo_id
                where r2.situacao = 'ATIVA'),
         po as (select ro.*,
                  case when volta ->> 'situacao' = 'EM_ANDAMENTO' then 'EM_ROTA' when ida ->> 'situacao' = 'EM_ANDAMENTO' then 'EM_ROTA'
                       when ida ->> 'situacao' = 'CONCLUIDA' and volta ->> 'situacao' = 'PREVISTA' then 'NA_ESCOLA'
                       when volta ->> 'situacao' = 'CONCLUIDA' then 'ENCERRADO'
                       when ida ->> 'situacao' in ('NAO_REALIZADA') or volta ->> 'situacao' = 'NAO_REALIZADA' then 'NAO_REALIZADA'
                       when ida ->> 'situacao' = 'SEM_AULA' then 'SEM_AULA'
                       else 'AGUARDANDO' end est,
                  coalesce(volta -> 'posicao', ida -> 'posicao') pos,
                  coalesce(volta -> 'proximo', ida -> 'proximo') prox,
                  coalesce((volta ->> 'atraso_min')::int, (ida ->> 'atraso_min')::int, 0) atraso
                from ro),
         pp as (select po.*,
                  coalesce((pos ->> 'lat')::double precision, case when est = 'NA_ESCOLA' then ulat else (inicio ->> 'lat')::double precision end, ulat) lat,
                  coalesce((pos ->> 'lng')::double precision, case when est = 'NA_ESCOLA' then ulng else (inicio ->> 'lng')::double precision end, ulng) lng
                from po)
    select jsonb_build_object('modo', 'densidade', 'sufixo', ' veículo(s)', 'agora', to_char(iara.agora_local(), 'HH24:MI'),
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', 1,
                   'cor', case est when 'EM_ROTA' then '#2563eb' when 'NA_ESCOLA' then '#f59e0b' when 'NAO_REALIZADA' then '#dc2626' else '#64748b' end,
                   'titulo', format('Rota %s (%s) · %s%s: %s%s', codigo, unidade, coalesce(tipo, 'veículo'), coalesce(' ' || placa, ''),
                                    case est when 'EM_ROTA' then 'em rota' when 'NA_ESCOLA' then 'aguardando a volta na escola' when 'ENCERRADO' then 'encerrou o dia'
                                             when 'NAO_REALIZADA' then 'viagem não realizada hoje' when 'SEM_AULA' then 'sem aula hoje' else 'aguardando a saída' end,
                                    case when est = 'EM_ROTA' then format(' · próximo: %s%s', prox ->> 'nome', case when atraso > 5 then format(' (%s min de atraso)', atraso) else '' end) else '' end))), '[]') from pp),
      'max', 3,
      'legenda', jsonb_build_array(jsonb_build_array('#2563eb', 'Em rota'), jsonb_build_array('#f59e0b', 'Na escola, aguardando a volta'),
                                   jsonb_build_array('#64748b', 'Fora de viagem'), jsonb_build_array('#dc2626', 'Viagem não realizada')),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Em rota agora', 'valor', (select count(*) from pp where est = 'EM_ROTA')),
        jsonb_build_object('rotulo', 'Na escola', 'valor', (select count(*) from pp where est = 'NA_ESCOLA')),
        jsonb_build_object('rotulo', 'Com atraso acima de 5 min', 'valor', (select count(*) from pp where est = 'EM_ROTA' and atraso > 5)),
        jsonb_build_object('rotulo', 'Viagens não realizadas hoje', 'valor', (select count(*) from pp where est = 'NAO_REALIZADA'))),
      'ranking', jsonb_build_object('titulo', 'Em rota com mais atraso', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', 'Rota ' || codigo || ' · ' || unidade, 'valor', atraso, 'sufixo', ' min', 'detalhe', 'próximo: ' || coalesce(prox ->> 'nome', '—')) z
                   from pp where est = 'EM_ROTA' and atraso > 0 order by atraso desc limit 8) q)),
      'nota', format('Situação às %s. Posição simulada pelo horário planejado de cada rota (o GPS dos veículos ainda não está integrado).', to_char(iara.agora_local(), 'HH24:MI'))) into r;

  elsif v_camada = 'frequencia' then
    with t as (select r2.id, c.unit_id, (select count(*) from iara.enrollments e where e.class_id = r2.class_id and e.status = 'ACTIVE') n
               from iara.frequencia_registros r2 join iara.classes c on c.id = r2.class_id where r2.data >= v_hoje - 30),
         fr as (select t.unit_id, sum(t.n) possiveis from t group by 1),
         ff as (select t.unit_id, count(*) faltas from t join iara.frequencia_faltas f on f.registro_id = t.id group by 1),
         fu as (select fr.unit_id, fr.possiveis, coalesce(ff.faltas, 0) faltas from fr left join ff on ff.unit_id = fr.unit_id),
         uv as (select u.short_name, u.lat, u.lng, fu.possiveis, fu.faltas, round(100.0 - 100.0 * fu.faltas / nullif(fu.possiveis, 0), 1) valor,
                       (select count(*) from iara.frequencia_alertas a where a.unit_id = u.id and a.situacao <> 'RESOLVIDO') alertas
                from fu join iara.education_units u on u.id = fu.unit_id)
    select jsonb_build_object('modo', 'taxa', 'sufixo', '%',
      'escala', jsonb_build_array(jsonb_build_array(88, '#dc2626'), jsonb_build_array(91, '#f97316'), jsonb_build_array(93, '#facc15'), jsonb_build_array(95, '#22c55e'), jsonb_build_array(97, '#1d4ed8')),
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', valor, 'titulo', format('%s: %s%% de presença em 30 dias · %s aluno(s) em alerta', short_name, replace(valor::text, '.', ','), alertas))), '[]') from uv where valor is not null),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Presença na rede (30 dias)', 'valor', (select round(100.0 - 100.0 * sum(faltas) / nullif(sum(possiveis), 0), 1) from fu), 'sufixo', '%'),
        jsonb_build_object('rotulo', 'Unidades abaixo de 90%', 'valor', (select count(*) from uv where valor < 90)),
        jsonb_build_object('rotulo', 'Alunos em alerta de frequência', 'valor', (select count(*) from iara.frequencia_alertas where situacao <> 'RESOLVIDO')),
        jsonb_build_object('rotulo', 'Casos de busca ativa abertos', 'valor', (select count(*) from iara.busca_ativa_casos where situacao <> 'ENCERRADO'))),
      'ranking', jsonb_build_object('titulo', 'Unidades com menor presença', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', short_name, 'valor', valor, 'sufixo', '%', 'detalhe', format('%s em alerta', alertas)) z from uv where valor is not null order by valor limit 8) q)),
      'nota', 'Presença = 1 − faltas ÷ (alunos × dias de chamada), nos últimos 30 dias.') into r;

  elsif v_camada = 'faltas' then
    -- faltas pela casa da criança: onde a ausência se concentra na cidade (apoio à busca ativa)
    with fa as (select f.student_id, count(*) n from iara.frequencia_faltas f join iara.frequencia_registros r2 on r2.id = f.registro_id
                where r2.data >= v_hoje - 30 and f.tipo = 'FALTA' group by 1),
         al as (select extensions.st_y(a.location::extensions.geometry) lat, extensions.st_x(a.location::extensions.geometry) lng, coalesce(fa.n, 0) faltas
                from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.addresses a on a.id = s.address_id
                left join fa on fa.student_id = s.id where a.location is not null),
         cel as (select round(lat::numeric / v_cel) * v_cel clat, round(lng::numeric / v_cel) * v_cel clng, count(*) alunos, sum(faltas) faltas, count(*) filter (where faltas >= 3) tres
                 from al group by 1, 2)
    select jsonb_build_object('modo', 'densidade', 'sufixo', ' falta(s)',
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', clat, 'lng', clng, 'valor', faltas,
                   'titulo', format('%s falta(s) sem justificativa em 30 dias entre %s criança(s) que moram aqui · %s com 3 ou mais', faltas, alunos, tres))), '[]')
                 from cel where alunos >= v_min and faltas > 0),
      'max', (select percentile_cont(0.98) within group (order by faltas) from cel where alunos >= v_min and faltas > 0),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Faltas sem justificativa (30 dias)', 'valor', (select sum(n) from fa)),
        jsonb_build_object('rotulo', 'Crianças com 3 ou mais faltas', 'valor', (select count(*) from fa where n >= 3)),
        jsonb_build_object('rotulo', 'Casos de busca ativa abertos', 'valor', (select count(*) from iara.busca_ativa_casos where situacao <> 'ENCERRADO'))),
      'ranking', jsonb_build_object('titulo', 'Bairros com mais faltas', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', coalesce(a.neighborhood, 'Sem bairro'), 'valor', sum(coalesce(fa.n, 0)), 'detalhe', format('%s criança(s) com 3+ faltas', count(*) filter (where fa.n >= 3))) z
                   from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.addresses a on a.id = s.address_id
                   left join fa on fa.student_id = s.id group by a.neighborhood having count(*) >= v_min order by sum(coalesce(fa.n, 0)) desc limit 8) q)),
      'nota', format('Faltas sem justificativa pela casa da criança, em células de ~400 m (menos de %s crianças não aparece).', v_min)) into r;

  elsif v_camada = 'ocorrencias' then
    with oc as (select o.unit_id, count(*) n, count(*) filter (where o.gravidade = 'GRAVE') graves, count(*) filter (where cardinality(coalesce(o.violencia, '{}')) > 0) violencia,
                       count(*) filter (where o.situacao <> 'ENCERRADA') abertas
                from iara.ocorrencias o where o.ocorrida_em >= now() - interval '90 days' and o.tipo <> 'ELOGIO' group by 1),
         uv as (select u.short_name, u.lat, u.lng, oc.*, round(100.0 * oc.n / nullif((select count(*) from iara.enrollments e where e.unit_id = u.id and e.status = 'ACTIVE'), 0), 1) por_cem
                from oc join iara.education_units u on u.id = oc.unit_id)
    select jsonb_build_object('modo', 'densidade', 'sufixo', ' ocorrência(s)',
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', n,
                   'titulo', format('%s: %s ocorrência(s) em 90 dias (%s por 100 alunos) · %s grave(s) · %s com violência · %s em aberto', short_name, n, replace(coalesce(por_cem, 0)::text, '.', ','), graves, violencia, abertas))), '[]') from uv),
      'max', (select max(n) from uv),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Ocorrências em 90 dias', 'valor', (select sum(n) from oc)),
        jsonb_build_object('rotulo', 'Graves', 'valor', (select sum(graves) from oc)),
        jsonb_build_object('rotulo', 'Com violência', 'valor', (select sum(violencia) from oc)),
        jsonb_build_object('rotulo', 'Em aberto', 'valor', (select sum(abertas) from oc))),
      'ranking', jsonb_build_object('titulo', 'Mais ocorrências por 100 alunos', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', short_name, 'valor', por_cem, 'detalhe', format('%s ocorrência(s) · %s grave(s)', n, graves)) z from uv order by por_cem desc nulls last limit 8) q)),
      'nota', 'Ocorrências com alunos nos últimos 90 dias (elogios não contam), no ponto da unidade. Detalhes ficam só com a escola e a Secretaria.') into r;

  elsif v_camada in ('alfa_esperado', 'alfa_precoce', 'alfa_abaixo') then
    with so as (select distinct on (a.student_id) a.student_id, a.class_id, a.nivel, a.data, a.ciclo,
                       ((extract(year from age(a.data, s.birth_date)) * 12 + extract(month from age(a.data, s.birth_date))))::int meses
                from iara.alfabetizacao_sondagens a join iara.students s on s.id = a.student_id
                join iara.enrollments e on e.student_id = a.student_id and e.status = 'ACTIVE'
                where a.ano = v_ano order by a.student_id, a.data desc),
         sx as (select so.*, iara.alfa_situacao_idade(so.nivel, so.meses) sit, c.unit_id from so join iara.classes c on c.id = so.class_id),
         uv as (select u.short_name, u.lat, u.lng, count(*) n, count(*) filter (where sit = 'PRECOCE') precoces, count(*) filter (where sit = 'ABAIXO') abaixo,
                       round(100.0 * count(*) filter (where sit <> 'ABAIXO') / count(*)) pct
                from sx join iara.education_units u on u.id = sx.unit_id group by u.id, u.short_name, u.lat, u.lng)
    select jsonb_build_object('modo', case when v_camada = 'alfa_esperado' then 'taxa' else 'densidade' end,
      'sufixo', case when v_camada = 'alfa_esperado' then '%' else ' criança(s)' end,
      'escala', jsonb_build_array(jsonb_build_array(65, '#dc2626'), jsonb_build_array(72, '#f97316'), jsonb_build_array(78, '#facc15'), jsonb_build_array(84, '#22c55e'), jsonb_build_array(90, '#1d4ed8')),
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng,
                   'valor', case v_camada when 'alfa_esperado' then pct when 'alfa_precoce' then precoces else abaixo end,
                   'titulo', format('%s: %s criança(s) avaliadas · %s%% no nível esperado para a idade ou acima · %s precoce(s) · %s abaixo do esperado', short_name, n, pct, precoces, abaixo))), '[]')
                 from uv where case v_camada when 'alfa_precoce' then precoces > 0 when 'alfa_abaixo' then abaixo > 0 else true end),
      'max', case v_camada when 'alfa_precoce' then (select max(precoces) from uv) when 'alfa_abaixo' then (select max(abaixo) from uv) end,
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Crianças avaliadas (1º e 2º ano)', 'valor', (select count(*) from sx)),
        jsonb_build_object('rotulo', 'No nível esperado ou acima', 'valor', (select round(100.0 * count(*) filter (where sit <> 'ABAIXO') / nullif(count(*), 0)) from sx), 'sufixo', '%'),
        jsonb_build_object('rotulo', 'Precoces', 'valor', (select count(*) from sx where sit = 'PRECOCE')),
        jsonb_build_object('rotulo', 'Abaixo do esperado para a idade', 'valor', (select count(*) from sx where sit = 'ABAIXO'))),
      'ranking', jsonb_build_object('titulo', case v_camada when 'alfa_precoce' then 'Mais crianças precoces' when 'alfa_abaixo' then 'Mais crianças abaixo do esperado' else 'Menor proporção no nível esperado' end,
                   'itens', (select coalesce(jsonb_agg(z), '[]') from (
                     select jsonb_build_object('nome', short_name, 'valor', case v_camada when 'alfa_esperado' then pct when 'alfa_precoce' then precoces else abaixo end,
                                               'sufixo', case when v_camada = 'alfa_esperado' then '%' else '' end, 'detalhe', format('%s avaliadas · %s%% no esperado', n, pct)) z
                     from uv order by case v_camada when 'alfa_esperado' then pct when 'alfa_precoce' then -precoces else -abaixo end limit 8) q)),
      'faixas', jsonb_build_array('Até 6 anos e 5 meses: pré-silábico ainda é esperado', '6 anos e meio: silábico sem valor sonoro', '7 anos: silábico com valor sonoro',
                                  '7 anos e meio: silábico-alfabético', '8 anos: alfabético',
                                  'Precoce: alfabético antes dos 7 anos, ou silábico-alfabético antes dos 6 anos e meio'),
      'nota', 'Última sondagem de cada criança no ano × idade na data da sondagem. Faixas são proposta a validar com a equipe pedagógica.') into r;

  elsif v_camada = 'cadastros' then
    with al as (select e.unit_id,
                       cardinality(iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null))) = 0
                       and not exists (select 1 from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                                       where sg.student_id = s.id and sg.end_date is null and sg.is_primary and cardinality(iara.responsavel_pendencias(g)) > 0) ok
                from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'),
         uv as (select u.short_name, u.lat, u.lng, count(*) n, count(*) filter (where ok) completos, round(100.0 * count(*) filter (where ok) / count(*), 1) pct
                from al join iara.education_units u on u.id = al.unit_id group by u.id, u.short_name, u.lat, u.lng)
    select jsonb_build_object('modo', 'taxa', 'sufixo', '%',
      'escala', jsonb_build_array(jsonb_build_array(95, '#dc2626'), jsonb_build_array(96.5, '#f97316'), jsonb_build_array(98, '#facc15'), jsonb_build_array(99, '#38bdf8'), jsonb_build_array(100, '#1d4ed8')),
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', pct,
                   'titulo', format('%s: %s%% dos cadastros completos (%s de %s alunos e responsáveis)', short_name, replace(pct::text, '.', ','), completos, n))), '[]') from uv),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Cadastros completos na rede', 'valor', (select round(100.0 * sum(completos) / nullif(sum(n), 0), 1) from uv), 'sufixo', '%'),
        jsonb_build_object('rotulo', 'Unidades em 100%', 'valor', (select count(*) from uv where pct = 100)),
        jsonb_build_object('rotulo', 'Unidades até 95% (vermelho)', 'valor', (select count(*) from uv where pct <= 95)),
        jsonb_build_object('rotulo', 'Cadastros a completar', 'valor', (select sum(n - completos) from uv))),
      'ranking', jsonb_build_object('titulo', 'Unidades mais longe dos 100%', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', short_name, 'valor', pct, 'sufixo', '%', 'detalhe', format('%s a completar', n - completos)) z from uv order by pct, n desc limit 8) q)),
      'pendencias', (select coalesce(jsonb_agg(jsonb_build_object('item', p2, 'n', n) order by n desc), '[]') from (
                   select p2, count(*) n from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE',
                   unnest(iara.aluno_pendencias(s, true)) p2 group by 1) q),
      'nota', 'Cadastro completo = aluno sem pendência (sexo, cor/raça, naturalidade, filiação, certidão ou CPF, endereço, responsável) e responsável principal sem pendência (CPF, nascimento, telefone, endereço, NIS se CadÚnico). Escala: até 95% vermelho, oscilando até 100% azul.') into r;

  elsif v_camada = 'formacao' then
    with pf as (select st.unit_id, iara.formacao_nivel(st.escolaridade) nv from iara.staff st
                where st.role in ('PROFESSOR', 'EDUCADOR', 'AEE') and coalesce(st.situacao, 'ATIVO') = 'ATIVO' and st.unit_id is not null),
         uv as (select u.short_name, u.lat, u.lng, count(*) n, count(*) filter (where nv >= 4) pos, count(*) filter (where nv >= 5) mestres,
                       count(*) filter (where nv = 3) superior, count(*) filter (where nv <= 2) medio, count(*) filter (where nv is null) sem,
                       round(100.0 * count(*) filter (where nv >= 4) / nullif(count(*) filter (where nv is not null), 0)) pct
                from pf join iara.education_units u on u.id = pf.unit_id group by u.id, u.short_name, u.lat, u.lng)
    select jsonb_build_object('modo', 'taxa', 'sufixo', '%',
      'escala', jsonb_build_array(jsonb_build_array(25, '#dc2626'), jsonb_build_array(38, '#f97316'), jsonb_build_array(50, '#facc15'), jsonb_build_array(62, '#22c55e'), jsonb_build_array(75, '#1d4ed8')),
      'pontos', (select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', pct,
                   'titulo', format('%s: %s%% com pós-graduação · %s professor(es): %s nível médio/magistério, %s superior, %s especialização, %s mestrado ou doutorado%s',
                                    short_name, pct, n, medio, superior, pos - mestres, mestres, case when sem > 0 then format(', %s sem informação', sem) else '' end))), '[]') from uv where pct is not null),
      'resumo', jsonb_build_array(
        jsonb_build_object('rotulo', 'Com pós-graduação', 'valor', (select round(100.0 * count(*) filter (where nv >= 4) / nullif(count(*) filter (where nv is not null), 0)) from pf), 'sufixo', '%'),
        jsonb_build_object('rotulo', 'Mestres e doutores', 'valor', (select count(*) from pf where nv >= 5)),
        jsonb_build_object('rotulo', 'Só nível médio / magistério', 'valor', (select count(*) from pf where nv <= 2)),
        jsonb_build_object('rotulo', 'Professores na conta', 'valor', (select count(*) from pf))),
      'ranking', jsonb_build_object('titulo', 'Menor proporção com pós-graduação', 'itens', (select coalesce(jsonb_agg(z), '[]') from (
                   select jsonb_build_object('nome', short_name, 'valor', pct, 'sufixo', '%', 'detalhe', format('%s professor(es) · %s só nível médio', n, medio)) z
                   from uv where pct is not null order by pct, n desc limit 8) q)),
      'niveis', (select jsonb_agg(jsonb_build_object('nivel', nv, 'rotulo', case nv when 1 then 'Nível médio / magistério' when 2 then 'Superior incompleto' when 3 then 'Superior completo'
                    when 4 then 'Especialização' when 5 then 'Mestrado' when 6 then 'Doutorado' else 'Sem informação' end, 'n', n) order by nv nulls last)
                 from (select nv, count(*) n from pf group by nv) q),
      'nota', 'Professores, educadores e professores do AEE ativos, pela escolaridade do cadastro funcional (texto padronizado em 6 níveis).') into r;

  else
    raise exception 'Camada desconhecida.' using errcode = '22023';
  end if;
  return r || jsonb_build_object('camada', v_camada, 'atualizado_em', now());
end $$;

revoke all on function iara.formacao_nivel(text), iara.alfa_esperado(integer), iara.alfa_situacao_idade(text, integer) from public;

commit;
