-- IARA Educa — 099.09 · Organograma da Educação Especial e Apoio Pedagógico Interdisciplinar, com as funções estabelecidas
-- A GEE passa a ser a gerência publicada no portal da Prefeitura (Educação → Apoio Pedagógico Interdisciplinar), com contato oficial,
-- as oito áreas e as funções descritas na página (fonte OFICIAL). A posição da gerência no organograma da SEDUC continua a validar.
-- Funções: tabela nova (org_funcoes), com as atribuições de cada função; pessoas continuam nos vínculos (org_vinculos).
-- Demonstração: equipe fictícia do apoio (nomes fictícios, bandeirinha), casos nas oito áreas e o caso de fonoaudiologia da Ana,
-- e os perfis da gerência e do profissional na tela de entrada. As mudanças desta migração não entram no histórico que a limpeza desfaz.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

select set_config('iara.gestao_restaurando', 'on', true);
delete from iara.role_permissions where role_code = 'APOIO_INTERDISCIPLINAR' and permission_code = 'students.read';

-- 1. Funções --------------------------------------------------------------------------------------------------------------------------
create table if not exists iara.org_funcoes (
  id uuid primary key default gen_random_uuid(),
  setor_id uuid not null references iara.org_setores(id) on delete cascade,
  nome text not null,
  atribuicoes text[] not null default '{}',
  formacao text,
  ordem smallint not null default 0,
  fonte text not null default 'A_VALIDAR' check (fonte in ('OFICIAL', 'A_VALIDAR', 'DEMONSTRACAO')),
  ativo boolean not null default true,
  unique (setor_id, nome)
);
alter table iara.org_funcoes enable row level security;

-- 2. Gerência e áreas -------------------------------------------------------------------------------------------------------------------
update iara.org_setores set nome = 'Gerência de Educação Especial e Apoio Pedagógico Interdisciplinar',
  competencias = 'Articula os profissionais que asseguram uma educação inclusiva e de qualidade na rede: orientação educacional, acompanhamento pedagógico, assessoria da educação especial e inclusão, psicologia, fonoaudiologia, estimulação essencial e atendimento psicopedagógico. (Posição no organograma da SEDUC a validar.)',
  telefone = '(44) 3221-6936', email = 'seduc_apoiopedagogico@maringa.pr.gov.br', fonte = 'OFICIAL'
where sigla = 'GEE';

insert into iara.org_setores (sigla, nome, tipo, superior_id, ordem, fonte, competencias)
select v.sigla, v.nome, 'NUCLEO', (select id from iara.org_setores where sigla = 'GEE'), v.ordem, 'OFICIAL', v.comp
from (values
  ('GEE-OE', 'Orientação Educacional', 1, 'Acompanha o processo de ensino e aprendizagem em todas as unidades, da Educação Infantil ao Ensino Fundamental; orienta professores, media conflitos, orienta famílias e encaminha casos a outras políticas.'),
  ('GEE-AP', 'Acompanhamento Pedagógico', 2, 'Ajuda os alunos a superar dificuldades de aprendizagem (dislexia, disortografia, disgrafia, discalculia, TDAH, DDA ou dificuldades gerais).'),
  ('GEE-EEI', 'Assessoria Pedagógica da Educação Especial e Inclusão Educacional', 3, 'Atendimento educacional especializado: salas de recursos multifuncionais, professores de apoio, estimulação essencial (0 a 3 anos) e escola municipal bilíngue para surdos.'),
  ('GEE-FOR', 'Formação em Educação Especial', 4, 'Formação continuada e regular em educação especial para todos os servidores da área pedagógica.'),
  ('GEE-PSI', 'Psicologia Escolar e Educacional', 5, 'Suporte a todas as modalidades (Educação Infantil, Ensino Fundamental, Educação Especial, Ampliação da Jornada Escolar e EJA) e participação na rede de atendimento.'),
  ('GEE-FONO', 'Fonoaudiologia Escolar', 6, 'Desenvolvimento da audição e da linguagem oral e escrita, com ações preventivas, educativas e interventivas.'),
  ('GEE-DV', 'Atendimento Educacional Especializado · Deficiência Visual', 7, 'Acesso, permanência, participação e aprendizagem dos alunos com deficiência visual, de forma complementar ou suplementar ao ensino regular.'),
  ('GEE-AHSD', 'Triagem e Acompanhamento · Altas Habilidades/Superdotação', 8, 'Identificação e acompanhamento dos alunos com altas habilidades ou superdotação, com equipe multiprofissional.')
) v(sigla, nome, ordem, comp)
on conflict (sigla) do update set nome = excluded.nome, superior_id = excluded.superior_id, ordem = excluded.ordem, fonte = excluded.fonte, competencias = excluded.competencias;

