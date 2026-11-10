-- IARA Educa — 099.12 · Central de pendências: cenário da demonstração
--   • procedimentos periódicos de exemplo (conferência do estoque da cozinha, vistoria de segurança, contatos e autorizados,
--     Sistema Presença, planejamento do mês, relatório da fila, inventário, cardápio, preventiva e frota), desde 01/08/2026,
--     com os períodos passados concluídos como numa rede real: a maioria no prazo, uma parte com atraso, poucos em aberto;
--   • tarefas atribuídas pela chefia: na unidade da Maria, a direção pediu à professora da Ana o relatório de adaptação (vence em
--     2 dias) e à secretaria a conferência das fichas do Infantil 4 (atrasada, já cobrada); na rede, tarefas da SEDUC às diretorias,
--     à Central de Vagas e às direções; histórico de tarefas concluídas nas últimas 12 semanas;
--   • histórico das pendências por item reconstruído dos módulos (chamadas, ocorrências, manutenção e pedidos), para as estatísticas.
-- Tudo marcado como demonstração; a limpeza da apresentação desfaz o que os visitantes fizeram e recria o cenário.
begin;
set statement_timeout = '20min';

create or replace function iara.demo_gerar_pendencias() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_unit_nome text;
  v_prof uuid;
  v_sec_posto text;
  v_unid uuid := iara.pend_setor('UNID');
  v_inicio date := date '2026-08-03';
  v_criada timestamptz := (date '2026-08-03'::timestamp + time '08:00') at time zone 'America/Sao_Paulo';
  v_id uuid;
  d date;
  n_rot integer;
  n_tar integer;
  v_hist jsonb;
