-- Dados do simulador de preços — PRIVADO: preços e propostas, fora do repositório público (ver .gitignore).
-- Gerado por scripts/simulador/extrai_sim.py a partir da calculadora; aplicar depois da migration 084:
-- node scripts/aplicar.mjs supabase/privado/simulador_dados.sql
begin;

-- o redutor que o titular definiu no simulador vale mais que o da planilha: guarda e devolve pelo nome da prefeitura
create temp table _redutor_app on commit drop as select nome, redutor from iara.sim_municipios where redutor <> 0;
-- licença e treinamento da implantação não vêm da planilha: os valores definidos no banco continuam valendo
create temp table _implantacao_app on commit drop as select chave, valor from iara.sim_parametros where chave like 'impl\_%';
truncate iara.sim_agentes, iara.sim_municipios, iara.sim_parametros;
insert into iara.sim_agentes (num, nome, assuntos, tipo, criticidade, dimensao, situacao, cobranca, disparador, implantacao, mensal) values
--AGENTES--;
insert into iara.sim_municipios (id, nome, uf, unidades, ocupadas, creche, fila_informada, docentes, outros, filas_centrais, filas_setor, conveniadas, redutor, observacao) values
--MUNICIPIOS--;
insert into iara.sim_parametros (chave, valor) values
--PARAMETROS--;
update iara.sim_municipios m set redutor = r.redutor from _redutor_app r where r.nome = m.nome;
insert into iara.sim_parametros (chave, valor) select chave, valor from _implantacao_app on conflict (chave) do update set valor = excluded.valor;

commit;
