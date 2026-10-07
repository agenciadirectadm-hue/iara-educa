import { Accessibility, Apple, ArrowRightLeft, Award, Backpack, Bus, ChartLine, DoorOpen, Flame, Gavel, LibraryBig, LifeBuoy, Network, NotebookPen, ScanQrCode, SearchCheck, Warehouse, BadgeCheck, Boxes, FolderOpen, ShieldAlert, BookOpen, Building2, CalendarCheck, CalendarDays, ChartColumn, ChefHat, CircleHelp, ClipboardList, Contact, Database, FileCheck, FileSearch, GraduationCap, House, IdCard, Inbox, ListChecks, ListOrdered, Map as MapIcon, Megaphone, MessageCircle, Route, Scale, School, ScrollText, Search, ShieldCheck, Smartphone, Users, Wrench } from 'lucide-react';
import type { ComponentType } from 'react';
import type { Me } from '@/lib/types';

/** Grupos da barra lateral (e do “Mais” no celular): o acesso fica organizado por assunto. */
export type Grupo = 'atendimento' | 'matricula' | 'escolar' | 'pedagogico' | 'estrutura' | 'gestao' | 'controle' | 'ajuda';
export const GRUPOS: { key: Grupo; label: string }[] = [
  { key: 'atendimento', label: 'Atendimento' },
  { key: 'matricula', label: 'Matrícula e cadastro' },
  { key: 'escolar', label: 'Vida escolar' },
  { key: 'pedagogico', label: 'Pedagógico' },
  { key: 'estrutura', label: 'Rede e logística' },
  { key: 'gestao', label: 'Gestão e indicadores' },
  { key: 'controle', label: 'Controle e transparência' },
  { key: 'ajuda', label: 'Ajuda' },
];

export type NavItem = { to: string; label: string; icon: ComponentType<{ className?: string }>; match?: string; grupo?: Grupo };

