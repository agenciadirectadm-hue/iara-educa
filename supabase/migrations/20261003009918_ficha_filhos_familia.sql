-- IARA Educa — Ficha de cada filho no portal da família ("Minha família") e vida escolar por filho.
-- 1. api.familia_fichas: a ficha completa de cada criança da família, só para o próprio responsável
--    (documentos mascarados, como em "Documentos e dados das crianças").
-- 2. api.familia_reunioes passa a mandar o student_id, para a aba "Reuniões" abrir por filho.

-- 1. Ficha dos filhos ----------------------------------------------------------------------------------------------
create or replace function api.familia_fichas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v_addr uuid;
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select address_id into v_addr from iara.guardians where id = v_g;
  return coalesce((select jsonb_agg(f order by f ->> 'nascimento') from (
    select jsonb_build_object(
      'student_id', s.id, 'nome', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1), 'nome_social', s.social_name,
      'nascimento', s.birth_date, 'idade', iara.age_text(s.birth_date), 'sexo', s.gender, 'cor_raca', s.race_color,
      'nacionalidade', s.nationality, 'pais_nascimento', s.birth_country, 'naturalidade_municipio', s.birth_city, 'naturalidade_uf', s.birth_state,
      'filiacao_1', s.parent1_name, 'filiacao_2', s.parent2_name, 'situacao', s.status, 'foto_arquivo_id', s.foto_arquivo_id,
      'parentesco', sg.relationship, 'uso_imagem', s.image_consent, 'aee', s.aee_status, 'acessibilidade', s.accessibility_needs,
      'registro', s.student_registry_number, 'codigo_inep', s.inep_id,
      'cpf', iara.mascara_doc(s.cpf), 'nis', iara.mascara_doc(s.nis), 'cartao_sus', iara.mascara_doc(s.sus_card),
      'certidao', iara.mascara_doc(s.birth_certificate),
      'faixa', iara.grade_for_birthdate(s.birth_date),
      'pendencias', to_jsonb(iara.aluno_pendencias(s, true)),
      'mesmo_endereco', s.address_id is not distinct from v_addr,
      'endereco', case when s.address_id is not null and s.address_id is distinct from v_addr then (iara.endereco_json(s.address_id) ->> 'linha') end,
      'matricula', (select jsonb_build_object(
          'unidade_id', u.id, 'unidade', u.name, 'unidade_curta', u.short_name, 'unidade_endereco', u.address_line, 'unidade_bairro', u.neighborhood,
          'unidade_telefone', u.phone, 'direcao', u.director_name,
          'turma', c.class_name, 'etapa', gl.name, 'turno', c.shift, 'sala', c.room_label, 'ano_letivo', e.school_year,
          'desde', coalesce(e.start_date, e.enrollment_date), 'entrada', e.entry_type,
          'distancia_m', (select round(st_distance(u.location, a.location))::int from iara.addresses a where a.id = coalesce(s.address_id, v_addr)),
          'regente', (select st.full_name from iara.class_staff cs join iara.staff st on st.id = cs.staff_id
                      where cs.class_id = c.id and cs.end_date is null and cs.role_type = 'REGENTE' order by cs.is_primary desc limit 1),
          'outros_professores', (select count(*) from iara.class_staff cs where cs.class_id = c.id and cs.end_date is null and cs.role_type <> 'REGENTE'))
        from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.education_units u on u.id = e.unit_id
        left join iara.grade_levels gl on gl.id = c.grade_level_id
        where e.student_id = s.id and e.status = 'ACTIVE' order by e.enrollment_date desc limit 1),
      'fila', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'situacao', w.status, 'posicao', w.position, 'pontos', w.priority_score,
          'unidade', u.name, 'etapa', gl.name, 'categoria', w.demand_category, 'desde', w.entered_at) order by w.entered_at desc)
        from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id join iara.grade_levels gl on gl.id = w.grade_level_id
        where w.student_id = s.id and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')), '[]'),
      'restricoes', coalesce((select jsonb_agg(jsonb_build_object('descricao', ra.descricao, 'detalhe', r.detalhe, 'situacao', r.situacao) order by ra.ordem)
        from iara.aluno_restricoes r join iara.restricoes_alimentares ra on ra.codigo = r.restricao_codigo
        where r.student_id = s.id and (r.fim is null or r.fim >= current_date) and r.situacao <> 'RECUSADA'), '[]'),
      'transporte', jsonb_build_object('precisa', s.transport_need, 'situacao', s.school_transport_status,
        'rota', (select jsonb_build_object('codigo', ro.codigo, 'nome', ro.nome, 'ponto', po.nome, 'ida', po.horario_ida, 'volta', po.horario_volta)
                 from iara.transporte_alunos t join iara.transporte_rotas ro on ro.id = t.rota_id left join iara.transporte_pontos po on po.id = t.ponto_id
                 where t.student_id = s.id and t.fim is null order by t.inicio desc limit 1)),
      'responsaveis', coalesce((select jsonb_agg(jsonb_build_object(
          'nome', g.full_name, 'eu', g.id = v_g, 'parentesco', x.relationship, 'principal', x.is_primary, 'pode_buscar', x.can_pick_up,
          'recebe_avisos', x.can_receive_notifications, 'situacao_legal', x.legal_authority_status,
          'telefone', iara.mask_phone(coalesce(g.whatsapp_phone, g.primary_phone)))
          order by (g.id = v_g) desc, x.is_primary desc, g.full_name)
        from iara.student_guardians x join iara.guardians g on g.id = x.guardian_id
        where x.student_id = s.id and x.end_date is null), '[]'),
      'documentos', (select jsonb_build_object(
          'validados', count(*) filter (where d.status = 'VALIDADO'),
          'em_conferencia', count(*) filter (where d.status = 'PENDENTE'),
          'recusados', count(*) filter (where d.status = 'REJEITADO'),
          'faltando', (select coalesce(jsonb_agg(t order by t), '[]') from unnest(array['CERTIDAO', 'COMPROVANTE_ENDERECO', 'CARTAO_SUS', 'VACINACAO']) t
                       where not exists (select 1 from iara.documents d2 where d2.student_id = s.id and d2.doc_type = t)))
        from (select distinct on (doc_type) * from iara.documents where student_id = s.id order by doc_type, created_at desc) d)
    ) as f
    from iara.student_guardians sg join iara.students s on s.id = sg.student_id
    where sg.guardian_id = v_g and sg.end_date is null and s.id in (select iara.my_student_ids())) z), '[]'::jsonb);