begin
  if not iara.demo_mode() then return jsonb_build_object('ok', false); end if;
  select short_name into v_unit_nome from iara.education_units where id = v_unit;

  -- 0. limpa o cenário anterior (só o que o roteiro criou ou o que visitantes fizeram nele)
  delete from iara.pendencias where is_demo and origem <> 'AUTOMATICA';
  delete from iara.pend_rotinas where is_demo or criada_por is not null;
  delete from iara.pend_eventos where autor is not null;

  -- 1. procedimentos de exemplo (a validar pela SEDUC)
  insert into iara.pend_rotinas (titulo, procedimento, checklist, papel, alvo, periodicidade, dia, prazo_dias, inicio, criada_por_label, criada_em, atualizada_em, is_demo) values
  ('Conferência mensal do estoque da cozinha', 'Confira o estoque de alimentos da unidade no primeiro dia útil do mês: validade, quantidades e perdas. Assine a ficha e guarde na pasta da cozinha.',
   array['Conferir a validade dos alimentos', 'Contar os itens do estoque', 'Registrar perdas e sobras', 'Assinar a ficha de conferência'],
   'DIRETOR_UNIDADE', 'TODAS', 'MENSAL', 1, 5, v_inicio, 'SEDUC · Superintendência (exemplo)', v_criada, v_criada, true),
  ('Vistoria de segurança da unidade', 'Percorra a unidade com a lista e registre o que precisa de manutenção (abra chamado quando for o caso).',
   array['Extintores dentro da validade', 'Saídas de emergência livres e sinalizadas', 'Parquinho e brinquedos sem risco', 'Portões, grades e telas em ordem'],
   'DIRETOR_UNIDADE', 'TODAS', 'MENSAL', 5, 7, v_inicio, 'SEDUC · Superintendência (exemplo)', v_criada, v_criada, true),
  ('Atualizar contatos e autorizados de retirada', 'Confirme com as famílias os telefones e as pessoas autorizadas a buscar a criança; atualize o cadastro e Guarda e restrições.',
   array['Telefones confirmados', 'Autorizados de retirada revistos', 'Restrições judiciais conferidas'],
   'SECRETARIA_ESCOLAR', 'TODAS', 'SEMESTRAL', 3, 30, v_inicio, 'SEDUC · Superintendência (exemplo)', v_criada, v_criada, true),
  ('Conferir a frequência do Sistema Presença', 'Confira a frequência dos alunos do Bolsa Família no período e registre os motivos de baixa frequência antes do envio.',
   array['Alunos do Bolsa Família conferidos', 'Motivos de baixa frequência lançados', 'Período enviado'],
   'SECRETARIA_ESCOLAR', 'TODAS', 'BIMESTRAL', 10, 10, v_inicio, 'SEDUC · Superintendência (exemplo)', v_criada, v_criada, true),
  ('Revisar o planejamento e o diário do mês', 'Registre o planejamento do mês e confira se o diário de aulas, as sondagens e as avaliações estão em dia.',
   array['Planejamento do mês registrado', 'Diário de aulas em dia', 'Sondagens e avaliações lançadas'],
   'PROFESSOR', 'TODAS', 'MENSAL', 1, 15, v_inicio, 'SEDUC · Diretoria de Ensino (exemplo)', v_criada, v_criada, true),
  ('Relatório mensal da fila e das ofertas', 'Feche o relatório do mês: crianças na fila por etapa, ofertas feitas, aceites, recusas e prazos de 72 horas.',
   array['Fila por etapa e unidade', 'Ofertas e respostas do mês', 'Casos fora da ordem justificados'],
   'ANALISTA_CENTRAL', 'SETOR', 'MENSAL', 1, 10, v_inicio, 'SEDUC · Superintendência (exemplo)', v_criada, v_criada, true),
  ('Inventário rotativo do almoxarifado', 'Conte uma parte do estoque central por mês e confira com o sistema; registre as divergências.',
   array['Itens do mês contados', 'Divergências registradas', 'Lotes vencidos separados'],
   'ALMOXARIFADO', 'SETOR', 'MENSAL', 1, 10, v_inicio, 'SEDUC · Diretoria de Infraestrutura (exemplo)', v_criada, v_criada, true),
  ('Publicar o cardápio do mês seguinte', 'Monte e publique o cardápio do próximo mês para todas as unidades, com as adaptações das restrições validadas.',
   array['Cardápio das creches', 'Cardápio das escolas', 'Adaptações das restrições'],
   'NUTRICAO', 'SETOR', 'MENSAL', 1, 20, v_inicio, 'SEDUC · Diretoria de Infraestrutura (exemplo)', v_criada, v_criada, true),
  ('Plano semanal de manutenção preventiva', 'Defina as visitas preventivas da semana (elétrica, hidráulica, telhados) e distribua às equipes.',
   array['Unidades da semana escolhidas', 'Equipes avisadas'],
   'MANUTENCAO', 'SETOR', 'SEMANAL', 1, 4, v_inicio, 'SEDUC · Diretoria de Infraestrutura (exemplo)', v_criada, v_criada, true),
  ('Conferir a documentação da frota', 'Confira vistorias, CNH e cursos dos motoristas do transporte escolar e cobre as renovações.',
   array['Vistorias conferidas', 'CNH e cursos conferidos', 'Operadores avisados'],
   'TRANSPORTE', 'SETOR', 'MENSAL', 1, 10, v_inicio, 'SEDUC · Diretoria de Infraestrutura (exemplo)', v_criada, v_criada, true);

  -- 2. períodos passados e o atual
  for d in select generate_series(v_inicio, iara.hoje_local(), interval '7 days')::date union select iara.hoje_local() loop
    perform iara.pend_rotinas_gerar(null, d);
  end loop;
  update iara.pendencias set is_demo = true where origem = 'ROTINA' and rotina_id in (select id from iara.pend_rotinas where is_demo);

  -- 3. como uma rede real cumpre: período vencido — 86% no prazo, 10% com atraso, 4% em aberto; período corrente — parte já feita
  with s as (
    select p.id, p.criada_em, p.prazo, (abs(hashtext(p.id::text)) % 1000) / 10.0 sorteio, (abs(hashtext(p.chave)) % 1000) / 1000.0 frac
    from iara.pendencias p where p.is_demo and p.origem = 'ROTINA'),
  c as (
    select s.id,
           case when s.prazo < now() then
                  case when s.sorteio < 86 then s.criada_em + (s.prazo - s.criada_em) * (0.15 + 0.8 * s.frac)
                       when s.sorteio < 96 then least(now() - interval '1 hour', s.prazo + make_interval(hours => 6 + (s.frac * 140)::int)) end
                when s.sorteio < 100 * least(1, extract(epoch from now() - s.criada_em) / nullif(extract(epoch from s.prazo - s.criada_em), 0)) * 0.7
                  then s.criada_em + (now() - s.criada_em) * (0.1 + 0.85 * s.frac) end em
    from s)
  update iara.pendencias p set situacao = 'CONCLUIDA', concluida_em = c.em,
         concluida_por_label = iara.pend_posto_rotulo(p.papel, p.unit_id, p.setor_id, p.staff_id) || coalesce(' · ' || (select u.short_name from iara.education_units u where u.id = p.unit_id and p.staff_id is null), ''),
         checklist = (select jsonb_agg(i || jsonb_build_object('feito', true, 'em', c.em)) from jsonb_array_elements(p.checklist) i)
  from c where c.id = p.id and c.em is not null;
  select count(*) into n_rot from iara.pendencias where is_demo and origem = 'ROTINA';

  -- 4. tarefas atribuídas: o caso da unidade da Maria
  select r.staff_id into v_prof from iara.pend_regentes(v_unit) r
  order by exists (select 1 from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null
                   where e.class_id = r.class_id and e.status = 'ACTIVE' and sg.guardian_id = (iara.setting('demo_guardian_maria'))::uuid) desc, r.class_name limit 1;
  v_sec_posto := 'R:SECRETARIA_ESCOLAR:' || v_unit || ':' || v_unid;

  if v_prof is not null then
    insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, staff_id, prazo, checklist, atribuida_por_label, criada_em, is_demo)
    values ('ATRIBUIDA', 'TAREFA', 'TAR:demo-relatorio-adaptacao', 'Enviar o relatório de adaptação da turma',
            'Para a reunião pedagógica: como a turma está depois do primeiro mês com a nova rotina.', 'PROFESSOR', v_unit, v_unid, v_prof,
            iara.pend_dia(iara.hoje_local() + 2),
            '[{"item": "Avanços da turma", "feito": true}, {"item": "Crianças que precisam de mais atenção", "feito": false}, {"item": "Combinados com as famílias", "feito": false}]'::jsonb,
            'Direção · ' || v_unit_nome, now() - interval '1 day', true)
    returning id into v_id;
    insert into iara.pend_eventos (pendencia_id, tipo, texto, autor_label, em, is_demo)
    values (v_id, 'CRIADA', 'Para a reunião pedagógica: como a turma está depois do primeiro mês com a nova rotina.', 'Direção · ' || v_unit_nome, now() - interval '1 day', true);
  end if;

  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, prazo, checklist, atribuida_por_label, criada_em, is_demo)
  values ('ATRIBUIDA', 'TAREFA', 'TAR:demo-fichas-inf4', 'Conferir as fichas de matrícula do Infantil 4', 'Antes do fechamento do Censo Escolar.',
          'SECRETARIA_ESCOLAR', v_unit, v_unid, iara.pend_dia(iara.hoje_local() - 1),
          '[{"item": "Fichas assinadas pelos responsáveis", "feito": true}, {"item": "Certidões de nascimento anexadas", "feito": false}, {"item": "Carteira de vacinação conferida", "feito": false}]'::jsonb,
          'Direção · ' || v_unit_nome, now() - interval '5 days', true)
  returning id into v_id;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor_label, em, is_demo) values
    (v_id, 'CRIADA', 'Antes do fechamento do Censo Escolar.', 'Direção · ' || v_unit_nome, now() - interval '5 days', true),
    (v_id, 'COBRADA', 'Preciso disso para o Censo. Consegue fechar hoje?', 'Direção · ' || v_unit_nome, now() - interval '20 hours', true);

  insert into iara.pendencias (origem, tipo, chave, titulo, papel, unit_id, setor_id, prazo, atribuida_por_label, criada_em, situacao, concluida_em, concluida_por_label, conclusao, is_demo)
  values ('ATRIBUIDA', 'TAREFA', 'TAR:demo-mural-novembro', 'Atualizar o mural da entrada com o calendário de novembro', 'SECRETARIA_ESCOLAR', v_unit, v_unid,
          iara.pend_dia(iara.hoje_local() - 8), 'Direção · ' || v_unit_nome, now() - interval '12 days', 'CONCLUIDA', now() - interval '9 days',
          'Secretaria escolar · ' || v_unit_nome, 'Mural atualizado e foto enviada no grupo da equipe.', true);

  -- tarefas da SEDUC
  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, setor_id, prazo, atribuida_por_label, criada_em, is_demo) values
    ('ATRIBUIDA', 'TAREFA', 'TAR:demo-laudos-inf1', 'Revisar as prioridades por laudo na fila do Infantil 1', 'Conferir os laudos pendentes de análise e atualizar a prioridade.',
     'ANALISTA_CENTRAL', iara.pend_setor('CV'), iara.pend_dia(iara.hoje_local() + 5), 'Superintendência', now() - interval '2 days', true),
    ('ATRIBUIDA', 'TAREFA', 'TAR:demo-fono-dezembro', 'Plano de atendimento da fonoaudiologia para dezembro', 'Distribuir as escolas entre as fonoaudiólogas no recesso.',
     'GERENCIA_APOIO', iara.pend_setor('GEE'), iara.pend_dia(iara.hoje_local() + 10), 'Secretário(a) de Educação', now() - interval '1 day', true),
    ('ATRIBUIDA', 'TAREFA', 'TAR:demo-cardapio-ferias', 'Cardápio dos CMEIs em período de férias', 'Os CMEIs atendem em janeiro: cardápio e pedido de alimentos.',
     'NUTRICAO', iara.pend_setor('GME'), iara.pend_dia(iara.hoje_local() - 2), 'Superintendência', now() - interval '9 days', true);

  -- tarefas às direções: lista do transporte de 2027 (parte já entregue)
  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, prazo, atribuida_por_label, criada_em, situacao, concluida_em, concluida_por_label, is_demo)
  select 'ATRIBUIDA', 'TAREFA', 'TAR:demo-transporte-2027:' || u.id, 'Enviar a lista de alunos para o transporte de 2027',
         'Alunos que vão precisar de transporte escolar no ano que vem, com o endereço conferido.', 'DIRETOR_UNIDADE', u.id, v_unid,
         iara.pend_dia(iara.hoje_local() + 4), 'Superintendência', now() - interval '6 days',
         case when abs(hashtext(u.id::text || 'tr')) % 100 < 55 then 'CONCLUIDA' else 'ABERTA' end,
         case when abs(hashtext(u.id::text || 'tr')) % 100 < 55 then now() - make_interval(hours => 2 + abs(hashtext(u.id::text)) % 120) end,
         case when abs(hashtext(u.id::text || 'tr')) % 100 < 55 then 'Direção · ' || u.short_name end, true
  from iara.education_units u where u.status = 'ATIVA' and u.unit_type = 'ESCOLA' and u.id <> v_unit;

  -- histórico de tarefas concluídas (12 semanas): direção → secretaria e direção → professores
  insert into iara.pendencias (origem, tipo, chave, titulo, papel, unit_id, setor_id, staff_id, prazo, atribuida_por_label, criada_em, situacao, concluida_em, concluida_por_label, is_demo)
  select 'ATRIBUIDA', 'TAREFA', 'TAR:demo-hist:' || h.unit_id || ':' || h.k, h.titulo, h.papel, h.unit_id, v_unid, h.staff_id,
         h.criada + make_interval(days => h.prazo_d), 'Direção · ' || h.nome, h.criada, 'CONCLUIDA',
         h.criada + make_interval(days => h.prazo_d) * case when h.sorteio < 84 then 0.3 + 0.6 * h.frac else 1.15 + h.frac end,
         coalesce((select s.full_name from iara.staff s where s.id = h.staff_id), 'Secretaria escolar · ' || h.nome), true
  from (
    select u.id unit_id, u.short_name nome, k,
           (array['Conferir a lista de presença da reunião de pais', 'Organizar as pastas dos alunos transferidos', 'Atualizar o quadro de horários',
                  'Separar os kits para os alunos novos', 'Levantar os alunos sem uniforme', 'Enviar fotos do evento para o mural'])[1 + (abs(hashtext(u.id::text || k)) % 6)] titulo,
           case when k % 2 = 0 then 'SECRETARIA_ESCOLAR' else 'PROFESSOR' end papel,
           case when k % 2 = 1 then (select r.staff_id from iara.pend_regentes(u.id) r order by hashtext(r.class_id::text || k) limit 1) end staff_id,
           now() - make_interval(days => 6 + (abs(hashtext(u.id::text || k || 'd')) % 78)) criada,
           2 + abs(hashtext(u.id::text || k || 'p')) % 6 prazo_d,
           (abs(hashtext(u.id::text || k || 's')) % 100) sorteio, (abs(hashtext(u.id::text || k || 'f')) % 100) / 100.0 frac
    from iara.education_units u cross join generate_series(1, 4) k
    where u.status = 'ATIVA' and abs(hashtext(u.id::text)) % 3 <> 0) h
  where h.papel = 'SECRETARIA_ESCOLAR' or h.staff_id is not null;
  update iara.pendencias set concluida_em = least(concluida_em, now() - interval '1 hour') where chave like 'TAR:demo-hist:%';
  select count(*) into n_tar from iara.pendencias where is_demo and origem = 'ATRIBUIDA';

  -- 5. histórico dos módulos e situação atual
  v_hist := iara.pend_historico_reconstruir(84);
  update iara.pendencias set is_demo = true where origem = 'AUTOMATICA' and not is_demo;
  perform iara.pend_sincronizar(null);
  update iara.tenants set settings = settings || jsonb_build_object('demo_pend_gerado_em', now()) where id = 1;
  return jsonb_build_object('ok', true, 'procedimentos', n_rot, 'tarefas', n_tar, 'historico', v_hist);
