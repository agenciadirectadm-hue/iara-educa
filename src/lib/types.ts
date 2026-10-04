// Tipos das respostas do gateway (formas principais; blobs secundários ficam como `any`).
export type Role =
  | 'PREFEITO' | 'SECRETARIO' | 'SUPERINTENDENCIA' | 'ANALISTA_CENTRAL' | 'GERENCIA_EI'
  | 'DIRETOR_UNIDADE' | 'SECRETARIA_ESCOLAR' | 'ATENDIMENTO' | 'INOVACAO' | 'CIDADAO' | 'CIDADAO_NOVO';

export type Me = {
  user_id: string;
  display_name: string;
  role: Role;
  role_name: string;
  role_short: string;
  scope: 'AGGREGATE' | 'NETWORK' | 'UNIT' | 'GUARDIAN';
  stage_filter: string | null;
  question: string;
  org_unit: string;
  is_demo: boolean;
  unit: { id: number; name: string; short_name: string; type: string; lat: number; lng: number } | null;
  guardian: { id: string; name: string } | null;
  permissions: string[];
};

export type Persona = {
  code: Role;
  name: string;
  short_name: string;
  description: string;
  question: string;
  scope_type: Me['scope'];
  org_unit: string;
  stage_filter: string | null;
};

export type Kpis = {
  official: {
    units: number; cmeis: number; schools: number; classes: number; enrollments: number;
    teachers_census: number; special_ed_census: number; reference: string; reference_date: string;
  };
  operational: {
    classes: number; capacity: number; enrolled: number; physical: number; blocked: number; reserved: number; offerable: number;
    occupancy: number; full_classes: number; waiting: number; waiting_no_service: number; offers_pending: number;
    offers_accepted: number; open_cases: number; overdue_cases: number; source: string; updated_at: string;
  };
  demo_metrics: Record<string, { label: string; value: number; source: string }>;
};

export type Bootstrap = {
  tenant: {
    id: number; name: string; state: string; ibge: string; network_name: string; secretariat: string; school_year: number;
    official_reference_date: string; city_center: [number, number]; demo_mode: boolean; demo_unit: number;
  };
  /** Contato da IARA no WhatsApp. Sem número oficial, o QR code e o link abrem a conversa simulada. */
  whatsapp?: { numero: string | null; numero_demo: string; mensagem: string; url_publica: string | null };
  flags: Record<string, boolean>;
  personas: Persona[];
  stages: { id: number; code: string; name: string; short_name: string; color: string }[];
  grades: { id: number; code: string; name: string; short_name: string; stage_id: number; min_age_months: number; max_age_months: number }[];
  territories: { id: number; code: string; name: string; kind: string; color: string; lat: number; lng: number }[];
  kpis: Kpis;
  rule_version: string;
};

export type UnitMapItem = {
  id: number; name: string; short_name: string; type: 'CMEI' | 'ESCOLA'; type_label: string; status: string;
  lat: number; lng: number; macro_id: number; neighborhood: string | null; address: string | null; stages: string | null;
  geo_precision: string; has_aee: boolean; inep: string | null; public_classes: number | null; public_enrollments: number | null;
  classes: number; capacity: number; enrolled: number; offerable: number; offerable_creche: number; offerable_pre: number;
  offerable_ef: number; blocked: number; reserved: number; occupancy: number | null; queue: number; queue_creche: number;
  grades: number[]; shifts: string[];
};

export type Ops = {
  classes: number; capacity: number; enrolled: number; physical: number; blocked: number; reserved: number;
  offerable: number; occupancy: number | null; queue: number; source: string;
};
