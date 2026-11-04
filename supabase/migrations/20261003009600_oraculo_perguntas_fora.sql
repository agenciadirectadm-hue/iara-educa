-- IARA Educa — 096 · Oráculo: perguntas que ele não responde
-- O Oráculo traz só números consolidados por assunto. Pergunta sobre pessoas pelo nome ("quantos alunos se chamam Silvio?")
-- recebe a explicação, sem número; pergunta em que não se acha assunto recebe o aviso e o resumo da rede (antes vinha só o
-- resumo, como se fosse a resposta).
begin;

create or replace function api.oraculo_perguntar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  v_n text := iara.norm(coalesce(p ->> 'pergunta', ''));
  v_topico text;
  v_rec jsonb := iara.oraculo_recorte(p ->> 'pergunta');
  r jsonb;
  v_texto text;
  x jsonb;
  v_partes text[] := '{}';
  v_exemplos constant text := 'Pergunte, por exemplo: “Quantas crianças esperam vaga na creche?”, “Como está a frequência na AP 017?” '
                              || 'ou “Quantos alunos do Bolsa Família ficaram abaixo da frequência mínima?”.';
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then
    raise exception 'Faça uma pergunta.' using errcode = '22023';
  end if;
  -- pessoas pelo nome: fora do Oráculo (só números agregados, sem dado de pessoa)
  if v_n ~ '(se chama|chamad|com o nome|com nome|de nome|nomes? )' then
    v_texto := 'O Oráculo não conta nem procura pessoas pelo nome: ele traz só números consolidados por assunto (matrículas, fila, vagas, '
               || 'frequência, ocorrências, profissionais, transporte, alfabetização, busca ativa, cadastros e Bolsa Família). ' || v_exemplos;
    insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
    values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', v_texto, '[]'::jsonb, iara.demo_mode());
    return jsonb_build_object('pergunta', v_perg, 'resposta', v_texto, 'modo', 'REGRAS', 'topico', null, 'numeros', '[]'::jsonb, 'fora', true);
  end if;
  v_topico := case
    when v_n ~ 'bolsa|beneficio|condicionalidade|sistema presenca|cadunico' then 'bolsa_familia'
    when v_n ~ 'creche|bercario' then 'creche'
    when v_n ~ 'fila|espera|aguard' then 'fila'
    when v_n ~ 'vaga' then 'vagas'
    when v_n ~ 'frequenc|presenc|falta|ausen' then 'frequencia'
    when v_n ~ 'ocorrenc|violenc|bullying|briga|acidente|indisciplina' then 'ocorrencias'
    when v_n ~ 'professor|profissiona|servidor|educador|auxiliar|docente|funcionari' then 'profissionais'
    when v_n ~ 'transporte|onibus|rota|van|veicul|motorista' then 'transporte'
    when v_n ~ 'alfabetiz|leitura|escrita|sondagem|ler e escrever' then 'alfabetizacao'
    when v_n ~ 'busca ativa|evasao|abandono' then 'busca_ativa'
    when v_n ~ 'cadastr|documento' then 'cadastros'
    when v_n ~ 'matricul|aluno|estudante' then 'matriculas'
    when v_n ~ 'unidade|escola|cmei' then 'unidades'
    when v_n ~ 'geral|resumo|panorama|como esta|situacao|rede' then 'visao_geral'
    else null end;
  r := iara.oraculo_numeros(coalesce(v_topico, 'visao_geral'), (v_rec ->> 'unidade')::int, (v_rec ->> 'area')::int);
  for x in select * from jsonb_array_elements(r -> 'numeros') loop
    v_partes := v_partes || ((x ->> 'rotulo') || ': '
                 || iara.num_br((x ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', ''));
  end loop;
  v_texto := case when v_topico is null then 'Não achei na pergunta um assunto que o Oráculo conheça. Segue o resumo da rede. ' else '' end
             || 'Em ' || (r ->> 'recorte') || ' — ' || array_to_string(v_partes, '; ') || '.'
             || case when v_topico is null then ' ' || v_exemplos else '' end;
  insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
  values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', v_texto,
          jsonb_build_array(jsonb_build_object('topico', coalesce(v_topico, 'visao_geral'), 'unidade', v_rec -> 'unidade', 'area', v_rec -> 'area')), iara.demo_mode());
  return r || jsonb_build_object('pergunta', v_perg, 'resposta', v_texto, 'modo', 'REGRAS', 'fora', v_topico is null);
end $$;

commit;