insert into iara.org_funcoes (setor_id, nome, atribuicoes, formacao, ordem, fonte)
select (select id from iara.org_setores where sigla = v.sigla), v.nome, v.atr, v.form, v.ordem, v.fonte
from (values
  ('GEE', 'Gerente', array['Articular as áreas da gerência e os profissionais da rede', 'Receber os encaminhamentos das unidades e os pedidos das famílias', 'Distribuir os casos e acompanhar o tempo de espera', 'Responder pela gerência (telefone e e-mail oficiais)'], null::text, 0, 'A_VALIDAR'),
  ('GEE-OE', 'Orientador(a) educacional', array['Acompanhar o ensino e a aprendizagem em todas as unidades (Educação Infantil e Ensino Fundamental)',
     'Orientar os professores nas intervenções pedagógicas (defasagem de conteúdo, dificuldades de aprendizagem, alunos com deficiência)',
     'Mediar conflitos entre alunos, professores, funcionários e familiares', 'Orientar as famílias e promover reuniões sistemáticas',
     'Encaminhar casos a outras políticas de atendimento e a serviços externos'], null, 1, 'OFICIAL'),
  ('GEE-AP', 'Pedagogo(a) do acompanhamento pedagógico', array['Atender estudantes com dislexia, disortografia, disgrafia, discalculia, TDAH, DDA ou dificuldades gerais de aprendizagem',
     'Desenvolver estruturas que favoreçam o raciocínio lógico e a compreensão dos conteúdos escolares'], 'Graduação em Pedagogia e especialização em Psicopedagogia', 1, 'OFICIAL'),
  ('GEE-EEI', 'Professor(a) de Sala de Recursos Multifuncional', array['Atendimento individualizado, de acordo com as necessidades de cada aluno'], null, 1, 'OFICIAL'),
  ('GEE-EEI', 'Professor(a) de apoio em sala de aula', array['Auxiliar diretamente o processo de ensino dos alunos com deficiência na sala comum'], null, 2, 'OFICIAL'),
  ('GEE-EEI', 'Profissional da estimulação essencial', array['Atender crianças de 0 a 3 anos com atraso no desenvolvimento neuropsicomotor'], null, 3, 'OFICIAL'),
  ('GEE-EEI', 'Equipe da escola municipal bilíngue para surdos', array['Atender alunos surdos da Educação Infantil até a conclusão da primeira etapa do Ensino Fundamental'], null, 4, 'OFICIAL'),
  ('GEE-FOR', 'Formador(a) em educação especial', array['Princípios da educação inclusiva e legislação (LDB, Política Nacional de Educação Especial na Perspectiva da Educação Inclusiva, Convenção sobre os Direitos das Pessoas com Deficiência)',
     'Deficiências, transtornos e condições específicas e estratégias de ensino', 'Recursos pedagógicos acessíveis, tecnologias assistivas e adaptações curriculares',
     'Elaboração e acompanhamento do PAEE e do PEI', 'Práticas colaborativas entre a sala comum e o AEE', 'Formação humanizada: acolhimento, empatia e valorização da diversidade'], null, 1, 'OFICIAL'),
  ('GEE-PSI', 'Psicólogo(a) escolar e educacional', array['Acompanhar o processo de ensino e aprendizagem em todas as modalidades (Educação Infantil, Ensino Fundamental, Educação Especial, Ampliação da Jornada Escolar e EJA)',
     'Participar da formação dos profissionais da educação e das equipes multiprofissionais', 'Atender as famílias dos alunos', 'Colaborar na mediação de conflitos',
     'Participar das redes de atendimento (Conselho Tutelar, Ministério Público, APAE e outras instituições)'], 'Psicologia (registro no CRP)', 1, 'OFICIAL'),
  ('GEE-FONO', 'Fonoaudiólogo(a) escolar', array['Capacitar e orientar professores e familiares para a identificação precoce de alterações na comunicação e estratégias de estimulação',
     'Realizar triagens fonoaudiológicas (dificuldades auditivas ou de linguagem)', 'Encaminhar aos serviços de saúde especializados, quando necessário',
     'Acompanhar e assessorar os professores na adaptação de atividades e metodologias'], 'Fonoaudiologia (registro no CRFa)', 1, 'OFICIAL'),
  ('GEE-DV', 'Professor(a) do AEE para deficiência visual', array['Ensinar o sistema Braille (leitura e escrita)', 'Treinar o uso de tecnologias assistivas (reglete, sorobã, ampliadores, leitores de tela)',
     'Estimular as habilidades sensoriais remanescentes (tátil, auditiva e cinestésica)', 'Orientação e mobilidade no ambiente escolar',
     'Adaptar materiais didáticos e produzir recursos acessíveis', 'Planejar com os professores do ensino comum', 'Orientar a família e a equipe escolar'], null, 1, 'OFICIAL'),
  ('GEE-AHSD', 'Equipe de triagem e acompanhamento de AH/SD', array['Triagem educacional: observação sistemática, instrumentos específicos, entrevistas com família e professores e análise das produções',
     'Encaminhar os casos com indícios para avaliação aprofundada', 'Enriquecimento curricular nas áreas de interesse do aluno',
     'Desafios cognitivos, projetos de pesquisa, oficinas criativas e mentorias', 'Atendimentos individuais ou em pequenos grupos (socioemocional, autonomia, autorregulação)',
     'Articular com os professores a flexibilização curricular e a aceleração, quando necessário', 'Orientar a família'], 'Equipe multiprofissional', 1, 'OFICIAL')
) v(sigla, nome, atr, form, ordem, fonte)
on conflict (setor_id, nome) do update set atribuicoes = excluded.atribuicoes, formacao = excluded.formacao, ordem = excluded.ordem, fonte = excluded.fonte;