end $$;

-- limpeza da apresentação: desfaz o que os visitantes fizeram (tarefas, procedimentos, conclusões, cobranças) e recria o cenário
create or replace function iara.demo_purge_pendencias(p_desde timestamptz) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_gerado timestamptz := nullif(iara.setting('demo_pend_gerado_em'), '')::timestamptz;
begin
  if not iara.demo_mode() then return jsonb_build_object('ok', false); end if;
  if v_gerado is not null
     and not exists (select 1 from iara.pendencias where atribuida_por is not null or concluida_por is not null)
     and not exists (select 1 from iara.pend_rotinas where criada_por is not null)
     and not exists (select 1 from iara.pend_eventos where autor is not null) then
    return jsonb_build_object('ok', true, 'recriado', false);
  end if;
  delete from iara.pendencias where atribuida_por is not null or rotina_id in (select id from iara.pend_rotinas where criada_por is not null);
  -- automáticas fechadas depois da geração voltam a ser conferidas (os módulos também foram desfeitos)
  delete from iara.pendencias where origem = 'AUTOMATICA' and situacao = 'CONCLUIDA' and concluida_em > coalesce(p_desde, v_gerado, now() - interval '1 day');
  return jsonb_build_object('ok', true, 'recriado', true, 'demonstracao', iara.demo_gerar_pendencias());
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
                               'sprint4', iara.demo_purge_sprint4(null), 'sprint5', iara.demo_purge_sprint5(null),
                               'reunioes', iara.demo_purge_reunioes(null),
                               'uniformes', iara.demo_purge_uniformes(null), 'apoio', iara.demo_purge_apoio(null),
                               'pendencias', iara.demo_purge_pendencias(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_gerar_pendencias(), iara.demo_purge_pendencias(timestamptz) from public;

select iara.demo_gerar_pendencias();

commit;