end $$;

-- 2. Reuniões com o identificador do filho ---------------------------------------------------------------------------
create or replace function api.familia_reunioes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (with base as (
      select r.* from iara.reunioes_responsavel r
      where r.guardian_id = v_g and r.envia_responsavel and r.student_id in (select iara.my_student_ids()))
    select jsonb_build_object(
      'aguardando', (select count(*) from base where situacao in ('AGUARDANDO', 'PRAZO_VENCIDO')),
      'reunioes', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', b.id, 'codigo', iara.reuniao_codigo(b.id), 'student_id', b.student_id, 'aluno', split_part(s.full_name, ' ', 1), 'unidade', u.short_name,
          'tema_rotulo', iara.reuniao_tema_rotulo(b.tema),
          'realizada_em', b.realizada_em, 'resumo', b.resumo, 'solucoes', b.solucoes, 'posicao_escola', b.posicao_escola, 'posicao_responsavel', b.posicao_responsavel,
          'situacao', b.situacao, 'pode_responder', b.situacao in ('AGUARDANDO', 'PRAZO_VENCIDO'), 'resposta_em', b.resposta_em, 'manifestacao', b.manifestacao,
          'avisos', (select coalesce(jsonb_agg(jsonb_build_object('dia', e.dia, 'titulo', e.titulo, 'texto', e.texto, 'em', e.em) order by e.dia), '[]')
                     from iara.reuniao_eventos e where e.reuniao_id = b.id and e.tipo = 'AVISO'))
          order by (b.situacao in ('AGUARDANDO', 'PRAZO_VENCIDO')) desc, b.realizada_em desc), '[]')
        from base b join iara.students s on s.id = b.student_id left join iara.education_units u on u.id = b.unit_id)));
end $$;