-- organograma com as funções e o contador de pessoas por função
create or replace function iara.org_json(s iara.org_setores) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(s) || jsonb_build_object('superior', (select x.sigla from iara.org_setores x where x.id = s.superior_id),
    'pessoas', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'nome', v.pessoa_nome, 'funcao', v.funcao, 'chefia', v.chefia, 'staff_id', v.staff_id,
                  'inicio', v.inicio, 'is_demo', v.is_demo) order by v.chefia desc, v.pessoa_nome), '[]') from iara.org_vinculos v where v.setor_id = s.id and v.fim is null),
    'funcoes', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'atribuicoes', f.atribuicoes, 'formacao', f.formacao, 'fonte', f.fonte,
                  'pessoas', (select count(*) from iara.org_vinculos v where v.setor_id = s.id and v.fim is null and v.funcao = f.nome)) order by f.ordem, f.nome), '[]')
                from iara.org_funcoes f where f.setor_id = s.id and f.ativo))
$$;

create or replace function api.org_funcao_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid;
begin
  perform iara.require_perm('gestao.organograma');
  if length(btrim(coalesce(p ->> 'nome', ''))) < 3 then raise exception 'Informe o nome da função.' using errcode = '22023'; end if;
  if nullif(p ->> 'id', '') is not null then
    update iara.org_funcoes set nome = btrim(p ->> 'nome'), formacao = nullif(btrim(coalesce(p ->> 'formacao', '')), ''),
      atribuicoes = coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(p -> 'atribuicoes') x where btrim(x) <> ''), '{}'), fonte = 'A_VALIDAR'
    where id = (p ->> 'id')::uuid returning id into v_id;
  else
    insert into iara.org_funcoes (setor_id, nome, formacao, atribuicoes, ordem)
    values ((p ->> 'setor_id')::uuid, btrim(p ->> 'nome'), nullif(btrim(coalesce(p ->> 'formacao', '')), ''),
            coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(p -> 'atribuicoes') x where btrim(x) <> ''), '{}'),
            coalesce((select max(ordem) + 1 from iara.org_funcoes where setor_id = (p ->> 'setor_id')::uuid), 1))
    returning id into v_id;
  end if;
  if v_id is null then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  perform iara.audit_event('ORGANOGRAMA', 'org_funcao', v_id::text, null, format('Função “%s” salva.', btrim(p ->> 'nome')));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function api.org_funcao_excluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('gestao.organograma');
  update iara.org_funcoes set ativo = false where id = (p ->> 'id')::uuid;
  if not found then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  perform iara.audit_event('ORGANOGRAMA', 'org_funcao', p ->> 'id', null, 'Função desativada.');
  return jsonb_build_object('ok', true);
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('org_funcoes', 'nome', 'PUBLICO', 'estrutura administrativa', 'organograma', null),
  ('org_funcoes', 'atribuicoes', 'PUBLICO', 'estrutura administrativa', 'organograma', null)
on conflict (tabela, coluna) do nothing;

-- 3. Demonstração: equipe do apoio e casos ------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_apoio() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_ana uuid;
  v_unit integer;
  v_fono uuid;
  v_caso uuid;
  x record;
