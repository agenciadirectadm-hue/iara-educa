-- IARA Educa — 037 · Limite de requisições compartilhado entre instâncias do gateway (Fase 2, item 13; SEC-AT-01)
-- Antes: só a criação de sessão tinha limite, em memória de cada instância. Agora o gateway conta, numa janela fixa,
-- por IP, por sessão, por rota cara e por telefone do WhatsApp. Tabela sem registro de transação (contagem efêmera)
-- e limpa automaticamente (janelas com mais de 1 dia).
begin;

create unlogged table if not exists iara.limites_taxa (
  chave text not null,
  janela timestamptz not null,
  n integer not null default 0,
  primary key (chave, janela)
);
alter table iara.limites_taxa enable row level security;

-- conta 1 em cada chave; devolve a primeira chave que passou do limite (ou null)
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
      return p_chaves[i];
    end if;
  end loop;
  if random() < 0.01 then
    delete from iara.limites_taxa where janela < now() - interval '1 day';
  end if;
  return null;
end $$;
revoke all on function iara.taxa(text[], integer[], integer[]) from public;

commit;
