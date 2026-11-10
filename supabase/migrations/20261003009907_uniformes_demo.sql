-- IARA Educa — 099.07 · Uniformes e kits: demonstração e limpeza da apresentação
-- Cenário fictício coerente com a rede (31 mil matrículas da demonstração):
--   • campanha 2026 em entrega: tamanhos informados em fevereiro, quase tudo retirado (código ou documento), poucos com prazo vencido
--     (mais em algumas unidades, para o mapa e para o Conselho Tutelar), alunos novos, trocas, reposições e material adaptado do AEE;
--   • campanha 2027 em coleta de tamanhos (03/11 a 15/12/2026): parte das famílias já informou, pelo portal, pela IARA ou na unidade;
--   • família da Maria: Ana retirou uniforme e kit 2026; a troca da jaqueta está liberada (código e aviso aguardando ciência);
--     o tamanho de 2027 ainda não foi informado (a IARA pede).
-- Valores de referência dos itens: fictícios, marcados como demonstração (a SEDUC informa os do contrato na tela).
-- Alunos da Ampliação de Jornada: parte dos alunos do 1º ao 5º ano das escolas com Atividades Complementares (fictício).
-- Limpeza da apresentação: apaga o que foi feito ao vivo e, se algo da demonstração mudou, recria o cenário.
begin;
-- a geração da demonstração mexe com ~150 mil linhas
set statement_timeout = '20min';

create or replace function iara.demo_gerar_uniformes() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_ana uuid;
  v_ana_unit integer;
  c26 uuid;
  c27 uuid;
  d27 uuid;
  v_nec uuid;
  r jsonb := '{}';