begin
  if not iara.demo_mode() then return jsonb_build_object('ok', false); end if;
  perform set_config('iara.gestao_restaurando', 'on', true);
  delete from iara.apoio_registros;
  delete from iara.apoio_casos;
  delete from iara.org_vinculos where is_demo and setor_id in (select id from iara.org_setores where sigla like 'GEE%');
  delete from iara.apoio_profissionais where is_demo;
  delete from iara.staff where is_demo and role = 'APOIO' and unit_id is null and full_name in (select n from unnest(array[
    'Cláudia Regina Moraes', 'Juliana Prado Nunes', 'Rafael Augusto Lima', 'Patrícia Helena Souza', 'Fernanda Ribeiro Alves', 'Mariana Costa Teixeira',
    'Luciana Barros Melo', 'Adriana Lopes Fagundes', 'Simone Carvalho Reis', 'Tatiane Moura Campos', 'Renata Duarte Pires', 'Cristiane Mendes Rocha',
    'Daniela Freitas Castro', 'Marcos Vinícius Paiva', 'Eliane Santos Araújo', 'Vanessa Gomes Andrade']) n);

  -- equipe fictícia (nome, área, setor, função, chefia)
  for x in select * from (values
      ('Cláudia Regina Moraes', 'PSICOLOGIA', 'GEE', 'Gerente', true, 'CRP 08/00000-D'),
      ('Juliana Prado Nunes', 'PSICOLOGIA', 'GEE-PSI', 'Psicólogo(a) escolar e educacional', false, 'CRP 08/00001-D'),
      ('Rafael Augusto Lima', 'PSICOLOGIA', 'GEE-PSI', 'Psicólogo(a) escolar e educacional', false, 'CRP 08/00002-D'),
      ('Patrícia Helena Souza', 'PSICOLOGIA', 'GEE-PSI', 'Psicólogo(a) escolar e educacional', false, 'CRP 08/00003-D'),
      ('Fernanda Ribeiro Alves', 'FONOAUDIOLOGIA', 'GEE-FONO', 'Fonoaudiólogo(a) escolar', false, 'CRFa 3-00001-D'),
      ('Mariana Costa Teixeira', 'FONOAUDIOLOGIA', 'GEE-FONO', 'Fonoaudiólogo(a) escolar', false, 'CRFa 3-00002-D'),
      ('Luciana Barros Melo', 'FONOAUDIOLOGIA', 'GEE-FONO', 'Fonoaudiólogo(a) escolar', false, 'CRFa 3-00003-D'),
      ('Adriana Lopes Fagundes', 'ACOMPANHAMENTO_PEDAGOGICO', 'GEE-AP', 'Pedagogo(a) do acompanhamento pedagógico', false, null),
      ('Simone Carvalho Reis', 'ACOMPANHAMENTO_PEDAGOGICO', 'GEE-AP', 'Pedagogo(a) do acompanhamento pedagógico', false, null),
      ('Tatiane Moura Campos', 'ACOMPANHAMENTO_PEDAGOGICO', 'GEE-AP', 'Pedagogo(a) do acompanhamento pedagógico', false, null),
      ('Renata Duarte Pires', 'ORIENTACAO_EDUCACIONAL', 'GEE-OE', 'Orientador(a) educacional', false, null),
      ('Cristiane Mendes Rocha', 'ORIENTACAO_EDUCACIONAL', 'GEE-OE', 'Orientador(a) educacional', false, null),
      ('Daniela Freitas Castro', 'EDUCACAO_ESPECIAL', 'GEE-EEI', 'Profissional da estimulação essencial', false, null),
      ('Marcos Vinícius Paiva', 'DEFICIENCIA_VISUAL', 'GEE-DV', 'Professor(a) do AEE para deficiência visual', false, null),
      ('Eliane Santos Araújo', 'ALTAS_HABILIDADES', 'GEE-AHSD', 'Equipe de triagem e acompanhamento de AH/SD', false, null),
      ('Vanessa Gomes Andrade', 'FORMACAO', 'GEE-FOR', 'Formador(a) em educação especial', false, null)
    ) v(nome, area, sigla, funcao, chefia, reg) loop
    with st as (insert into iara.staff (tenant_id, unit_id, full_name, role, bond, is_demo) values (1, null, x.nome, 'APOIO', 'Efetivo', true) returning id)
    , pr as (insert into iara.apoio_profissionais (staff_id, area_codigo, registro_conselho, is_demo) select id, x.area, x.reg, true from st returning staff_id)
    insert into iara.org_vinculos (setor_id, staff_id, pessoa_nome, funcao, chefia, inicio, is_demo)
    select (select id from iara.org_setores where sigla = x.sigla), pr.staff_id, x.nome, x.funcao, x.chefia, date '2025-02-03', true from pr;
  end loop;

  -- casos fictícios nas áreas, em alunos da rede (≈ 1%)
  with al as (
    select e.student_id, e.unit_id, abs(hashtext(e.student_id::text || 'apoio')) h, g.code grade
    from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels g on g.id = c.grade_level_id
    where e.status = 'ACTIVE' and abs(hashtext(e.student_id::text || 'apoio')) % 1000 < 11),
  -- a escolha do aluno usa os últimos dígitos do sorteio; área, situação e dias usam os seguintes (senão sairiam todos iguais)
  ar0 as (select al.*, (al.h / 1000) % 100 xa, (al.h / 100000) % 100 xs, (al.h / 10000000) % 160 + 5 dias from al),
  ar as (
    select ar0.*, case
        when ar0.grade = 'CRECHE' and ar0.xa % 10 < 4 then 'EDUCACAO_ESPECIAL'
        when ar0.xa < 28 then case when ar0.grade in ('CRECHE', 'PRE') then 'FONOAUDIOLOGIA' else 'ACOMPANHAMENTO_PEDAGOGICO' end
        when ar0.xa < 50 then 'FONOAUDIOLOGIA' when ar0.xa < 70 then 'PSICOLOGIA' when ar0.xa < 84 then 'ORIENTACAO_EDUCACIONAL'
        when ar0.xa < 90 then case when ar0.grade ~ '^EF' then 'ALTAS_HABILIDADES' else 'PSICOLOGIA' end
        when ar0.xa < 93 then 'DEFICIENCIA_VISUAL' else 'EDUCACAO_ESPECIAL' end area,
      case when ar0.xs < 6 then 'PEDIDO_FAMILIA' when ar0.xs < 22 then 'ENCAMINHADO' when ar0.xs < 36 then 'EM_TRIAGEM'
           when ar0.xs < 66 then 'EM_ATENDIMENTO' when ar0.xs < 72 then 'AGUARDANDO_REDE' when ar0.xs < 96 then 'CONCLUIDO' else 'NAO_ACEITO' end sit
    from ar0),
  -- quem ainda espera, espera há menos tempo (a fila anda)
  ar2 as (select ar.*, case when ar.sit = 'ENCAMINHADO' then 3 + ar.dias % 45 when ar.sit = 'PEDIDO_FAMILIA' then 1 + ar.dias % 12 else ar.dias end dd from ar)
  insert into iara.apoio_casos (student_id, unit_id, area_codigo, origem, motivo, analise_unidade, solicitado_por_label, situacao, prioridade, profissional_staff,
                                encaminhado_em, atribuido_em, primeiro_atendimento_em, concluido_em, conclusao, created_at, updated_at, is_demo)
  select ar.student_id, ar.unit_id, ar.area,
         case when ar.h % 7 = 0 or ar.sit = 'PEDIDO_FAMILIA' then 'FAMILIA' when ar.h % 5 = 0 then 'AEE' when ar.h % 11 = 0 then 'CONSELHO_CLASSE' else 'UNIDADE' end,
         case ar.area
           when 'FONOAUDIOLOGIA' then 'A professora observou trocas na fala e dificuldade para entender comandos em sala barulhenta.'
           when 'ACOMPANHAMENTO_PEDAGOGICO' then 'Dificuldade persistente na leitura e na escrita, mesmo com o plano de apoio da turma.'
           when 'PSICOLOGIA' then 'Choro frequente na chegada e isolamento no recreio desde o início do semestre.'
           when 'ORIENTACAO_EDUCACIONAL' then 'Conflitos repetidos com colegas no recreio; família pede orientação.'
           when 'ALTAS_HABILIDADES' then 'Resolve problemas de matemática muito acima da turma e pede desafios.'
           when 'DEFICIENCIA_VISUAL' then 'Aproxima muito o caderno do rosto e não acompanha o quadro.'
           else 'Atraso no desenvolvimento motor observado pela educadora.' end,
         case when ar.sit = 'NAO_ACEITO' then 'Conversamos com a família: a escola fará primeiro o plano de apoio em sala por 60 dias e reavalia.'
              when ar.sit <> 'PEDIDO_FAMILIA' and (ar.h % 7 = 0) then 'A escola confirmou o que a família relatou e encaminhou.' end,
         case when ar.h % 7 = 0 or ar.sit = 'PEDIDO_FAMILIA' then 'Família' when ar.h % 5 = 0 then 'Professora do AEE' else 'Direção' end,
         ar.sit, case when ar.h % 13 = 0 then 'ALTA' else 'NORMAL' end,
         case when ar.sit in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE', 'CONCLUIDO') then
           (select ap.staff_id from iara.apoio_profissionais ap join iara.staff s on s.id = ap.staff_id
            where ap.area_codigo = ar.area and ap.is_demo and s.full_name <> 'Cláudia Regina Moraes'
            order by abs(hashtext(ap.staff_id::text || ar.student_id::text)) limit 1) end,
         case when ar.sit not in ('PEDIDO_FAMILIA', 'NAO_ACEITO') then now() - make_interval(days => ar.dd) end,
         case when ar.sit in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE', 'CONCLUIDO') then now() - make_interval(days => greatest(ar.dd - 9 - ar.h % 20, 1)) end,
         case when ar.sit in ('EM_ATENDIMENTO', 'AGUARDANDO_REDE', 'CONCLUIDO') then now() - make_interval(days => greatest(ar.dd - 15 - ar.h % 20, 1)) end,
         case when ar.sit = 'CONCLUIDO' then now() - make_interval(days => greatest(ar.dd - 60, 1)) end,
         case when ar.sit = 'CONCLUIDO' then 'Objetivos alcançados; a escola segue com as orientações e a família pode procurar a gerência se as dificuldades voltarem.' end,
         now() - make_interval(days => ar.dd + 2), now(), true
  from ar2 ar;

  -- registros fictícios (técnico, orientação à escola e à família)
  insert into iara.apoio_registros (caso_id, staff_id, autor_label, data, tipo, presenca, registro_tecnico, orientacao_escola, orientacao_familia, familia_ciente_em, familia_ciente_canal, created_at, is_demo)
  select c.id, c.profissional_staff, s.full_name || ' · ' || a.profissional, (c.primeiro_atendimento_em + make_interval(days => k.n * 12))::date,
         case k.n when 0 then 'TRIAGEM' when 1 then 'ATENDIMENTO' else 'ORIENTACAO_FAMILIA' end, 'PRESENTE',
         case c.area_codigo
           when 'FONOAUDIOLOGIA' then 'Triagem: trocas na fala (/r/ e /l/) e atenção auditiva reduzida com ruído. Sugerida avaliação audiológica na UBS.'
           when 'ACOMPANHAMENTO_PEDAGOGICO' then 'Avaliação: dificuldade na consciência fonológica e na memória de trabalho; hipótese de dislexia a confirmar.'
           when 'PSICOLOGIA' then 'Entrevista com a família e observação em sala: ansiedade na separação; sem indicativo de risco.'
           when 'ORIENTACAO_EDUCACIONAL' then 'Mediação com os alunos envolvidos; combinados construídos com a turma.'
           when 'ALTAS_HABILIDADES' then 'Triagem: indícios de altas habilidades em raciocínio lógico-matemático e criatividade.'
           when 'DEFICIENCIA_VISUAL' then 'Avaliação funcional: baixa visão; precisa de material ampliado (fonte 24) e lupa.'
           else 'Estimulação essencial: atraso motor leve; plano com atividades de equilíbrio e preensão.' end,
         case when k.n >= 1 then case c.area_codigo
           when 'FONOAUDIOLOGIA' then 'Falar de frente para a criança, com frases curtas; sentar longe da porta e do ventilador.'
           when 'ACOMPANHAMENTO_PEDAGOGICO' then 'Leitura em voz alta só com aviso prévio; tempo ampliado nas atividades escritas.'
           when 'PSICOLOGIA' then 'Rotina previsível na chegada, com acolhimento pela mesma educadora.'
           when 'ORIENTACAO_EDUCACIONAL' then 'Retomar os combinados na roda de conversa toda segunda-feira.'
           when 'ALTAS_HABILIDADES' then 'Desafios extras de lógica e projeto de pesquisa no tema de interesse.'
           when 'DEFICIENCIA_VISUAL' then 'Material ampliado e lugar próximo ao quadro, com boa iluminação.'
           else 'Atividades de encaixe e massinha todos os dias.' end end,
         case when k.n = 2 then case c.area_codigo
           when 'FONOAUDIOLOGIA' then 'Ler histórias em voz alta 10 minutos por dia e pedir que a criança reconte com as próprias palavras.'
           when 'ACOMPANHAMENTO_PEDAGOGICO' then 'Jogos de rima e de sílabas em casa, 15 minutos por dia.'
           when 'PSICOLOGIA' then 'Despedida curta e sempre do mesmo jeito; avise a escola de mudanças em casa.'
           when 'ORIENTACAO_EDUCACIONAL' then 'Converse sobre o que aconteceu sem julgamentos e reforce os combinados da escola.'
           when 'ALTAS_HABILIDADES' then 'Visitas a museus e bibliotecas; incentive o interesse sem cobrança excessiva.'
           when 'DEFICIENCIA_VISUAL' then 'Use a lupa nas tarefas de casa e mantenha a consulta oftalmológica em dia.'
           else 'Brinque no chão com a criança, incentivando engatinhar e alcançar objetos.' end end,
         case when k.n = 2 and abs(hashtext(c.id::text)) % 10 < 7 then c.primeiro_atendimento_em + make_interval(days => 25) end,
         case when k.n = 2 and abs(hashtext(c.id::text)) % 10 < 7 then 'WHATSAPP' end,
         c.primeiro_atendimento_em + make_interval(days => k.n * 12), true
  from iara.apoio_casos c join iara.staff s on s.id = c.profissional_staff join iara.apoio_areas a on a.codigo = c.area_codigo
  cross join generate_series(0, 2) k(n)
  where c.primeiro_atendimento_em is not null and c.primeiro_atendimento_em + make_interval(days => k.n * 12) < now();
  insert into iara.apoio_registros (caso_id, staff_id, autor_label, data, tipo, registro_tecnico, created_at, is_demo)
  select c.id, c.profissional_staff, s.full_name || ' · ' || a.profissional, c.atribuido_em::date, 'TRIAGEM',
         'Contato com a escola agendado; observação em sala na próxima semana.', c.atribuido_em + interval '1 day', true
  from iara.apoio_casos c join iara.staff s on s.id = c.profissional_staff join iara.apoio_areas a on a.codigo = c.area_codigo
  where c.situacao = 'EM_TRIAGEM' and c.primeiro_atendimento_em is null;

  -- caso da Ana: a Maria pediu pela IARA, a escola encaminhou, a fonoaudióloga atende; orientação nova esperando a ciência
  select sg.student_id, e.unit_id into v_ana, v_unit from iara.student_guardians sg join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
  where sg.guardian_id = v_maria order by sg.is_primary desc limit 1;
  select st.id into v_fono from iara.staff st where st.full_name = 'Fernanda Ribeiro Alves' and st.is_demo limit 1;
  if v_ana is not null and v_fono is not null then
    delete from iara.apoio_casos where student_id = v_ana;
    insert into iara.apoio_casos (student_id, unit_id, area_codigo, origem, motivo, analise_unidade, solicitado_por_label, solicitado_guardian, situacao, profissional_staff,
                                  encaminhado_em, atribuido_em, primeiro_atendimento_em, created_at, updated_at, is_demo)
    values (v_ana, v_unit, 'FONOAUDIOLOGIA', 'FAMILIA', 'A Ana troca o R pelo L quando fala (“baLata” em vez de “barata”) e às vezes não entende o que pedimos de longe.',
            'A professora também percebeu as trocas na roda de conversa. Encaminhado à fonoaudiologia.', (select full_name from iara.guardians where id = v_maria), v_maria,
            'EM_ATENDIMENTO', v_fono, now() - interval '33 days', now() - interval '27 days', now() - interval '20 days', now() - interval '36 days', now(), true)
    returning id into v_caso;
    insert into iara.apoio_registros (caso_id, staff_id, autor_label, data, tipo, presenca, registro_tecnico, orientacao_escola, orientacao_familia, created_at, is_demo) values
      (v_caso, v_fono, 'Fernanda Ribeiro Alves · Fonoaudiólogo(a)', (now() - interval '20 days')::date, 'TRIAGEM', 'PRESENTE',
       'Triagem fonoaudiológica: substituição de /r/ por /l/ em início e meio de palavra (processo de simplificação esperado até cerca de 5 anos; acompanhar). Atenção auditiva reduzida com ruído. Encaminhada para audiometria na UBS.',
       'Falar de frente para a Ana, com frases curtas; na roda, sentar a Ana perto da professora.', null, now() - interval '20 days', true),
      (v_caso, v_fono, 'Fernanda Ribeiro Alves · Fonoaudiólogo(a)', (now() - interval '1 day')::date, 'ORIENTACAO_FAMILIA', 'PRESENTE',
       'Devolutiva à família. Audiometria agendada pela UBS. Reavaliar em 60 dias.', null,
       'Leia uma história por dia com a Ana e peça que ela reconte. Quando ela trocar o som, repita a palavra certa com calma, sem pedir que ela repita. Leve o resultado da audiometria à escola.',
       now() - interval '1 day', true);
  end if;
  update iara.tenants set settings = settings || jsonb_build_object('demo_apoio_gerado_em', now()) where id = 1;
  return jsonb_build_object('ok', true, 'profissionais', (select count(*) from iara.apoio_profissionais where is_demo),
    'casos', (select count(*) from iara.apoio_casos), 'registros', (select count(*) from iara.apoio_registros));
