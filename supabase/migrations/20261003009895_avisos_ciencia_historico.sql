-- IARA Educa — 098.95 · Avisos da família: todo aviso pede ciência, e quem deu a ciência leva o aviso para o histórico.
-- Decisão de Rob (05/11/2026): sempre a data e a hora do envio e a opção de ciência; depois da ciência, o aviso some do quadro e vai para um
-- histórico de avisos. O histórico guarda o aviso mesmo depois de ele vencer ou ser arquivado, com a hora em que a família deu a ciência.
-- A escola vê a contagem de ciências em todo aviso para as famílias.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create or replace function api.familia_avisos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v_quadro jsonb;
  v_historico jsonb;
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  -- quadro: o que a família enxerga e ainda não deu ciência
  select coalesce(jsonb_agg(iara.mural_json(m) || jsonb_build_object('filhos', f.filhos, 'exige_confirmacao', true,
           'lido', l.lido_em is not null, 'confirmado', false, 'minha_resposta', r.opcao,
           'votos', case when r.opcao is not null then iara.mural_votos(m) end)
         order by m.fixado desc, m.publicado_em desc), '[]')
  into v_quadro
  from iara.mural_da_familia() f join iara.mural_publicacoes m on m.id = f.publicacao_id
  left join iara.mural_leituras l on l.publicacao_id = m.id and l.guardian_id = v_g
  left join iara.mural_enquete_respostas r on r.publicacao_id = m.id and r.guardian_id = v_g
  where l.confirmado_em is null;

  -- histórico: tudo a que a família deu ciência, mesmo depois de o aviso vencer ou ser arquivado
  select coalesce(jsonb_agg(iara.mural_json(q.m) || jsonb_build_object('filhos', q.filhos, 'exige_confirmacao', true, 'lido', true, 'confirmado', true,
           'ciente_em', q.confirmado_em, 'minha_resposta', q.opcao, 'votos', case when q.opcao is not null then iara.mural_votos(q.m) end)
         order by q.confirmado_em desc), '[]')
  into v_historico
  from (select m, f.filhos, l.confirmado_em, r.opcao
        from iara.mural_leituras l join iara.mural_publicacoes m on m.id = l.publicacao_id
        left join iara.mural_da_familia() f on f.publicacao_id = m.id
        left join iara.mural_enquete_respostas r on r.publicacao_id = m.id and r.guardian_id = v_g
        where l.guardian_id = v_g and l.confirmado_em is not null
        order by l.confirmado_em desc limit 100) q;

  return jsonb_build_object('avisos', v_quadro, 'historico', v_historico,
    'nao_lidos', (select count(*) from jsonb_array_elements(v_quadro) a where not (a ->> 'lido')::boolean),
    'pendentes_confirmacao', jsonb_array_length(v_quadro),
    'enquetes_abertas', (select count(*) from jsonb_array_elements(v_quadro) a where a ->> 'tipo' = 'ENQUETE' and a ->> 'minha_resposta' is null));
end $$;

-- ciência dá a resposta com a hora: a família e a IARA dizem quando foi
create or replace function api.familia_aviso_ler(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v_id uuid := (p ->> 'id')::uuid;
  v_conf boolean := coalesce((p ->> 'confirmar')::boolean, false);
  v_em timestamptz;
begin
  if v_g is null or not exists (select 1 from iara.mural_da_familia() f where f.publicacao_id = v_id) then
    raise exception 'Aviso não encontrado.' using errcode = 'P0002';
  end if;
  insert into iara.mural_leituras (publicacao_id, guardian_id, lido_em, confirmado_em)
  values (v_id, v_g, now(), case when v_conf then now() end)
  on conflict (publicacao_id, guardian_id) do update set confirmado_em = coalesce(iara.mural_leituras.confirmado_em, excluded.confirmado_em)
  returning confirmado_em into v_em;
  if v_conf then
    perform iara.audit_event('MURAL_CIENCIA', 'mural', v_id::text, null, 'Ciência de aviso confirmada pela família.');
  end if;
  return jsonb_build_object('ok', true, 'confirmado', v_em is not null, 'ciente_em', v_em);
end $$;

-- todo aviso às famílias pede ciência. Na demonstração, quem não pedia ganha a contagem proporcional às leituras, para o quadro da escola
-- não mostrar "0 confirmaram"
update iara.mural_publicacoes set exige_confirmacao = true,
       confirmacoes_demo = case when is_demo and confirmacoes_demo = 0 then round(leituras_demo * 0.8)::int else confirmacoes_demo end
where publico <> 'PROFISSIONAIS' and not exige_confirmacao;

commit;
