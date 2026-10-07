-- Auditoria reforçada: imutabilidade (UPDATE, DELETE, TRUNCATE), corrente de hashes e proteção de dados sensíveis na trilha.
-- Roda numa transação revertida: as adulterações simuladas abaixo NÃO ficam na base.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/auditoria_integridade.sql
do $$
declare
  v_out jsonb := '[]';
  v_err text;
  r jsonb;
  v_id bigint;
  v_aluno uuid;
begin
  -- 1. novo evento entra na corrente
  perform iara.audit_event('TESTE_INTEGRIDADE', 'teste', '1', null, 'Evento de teste da corrente');
  r := iara.auditoria_verificar((select seq from iara.audit_chain_head) - 5, null);
  v_out := v_out || jsonb_build_object('passo', '1. Evento novo encadeado', 'ok', (r ->> 'integra')::boolean);

  -- 2. alterar, apagar ou truncar: recusado
  select max(id) into v_id from iara.audit_log;
  begin update iara.audit_log set summary = 'adulterado' where id = v_id; v_err := null; exception when others then v_err := sqlstate; end;
  v_out := v_out || jsonb_build_object('passo', '2a. UPDATE recusado', 'ok', v_err = '42501');
  begin delete from iara.audit_log where id = v_id; v_err := null; exception when others then v_err := sqlstate; end;
  v_out := v_out || jsonb_build_object('passo', '2b. DELETE recusado', 'ok', v_err = '42501');
  begin truncate iara.audit_log; v_err := null; exception when others then v_err := sqlstate; end;
  v_out := v_out || jsonb_build_object('passo', '2c. TRUNCATE recusado', 'ok', v_err = '42501');

  -- 3. quem desliga a proteção (dono do banco) e altera o conteúdo é descoberto pela verificação
  alter table iara.audit_log disable trigger audit_log_no_update;
  update iara.audit_log set summary = 'adulterado' where id = v_id;
  r := iara.auditoria_verificar(1, null);
  v_out := v_out || jsonb_build_object('passo', '3. Alteração detectada', 'ok', not (r ->> 'integra')::boolean
    and r #>> '{primeira_quebra,motivo}' = 'conteúdo alterado', 'quebra', r -> 'primeira_quebra');

  -- 4. ... e a remoção de um registro do meio também
  update iara.audit_log set summary = 'Evento de teste da corrente' where id = v_id;
  delete from iara.audit_log where chain_seq = (select seq from iara.audit_chain_head) - 3;
  r := iara.auditoria_verificar(1, null);
  v_out := v_out || jsonb_build_object('passo', '4. Remoção detectada', 'ok', not (r ->> 'integra')::boolean
    and r #>> '{primeira_quebra,motivo}' like 'corrente interrompida%');
  alter table iara.audit_log enable trigger audit_log_no_update;

  -- 5. fora do modo demonstração, CPF entra na trilha como hash (sem o número)
  update iara.tenants set settings = settings || '{"demo_mode": false}'::jsonb where id = 1;
  select id into v_aluno from iara.students limit 1;
  update iara.students set cpf = '529.982.247-25' where id = v_aluno;
  select after_json into r from iara.audit_log where entity_type = 'students' and entity_id = v_aluno::text order by id desc limit 1;
  v_out := v_out || jsonb_build_object('passo', '5. CPF protegido na trilha (produção)', 'ok', (r ->> 'cpf') like 'sha256:%' and r::text not like '%529.982%');

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