end $$;

create or replace function iara.demo_purge_apoio(p_desde timestamptz) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_gerado timestamptz := nullif(iara.setting('demo_apoio_gerado_em'), '')::timestamptz;
begin
  if not iara.demo_mode() then return jsonb_build_object('ok', false); end if;
  if v_gerado is not null and not exists (select 1 from iara.apoio_casos where not is_demo or updated_at > v_gerado + interval '1 minute')
     and not exists (select 1 from iara.apoio_registros where not is_demo or familia_ciente_em > v_gerado) then
    return jsonb_build_object('ok', true, 'recriado', false);
  end if;
  return jsonb_build_object('ok', true, 'recriado', true, 'demonstracao', iara.demo_gerar_apoio());
end $$;

create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null), 'pedagogico', iara.demo_purge_sprint2(null),
                               'transporte_almoxarifado', iara.demo_purge_sprint3(null), 'busca_ativa', iara.demo_purge_busca_ativa(null),
                               'ocorrencias', iara.demo_purge_ocorrencias(null), 'gestao', iara.demo_purge_gestao(null),
                               'sprint4', iara.demo_purge_sprint4(null), 'sprint5', iara.demo_purge_sprint5(null),
                               'reunioes', iara.demo_purge_reunioes(null),
                               'uniformes', iara.demo_purge_uniformes(null), 'apoio', iara.demo_purge_apoio(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

-- 4. Sessão de demonstração: os perfis novos -------------------------------------------------------------------------------------------
create or replace function iara.session_create(p_persona text, p_unit integer, p_token_hash text, p_user_agent text)
returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.organizational_roles;
  v_user uuid := gen_random_uuid();
  v_unit integer;
  v_guardian uuid;
  v_staff uuid;
  v_staff_name text;
  v_label text;
  v_unit_name text;
  v_suffix text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    raise exception 'Seleção de perfil disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
  select * into r from iara.organizational_roles where code = p_persona and is_persona;
  if not found then
    raise exception 'Perfil desconhecido: %', p_persona using errcode = '22023';
  end if;
  if r.scope_type = 'UNIT' then
    v_unit := coalesce(p_unit, (iara.setting('demo_unit_maria'))::int);
    select name into v_unit_name from iara.education_units where id = v_unit;
    if v_unit_name is null then
      raise exception 'Unidade inválida.' using errcode = '22023';
    end if;
  elsif r.scope_type = 'GUARDIAN' and r.code = 'CIDADAO' then  -- CIDADAO_NOVO começa sem cadastro (faz pela IARA ou portal)
    v_guardian := (iara.setting('demo_guardian_maria'))::uuid;
  end if;
  if r.code = 'PROFESSOR' then
    select s.id, s.full_name into v_staff, v_staff_name
    from iara.class_staff cs join iara.classes c on c.id = cs.class_id join iara.staff s on s.id = cs.staff_id
    where c.unit_id = v_unit and c.status = 'ATIVA' and cs.role_type = 'REGENTE' and (cs.end_date is null or cs.end_date >= current_date)
    order by exists (select 1 from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null
                     where e.class_id = c.id and e.status = 'ACTIVE' and sg.guardian_id = (iara.setting('demo_guardian_maria'))::uuid) desc,
             c.class_name, s.full_name limit 1;
    if v_staff is null then
      raise exception 'Esta unidade não tem turma com professor(a) regente cadastrado(a).' using errcode = '22023';
    end if;
  elsif r.code = 'PROFESSOR_AEE' then
    -- a sala de recursos pode ficar em outra escola (polo): a sessão fica na unidade do(a) professor(a) e vê os alunos que atende
    v_staff := iara.aee_professor_da_unidade(v_unit);
    if v_staff is null then
      raise exception 'Nenhum(a) professor(a) do AEE cadastrado(a) na rede.' using errcode = '22023';
    end if;
    select s.full_name, s.unit_id, u.name into v_staff_name, v_unit, v_unit_name
    from iara.staff s join iara.education_units u on u.id = s.unit_id where s.id = v_staff;
  elsif r.code = 'APOIO_INTERDISCIPLINAR' then
    -- abre o(a) profissional que atende a filha da Maria (se houver); senão, quem tem mais casos em aberto
    select ap.staff_id, s.full_name into v_staff, v_staff_name
    from iara.apoio_profissionais ap join iara.staff s on s.id = ap.staff_id
    where ap.ativo and not exists (select 1 from iara.org_vinculos v where v.staff_id = ap.staff_id and v.chefia and v.fim is null)
    order by exists (select 1 from iara.apoio_casos c join iara.student_guardians sg on sg.student_id = c.student_id and sg.end_date is null
                     where c.profissional_staff = ap.staff_id and sg.guardian_id = (iara.setting('demo_guardian_maria'))::uuid) desc,
             (select count(*) from iara.apoio_casos c where c.profissional_staff = ap.staff_id and c.situacao in ('EM_TRIAGEM', 'EM_ATENDIMENTO')) desc
    limit 1;
    if v_staff is null then
      raise exception 'Nenhum profissional do apoio interdisciplinar cadastrado.' using errcode = '22023';
    end if;
  elsif r.code = 'GERENCIA_APOIO' then
    select v.staff_id, v.pessoa_nome into v_staff, v_staff_name from iara.org_vinculos v join iara.org_setores s on s.id = v.setor_id
    where s.sigla = 'GEE' and v.chefia and v.fim is null order by v.inicio limit 1;
  end if;
  v_label := case r.code
    when 'PREFEITO' then 'Gabinete do Prefeito'
    when 'SECRETARIO' then 'Secretaria Municipal de Educação'
    when 'SUPERINTENDENCIA' then 'Superintendência da SEDUC'
    when 'ANALISTA_CENTRAL' then 'Analista · Central de Vagas'
    when 'GERENCIA_EI' then 'Gerência de Educação Infantil'
    when 'DIRETOR_UNIDADE' then 'Direção · ' || v_unit_name
    when 'SECRETARIA_ESCOLAR' then 'Secretaria escolar · ' || v_unit_name
    when 'PROFESSOR' then v_staff_name || ' · ' || v_unit_name
    when 'PROFESSOR_AEE' then v_staff_name || ' · AEE · ' || v_unit_name
    when 'APOIO_INTERDISCIPLINAR' then v_staff_name || ' · ' || coalesce((select a.profissional from iara.apoio_profissionais ap join iara.apoio_areas a on a.codigo = ap.area_codigo where ap.staff_id = v_staff), 'Apoio')
    when 'GERENCIA_APOIO' then 'Gerência de apoio' || coalesce(' · ' || v_staff_name, '')
    when 'ATENDIMENTO' then 'Atendimento ao Cidadão'
    when 'INOVACAO' then 'Diretoria de Inovação Educacional'
    when 'NUTRICAO' then 'Nutrição escolar · SEDUC'
    when 'MANUTENCAO' then 'Infraestrutura · SEDUC'
    when 'CIDADAO' then (select full_name from iara.guardians where id = v_guardian)
    else r.name end || ' (demo #' || v_suffix || ')';

  insert into iara.app_users (id, tenant_id, display_name, role_code, unit_id, guardian_id, staff_id, auth_provider, is_demo, last_seen_at)
  values (v_user, 1, v_label, r.code, v_unit, v_guardian, v_staff, 'DEMO', true, now());
  insert into iara.app_sessions (token_hash, user_id, expires_at, user_agent)
  values (p_token_hash, v_user, now() + interval '12 hours', left(p_user_agent, 300));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform iara.audit_event('LOGIN_DEMO', 'app_user', v_user::text, v_unit, 'Sessão de demonstração iniciada: ' || r.name);
  return jsonb_build_object('user_id', v_user, 'role', r.code);
end $$;

revoke all on function iara.demo_gerar_apoio(), iara.demo_purge_apoio(timestamptz) from public;

select set_config('iara.gestao_restaurando', 'off', true);

select iara.demo_gerar_apoio();

commit;
