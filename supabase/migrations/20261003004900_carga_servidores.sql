-- IARA Educa — 049 · Carga de dados reais: ficha funcional dos servidores (Sprint 1)
-- O layout SERVIDORES ganha os campos da ficha (cargo, jornada, admissão, escolaridade, formação, área e situação).
-- A promoção do lote continua a mesma (036); um gatilho na linha promovida completa a ficha em iara.staff, e a reversão
-- do lote devolve o estado anterior (o "antes" guarda a linha inteira de iara.staff, com estes campos).
begin;

insert into carga.layouts (dominio, ordem, campo, tipo, obrigatorio, chave, valores, descricao, exemplo) values
  ('SERVIDORES', 6, 'cargo', 'texto', false, false, null, 'Cargo no RH', 'Professor(a) de Educação Básica'),
  ('SERVIDORES', 7, 'carga_horaria_semanal', 'inteiro', false, false, null, 'Jornada semanal em horas (20, 30 ou 40)', '40'),
  ('SERVIDORES', 8, 'data_admissao', 'data', false, false, null, 'Data de admissão', '2015-03-02'),
  ('SERVIDORES', 9, 'escolaridade', 'texto', false, false, null, 'Maior escolaridade', 'Pós-graduação'),
  ('SERVIDORES', 10, 'formacao', 'texto', false, false, null, 'Curso de formação', 'Pedagogia'),
  ('SERVIDORES', 11, 'area_atuacao', 'texto', false, false, null, 'Área ou componente de atuação', 'Anos iniciais'),
  ('SERVIDORES', 12, 'situacao', 'lista', false, false, '{ATIVO,LICENCA,AFASTADO}', 'Situação funcional (padrão: ATIVO)', 'ATIVO')
on conflict (dominio, campo) do update set ordem = excluded.ordem, tipo = excluded.tipo, obrigatorio = excluded.obrigatorio,
  valores = excluded.valores, descricao = excluded.descricao, exemplo = excluded.exemplo;

create or replace function carga.servidor_ficha() returns trigger
language plpgsql security definer set search_path = iara, carga, public
as $$
declare
  d jsonb := new.limpo;
begin
  if new.situacao = 'PROMOVIDO' and old.situacao is distinct from 'PROMOVIDO' and new.destino_id is not null
     and (select dominio from carga.lotes where id = new.lote_id) = 'SERVIDORES' then
    update iara.staff set
      matricula_funcional = coalesce(carga.txt(d, 'matricula_funcional'), matricula_funcional),
      cargo = coalesce(carga.txt(d, 'cargo'), cargo),
      carga_horaria_semanal = coalesce(carga.num(carga.txt(d, 'carga_horaria_semanal'))::int, carga_horaria_semanal),
      data_admissao = coalesce(carga.data(carga.txt(d, 'data_admissao')), data_admissao),
      escolaridade = coalesce(carga.txt(d, 'escolaridade'), escolaridade),
      formacao = coalesce(carga.txt(d, 'formacao'), formacao),
      area_atuacao = coalesce(carga.txt(d, 'area_atuacao'), area_atuacao),
      situacao = coalesce(upper(carga.txt(d, 'situacao')), situacao, 'ATIVO')
    where id = new.destino_id::uuid;
  end if;
  return new;
end $$;

drop trigger if exists carga_servidor_ficha on carga.registros;
create trigger carga_servidor_ficha after update of situacao on carga.registros
  for each row execute function carga.servidor_ficha();

revoke all on function carga.servidor_ficha() from public;

commit;