const I = {
  inicio: { to: '/inicio', label: 'Início', icon: House },
  mapa: { to: '/mapa', label: 'Mapa', icon: MapIcon, grupo: 'estrutura' },
  unidades: { to: '/unidades', label: 'Unidades', icon: Building2, grupo: 'estrutura' },
  indicadores: { to: '/indicadores', label: 'Indicadores', icon: ChartColumn, grupo: 'gestao' },
  atendimentos: { to: '/atendimentos', label: 'Atendimentos', icon: ClipboardList, grupo: 'atendimento' },
  vagas: { to: '/vagas', label: 'Buscar vaga', icon: Search, grupo: 'matricula' },
  fila: { to: '/fila', label: 'Fila', icon: ListOrdered, grupo: 'matricula' },
  ofertas: { to: '/ofertas', label: 'Ofertas', icon: FileCheck, grupo: 'matricula' },
  iara: { to: '/iara', label: 'Conversas', icon: Inbox, grupo: 'atendimento' },
  auditoria: { to: '/auditoria', label: 'Auditoria', icon: ShieldCheck, grupo: 'controle' },
  qualidade: { to: '/qualidade', label: 'Qualidade de dados', icon: Database, grupo: 'controle' },
  regras: { to: '/regras', label: 'Regras e critérios', icon: ScrollText, grupo: 'controle' },
  ajuda: { to: '/ajuda', label: 'Ajuda e fontes', icon: CircleHelp, grupo: 'ajuda' },
  whatsapp: { to: '/canal-whatsapp', label: 'WhatsApp da IARA', icon: Smartphone, grupo: 'atendimento' },
  alunos: { to: '/alunos', label: 'Alunos', icon: Backpack, grupo: 'matricula' },
  responsaveis: { to: '/responsaveis', label: 'Responsáveis', icon: Contact, grupo: 'matricula' },
  controle: { to: '/controle', label: 'Controle externo', icon: Scale, grupo: 'controle' },
  controleFila: { to: '/controle/fila', label: 'Fila pública', icon: ListChecks, grupo: 'controle' },
  controleCaso: { to: '/controle/caso', label: 'Consultar caso', icon: FileSearch, grupo: 'controle' },
  distancias: { to: '/regras#distancia', label: 'Distâncias', icon: Route, match: '/regras', grupo: 'controle' },
  // vida escolar (Sprint 1)
  pessoal: { to: '/pessoal', label: 'Pessoal', icon: IdCard, grupo: 'gestao' },
  frequencia: { to: '/frequencia', label: 'Frequência', icon: CalendarCheck, grupo: 'escolar' },
  nutricao: { to: '/nutricao', label: 'Cardápio e nutrição', icon: Apple, grupo: 'estrutura' },
  cozinha: { to: '/cozinha', label: 'Cozinha', icon: ChefHat, grupo: 'estrutura' },
  manutencao: { to: '/manutencao', label: 'Manutenção', icon: Wrench, grupo: 'estrutura' },
  mural: { to: '/mural', label: 'Mural', icon: Megaphone, grupo: 'escolar' },
  calendario: { to: '/calendario', label: 'Calendário', icon: CalendarDays, grupo: 'escolar' },
  ocorrencias: { to: '/ocorrencias', label: 'Ocorrências', icon: ShieldAlert, grupo: 'escolar' },
  validacoes: { to: '/validacoes', label: 'Validações', icon: BadgeCheck, grupo: 'matricula' },
  materiais: { to: '/materiais', label: 'Materiais', icon: Boxes, grupo: 'estrutura' },
  // pedagógico (Sprint 2)
  desempenho: { to: '/desempenho', label: 'Desempenho escolar', icon: ChartLine, grupo: 'pedagogico' },
  aee: { to: '/aee', label: 'AEE', icon: Accessibility, grupo: 'pedagogico' },
  verificar: { to: '/verificar', label: 'Verificar documento', icon: ScanQrCode, grupo: 'pedagogico' },
  // transporte e almoxarifado (Sprint 3)
  transporte: { to: '/transporte', label: 'Transporte escolar', icon: Bus, grupo: 'estrutura' },
  buscaAtiva: { to: '/busca-ativa', label: 'Busca ativa', icon: SearchCheck, grupo: 'escolar' },
  gestao: { to: '/gestao', label: 'Gestão da rede', icon: Network, grupo: 'gestao' },
  guarda: { to: '/guarda', label: 'Guarda e restrições', icon: Gavel, grupo: 'escolar' },
  suporte: { to: '/suporte', label: 'Suporte técnico', icon: LifeBuoy, grupo: 'ajuda' },
  biblioteca: { to: '/biblioteca', label: 'Biblioteca', icon: LibraryBig, grupo: 'pedagogico' },
  mapaRotas: { to: '/transporte?aba=mapa', label: 'Mapa das rotas', icon: Route, match: '/transporte', grupo: 'estrutura' },
  almoxarifado: { to: '/materiais?aba=pedidos', label: 'Pedidos de material', icon: Warehouse, match: '/materiais', grupo: 'estrutura' },
  // Sprint 5
  rematricula: { to: '/rematricula', label: 'Rematrícula', icon: ArrowRightLeft, grupo: 'matricula' },
  ensalamento: { to: '/ensalamento', label: 'Ensalamento', icon: DoorOpen, grupo: 'estrutura' },
  eventos: { to: '/eventos', label: 'Eventos e certificados', icon: Award, grupo: 'pedagogico' },
  calor: { to: '/mapas-de-calor', label: 'Mapas de calor', icon: Flame, grupo: 'gestao' },
} satisfies Record<string, NavItem>;

/** Agrupa os itens na ordem dos grupos, mantendo a ordem de cada grupo. */
export function agrupar(items: NavItem[]): { key: Grupo; label: string; items: NavItem[] }[] {
  return GRUPOS.map((g) => ({ ...g, items: items.filter((it) => (it.grupo ?? 'ajuda') === g.key) })).filter((g) => g.items.length > 0);
}

