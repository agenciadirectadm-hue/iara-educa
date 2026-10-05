import { Backpack, Building2, ChartColumn, CircleHelp, ClipboardList, Contact, Database, FileCheck, FileSearch, GraduationCap, House, Inbox, ListChecks, ListOrdered, Map as MapIcon, MessageCircle, Route, Scale, ScrollText, Search, ShieldCheck, Smartphone, Users } from 'lucide-react';
import type { ComponentType } from 'react';
import type { Me } from '@/lib/types';

export type NavItem = { to: string; label: string; icon: ComponentType<{ className?: string }>; match?: string };

const I = {
  inicio: { to: '/inicio', label: 'Início', icon: House },
  mapa: { to: '/mapa', label: 'Mapa', icon: MapIcon },
  unidades: { to: '/unidades', label: 'Unidades', icon: Building2 },
  indicadores: { to: '/indicadores', label: 'Indicadores', icon: ChartColumn },
  atendimentos: { to: '/atendimentos', label: 'Atendimentos', icon: ClipboardList },
  vagas: { to: '/vagas', label: 'Buscar vaga', icon: Search },
  fila: { to: '/fila', label: 'Fila', icon: ListOrdered },
  ofertas: { to: '/ofertas', label: 'Ofertas', icon: FileCheck },
  iara: { to: '/iara', label: 'Conversas', icon: Inbox },
  auditoria: { to: '/auditoria', label: 'Auditoria', icon: ShieldCheck },
  qualidade: { to: '/qualidade', label: 'Qualidade de dados', icon: Database },
  regras: { to: '/regras', label: 'Regras e critérios', icon: ScrollText },
  ajuda: { to: '/ajuda', label: 'Ajuda e fontes', icon: CircleHelp },
  whatsapp: { to: '/canal-whatsapp', label: 'WhatsApp da IARA', icon: Smartphone },
  alunos: { to: '/alunos', label: 'Alunos', icon: Backpack },
  responsaveis: { to: '/responsaveis', label: 'Responsáveis', icon: Contact },
  controle: { to: '/controle', label: 'Controle externo', icon: Scale },
  controleFila: { to: '/controle/fila', label: 'Fila pública', icon: ListChecks },
  controleCaso: { to: '/controle/caso', label: 'Consultar caso', icon: FileSearch },
  distancias: { to: '/regras#distancia', label: 'Distâncias', icon: Route, match: '/regras' },
} satisfies Record<string, NavItem>;

export function navFor(me: Me | null): { primary: NavItem[]; more: NavItem[] } {
  const role = me?.role;
  const unitId = me?.unit?.id;
  switch (role) {
    case 'PREFEITO':
      return { primary: [I.inicio, I.mapa, I.unidades, I.indicadores], more: [I.qualidade, I.regras, I.ajuda] };
    case 'SECRETARIO':
    case 'SUPERINTENDENCIA':
    case 'GERENCIA_EI':
      return {
        primary: [I.inicio, I.mapa, I.atendimentos, I.fila],
        more: [I.unidades, I.alunos, I.responsaveis, I.vagas, I.ofertas, I.iara, I.whatsapp, I.indicadores, I.auditoria, I.qualidade, I.regras,
          // o que o Ministério Público e a Defensoria veem (Secretaria e Superintendência)
          ...(role === 'GERENCIA_EI' ? [] : [I.controle]), I.ajuda],
      };
    case 'CONTROLE_EXTERNO':
      return {
        primary: [{ ...I.inicio, label: 'Painel', icon: Scale }, I.controleFila, I.controleCaso, I.regras],
        more: [I.distancias, I.mapa, I.unidades, I.indicadores, I.qualidade, I.ajuda],
      };
    case 'INOVACAO':
      return { primary: [I.inicio, I.qualidade, I.mapa, I.auditoria], more: [I.whatsapp, I.unidades, I.indicadores, I.regras, I.ajuda] };
    case 'ANALISTA_CENTRAL':
    case 'ATENDIMENTO':
      return {
        primary: [I.inicio, I.iara, I.atendimentos, { ...I.vagas, label: 'Vagas' }],
        more: [I.alunos, I.responsaveis, I.fila, I.whatsapp, I.ofertas, I.mapa, I.unidades, I.auditoria, I.regras, I.ajuda],
      };
    case 'DIRETOR_UNIDADE':
      return {
        primary: [
          { ...I.inicio, label: 'Minha unidade' },
          I.iara,
          { ...I.fila, to: `/fila?unidade=${unitId}`, match: '/fila' },
          I.atendimentos,
        ],
        more: [
          I.alunos, I.responsaveis,
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap, match: `/unidades/${unitId}` },
          { ...I.ofertas, label: 'Matrículas e ofertas' }, I.mapa, I.indicadores, I.auditoria, I.regras, I.ajuda,
        ],
      };
    case 'SECRETARIA_ESCOLAR':
      return {
        primary: [
          I.inicio,
          I.alunos,
          { ...I.ofertas, label: 'Matrículas' },
          I.iara,
        ],
        more: [
          I.responsaveis, I.atendimentos,
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap }, { ...I.fila, to: `/fila?unidade=${unitId}` }, I.mapa, I.ajuda,
        ],
      };
    case 'CIDADAO':
    case 'CIDADAO_NOVO':
      return {
        primary: [I.inicio, { to: '/iara', label: 'IARA', icon: MessageCircle }, { to: '/familia', label: 'Família', icon: Users }, { to: '/protocolos', label: 'Protocolos', icon: ClipboardList }],
        more: [{ ...I.mapa, label: 'Unidades no mapa' }, { ...I.vagas, label: 'Consultar vagas' }, I.regras, I.ajuda],
      };
    default:
      return { primary: [I.mapa, I.unidades, I.vagas, I.ajuda], more: [I.regras, I.qualidade] };
  }
}