begin
  if not iara.demo_mode() then return jsonb_build_object('ok', false, 'motivo', 'fora do modo demonstração'); end if;
  -- recomeça do zero (só o que é da demonstração e o que foi feito ao vivo em uniformes e kits)
  delete from iara.uk_avisos;
  delete from iara.uk_disparos;
  delete from iara.uk_necessidades;
  delete from iara.uk_codigos;
  delete from iara.uk_tamanhos;
  delete from iara.ampliacao_jornada where is_demo;
  delete from iara.uk_campanhas where is_demo or ano in (2026, 2027);
  delete from iara.pedidos where justificativa like 'Uniformes e kits %';
  delete from iara.materiais where codigo ~ '^(UNI|KIT)-[A-Z]' and is_demo;

  -- valores de referência fictícios (R$), marcados como demonstração
  update iara.uk_itens i set valor_referencia = v.valor, valor_demo = true
  from (values ('UNI-REG', 16.90), ('UNI-MC', 18.50), ('UNI-SHS', 21.40), ('UNI-BER', 20.80), ('UNI-CAL', 32.60), ('UNI-JAQ', 54.90), ('UNI-LA', 48.70),
               ('UNI-PAP', 39.90), ('UNI-MEI', 7.80), ('KIT-INF01', 42.00), ('KIT-INF2', 61.00), ('KIT-INF3', 118.00), ('KIT-INF4', 131.00),
               ('KIT-INF5', 139.00), ('KIT-EF1', 127.00), ('KIT-EF2', 119.00), ('KIT-EF34', 116.00), ('KIT-EF5', 116.00), ('KIT-EJA', 88.00),
               ('KIT-AJE1', 104.00), ('KIT-AJE25', 97.00)) v(codigo, valor)
  where i.codigo = v.codigo and (i.valor_referencia is null or i.valor_demo);

  -- produtos do almoxarifado para todas as peças e tamanhos da grade, e um por kit
  perform iara.uk_produtos_garantir();

  -- Ampliação de Jornada (contraturno): parte dos alunos do 1º ao 5º ano das escolas com Atividades Complementares
  insert into iara.ampliacao_jornada (student_id, ano, unit_id, origem, is_demo)
  select e.student_id, y.ano, e.unit_id, 'DEMONSTRACAO', true
  from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels g on g.id = c.grade_level_id
  join iara.education_units u on u.id = e.unit_id
  cross join (values (2026), (2027)) y(ano)
  where e.status = 'ACTIVE' and g.code ~ '^EF[1-5]$' and u.offers_text ilike '%atividades complementares%'
    and abs(hashtext(e.student_id::text || 'aje')) % 100 < 35 and not (g.code = 'EF5' and y.ano = 2027)
  on conflict do nothing;

  insert into iara.uk_campanhas (ano, nome, coleta_inicio, coleta_fim, entrega_inicio, entrega_fim, prazo_retirada_dias, situacao, gerada_em, observacao, atualizado_por_label, is_demo)
  values (2026, 'Uniformes e kits 2026', date '2025-11-03', date '2025-12-12', date '2026-02-02', date '2026-12-18', 30, 'ENTREGA', timestamptz '2026-01-20 09:00-03',
          'Entrega anual concluída em março; seguem alunos novos, trocas e reposições.', 'Gerência de Suprimentos e Almoxarifado', true)
  returning id into c26;
  insert into iara.uk_campanhas (ano, nome, coleta_inicio, coleta_fim, entrega_inicio, entrega_fim, prazo_retirada_dias, situacao, observacao, atualizado_por_label, is_demo)
  values (2027, 'Uniformes e kits 2027', date '2026-11-03', date '2026-12-15', date '2027-02-01', date '2027-03-31', 30, 'COLETA_TAMANHOS',
          'Coleta de tamanhos pelo portal, pela IARA e nas unidades.', 'Gerência de Suprimentos e Almoxarifado', true)
  returning id into c27;

  -- ======== 2026 ========
  -- tamanhos 2026 (93% informados; o resto estimado pela idade)
  insert into iara.uk_tamanhos (student_id, ano, superior, inferior, calcado, modelo_inferior, canal, informado_por_label, informado_em, is_demo)
  select x.student_id, 2026, x.s ->> 'superior', x.s ->> 'inferior', (x.s ->> 'calcado')::int + case when x.h % 7 = 0 then 1 when x.h % 11 = 0 then -1 else 0 end,
         case when x.h % 2 = 0 then 'SHORTS_SAIA' else 'BERMUDA' end,
         case when x.h % 100 < 46 then 'PORTAL' when x.h % 100 < 77 then 'WHATSAPP' when x.h % 100 < 93 then 'UNIDADE' else 'ESTIMATIVA' end,
         case when x.h % 100 < 77 then 'Família' when x.h % 100 < 93 then 'Secretaria escolar' else 'Estimativa pela idade' end,
         timestamptz '2025-11-04 08:00-03' + make_interval(days => x.h % 38, mins => x.h % 660), true
  from (select e.student_id, abs(hashtext(e.student_id::text || 'tam26')) h,
               iara.uk_sugestao_meses((extract(year from age(date '2026-02-15', s.birth_date)) * 12 + extract(month from age(date '2026-02-15', s.birth_date)))::int) s
        from iara.uk_etapas(2026) e join iara.students s on s.id = e.student_id where e.etapa is distinct from 'EJA') x;

  -- necessidades 2026: entrega anual (ou aluno novo), uniforme e kit
  with al as (
    select e.student_id, e.unit_id, e.etapa, e.ampliacao amp,
           abs(hashtext(e.student_id::text || 'nec26')) h, abs(hashtext(e.unit_id::text || 'ukunid')) % 100 fu
    from iara.uk_etapas(2026) e),
  cont as (
    select al.*, k.conteudo from al cross join (values ('UNIFORME'), ('KIT')) k(conteudo)
    where al.etapa is not null and (k.conteudo = 'KIT' or al.etapa <> 'EJA')),
  base as (
    select cont.*, t.superior, t.inferior, t.calcado, t.modelo_inferior,
           case when cont.h % 1000 < 15 then 'ALUNO_NOVO' else 'ANUAL' end tipo,
           -- situação: quase tudo retirado; algumas unidades com mais pendência
           case when cont.h % 1000 < 15 then case when cont.h % 10 < 7 then 'RETIRADA' when cont.h % 10 < 9 then 'DISPONIVEL' else 'AGUARDANDO_MATERIAL' end
                when cont.h % 1000 < 15 + case when cont.fu < 10 then 20 else 4 end then 'DISPONIVEL'
                when cont.h % 1000 < 30 + case when cont.fu < 10 then 20 else 4 end then 'PARCIAL'
                else 'RETIRADA' end situacao
    from cont left join iara.uk_tamanhos t on t.student_id = cont.student_id and t.ano = 2026)
  insert into iara.uk_necessidades (campanha_id, ano, student_id, unit_id, etapa, ampliacao, tipo, conteudo, itens, origem, situacao, disponivel_em, prazo_retirada,
                                    retirada_em, retirada_por_nome, retirada_por_parentesco, retirada_por_guardian, retirada_documento, codigo_conferido,
                                    registrado_por_label, entregue, created_at, updated_at, is_demo)
  select c26, 2026, b.student_id, b.unit_id, b.etapa, b.amp, b.tipo, b.conteudo,
         (select coalesce(jsonb_agg(jsonb_build_object('item', i.codigo, 'nome', i.nome, 'quantidade', i.quantidade,
                   'tamanho', case i.medida when 'SUPERIOR' then b.superior when 'INFERIOR' then b.inferior when 'CALCADO' then b.calcado::text
                                                when 'MEIA' then iara.uk_meia(b.calcado) end,
                   'produto', iara.uk_produto_codigo(i.codigo, case i.medida when 'SUPERIOR' then b.superior when 'INFERIOR' then b.inferior
                                                       when 'CALCADO' then b.calcado::text when 'MEIA' then iara.uk_meia(b.calcado) end)) order by i.ordem), '[]')
          from iara.uk_itens i where i.tipo = b.conteudo and i.ativo and b.etapa = any (i.etapas) and (not i.so_ampliacao or b.amp)
            and (i.modelo is null or i.modelo = b.modelo_inferior)),
         'SISTEMA', b.situacao,
         case when b.situacao <> 'AGUARDANDO_MATERIAL' then case when b.tipo = 'ALUNO_NOVO' and b.situacao = 'DISPONIVEL' then now() - make_interval(days => 3 + b.h % 12)
                                                              when b.tipo = 'ALUNO_NOVO' then timestamptz '2026-03-10 09:00-03' + make_interval(days => b.h % 200)
                                                              else timestamptz '2026-02-05 14:00-03' end end,
         case when b.situacao <> 'AGUARDANDO_MATERIAL' then case when b.tipo = 'ALUNO_NOVO' and b.situacao = 'DISPONIVEL' then (now() - make_interval(days => 3 + b.h % 12))::date + 30
                                                              when b.tipo = 'ALUNO_NOVO' then date '2026-04-09' + (b.h % 200)
                                                              else date '2026-03-07' end end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') then case when b.tipo = 'ALUNO_NOVO' then timestamptz '2026-03-12 08:00-03' + make_interval(days => b.h % 200, mins => b.h % 540)
                                                                    else timestamptz '2026-02-09 08:00-03' + make_interval(days => b.h % 26, mins => b.h % 540) end end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') then g.full_name end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') then iara.uk_parentesco(sg.relationship) end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') then g.id end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') and b.h % 100 >= 82 then '…' || lpad((b.h % 10000)::text, 4, '0') end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') then b.h % 100 < 82 end,
         case when b.situacao in ('RETIRADA', 'PARCIAL') then 'Secretaria escolar' end,
         null, timestamptz '2026-01-20 09:00-03', now(), true
  from base b
  left join lateral (select sg.guardian_id, sg.relationship from iara.student_guardians sg where sg.student_id = b.student_id and sg.end_date is null and sg.can_pick_up
                     order by sg.is_primary desc limit 1) sg on true
  left join iara.guardians g on g.id = sg.guardian_id;
  -- retirada em parte: a jaqueta ficou para depois
  update iara.uk_necessidades set entregue = (select jsonb_agg(it || jsonb_build_object('entregue', it ->> 'item' <> 'UNI-JAQ')) from jsonb_array_elements(itens) it)
  where ano = 2026 and situacao = 'PARCIAL' and conteudo = 'UNIFORME';
  update iara.uk_necessidades set situacao = 'RETIRADA' where ano = 2026 and situacao = 'PARCIAL' and conteudo <> 'UNIFORME';

  -- códigos 2026 de quem tem algo liberado
  insert into iara.uk_codigos (student_id, ano, codigo)
  select distinct on (student_id) student_id, 2026, lpad((abs(hashtext(student_id::text || 'cod26')) % 1000000)::text, 6, '0')
  from iara.uk_necessidades where ano = 2026 and situacao <> 'AGUARDANDO_MATERIAL'
  on conflict do nothing;

  -- trocas, reposições (pedidas pela família) e material adaptado (AEE)
  insert into iara.uk_necessidades (campanha_id, ano, student_id, unit_id, etapa, tipo, conteudo, itens, motivo, origem, solicitante_label, situacao,
                                    decisao_motivo, decidido_por_label, decidido_em, disponivel_em, prazo_retirada, retirada_em, retirada_por_nome, retirada_por_parentesco,
                                    codigo_conferido, registrado_por_label, created_at, is_demo)
  select c26, 2026, n.student_id, n.unit_id, n.etapa, x.tipo, 'UNIFORME',
         case x.tipo when 'TROCA_TAMANHO' then jsonb_build_array(jsonb_build_object('nome', 'Calça', 'quantidade', 2), jsonb_build_object('nome', 'Jaqueta', 'quantidade', 1))
                     else jsonb_build_array(jsonb_build_object('nome', 'Jaqueta', 'quantidade', 1)) end,
         case x.tipo when 'TROCA_TAMANHO' then 'A calça e a jaqueta ficaram pequenas; precisa de um número acima.' else 'A jaqueta foi perdida no parque da escola.' end,
         'FAMILIA', 'Família',
         case when n.h % 10 < 7 then 'RETIRADA' when n.h % 10 < 9 then 'AGUARDANDO_DECISAO' else 'NEGADA' end,
         case when n.h % 10 = 9 then 'Sem a jaqueta neste tamanho no estoque; a reposição entra na compra de 2027.' end,
         case when n.h % 10 < 7 or n.h % 10 = 9 then 'Secretaria escolar' end,
         case when n.h % 10 < 7 or n.h % 10 = 9 then timestamptz '2026-04-01 10:00-03' + make_interval(days => n.h % 180) end,
         case when n.h % 10 < 7 then timestamptz '2026-04-02 10:00-03' + make_interval(days => n.h % 180) end,
         case when n.h % 10 < 7 then date '2026-05-02' + (n.h % 180) end,
         case when n.h % 10 < 7 then timestamptz '2026-04-06 08:30-03' + make_interval(days => n.h % 180, mins => n.h % 500) end,
         case when n.h % 10 < 7 then n.retirada_por_nome end, case when n.h % 10 < 7 then n.retirada_por_parentesco end,
         case when n.h % 10 < 7 then true end, case when n.h % 10 < 7 then 'Secretaria escolar' end,
         case when n.h % 10 in (7, 8) then now() - make_interval(days => 1 + n.h % 9) else timestamptz '2026-03-28 10:00-03' + make_interval(days => n.h % 180) end, true
  from (select nn.*, abs(hashtext(nn.student_id::text || 'troca')) h from iara.uk_necessidades nn where nn.ano = 2026 and nn.conteudo = 'UNIFORME' and nn.situacao = 'RETIRADA') n
  cross join lateral (select case when n.h % 1000 < 14 then 'TROCA_TAMANHO' when n.h % 1000 < 20 then 'REPOSICAO' end tipo) x
  where x.tipo is not null;

  insert into iara.uk_necessidades (campanha_id, ano, student_id, unit_id, etapa, tipo, conteudo, itens, motivo, origem, solicitante_label, situacao,
                                    decidido_por_label, decidido_em, disponivel_em, prazo_retirada, retirada_em, retirada_por_nome, retirada_por_parentesco,
                                    codigo_conferido, registrado_por_label, created_at, is_demo)
  select c26, 2026, s.id, e.unit_id, iara.uk_etapa_aluno(s.id, 2026), 'ADAPTADO', 'ADAPTADO',
         (array[jsonb_build_array(jsonb_build_object('nome', 'Caderno com pauta ampliada', 'quantidade', 4), jsonb_build_object('nome', 'Lápis jumbo triangular', 'quantidade', 6)),
                jsonb_build_array(jsonb_build_object('nome', 'Tesoura adaptada com mola', 'quantidade', 1), jsonb_build_object('nome', 'Engrossador de lápis', 'quantidade', 3)),
                jsonb_build_array(jsonb_build_object('nome', 'Material em Braille (alfabeto e números)', 'quantidade', 1), jsonb_build_object('nome', 'Reglete e punção', 'quantidade', 1)),
                jsonb_build_array(jsonb_build_object('nome', 'Plano inclinado de leitura', 'quantidade', 1), jsonb_build_object('nome', 'Caderno de pauta ampliada', 'quantidade', 4))])[1 + abs(hashtext(s.id::text || 'ad')) % 4],
         'Indicado no PAEE para a autonomia na escrita e na leitura.', 'AEE', 'Professora do AEE',
         case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then 'RETIRADA' when abs(hashtext(s.id::text || 'ad2')) % 10 < 8 then 'AGUARDANDO_DECISAO' else 'AGUARDANDO_MATERIAL' end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 not in (6, 7) then 'Assessoria de Educação Especial · SEDUC' end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 not in (6, 7) then timestamptz '2026-03-16 11:00-03' + make_interval(days => abs(hashtext(s.id::text)) % 150) end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then timestamptz '2026-03-23 11:00-03' + make_interval(days => abs(hashtext(s.id::text)) % 150) end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then date '2026-04-22' + abs(hashtext(s.id::text)) % 150 end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then timestamptz '2026-03-25 09:00-03' + make_interval(days => abs(hashtext(s.id::text)) % 150) end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then 'Responsável' end, case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then 'Responsável' end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then true end, case when abs(hashtext(s.id::text || 'ad2')) % 10 < 6 then 'Secretaria escolar' end,
         case when abs(hashtext(s.id::text || 'ad2')) % 10 in (6, 7) then now() - make_interval(days => 2 + abs(hashtext(s.id::text)) % 15)
              else timestamptz '2026-03-09 10:00-03' + make_interval(days => abs(hashtext(s.id::text)) % 150) end, true
  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
  where s.aee_status and abs(hashtext(s.id::text || 'adapt')) % 100 < 28;

  -- avisos de retirada 2026 (um por aluno; ciência de quase todos)
  insert into iara.uk_avisos (student_id, guardian_id, unit_id, ano, tipo, necessidade_ids, titulo, texto, enviado_em, whatsapp_status, whatsapp_em, ciente_em, ciente_canal, is_demo)
  select n.student_id, iara.uk_responsavel(n.student_id), n.unit_id, 2026, 'RETIRADA', n.ids, 'Uniforme e kit escolar: pode retirar',
         format('Uniforme e kit escolar de %s: disponível para retirada no(a) %s até %s. Leve o código de retirada ou documento com foto.',
                split_part(s.full_name, ' ', 1), u.short_name, to_char(n.prazo, 'DD/MM/YYYY')),
         n.disp, case when n.h % 100 < 64 then 'SIMULADO' else 'SEM_WHATSAPP' end, n.disp + interval '40 minutes',
         case when n.h % 100 < 90 or n.retirada then n.disp + make_interval(hours => 2 + n.h % 70) end,
         case when n.h % 100 < 90 or n.retirada then case when n.h % 2 = 0 then 'WHATSAPP' else 'PORTAL' end end, true
  from (select student_id, min(unit_id) unit_id, array_agg(id) ids, min(disponivel_em) disp, min(prazo_retirada) prazo, bool_and(situacao in ('RETIRADA', 'PARCIAL')) retirada,
               abs(hashtext(student_id::text || 'av26')) h
        from iara.uk_necessidades where ano = 2026 and tipo in ('ANUAL', 'ALUNO_NOVO') and disponivel_em is not null group by student_id) n
  join iara.students s on s.id = n.student_id join iara.education_units u on u.id = n.unit_id;

  -- ======== 2027: coleta de tamanhos aberta ========
  perform iara.uk_gerar(c27);
  insert into iara.uk_disparos (tipo, ano, filtro, total, criado_por_label, created_at, is_demo)
  values ('TAMANHO', 2027, '{}', 0, 'Gerência de Suprimentos e Almoxarifado', timestamptz '2026-11-03 08:05-03', true) returning id into d27;
  -- tamanhos já informados: varia por unidade (algumas quase tudo, outras pouco)
  insert into iara.uk_tamanhos (student_id, ano, superior, inferior, calcado, modelo_inferior, canal, informado_por_label, informado_em, is_demo)
  select x.student_id, 2027, x.s ->> 'superior', x.s ->> 'inferior', (x.s ->> 'calcado')::int + case when x.h % 9 = 0 then 1 else 0 end,
         case when x.h % 2 = 0 then 'SHORTS_SAIA' else 'BERMUDA' end,
         case when x.h % 100 < 50 then 'WHATSAPP' when x.h % 100 < 85 then 'PORTAL' else 'UNIDADE' end,
         case when x.h % 100 < 85 then 'Família' else 'Secretaria escolar' end,
         least(timestamptz '2026-11-03 09:00-03' + make_interval(days => x.h % 7, mins => x.h % 600), now() - interval '1 hour'), true
  from (select n.student_id, abs(hashtext(n.student_id::text || 'tam27')) h, abs(hashtext(n.unit_id::text || 'ukc27')) % 100 fu,
               iara.uk_sugestao_meses((extract(year from age(date '2027-02-15', st.birth_date)) * 12 + extract(month from age(date '2027-02-15', st.birth_date)))::int) s
        from iara.uk_necessidades n join iara.students st on st.id = n.student_id where n.campanha_id = c27 and n.conteudo = 'UNIFORME') x
  where x.h % 100 < case when x.fu < 15 then 12 when x.fu < 70 then 38 else 71 end
    and x.student_id is distinct from (select sg.student_id from iara.student_guardians sg join iara.students st on st.id = sg.student_id
                                       where sg.guardian_id = v_maria and st.status = 'MATRICULADO' limit 1);
  perform iara.uk_gerar(c27);
  -- aviso do pedido de tamanho (03/11) para todos; ciência de quem já informou e de parte dos outros
  insert into iara.uk_avisos (student_id, guardian_id, unit_id, ano, tipo, disparo_id, titulo, texto, enviado_em, whatsapp_status, whatsapp_em, ciente_em, ciente_canal, is_demo)
  select n.student_id, iara.uk_responsavel(n.student_id), n.unit_id, 2027, 'TAMANHO', d27, 'Uniforme 2027: informe os tamanhos',
         format('Informe os tamanhos do uniforme 2027 de %s até 15/12/2026: parte de cima, parte de baixo, número do calçado e o modelo (shorts-saia ou bermuda). Responda aqui com “tamanho do uniforme” ou pelo portal (Vida escolar → Uniforme e kit).',
                split_part(s.full_name, ' ', 1)),
         timestamptz '2026-11-03 08:05-03' + make_interval(secs => (row_number() over (order by n.student_id)) * 20),
         case when abs(hashtext(n.student_id::text || 'w27')) % 100 < 66 then 'SIMULADO' else 'SEM_WHATSAPP' end,
         timestamptz '2026-11-03 08:05-03' + make_interval(secs => (row_number() over (order by n.student_id)) * 20),
         case when t.student_id is not null then t.informado_em when abs(hashtext(n.student_id::text || 'c27')) % 100 < 22 then timestamptz '2026-11-04 19:00-03' end,
         case when t.student_id is not null then t.canal when abs(hashtext(n.student_id::text || 'c27')) % 100 < 22 then 'WHATSAPP' end, true
  from iara.uk_necessidades n join iara.students s on s.id = n.student_id
  left join iara.uk_tamanhos t on t.student_id = n.student_id and t.ano = 2027
  where n.campanha_id = c27 and n.conteudo = 'UNIFORME';
  update iara.uk_disparos set total = (select count(*) from iara.uk_avisos where disparo_id = d27) where id = d27;

  -- ======== estoque ========
  -- SEDUC: kits de 2027 já recebidos em parte; reserva de peças para trocas
  perform iara.estoque_entrar((iara.material_do_produto(null, k.codigo)).id, k.q, 'Entrega do fornecedor (contrato 2027)', 'K27-' || k.codigo, null, null)
  from (select it ->> 'produto' codigo, round(count(*) * 0.6) q from iara.uk_necessidades n, jsonb_array_elements(n.itens) it
        where n.campanha_id = c27 and n.conteudo = 'KIT' group by 1) k where k.q > 0;
  perform iara.estoque_entrar((iara.material_do_produto(null, iara.uk_produto_codigo(i.codigo, g.tamanho))).id, 40 + (abs(hashtext(i.codigo || g.tamanho)) % 120),
                              'Reserva para trocas e reposições', null, null, null)
  from iara.uk_itens i join iara.uk_grades g on g.grade = 'ROUPA' and g.ativo and g.tamanho in ('2', '4', '6', '8', '10', '12')
  where i.tipo = 'UNIFORME' and i.medida in ('SUPERIOR', 'INFERIOR');
  -- unidades: pequena reserva de calça e jaqueta para as trocas
  perform iara.estoque_entrar((iara.material_do_produto(u.id, iara.uk_produto_codigo(i.codigo, g.tamanho))).id, 2 + (abs(hashtext(u.id::text || i.codigo || g.tamanho)) % 4),
                              'Sobra da entrega 2026', null, null, null)
  from iara.education_units u cross join iara.uk_itens i join iara.uk_grades g on g.grade = 'ROUPA' and g.tamanho in ('4', '6', '8', '10')
  where i.codigo in ('UNI-CAL', 'UNI-JAQ') and u.status <> 'SEM_TURMAS';
  update iara.materiais set is_demo = true where codigo ~ '^(UNI|KIT)-[A-Z]';

  -- remessas 2026 (histórico do almoxarifado)
  insert into iara.pedidos (unit_id, origem, situacao, prioridade, justificativa, solicitado_por_label, solicitado_em, decidido_por_label, decidido_em,
                            despachado_em, previsao_entrega, recebido_em, conferido_por_label, is_demo)
  select u.unit_id, 'ALMOXARIFADO', 'RECEBIDO', 'NORMAL', format('Uniformes e kits 2026 — remessa de %s por etapa e tamanho (%s aluno(s)).', k.c, u.n),
         'Gerência de Suprimentos e Almoxarifado', timestamptz '2026-01-21 09:00-03', 'Gerência de Suprimentos e Almoxarifado', timestamptz '2026-01-21 09:00-03',
         timestamptz '2026-01-28 07:30-03', date '2026-02-02', timestamptz '2026-02-03 10:00-03', 'Secretaria escolar', true
  from (select unit_id, count(distinct student_id) n from iara.uk_necessidades where ano = 2026 and tipo = 'ANUAL' group by unit_id) u
  cross join (values ('uniforme'), ('kit escolar')) k(c);
  insert into iara.pedido_itens (pedido_id, produto_codigo, quantidade_pedida, quantidade_aprovada, quantidade_enviada, quantidade_recebida, is_demo)
  select pe.id, it ->> 'produto', sum((it ->> 'quantidade')::numeric), sum((it ->> 'quantidade')::numeric), sum((it ->> 'quantidade')::numeric), sum((it ->> 'quantidade')::numeric), true
  from iara.pedidos pe
  join iara.uk_necessidades n on n.unit_id = pe.unit_id and n.ano = 2026 and n.tipo = 'ANUAL'
       and n.conteudo = case when pe.justificativa like '%remessa de uniforme%' then 'UNIFORME' else 'KIT' end
  cross join jsonb_array_elements(n.itens) it
  where pe.justificativa like 'Uniformes e kits 2026%' and it ->> 'produto' is not null
  group by pe.id, it ->> 'produto';
  update iara.uk_necessidades n set pedido_id = pe.id
  from iara.pedidos pe where pe.justificativa like 'Uniformes e kits 2026%' and pe.unit_id = n.unit_id and n.ano = 2026 and n.tipo = 'ANUAL'
    and n.conteudo = case when pe.justificativa like '%remessa de uniforme%' then 'UNIFORME' else 'KIT' end;

  -- ======== família da Maria ========
  select sg.student_id, e.unit_id into v_ana, v_ana_unit from iara.student_guardians sg join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
  where sg.guardian_id = v_maria order by sg.is_primary desc limit 1;
  if v_ana is not null then
    update iara.uk_tamanhos set superior = '6', inferior = '6', calcado = 28, modelo_inferior = 'SHORTS_SAIA', canal = 'WHATSAPP', guardian_id = v_maria,
           informado_por_label = (select full_name from iara.guardians where id = v_maria), informado_em = timestamptz '2025-11-06 20:41-03'
    where student_id = v_ana and ano = 2026;
    update iara.uk_necessidades set itens = iara.uk_montar_itens(conteudo, etapa, ampliacao, (select t from iara.uk_tamanhos t where t.student_id = v_ana and t.ano = 2026)),
           tipo = 'ANUAL', situacao = 'RETIRADA', disponivel_em = timestamptz '2026-02-05 14:00-03', prazo_retirada = date '2026-03-07',
           retirada_em = timestamptz '2026-02-12 10:14-03', retirada_por_nome = (select full_name from iara.guardians where id = v_maria), retirada_por_parentesco = 'Mãe',
           retirada_por_guardian = v_maria, retirada_documento = null, codigo_conferido = true, entregue = null
    where student_id = v_ana and ano = 2026 and tipo in ('ANUAL', 'ALUNO_NOVO');
    delete from iara.uk_necessidades where student_id = v_ana and tipo in ('TROCA_TAMANHO', 'REPOSICAO', 'ADAPTADO');
    -- a troca da jaqueta: aprovada e liberada (código e aviso aguardando a ciência da Maria)
    insert into iara.uk_necessidades (campanha_id, ano, student_id, unit_id, etapa, tipo, conteudo, itens, motivo, origem, solicitante_label, situacao,
                                      decisao_motivo, decidido_por_label, decidido_em, disponivel_em, prazo_retirada, created_at, is_demo)
    values (c26, 2026, v_ana, v_ana_unit, iara.uk_etapa_aluno(v_ana, 2026), 'TROCA_TAMANHO', 'UNIFORME',
            jsonb_build_array(jsonb_build_object('item', 'UNI-JAQ', 'nome', 'Jaqueta', 'tamanho', '8', 'quantidade', 1, 'produto', iara.uk_produto_codigo('UNI-JAQ', '8'))),
            'A jaqueta tamanho 6 ficou apertada nos braços.', 'FAMILIA', (select full_name from iara.guardians where id = v_maria), 'DISPONIVEL',
            null, 'Secretaria escolar', now() - interval '2 days', now() - interval '1 day', iara.hoje_local() + 29, now() - interval '4 days', true)
    returning id into v_nec;
    perform iara.estoque_entrar((iara.material_do_produto(v_ana_unit, iara.uk_produto_codigo('UNI-JAQ', '8'))).id, 3, 'Sobra da entrega 2026', null, null, null);
    update iara.materiais set is_demo = true where unit_id = v_ana_unit and codigo = iara.uk_produto_codigo('UNI-JAQ', '8');
    delete from iara.uk_codigos where ano = 2026 and (codigo = '482913' or student_id = v_ana);
    insert into iara.uk_codigos (student_id, ano, codigo) values (v_ana, 2026, '482913');
    delete from iara.uk_avisos where student_id = v_ana;
    insert into iara.uk_avisos (student_id, guardian_id, unit_id, ano, tipo, necessidade_ids, titulo, texto, enviado_em, whatsapp_status, whatsapp_em, ciente_em, ciente_canal, is_demo) values
      (v_ana, v_maria, v_ana_unit, 2026, 'RETIRADA', '{}', 'Uniforme e kit escolar: pode retirar',
       format('Uniforme e kit escolar de Ana: disponível para retirada no(a) %s até 07/03/2026. Leve o código de retirada ou documento com foto.', (select short_name from iara.education_units where id = v_ana_unit)),
       timestamptz '2026-02-05 14:00-03', 'SIMULADO', timestamptz '2026-02-05 14:01-03', timestamptz '2026-02-05 18:22-03', 'WHATSAPP', true),
      (v_ana, v_maria, v_ana_unit, 2026, 'RETIRADA_REGISTRADA', '{}', 'Retirada registrada',
       format('Uniforme e kit escolar de Ana retirado(s) em 12/02/2026 às 10:14 por %s (mãe), no(a) %s.', (select full_name from iara.guardians where id = v_maria),
              (select short_name from iara.education_units where id = v_ana_unit)),
       timestamptz '2026-02-12 10:14-03', 'SIMULADO', timestamptz '2026-02-12 10:15-03', timestamptz '2026-02-12 12:03-03', 'PORTAL', true),
      (v_ana, v_maria, v_ana_unit, 2026, 'DECISAO', array[v_nec], 'Troca de tamanho: aprovada',
       'O pedido de troca de tamanho de Ana foi aprovado. Avisaremos quando puder retirar.',
       now() - interval '2 days', 'SIMULADO', now() - interval '2 days', now() - interval '2 days' + interval '3 hours', 'WHATSAPP', true),
      (v_ana, v_maria, v_ana_unit, 2026, 'RETIRADA', array[v_nec], 'Uniforme e kit escolar: pode retirar',
       iara.uk_texto_retirada(v_ana, 2026, array['UNIFORME'], iara.hoje_local() + 29), now() - interval '1 day', 'SIMULADO', now() - interval '1 day', null, null, true),
      (v_ana, v_maria, v_ana_unit, 2027, 'TAMANHO', '{}', 'Uniforme 2027: informe os tamanhos',
       'Informe os tamanhos do uniforme 2027 de Ana até 15/12/2026: parte de cima, parte de baixo, número do calçado e o modelo (shorts-saia ou bermuda). Responda aqui com “tamanho do uniforme” ou pelo portal (Vida escolar → Uniforme e kit).',
       timestamptz '2026-11-03 08:31-03', 'SIMULADO', timestamptz '2026-11-03 08:31-03', null, null, true);
  end if;

  -- quem ficou sem código (coincidência de números na geração) recebe um novo
  perform iara.uk_codigo(x.student_id, 2026)
  from (select distinct n.student_id from iara.uk_necessidades n where n.ano = 2026 and n.situacao <> 'AGUARDANDO_MATERIAL'
        and not exists (select 1 from iara.uk_codigos c where c.student_id = n.student_id and c.ano = 2026)) x;
  update iara.uk_avisos set agendado_para = coalesce(agendado_para, whatsapp_em, enviado_em) where is_demo;
  update iara.uk_necessidades set is_demo = true where not is_demo;
  update iara.tenants set settings = settings || jsonb_build_object('demo_uniformes_gerado_em', now()) where id = 1;
  return jsonb_build_object('ok', true,
    'necessidades_2026', (select count(*) from iara.uk_necessidades where ano = 2026),
    'necessidades_2027', (select count(*) from iara.uk_necessidades where ano = 2027),
    'tamanhos_2027', (select count(*) from iara.uk_tamanhos where ano = 2027),
    'avisos', (select count(*) from iara.uk_avisos),
    'pedidos', (select count(*) from iara.pedidos where justificativa like 'Uniformes e kits %'));
