-- IARA Educa — 040 · Classificação dos dados pessoais (Fase 2, item 18 do documento de estrutura — SEC-DADOS-01)
-- Cada coluna das tabelas de pessoas e atendimento tem nível, categoria LGPD e finalidade. É a base do relatório de
-- impacto (RIPD), das máscaras por perfil, da criptografia de campo e do descarte por prazo. Coluna nova numa dessas
-- tabelas sem classificação é apontada por iara.classificacao_pendente() (e pelo teste de autorização).
-- Níveis: PUBLICO · INTERNO · PESSOAL · SENSIVEL (LGPD art. 5º, II: saúde, origem racial, dado de criança em contexto
-- de proteção). Tudo o que é de criança é tratado no melhor interesse dela (art. 14).
begin;

create table if not exists iara.classificacao_dados (
  tabela text not null,
  coluna text not null,
  nivel text not null check (nivel in ('PUBLICO', 'INTERNO', 'PESSOAL', 'SENSIVEL')),
  categoria text not null,
  finalidade text not null,
  protecao text,
  primary key (tabela, coluna)
);
alter table iara.classificacao_dados enable row level security;

delete from iara.classificacao_dados;
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao)
select t, c, n, cat, fin, prot from (values
  -- alunos
  ('students', 'full_name', 'PESSOAL', 'identificação', 'matrícula, fila e atendimento', 'escopo família/unidade'),
  ('students', 'social_name', 'PESSOAL', 'identificação', 'tratamento pelo nome social', 'escopo família/unidade'),
  ('students', 'birth_date', 'PESSOAL', 'identificação', 'faixa etária e série (data de corte)', 'escopo família/unidade'),
  ('students', 'gender', 'PESSOAL', 'identificação', 'Censo Escolar', 'escopo família/unidade'),
  ('students', 'race_color', 'SENSIVEL', 'origem racial (art. 11)', 'Censo Escolar e políticas de equidade', 'só agregados fora da unidade'),
  ('students', 'cpf', 'PESSOAL', 'documento', 'identificação única', 'máscara por perfil; hash na auditoria'),
  ('students', 'nis', 'PESSOAL', 'documento', 'programas sociais', 'máscara por perfil; hash na auditoria'),
  ('students', 'sus_card', 'SENSIVEL', 'saúde (art. 11)', 'matrícula (documento exigido)', 'máscara; hash na auditoria'),
  ('students', 'birth_certificate', 'PESSOAL', 'documento', 'matrícula', 'máscara; hash na auditoria'),
  ('students', 'inep_id', 'INTERNO', 'identificador oficial', 'Censo Escolar', null),
  ('students', 'student_registry_number', 'INTERNO', 'identificador', 'registro permanente do aluno', null),
  ('students', 'nationality', 'PESSOAL', 'identificação', 'Censo Escolar', null),
  ('students', 'birth_country', 'PESSOAL', 'identificação', 'Censo Escolar', null),
  ('students', 'birth_city', 'PESSOAL', 'identificação', 'Censo Escolar', null),
  ('students', 'birth_state', 'PESSOAL', 'identificação', 'Censo Escolar', null),
  ('students', 'parent1_name', 'PESSOAL', 'filiação', 'documentação escolar', 'escopo família/unidade'),
  ('students', 'parent2_name', 'PESSOAL', 'filiação', 'documentação escolar', 'escopo família/unidade'),
  ('students', 'aee_status', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'atendimento especializado e prioridade da fila', 'permissão students.read_sensitive'),
  ('students', 'accessibility_needs', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'acessibilidade na unidade', 'permissão students.read_sensitive'),
  ('students', 'transport_need', 'PESSOAL', 'serviço', 'transporte escolar', null),
  ('students', 'school_transport_status', 'PESSOAL', 'serviço', 'transporte escolar', null),
  ('students', 'image_consent', 'PESSOAL', 'consentimento', 'uso de imagem', null),
  ('students', 'address_id', 'PESSOAL', 'localização', 'território e distância casa–unidade', 'endereço aproximado fora do escopo'),
  ('student_sensitive', 'special_education_need', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'AEE e inclusão', 'permissão própria; cada acesso auditado; hash na auditoria'),
  ('student_sensitive', 'medical_alerts', 'SENSIVEL', 'saúde (art. 11)', 'cuidado na unidade', 'permissão própria; cada acesso auditado; hash na auditoria'),
  ('student_sensitive', 'food_allergies', 'SENSIVEL', 'saúde (art. 11)', 'alimentação escolar', 'cozinha vê só a instrução de preparo; hash na auditoria'),
  ('student_sensitive', 'legal_notes', 'SENSIVEL', 'situação legal/proteção', 'guarda e proteção da criança', 'permissão própria; hash na auditoria'),
  -- responsáveis e família
  ('guardians', 'full_name', 'PESSOAL', 'identificação', 'atendimento e vínculo com a criança', 'escopo família/unidade'),
  ('guardians', 'social_name', 'PESSOAL', 'identificação', 'tratamento pelo nome social', null),
  ('guardians', 'cpf', 'PESSOAL', 'documento', 'identificação única', 'máscara por perfil; hash na auditoria'),
  ('guardians', 'nis', 'PESSOAL', 'documento', 'CadÚnico (critério da fila)', 'máscara; hash na auditoria'),
  ('guardians', 'rg', 'PESSOAL', 'documento', 'identificação', 'máscara; hash na auditoria'),
  ('guardians', 'birth_date', 'PESSOAL', 'identificação', 'identificação', null),
  ('guardians', 'gender', 'PESSOAL', 'identificação', 'identificação', null),
  ('guardians', 'email', 'PESSOAL', 'contato', 'comunicação', 'máscara por perfil'),
  ('guardians', 'primary_phone', 'PESSOAL', 'contato', 'comunicação', 'máscara por perfil'),
  ('guardians', 'secondary_phone', 'PESSOAL', 'contato', 'comunicação', 'máscara por perfil'),
  ('guardians', 'whatsapp_phone', 'PESSOAL', 'contato', 'atendimento pela IARA', 'máscara por perfil'),
  ('guardians', 'family_income', 'PESSOAL', 'socioeconômico', 'indicadores de vulnerabilidade', 'hash na auditoria'),
  ('guardians', 'monthly_income', 'PESSOAL', 'socioeconômico', 'indicadores de vulnerabilidade', 'hash na auditoria'),
  ('guardians', 'income_bracket', 'PESSOAL', 'socioeconômico', 'indicadores de vulnerabilidade', null),
  ('guardians', 'cadunico_status', 'PESSOAL', 'socioeconômico', 'critério da fila (IN 025)', null),
  ('guardians', 'benefits', 'PESSOAL', 'socioeconômico', 'indicadores de vulnerabilidade', null),
  ('guardians', 'single_mother', 'PESSOAL', 'composição familiar', 'critério da fila (IN 025)', null),
  ('guardians', 'occupation', 'PESSOAL', 'socioeconômico', 'educação integral (trabalho)', null),
  ('guardians', 'employment_status', 'PESSOAL', 'socioeconômico', 'educação integral (trabalho)', null),
  ('guardians', 'education_level', 'PESSOAL', 'socioeconômico', 'indicadores', null),
  ('guardians', 'marital_status', 'PESSOAL', 'composição familiar', 'cadastro', null),
  ('guardians', 'household_size', 'PESSOAL', 'composição familiar', 'renda por pessoa', null),
  ('guardians', 'accessibility_needs', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'atendimento acessível', 'escopo restrito'),
  ('guardians', 'consent_flags', 'PESSOAL', 'consentimento', 'comunicação e uso de dados', null),
  ('guardians', 'preferred_contact_channel', 'PESSOAL', 'contato', 'comunicação', null),
  ('guardians', 'preferred_language', 'PESSOAL', 'contato', 'comunicação', null),
  ('guardians', 'nationality', 'PESSOAL', 'identificação', 'cadastro', null),
  ('guardians', 'address_id', 'PESSOAL', 'localização', 'território e distância casa–unidade', null),
  ('household_members', 'full_name', 'PESSOAL', 'composição familiar', 'renda por pessoa', null),
  ('household_members', 'birth_date', 'PESSOAL', 'composição familiar', 'renda por pessoa', null),
  ('household_members', 'monthly_income', 'PESSOAL', 'socioeconômico', 'renda por pessoa', null),
  ('household_members', 'occupation', 'PESSOAL', 'socioeconômico', 'renda por pessoa', null),
  ('household_members', 'notes', 'PESSOAL', 'texto livre', 'cadastro', null),
  ('household_members', 'relationship', 'PESSOAL', 'composição familiar', 'cadastro', null),
  ('student_guardians', 'relationship', 'PESSOAL', 'vínculo', 'quem responde pela criança', null),
  ('student_guardians', 'legal_authority_status', 'SENSIVEL', 'situação legal/proteção', 'guarda e restrições', 'análise humana para mudanças'),
  ('student_guardians', 'can_pick_up', 'PESSOAL', 'vínculo', 'segurança na saída da unidade', null),
  ('addresses', 'street', 'PESSOAL', 'localização', 'território e distância', 'endereço aproximado fora do escopo'),
  ('addresses', 'number', 'PESSOAL', 'localização', 'território e distância', 'endereço aproximado fora do escopo'),
  ('addresses', 'complement', 'PESSOAL', 'localização', 'território e distância', null),
  ('addresses', 'neighborhood', 'PESSOAL', 'localização', 'território', null),
  ('addresses', 'postal_code', 'PESSOAL', 'localização', 'território', null),
  ('addresses', 'location', 'PESSOAL', 'localização precisa', 'distância casa–unidade (só coordenadas vão ao motor de rotas)', 'nunca em tela pública'),
  ('addresses', 'reference_point', 'PESSOAL', 'localização', 'atendimento', null),
  -- atendimento e conversas
  ('messages', 'body', 'PESSOAL', 'texto livre (pode conter dado sensível)', 'atendimento', 'escopo da conversa; descarte por prazo'),
  ('messages', 'payload', 'PESSOAL', 'texto livre/áudio transcrito', 'atendimento', 'escopo da conversa; descarte por prazo'),
  ('conversations', 'summary', 'PESSOAL', 'texto livre', 'passagem para atendimento humano', null),
  ('conversations', 'context', 'PESSOAL', 'estado da conversa', 'continuidade do atendimento', null),
  ('conversations', 'contact_phone_masked', 'INTERNO', 'contato mascarado', 'identificação da conversa', null),
  ('whatsapp_contacts', 'telefone_e164', 'PESSOAL', 'contato', 'canal WhatsApp', 'só a equipe do canal'),
  ('whatsapp_contacts', 'nome_wa', 'PESSOAL', 'identificação', 'canal WhatsApp', null),
  ('whatsapp_contacts', 'jid', 'PESSOAL', 'identificador do WhatsApp', 'canal WhatsApp', null),
  ('service_cases', 'protocol_number', 'INTERNO', 'identificador do atendimento', 'acompanhamento do protocolo pela família', 'consulta do controle externo só com motivo, auditada'),
  ('service_cases', 'description', 'PESSOAL', 'texto livre', 'atendimento', 'anonimizado para o controle externo'),
  ('service_cases', 'details', 'PESSOAL', 'texto livre', 'atendimento', null),
  ('service_cases', 'resolution_notes', 'PESSOAL', 'texto livre', 'atendimento', null),
  ('documents', 'file_name', 'PESSOAL', 'documento', 'matrícula', null),
  ('documents', 'notes', 'PESSOAL', 'texto livre', 'validação de documentos', null),
  ('waiting_list_entries', 'score_breakdown', 'PESSOAL', 'critérios da fila', 'transparência da posição (só a própria família e a gestão)', 'pseudônimo na fila pública'),
  ('waiting_list_entries', 'priority_flags', 'SENSIVEL', 'critérios (pode indicar deficiência)', 'prioridade da fila', 'pseudônimo na fila pública'),
  ('app_users', 'display_name', 'PESSOAL', 'identificação', 'auditoria (quem fez)', null),
  ('staff', 'full_name', 'PESSOAL', 'identificação funcional', 'lotação e turmas', null)
) v(t, c, n, cat, fin, prot);

-- colunas com dado de pessoa ainda sem classificação (nome, documento, contato, endereço, saúde, texto livre)
create or replace function iara.classificacao_pendente() returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name), '[]'::jsonb)
  from information_schema.columns c
  where c.table_schema = 'iara'
    and c.table_name in ('students', 'student_sensitive', 'guardians', 'household_members', 'student_guardians', 'addresses',
                         'messages', 'conversations', 'whatsapp_contacts', 'service_cases', 'documents', 'waiting_list_entries', 'staff')
    and c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

create or replace function api.classificacao_dados(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('audit.read');
  return jsonb_build_object(
    'colunas', (select jsonb_agg(to_jsonb(d) order by d.tabela, d.coluna) from iara.classificacao_dados d),
    'por_nivel', (select jsonb_object_agg(nivel, n) from (select nivel, count(*) n from iara.classificacao_dados group by 1) z),
    'pendentes', iara.classificacao_pendente());
end $$;

commit;
