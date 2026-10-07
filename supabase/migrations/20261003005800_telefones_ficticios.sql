-- IARA Educa — 058 · Demonstração: telefone do cadastro sempre fictício (decisão de Rob, 07/10/2026)
-- Nas apresentações a plateia manda mensagem ao WhatsApp de teste, então a lista de números autorizados fica desligada.
-- Para o cadastro não guardar o número real de quem participa, no modo demonstração todo telefone de responsável que não
-- esteja na faixa fictícia vira um número fictício (44) 9000X-XXXX. A conversa continua reconhecendo quem volta, porque o
-- vínculo é pelo contato do canal (whatsapp_contacts), não pelo telefone do cadastro. Na produção (demo_mode desligado),
-- nada muda. Tudo isso sai na limpeza total da demonstração.
begin;

create sequence if not exists iara.demo_tel_seq;

-- faixa (44) 90005-0000 a (44) 90009-9999: não colide com a da carga fictícia, que usa 90000-XXXX a 90004-XXXX
create or replace function iara.tel_ficticio() returns text
language sql volatile as $$
  select '(44) 9000' || (5 + (n / 10000) % 5)::text || '-' || lpad((n % 10000)::text, 4, '0') from (select nextval('iara.demo_tel_seq') n) z
$$;
create or replace function iara.e_tel_ficticio(p text) returns boolean
language sql immutable as $$ select p is null or p ~ '9000[0-9]-?[0-9]{4}$' $$;

create or replace function iara.demo_telefone_ficticio() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_novo text;
begin
  if not iara.demo_mode() then return new; end if;
  -- o mesmo número real (telefone e WhatsApp) vira o mesmo número fictício
  if not iara.e_tel_ficticio(new.primary_phone) then
    v_novo := iara.tel_ficticio();
    if iara.digitos(new.whatsapp_phone) = iara.digitos(new.primary_phone) then new.whatsapp_phone := v_novo; end if;
    if iara.digitos(new.secondary_phone) = iara.digitos(new.primary_phone) then new.secondary_phone := v_novo; end if;
    new.primary_phone := v_novo;
  end if;
  if not iara.e_tel_ficticio(new.whatsapp_phone) then new.whatsapp_phone := iara.tel_ficticio(); end if;
  if not iara.e_tel_ficticio(new.secondary_phone) then new.secondary_phone := iara.tel_ficticio(); end if;
  return new;
end $$;
drop trigger if exists guardians_telefone_ficticio on iara.guardians;
create trigger guardians_telefone_ficticio before insert or update of primary_phone, secondary_phone, whatsapp_phone on iara.guardians
  for each row execute function iara.demo_telefone_ficticio();

-- telefone mascarado da conversa: na demonstração, os 4 últimos dígitos também deixam de ser os reais
create or replace function iara.demo_conversa_tel_ficticio() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  if iara.demo_mode() and new.contact_phone_masked is not null and new.contact_phone_masked !~ '9000' and new.contact_phone_masked !~ '^\(44\) •••••-0[0-9]{3}$' then
    new.contact_phone_masked := '(44) •••••-0' || lpad((abs(hashtext(new.contact_phone_masked)) % 1000)::text, 3, '0');
  end if;
  return new;
end $$;
drop trigger if exists conversa_tel_ficticio on iara.conversations;
create trigger conversa_tel_ficticio before insert or update of contact_phone_masked on iara.conversations
  for each row execute function iara.demo_conversa_tel_ficticio();

-- o que já está no cadastro com número real (cadastros feitos pelo WhatsApp de teste)
do $$
begin
  if iara.demo_mode() then
    perform set_config('iara.skip_audit', 'on', true);
    update iara.guardians set primary_phone = primary_phone
    where not iara.e_tel_ficticio(primary_phone) or not iara.e_tel_ficticio(whatsapp_phone) or not iara.e_tel_ficticio(secondary_phone);
    update iara.conversations set contact_phone_masked = contact_phone_masked
    where contact_phone_masked is not null and contact_phone_masked !~ '9000' and contact_phone_masked !~ '^\(44\) •••••-0[0-9]{3}$';
    perform set_config('iara.skip_audit', 'off', true);
  end if;
end $$;

revoke all on function iara.demo_telefone_ficticio(), iara.demo_conversa_tel_ficticio(), iara.tel_ficticio() from public;

commit;