export function navFor(me: Me | null): { primary: NavItem[]; more: NavItem[] } {
  const role = me?.role;
  const unitId = me?.unit?.id;
  switch (role) {
    case 'PREFEITO':
      return { primary: [I.inicio, I.mapa, I.calor, I.indicadores], more: [I.unidades, I.gestao, I.nutricao, I.manutencao, I.qualidade, I.regras, I.suporte, I.ajuda] };
    case 'SECRETARIO':
    case 'SUPERINTENDENCIA':
    case 'GERENCIA_EI':
      return {
        primary: [I.inicio, I.mapa, I.atendimentos, I.fila],
        more: [I.iara, I.whatsapp,
          I.vagas, I.ofertas, I.rematricula, I.alunos, I.responsaveis, I.validacoes,
          I.frequencia, I.ocorrencias, I.buscaAtiva, I.guarda, I.mural, I.calendario,
          I.desempenho, I.aee, I.biblioteca, I.eventos,
          I.unidades, I.ensalamento, I.transporte, I.mapaRotas, I.nutricao, I.materiais, I.manutencao,
          I.gestao, I.calor, I.pessoal, I.indicadores,
          // o que o Ministério Público e a Defensoria veem (Secretaria e Superintendência)
          ...(role === 'GERENCIA_EI' ? [] : [I.controle]), I.auditoria, I.qualidade, I.regras,
          I.suporte, I.ajuda],
      };
    case 'CONTROLE_EXTERNO':
      return {
        primary: [{ ...I.inicio, label: 'Painel', icon: Scale }, I.controleFila, I.controleCaso, I.regras],
        more: [I.distancias, I.mapa, I.unidades, I.indicadores, I.qualidade, I.ajuda],
      };
    case 'INOVACAO':
      return { primary: [I.inicio, I.qualidade, I.mapa, I.auditoria], more: [I.whatsapp, I.calendario, I.eventos, I.unidades, I.nutricao, I.manutencao, I.gestao, I.pessoal, I.frequencia, I.indicadores, I.regras, I.suporte, I.ajuda] };
    case 'ANALISTA_CENTRAL':
    case 'ATENDIMENTO':
      return {
        primary: [I.inicio, I.iara, I.atendimentos, { ...I.vagas, label: 'Vagas' }],
        more: [I.whatsapp, I.fila, I.ofertas, I.rematricula, I.validacoes, I.alunos, I.responsaveis, I.verificar, I.mapa, I.unidades, I.ensalamento, I.auditoria, I.regras, I.suporte, I.ajuda],
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
          { ...I.ofertas, label: 'Matrículas e ofertas' }, I.rematricula, I.alunos, I.responsaveis, I.validacoes,
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap, match: `/unidades/${unitId}`, grupo: 'escolar' },
          I.frequencia, I.ocorrencias, I.buscaAtiva, I.guarda, I.mural, I.calendario,
          I.desempenho, I.aee, I.biblioteca, I.eventos,
          I.ensalamento, I.transporte, I.materiais, I.cozinha, I.manutencao, I.mapa,
          I.pessoal, I.gestao, I.indicadores, I.auditoria, I.regras, I.suporte, I.ajuda,
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
          I.atendimentos, I.rematricula, I.responsaveis, I.validacoes, { ...I.fila, to: `/fila?unidade=${unitId}` },
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap, grupo: 'escolar' },
          I.frequencia, I.ocorrencias, I.buscaAtiva, I.guarda, I.mural, I.calendario,
          I.desempenho, I.aee, I.biblioteca, I.eventos, I.verificar,
          I.ensalamento, I.transporte, I.materiais, I.cozinha, I.manutencao, I.mapa,
          I.pessoal, I.suporte, I.ajuda,
        ],
      };
    case 'CIDADAO':
    case 'CIDADAO_NOVO':
      return {
        primary: [I.inicio, { to: '/iara', label: 'IARA', icon: MessageCircle }, { to: '/familia', label: 'Família', icon: Users }, { to: '/protocolos', label: 'Protocolos', icon: ClipboardList }],
        more: [
          { to: '/escola', label: 'Vida escolar', icon: School, grupo: 'escolar' }, { to: '/escola?aba=aulas', label: 'O que estudou', icon: NotebookPen, match: '/escola', grupo: 'escolar' },
          { to: '/escola?aba=boletim', label: 'Boletim', icon: GraduationCap, match: '/escola', grupo: 'escolar' }, { to: '/escola?aba=historico', label: 'Histórico escolar', icon: GraduationCap, match: '/escola', grupo: 'escolar' },
          { to: '/escola?aba=biblioteca', label: 'Biblioteca', icon: LibraryBig, match: '/escola', grupo: 'escolar' }, { to: '/escola?aba=eventos', label: 'Eventos e certificados', icon: Award, match: '/escola', grupo: 'escolar' },
          { ...I.calendario, to: '/escola?aba=calendario', match: '/escola' },
          { to: '/escola?aba=rematricula', label: 'Rematrícula', icon: ArrowRightLeft, match: '/escola', grupo: 'matricula' },
          { to: '/escola?aba=declaracoes', label: 'Declarações', icon: ScrollText, match: '/escola', grupo: 'matricula' },
          { to: '/familia/documentos', label: 'Documentos e fotos', icon: FolderOpen, grupo: 'matricula' },
          { to: '/escola?aba=transporte', label: 'Transporte escolar', icon: Bus, match: '/escola', grupo: 'matricula' },
          { ...I.vagas, label: 'Consultar vagas' }, { ...I.mapa, label: 'Unidades no mapa', grupo: 'matricula' },
          I.regras, I.ajuda],
      };
    case 'PROFESSOR':
      return {
        primary: [{ ...I.inicio, label: 'Minhas turmas', icon: BookOpen }, I.ocorrencias, I.mural, I.calendario],
        more: [I.biblioteca, I.eventos, I.regras, I.suporte, I.ajuda],
      };
    case 'NUTRICAO':
      return {
        primary: [I.inicio, { ...I.nutricao, label: 'Cardápios' }, I.cozinha, I.mural],
        more: [{ ...I.almoxarifado, label: 'Alimentos e pedidos', to: '/materiais?aba=alimentos' }, I.materiais, I.unidades, I.mapa, I.calendario, I.eventos, I.suporte, I.ajuda],
      };
    case 'TRANSPORTE':
      return {
        primary: [{ ...I.inicio, label: 'Transporte hoje', icon: Bus }, I.mapaRotas, I.mapa, I.mural],
        more: [I.unidades, I.calendario, I.eventos, I.suporte, I.ajuda],
      };
    case 'ALMOXARIFADO':
      return {
        primary: [{ ...I.inicio, label: 'Almoxarifado', icon: Warehouse }, { ...I.materiais, label: 'Estoque' }, I.cozinha, I.mapa],
        more: [I.unidades, I.calendario, I.eventos, I.suporte, I.ajuda],
      };
    case 'PROFESSOR_AEE':
      return {
        primary: [{ ...I.inicio, label: 'Meus alunos', icon: Accessibility }, I.mural, I.calendario],
        more: [I.eventos, I.regras, I.suporte, I.ajuda],
      };
    case 'MANUTENCAO':
      return {
        primary: [I.inicio, { ...I.manutencao, label: 'Chamados' }, I.materiais, I.mapa],
        more: [I.unidades, I.calendario, I.suporte, I.ajuda],
      };
    default:
      return { primary: [I.mapa, I.unidades, I.vagas, I.ajuda], more: [I.verificar, I.regras, I.qualidade] };
  }
}
