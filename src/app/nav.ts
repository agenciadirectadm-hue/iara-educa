import { HeartHandshake, Shirt, TrendingUp, Accessibility, Users2, Handshake, ThumbsDown, Apple, ArrowRightLeft, Award, Backpack, Bus, Calculator, ChartLine, DoorOpen, Gavel, LibraryBig, LifeBuoy, Network, NotebookPen, ScanQrCode, SearchCheck, Warehouse, BadgeCheck, Boxes, FolderOpen, ShieldAlert, BookOpen, Building2, CalendarCheck, CalendarDays, ChartColumn, ChefHat, CircleHelp, ClipboardCheck, ClipboardList, Clock, Contact, Database, FileCheck, FileSearch, GraduationCap, HandCoins, House, IdCard, Inbox, ListChecks, ListOrdered, Map as MapIcon, Megaphone, MessageCircle, Route, Scale, School, ScrollText, Search, ShieldCheck, Smartphone, Sparkles, Users, Wrench } from 'lucide-react';
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

/** Itens da barra inferior no celular; os demais itens de `primary` vão para "Mais" (na barra lateral aparecem todos). */
export const NA_BARRA = 4;

export type NavItem = { to: string; label: string; icon: ComponentType<{ className?: string }>; match?: string; grupo?: Grupo };