end $$;

-- limpeza da apresentação: o que foi feito ao vivo some; se a demonstração foi alterada, o cenário é recriado
create or replace function iara.demo_purge_uniformes(p_desde timestamptz) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_gerado timestamptz := nullif(iara.setting('demo_uniformes_gerado_em'), '')::timestamptz;
  v_mudou boolean;
begin
  if not iara.demo_mode() then return jsonb_build_object('ok', false); end if;
  v_mudou := v_gerado is null
    or exists (select 1 from iara.uk_necessidades where not is_demo or updated_at > v_gerado + interval '1 minute')
    or exists (select 1 from iara.uk_tamanhos where not is_demo or informado_em > v_gerado)
    or exists (select 1 from iara.uk_avisos where not is_demo or ciente_em > v_gerado)
    or exists (select 1 from iara.uk_disparos where not is_demo)
    or exists (select 1 from iara.uk_campanhas where not is_demo or updated_at > v_gerado + interval '1 minute')
    or exists (select 1 from iara.pedidos where justificativa like 'Uniformes e kits %' and not is_demo);
  if not v_mudou then return jsonb_build_object('ok', true, 'recriado', false); end if;
  return jsonb_build_object('ok', true, 'recriado', true, 'demonstracao', iara.demo_gerar_uniformes());
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
                               'uniformes', iara.demo_purge_uniformes(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_gerar_uniformes(), iara.demo_purge_uniformes(timestamptz) from public;

select iara.demo_gerar_uniformes();

commit;
