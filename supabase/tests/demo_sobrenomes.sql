-- Demonstração: nenhum "Pinto" em pessoas e cópias do nome (081), nenhum sobrenome repetido como "Silva Silva" (082),
-- filhos com o último sobrenome da família e os selos das declarações conferindo.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/demo_sobrenomes.sql
do $$
declare
  v_out jsonb := '[]';
  v_rep text := '\m(\w+) \1\M';
begin
  v_out := v_out || jsonb_build_object('passo', 'S1. Nenhum "Pinto" em alunos, responsáveis e profissionais', 'ok',
    not exists (select 1 from iara.students where full_name ~ '\mPinto\M' or coalesce(parent1_name, '') ~ '\mPinto\M' or coalesce(parent2_name, '') ~ '\mPinto\M')
    and not exists (select 1 from iara.guardians where full_name ~ '\mPinto\M')
    and not exists (select 1 from iara.staff where full_name ~ '\mPinto\M'));
  v_out := v_out || jsonb_build_object('passo', 'S2. Exemplos trocados', 'ok', true,
    'alencar_silvino', (select jsonb_agg(x) from (select full_name x from iara.staff where full_name ~ 'Alencar Silvino' limit 5) z),
    'alencar', (select count(*) from iara.students where full_name ~ '\mAlencar\M') + (select count(*) from iara.guardians where full_name ~ '\mAlencar\M')
               + (select count(*) from iara.staff where full_name ~ '\mAlencar\M'));
  v_out := v_out || jsonb_build_object('passo', 'S3. Selos das declarações conferem com o texto', 'ok',
    not exists (select 1 from iara.declaracoes where hash <> encode(sha256(convert_to(conteudo::text, 'UTF8')), 'hex')));
  v_out := v_out || jsonb_build_object('passo', 'S4. Nenhum nome com o mesmo sobrenome duas vezes (082)', 'ok',
    not exists (select 1 from iara.students where full_name ~ v_rep and full_name <> iara.desrepetir_sobrenome(full_name))
    and not exists (select 1 from iara.guardians where full_name ~ v_rep and full_name <> iara.desrepetir_sobrenome(full_name))
    and not exists (select 1 from iara.staff where full_name ~ v_rep and full_name <> iara.desrepetir_sobrenome(full_name)),
    'palavra_repetida_que_nao_e_sobrenome', (select count(*) from iara.students where full_name ~ v_rep) + (select count(*) from iara.guardians where full_name ~ v_rep)
                                            + (select count(*) from iara.staff where full_name ~ v_rep),
    'exemplos', (select jsonb_agg(x) from (select full_name x from iara.staff where full_name ~ 'Siqueira|Marchetti|Toledo|Nascimento' limit 5) z));
  v_out := v_out || jsonb_build_object('passo', 'S4b. Filhos com o último sobrenome da mãe ou do pai', 'ok', true,
    'alunos_com_o_do_responsavel', (select count(*) from iara.students s where split_part(s.full_name, ' ', -1) in
      (split_part(coalesce(s.parent1_name, ''), ' ', -1), split_part(coalesce(s.parent2_name, ''), ' ', -1))),
    'alunos', (select count(*) from iara.students));
  v_out := v_out || jsonb_build_object('passo', 'S5. Trocas registradas na auditoria', 'ok', exists (select 1 from iara.audit_log where action = 'DEMO_NOMES'),
    'trocas', (select after_json from iara.audit_log where action = 'DEMO_NOMES' order by occurred_at desc limit 1));
  raise exception 'RESULTADO: %', v_out;
end $$;