const I = {
  inicio: { to: '/inicio', label: 'Início', icon: House },
  mapa: { to: '/mapa', label: 'Mapas', icon: MapIcon, grupo: 'estrutura' },
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
  controleReunioes: { to: '/controle/reunioes', label: 'Registros de reunião', icon: Users2, grupo: 'controle' },
  reunioes: { to: '/reunioes', label: 'Reuniões com responsáveis', icon: Users2, grupo: 'escolar' },
  distancias: { to: '/regras#distancia', label: 'Distâncias', icon: Route, match: '/regras', grupo: 'controle' },
  // vida escolar (Sprint 1)
  pessoal: { to: '/pessoal', label: 'Pessoal', icon: IdCard, grupo: 'gestao' },
  frequencia: { to: '/frequencia', label: 'Frequência', icon: CalendarCheck, grupo: 'escolar' },
  presenca: { to: '/presenca', label: 'Sistema Presença', icon: ClipboardCheck, grupo: 'escolar' },
  bolsaFamilia: { to: '/bolsa-familia', label: 'Bolsa Família', icon: HandCoins, grupo: 'gestao' },
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
  recusas: { to: '/recusas', label: 'Recusas de vaga', icon: ThumbsDown, grupo: 'matricula' },
  ensalamento: { to: '/ensalamento', label: 'Ensalamento', icon: DoorOpen, grupo: 'estrutura' },
  eventos: { to: '/eventos', label: 'Eventos e certificados', icon: Award, grupo: 'pedagogico' },
  // comercial (só o perfil Comercial)
  simulador: { to: '/simulador', label: 'Simulador de preços', icon: Calculator, grupo: 'gestao' },
  // só o Prefeito
  publicos: { to: '/publicos', label: 'Públicos', icon: Megaphone, grupo: 'gestao' },
  oraculo: { to: '/oraculo', label: 'Oráculo', icon: Sparkles, grupo: 'gestao' },
  meuPonto: { to: '/ponto', label: 'Meu ponto', icon: Clock, grupo: 'gestao' },
  pontoEquipe: { to: '/ponto/equipe', label: 'Ponto da equipe', icon: Clock, grupo: 'gestao' },
  // uniformes e kits, apoio interdisciplinar, Ideb e órgãos externos
  uniformes: { to: '/uniformes', label: 'Uniformes e kits', icon: Shirt, grupo: 'estrutura' },
  apoio: { to: '/apoio', label: 'Apoio interdisciplinar', icon: HeartHandshake, grupo: 'pedagogico' },
  ideb: { to: '/ideb', label: 'Ideb das escolas', icon: TrendingUp, grupo: 'gestao' },
  orgaos: { to: '/orgaos', label: 'Uniformes, kits e Ideb', icon: Scale, grupo: 'controle' },
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
      return { primary: [I.inicio, I.mapa, I.indicadores, I.unidades], more: [I.reunioes, I.recusas, I.oraculo, I.bolsaFamilia, I.publicos, I.uniformes, I.ideb, I.gestao, I.nutricao, I.manutencao, I.qualidade, I.regras, I.suporte, I.ajuda] };
    case 'SECRETARIO':
    case 'SUPERINTENDENCIA':
    case 'GERENCIA_EI':
      return {
        primary: [I.inicio, I.unidades, I.atendimentos, I.fila, I.mapa],
        more: [I.iara, I.whatsapp,
          I.vagas, I.ofertas, ...(role === 'GERENCIA_EI' ? [] : [I.recusas]), I.rematricula, I.alunos, I.responsaveis, I.validacoes,
          I.frequencia, I.presenca, I.bolsaFamilia, I.ocorrencias, I.reunioes, I.buscaAtiva, I.guarda, I.mural, I.calendario,
          I.desempenho, I.ideb, I.aee, I.apoio, I.biblioteca, I.eventos,
          I.ensalamento, I.transporte, I.mapaRotas, I.nutricao, I.materiais, I.uniformes, I.manutencao,
          I.gestao, I.pessoal, I.indicadores,
          // o que o Ministério Público e a Defensoria veem (Secretaria e Superintendência)
          ...(role === 'GERENCIA_EI' ? [] : [I.controle]), I.auditoria, I.qualidade, I.regras,
          I.suporte, I.ajuda],
      };
    case 'CONTROLE_EXTERNO':
      return {
        primary: [{ ...I.inicio, label: 'Painel', icon: Scale }, I.unidades, I.controleFila, I.controleCaso, I.controleReunioes, I.regras],
        more: [I.orgaos, I.recusas, I.distancias, I.mapa, I.indicadores, I.qualidade, I.ajuda],
      };
    case 'INOVACAO':
      return { primary: [I.inicio, I.unidades, I.qualidade, I.mapa, I.auditoria], more: [I.whatsapp, I.calendario, I.eventos, I.nutricao, I.uniformes, I.ideb, I.manutencao, I.gestao, I.pessoal, I.frequencia, I.indicadores, I.regras, I.suporte, I.ajuda] };
    case 'ANALISTA_CENTRAL':
    case 'ATENDIMENTO':
      return {
        primary: [I.inicio, I.iara, I.unidades, I.atendimentos, { ...I.vagas, label: 'Vagas' }],
        more: [I.whatsapp, I.fila, I.ofertas, ...(role === 'ANALISTA_CENTRAL' ? [I.recusas] : []), I.rematricula, I.validacoes, I.alunos, I.responsaveis, I.verificar, I.mapa, I.ensalamento, I.auditoria, I.regras, I.suporte, I.ajuda],
      };
    case 'DIRETOR_UNIDADE':
      return {
        primary: [
          { ...I.inicio, label: 'Minha unidade' },
          I.unidades,
          I.iara,
          { ...I.fila, to: `/fila?unidade=${unitId}`, match: '/fila' },
          I.atendimentos,
        ],
        more: [
          { ...I.ofertas, label: 'Matrículas e ofertas' }, I.rematricula, I.alunos, I.responsaveis, I.validacoes,
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap, match: `/unidades/${unitId}`, grupo: 'escolar' },
          I.frequencia, I.presenca, I.ocorrencias, I.reunioes, I.buscaAtiva, I.guarda, I.mural, I.calendario,
          I.desempenho, I.aee, I.apoio, I.biblioteca, I.eventos,
          I.ensalamento, I.transporte, I.materiais, I.uniformes, I.cozinha, I.manutencao, I.mapa,
          I.pessoal, I.pontoEquipe, I.gestao, I.indicadores, I.auditoria, I.regras, I.suporte, I.ajuda,
        ],
      };
    case 'SECRETARIA_ESCOLAR':
      return {
        primary: [
          I.inicio,
          I.unidades,
          I.alunos,
          { ...I.ofertas, label: 'Matrículas' },
          I.iara,
        ],
        more: [
          I.atendimentos, I.rematricula, I.responsaveis, I.validacoes, { ...I.fila, to: `/fila?unidade=${unitId}` },
          { to: `/unidades/${unitId}?aba=turmas`, label: 'Turmas', icon: GraduationCap, grupo: 'escolar' },
          I.frequencia, I.presenca, I.ocorrencias, I.reunioes, I.buscaAtiva, I.guarda, I.mural, I.calendario,
          I.desempenho, I.aee, I.apoio, I.biblioteca, I.eventos, I.verificar,
          I.ensalamento, I.transporte, I.materiais, I.uniformes, I.cozinha, I.manutencao, I.mapa,
          I.pessoal, I.pontoEquipe, I.suporte, I.ajuda,
        ],
      };
    case 'CIDADAO':
    case 'CIDADAO_NOVO':
      return {
        primary: [I.inicio, { to: '/iara', label: 'IARA', icon: MessageCircle }, { to: '/familia', label: 'Família', icon: Users }, I.unidades, { to: '/protocolos', label: 'Protocolos', icon: ClipboardList, grupo: 'matricula' }],
        more: [
          { to: '/escola', label: 'Vida escolar', icon: School, grupo: 'escolar' }, { to: '/escola?aba=aulas', label: 'O que estudou', icon: NotebookPen, match: '/escola', grupo: 'escolar' },
          { to: '/escola?aba=boletim', label: 'Boletim', icon: GraduationCap, match: '/escola', grupo: 'escolar' }, { to: '/escola?aba=historico', label: 'Histórico escolar', icon: GraduationCap, match: '/escola', grupo: 'escolar' },
          { to: '/escola?aba=biblioteca', label: 'Biblioteca', icon: LibraryBig, match: '/escola', grupo: 'escolar' }, { to: '/escola?aba=eventos', label: 'Eventos e certificados', icon: Award, match: '/escola', grupo: 'escolar' },
          { ...I.calendario, to: '/escola?aba=calendario', match: '/escola' },
          { to: '/escola?aba=uniforme', label: 'Uniforme e kit', icon: Shirt, match: '/escola', grupo: 'escolar' },
          { to: '/escola?aba=apoio', label: 'Apoio interdisciplinar', icon: HeartHandshake, match: '/escola', grupo: 'escolar' },
          { to: '/minhas-ofertas', label: 'Ofertas de vaga', icon: Handshake, grupo: 'matricula' },
          { to: '/escola?aba=rematricula', label: 'Rematrícula', icon: ArrowRightLeft, match: '/escola', grupo: 'matricula' },
          { to: '/escola?aba=declaracoes', label: 'Declarações', icon: ScrollText, match: '/escola', grupo: 'matricula' },
          { to: '/familia/documentos', label: 'Documentos e fotos', icon: FolderOpen, grupo: 'matricula' },
          { to: '/escola?aba=transporte', label: 'Transporte escolar', icon: Bus, match: '/escola', grupo: 'matricula' },
          { ...I.vagas, label: 'Consultar vagas' }, { ...I.mapa, label: 'Unidades no mapa', grupo: 'matricula' },
          I.regras, I.ajuda],
      };
    case 'PROFESSOR':
      return {
        primary: [{ ...I.inicio, label: 'Minhas turmas', icon: BookOpen }, I.unidades, I.ocorrencias, I.meuPonto, I.mural],
        more: [I.reunioes, I.calendario, I.biblioteca, I.eventos, I.regras, I.suporte, I.ajuda],
      };
    case 'NUTRICAO':
      return {
        primary: [I.inicio, { ...I.nutricao, label: 'Cardápios' }, I.unidades, I.cozinha, I.mural],
        more: [{ ...I.almoxarifado, label: 'Alimentos e pedidos', to: '/materiais?aba=alimentos' }, I.materiais, I.mapa, I.calendario, I.eventos, I.suporte, I.ajuda],
      };
    case 'TRANSPORTE':
      return {
        primary: [{ ...I.inicio, label: 'Transporte hoje', icon: Bus }, I.mapaRotas, I.unidades, I.mapa, I.mural],
        more: [I.calendario, I.eventos, I.suporte, I.ajuda],
      };
    case 'ALMOXARIFADO':
      return {
        primary: [{ ...I.inicio, label: 'Almoxarifado', icon: Warehouse }, { ...I.materiais, label: 'Estoque' }, I.unidades, I.cozinha, I.mapa],
        more: [I.uniformes, I.calendario, I.eventos, I.suporte, I.ajuda],
      };
    case 'PROFESSOR_AEE':
      return {
        primary: [{ ...I.inicio, label: 'Meus alunos', icon: Accessibility }, I.unidades, I.meuPonto, I.mural, I.calendario],
        more: [I.apoio, I.reunioes, I.eventos, I.regras, I.suporte, I.ajuda],
      };
    case 'GERENCIA_APOIO':
      return {
        primary: [{ ...I.inicio, label: 'Apoio interdisciplinar', icon: HeartHandshake }, I.unidades, I.aee, I.gestao],
        more: [I.calendario, I.regras, I.suporte, I.ajuda],
      };
    case 'APOIO_INTERDISCIPLINAR':
      return {
        primary: [{ ...I.inicio, label: 'Meus casos', icon: HeartHandshake }, I.unidades, I.calendario],
        more: [I.suporte, I.ajuda],
      };
    case 'TRIBUNAL_CONTAS':
    case 'CONSELHOS':
    case 'CONSELHO_TUTELAR':
    case 'CAMARA':
      return {
        primary: [{ ...I.inicio, label: 'Painel', icon: Scale }, I.unidades, I.mapa, I.ideb],
        more: [I.regras, I.qualidade, I.ajuda],
      };
    case 'COMERCIAL':
      return { primary: [{ ...I.inicio, label: 'Simulador de preços', icon: Calculator }, I.unidades, I.mapa, I.ajuda], more: [] };
    case 'MANUTENCAO':
      return {
        primary: [I.inicio, { ...I.manutencao, label: 'Chamados' }, I.unidades, I.materiais, I.mapa],
        more: [I.calendario, I.suporte, I.ajuda],
      };
    default:
      return { primary: [I.mapa, I.unidades, I.vagas, I.ajuda], more: [I.verificar, I.regras, I.qualidade] };
  }
}
