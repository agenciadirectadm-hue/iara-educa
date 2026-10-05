import { Building2, ChartColumn, CircleHelp, ClipboardList, Database, FileCheck, GraduationCap, House, Inbox, ListOrdered, Map as MapIcon, MessageCircle, ScrollText, Search, ShieldCheck, Smartphone, Users } from 'lucide-react';
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
  iara: { to: '/iara', label: 'Conversas IARA', icon: Inbox },
  auditoria: { to: '/auditoria', label: 'Auditoria', icon: ShieldCheck },
  qualidade: { to: '/qualidade', label: 'Qualidade de dados', icon: Database },
  regras: { to: '/regras', label: 'Regras e critérios', icon: ScrollText },
  ajuda: { to: '/ajuda', label: 'Ajuda e fontes', icon: CircleHelp },
  whatsapp: { to: '/canal-whatsapp', label: 'WhatsApp da IARA', icon: Smartphone },
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
        more: [I.unidades, I.vagas, I.ofertas, I.iara, I.whatsapp, I.indicadores, I.auditoria, I.qualidade, I.regras, I.ajuda],
      };
    case 'INOVACAO':
      return { primary: [I.inicio, I.qualidade, I.mapa, I.auditoria], more: [I.whatsapp, I.unidades, I.indicadores, I.regras, I.ajuda] };
    case 'ANALISTA_CENTRAL':
    case 'ATENDIMENTO':
      return {
        primary: [I.inicio, I.atendimentos, { ...I.vagas, label: 'Vagas' }, I.fila],
        more: [{ ...I.iara, label: 'Caixa da IARA' }, I.whatsapp, I.ofertas, I.mapa, I.unidades, I.auditoria, I.regras, I.ajuda],
      };
    case 'DIRETOR_UNIDADE':
      return {
        primary: [
          { ...I.inicio, label: 'Minha unidade' },
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap, match: `/unidades/${unitId}` },
          { ...I.fila, to: `/fila?unidade=${unitId}`, match: '/fila' },
          I.atendimentos,
        ],
        more: [{ ...I.ofertas, label: 'Matrículas e ofertas' }, I.mapa, I.indicadores, I.auditoria, I.regras, I.ajuda],
      };
    case 'SECRETARIA_ESCOLAR':
      return {
        primary: [
          I.inicio,
          { ...I.ofertas, label: 'Matrículas' },
          I.atendimentos,
          { to: `/unidades/${unitId}?aba=alunos`, label: 'Alunos', icon: Users, match: `/unidades/${unitId}` },
        ],
        more: [{ to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap }, { ...I.fila, to: `/fila?unidade=${unitId}` }, I.mapa, I.ajuda],
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
