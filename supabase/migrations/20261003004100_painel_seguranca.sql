-- IARA Educa — 041 · Painel de segurança (Fase 2, item 19 do documento de estrutura — SEC-MON-02 e SEC-MON-04)
-- Primeira versão, só com o que o próprio sistema já registra: integridade da trilha, bloqueios por excesso de
-- requisições, números barrados no WhatsApp, leituras de dado sensível, consultas do controle externo, exportações,
-- mudanças de regra e de prioridade, cargas de dados e limpezas da demonstração. Os alertas externos (e-mail/mensagem
-- para a equipe de plantão) dependem do responsável e do canal definidos no plano de incidentes (pendente).
begin;

-- registra o primeiro estouro de cada limite em cada janela (não a cada requisição recusada)
create table if not exists iara.eventos_seguranca (
  id bigserial primary key,
  tipo text not null,
  chave text,
  detalhe jsonb,
  em timestamptz not null default now()
);
create index if not exists eventos_seguranca_em_idx on iara.eventos_seguranca (em desc);
alter table iara.eventos_seguranca enable row level security;

create or replace function iara.taxa(p_chaves text[], p_max integer[], p_janela_s integer[]) returns text
language plpgsql security definer set search_path = iara, public
as $$
declare
  i integer;
  v_n integer;
  v_j timestamptz;
begin
  for i in 1 .. coalesce(array_length(p_chaves, 1), 0) loop
    v_j := to_timestamp(floor(extract(epoch from now()) / p_janela_s[i]) * p_janela_s[i]);
    insert into iara.limites_taxa as t (chave, janela, n) values (left(p_chaves[i], 200), v_j, 1)
    on conflict (chave, janela) do update set n = t.n + 1
    returning t.n into v_n;
    if v_n > p_max[i] then
      if v_n = p_max[i] + 1 then
        -- a chave guarda só o tipo e um resumo do IP/sessão (sem o endereço completo)
        insert into iara.eventos_seguranca (tipo, chave, detalhe)
        values ('LIMITE_EXCEDIDO', split_part(p_chaves[i], ':', 1),
                jsonb_build_object('origem', left(md5(p_chaves[i]), 10), 'maximo', p_max[i], 'janela_s', p_janela_s[i]));
      end if;
      return p_chaves[i];
    end if;
  end loop;
  if random() < 0.01 then
    delete from iara.limites_taxa where janela < now() - interval '1 day';
    delete from iara.eventos_seguranca where em < now() - interval '180 days';
  end if;
  return null;
end $$;
revoke all on function iara.taxa(text[], integer[], integer[]) from public;

create or replace function api.seguranca_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_h integer := least(greatest(coalesce((p ->> 'horas')::int, 24), 1), 24 * 30);
  v_desde timestamptz := now() - make_interval(hours => v_h);
  v_seq bigint := (select seq from iara.audit_chain_head where id = 1);
begin
  perform iara.require_perm('audit.read');
  return jsonb_build_object(
    'periodo_horas', v_h,
    'auditoria', iara.auditoria_verificar(greatest(v_seq - 5000, 1), null) || jsonb_build_object('total', v_seq),
    'limites_excedidos', (select coalesce(jsonb_object_agg(chave, n), '{}'::jsonb) from (
       select chave, count(*) n from iara.eventos_seguranca where tipo = 'LIMITE_EXCEDIDO' and em >= v_desde group by 1) z),
    'whatsapp_barrados', (select count(*) from iara.whatsapp_avisos_bloqueio where ultimo_aviso_em >= v_desde),
    'eventos', (select coalesce(jsonb_object_agg(action, n), '{}'::jsonb) from (
       select action, count(*) n from iara.audit_log
       where occurred_at >= v_desde
         and action in ('VIEW_SENSITIVE', 'CONTROLE_CONSULTA', 'EXPORT', 'RULE_VERSION', 'REGRA_MEDIDA_DISTANCIA', 'PRIORITY_DECISION',
                        'PRIORITY_FLAG', 'QUEUE_RECALCULATED', 'CARGA_PROMOVIDA', 'CARGA_REVERTIDA', 'DEMO_PURGE', 'WHATSAPP_CANAL',
                        'WHATSAPP_AUTORIZADOS', 'LOGIN_DEMO')
       group by 1) z),
    -- quem mais leu dado sensível no período (servidor que abre dezenas de fichas em pouco tempo merece olhar)
    'leituras_sensiveis_por_pessoa', (select coalesce(jsonb_agg(jsonb_build_object('quem', actor_label, 'perfil', actor_role, 'leituras', n) order by n desc), '[]'::jsonb)
       from (select actor_label, actor_role, count(*) n from iara.audit_log where action = 'VIEW_SENSITIVE' and occurred_at >= v_desde
             group by 1, 2 order by 3 desc limit 5) z),
    'modo_demonstracao', iara.demo_mode()
  );
end $$;

commit;
