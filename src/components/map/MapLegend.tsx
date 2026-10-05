import { useState, type ReactNode } from 'react';
import clsx from 'clsx';
import { Info, X } from 'lucide-react';
import type { UnitMapItem } from '@/lib/types';
import { PRESSURE } from '@/lib/labels';
import {
  BALANCE_LEGEND, HEAT_OFFERABLE_STOPS, HEAT_STOPS, OFFERABLE_REGION_STOPS, PURPLE, QUEUE_REGION_STOPS, ROTA_COLOR, ROUTE_LINE, SELECTED_STROKE,
  UNIT_COLOR, VACANCY_COLOR, cssGradient,
} from './mapStyle';

type HeatMode = 'queue' | 'queue_creche' | 'enrollments' | 'offerable' | null;
type RegionMetric = 'balance_creche' | 'balance' | 'queue' | 'offerable' | null;

/** O que o mapa está mostrando — a legenda descreve exatamente essas camadas e marcações. */
export type LegendInput = {
  units?: UnitMapItem[];
  showUnits?: boolean;
  colorMode?: 'type' | 'vacancy';
  regionMetric?: RegionMetric;
  heat?: HeatMode;
  hasBoundary?: boolean;
  showAreas?: boolean;
  home?: { radius_m?: number } | null;
  homeLabel?: string;
  highlight?: { id: number; label: string }[];
  highlightLabel?: string;
  lines?: boolean;
  rotas?: { A_PE?: boolean; CARRO?: boolean };
  selectedUnit?: UnitMapItem | null;
  selectedLabel?: string;
};

type Sym =
  | { kind: 'dot'; color: string }
  | { kind: 'selected'; color: string }
  | { kind: 'area'; color: string }
  | { kind: 'line'; color: string; style: 'dashed' | 'dotted' | 'solid'; thin?: boolean; thick?: boolean }
  | { kind: 'scale'; gradient: string }
  | { kind: 'home' }
  | { kind: 'radius' }
  | { kind: 'rank'; label: string };
type Item = { sym: Sym; label: string };
type Group = { title: string; items: Item[] };

const HEAT_LABEL: Record<NonNullable<HeatMode>, string> = {
  queue: 'Fila por unidade', queue_creche: 'Fila de creche por unidade', enrollments: 'Matrículas por unidade', offerable: 'Vagas ofertáveis por unidade',
};
const km = (m: number) => `${(m / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} km`;

export function buildLegend(i: LegendInput): Group[] {
  const groups: Group[] = [];

  const units = i.showUnits === false ? [] : i.units ?? [];
  const unitItems: Item[] = [];
  if (units.length) {
    if (i.colorMode === 'vacancy') {
      const st = new Set(units.map((u) => (u.offerable > 0 ? 'vaga' : u.queue > 0 ? 'fila' : 'neutro')));
      if (st.has('vaga')) unitItems.push({ sym: { kind: 'dot', color: VACANCY_COLOR.vaga }, label: 'Com vaga ofertável' });
      if (st.has('fila')) unitItems.push({ sym: { kind: 'dot', color: VACANCY_COLOR.fila }, label: 'Sem vaga, com fila' });
      if (st.has('neutro')) unitItems.push({ sym: { kind: 'dot', color: VACANCY_COLOR.neutro }, label: 'Sem vaga e sem fila' });
    } else {
      const active = units.filter((u) => u.status === 'ATIVA');
      if (active.some((u) => u.type === 'CMEI')) unitItems.push({ sym: { kind: 'dot', color: UNIT_COLOR.CMEI }, label: 'CMEI (educação infantil)' });
      if (active.some((u) => u.type !== 'CMEI')) unitItems.push({ sym: { kind: 'dot', color: UNIT_COLOR.ESCOLA }, label: 'Escola municipal' });
      if (units.some((u) => u.status !== 'ATIVA')) unitItems.push({ sym: { kind: 'dot', color: UNIT_COLOR.VALIDAR }, label: 'Situação a validar' });
    }
  }
  if (i.selectedUnit) {
    const s = i.selectedUnit;
    const color = i.colorMode === 'vacancy'
      ? (s.offerable > 0 ? VACANCY_COLOR.vaga : s.queue > 0 ? VACANCY_COLOR.fila : VACANCY_COLOR.neutro)
      : s.status !== 'ATIVA' ? UNIT_COLOR.VALIDAR : s.type === 'CMEI' ? UNIT_COLOR.CMEI : UNIT_COLOR.ESCOLA;
    unitItems.push({ sym: { kind: 'selected', color }, label: i.selectedLabel ?? 'Unidade selecionada' });
  }
  if (i.highlight?.length) {
    unitItems.push({ sym: { kind: 'rank', label: i.highlight[0].label }, label: i.highlightLabel ?? 'Unidades em destaque (número = posição)' });
  }
  if (unitItems.length) groups.push({ title: 'Unidades', items: unitItems });

  if (i.regionMetric === 'balance_creche' || i.regionMetric === 'balance') {
    groups.push({
      title: i.regionMetric === 'balance_creche' ? 'Regiões · saldo de creche (vagas − fila)' : 'Regiões · saldo de vagas (vagas − fila)',
      items: BALANCE_LEGEND.map((b) => ({ sym: { kind: 'area', color: b.color }, label: PRESSURE[b.key].label })),
    });
  } else if (i.regionMetric === 'queue') {
    groups.push({ title: 'Regiões', items: [{ sym: { kind: 'scale', gradient: cssGradient(QUEUE_REGION_STOPS) }, label: 'Crianças na fila' }] });
  } else if (i.regionMetric === 'offerable') {
    groups.push({ title: 'Regiões', items: [{ sym: { kind: 'scale', gradient: cssGradient(OFFERABLE_REGION_STOPS) }, label: 'Vagas ofertáveis' }] });
  }

  if (i.heat) {
    groups.push({
      title: 'Mapa de calor',
      items: [{ sym: { kind: 'scale', gradient: cssGradient(i.heat === 'offerable' ? HEAT_OFFERABLE_STOPS : HEAT_STOPS) }, label: HEAT_LABEL[i.heat] }],
    });
  }

  const refs: Item[] = [];
  if (i.home) refs.push({ sym: { kind: 'home' }, label: i.homeLabel ?? 'Residência informada' });
  if (i.home?.radius_m) refs.push({ sym: { kind: 'radius' }, label: `Raio de ${km(i.home.radius_m)}` });
  if (i.home && i.lines && i.highlight?.length) {
    refs.push({ sym: { kind: 'line', color: ROUTE_LINE, style: 'dotted' }, label: i.rotas?.A_PE || i.rotas?.CARRO ? 'Linha reta' : 'Distância em linha reta' });
  }
  if (i.rotas?.A_PE) refs.push({ sym: { kind: 'line', color: ROTA_COLOR.A_PE, style: 'dashed', thick: true }, label: 'Rota a pé' });
  if (i.rotas?.CARRO) refs.push({ sym: { kind: 'line', color: ROTA_COLOR.CARRO, style: 'solid', thick: true }, label: 'Rota de carro' });
  if (i.showAreas) refs.push({ sym: { kind: 'line', color: PURPLE, style: 'dashed', thin: true }, label: 'Áreas de influência (proximidade)' });
  if (i.hasBoundary) refs.push({ sym: { kind: 'line', color: PURPLE, style: 'dashed' }, label: 'Limite do município' });
  if (refs.length) groups.push({ title: 'Referências', items: refs });

  return groups;
}

function LegendSymbol({ sym }: { sym: Sym }) {
  switch (sym.kind) {
    case 'dot':
      return <span className="inline-block size-2.5 shrink-0 rounded-full shadow-[0_0_0_2px_#fff,0_0_0_3px_rgba(15,23,42,0.12)]" style={{ background: sym.color }} />;
    case 'selected':
      return <span className="inline-block size-2.5 shrink-0 rounded-full" style={{ background: sym.color, boxShadow: `0 0 0 2px ${SELECTED_STROKE}, 0 0 0 5px ${sym.color}33` }} />;
    case 'area':
      return <span className="inline-block h-2.5 w-3.5 shrink-0 rounded-[3px] ring-1 ring-black/5" style={{ background: sym.color, opacity: 0.72 }} />;
    case 'line':
      return (
        <span
          className={clsx('inline-block w-5 shrink-0', sym.thin ? 'border-t' : sym.thick ? 'border-t-[3px]' : 'border-t-2',
            sym.style === 'dashed' ? 'border-dashed' : sym.style === 'solid' ? 'border-solid' : 'border-dotted')}
          style={{ borderColor: sym.color }}
        />
      );
    case 'scale':
      return (
        <span className="inline-flex shrink-0 items-center gap-1 text-[10px] text-subtle">
          menos<span className="inline-block h-2 w-12 rounded-full ring-1 ring-black/5" style={{ background: sym.gradient }} />mais
        </span>
      );
    case 'home':
      return (
        <span className="inline-flex size-4 shrink-0 items-center justify-center rounded-full bg-ink text-white">
          <svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M3 10.5 12 3l9 7.5" /><path d="M5 9.5V21h14V9.5" /></svg>
        </span>
      );
    case 'radius':
      return <span className="inline-block size-3.5 shrink-0 rounded-full border-2 border-dashed" style={{ borderColor: PURPLE, background: 'rgba(122,36,197,0.10)' }} />;
    case 'rank':
      return (
        <span className="inline-flex size-4 shrink-0 items-center justify-center rounded-full text-[9px] font-bold leading-none text-white" style={{ background: PURPLE, boxShadow: '0 0 0 1.5px #fff' }}>
          {sym.label}
        </span>
      );
  }
}

function Entry({ item }: { item: Item }) {
  return (
    <span className="inline-flex items-center gap-1.5 font-semibold text-ink-2">
      <LegendSymbol sym={item.sym} />
      {item.label}
    </span>
  );
}

/**
 * Legenda do mapa, gerada a partir das camadas visíveis: pontos = unidades, quadrados = regiões,
 * linhas = limites e trajetos, barra = intensidade (calor/escala).
 * `strip`: faixa abaixo do mapa · `overlay`: cartão recolhível sobre o mapa (mapas de tela cheia).
 */
export function MapLegend({ variant = 'strip', note, className, defaultOpen = true, ...input }: LegendInput & {
  variant?: 'strip' | 'overlay';
  note?: ReactNode;
  className?: string;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const groups = buildLegend(input);
  if (!groups.length && !note) return null;

  if (variant === 'overlay') {
    if (!open) {
      return (
        <button
          onClick={() => setOpen(true)}
          className={clsx('glass absolute z-10 inline-flex h-10 items-center gap-1.5 rounded-2xl px-3 text-[13px] font-semibold shadow-soft ring-1 ring-white/70', className)}
          aria-label="Mostrar legenda do mapa"
        >
          <Info className="size-4" /> Legenda
        </button>
      );
    }
    return (
      <div
        className={clsx('glass absolute z-10 max-h-[45%] w-max max-w-[min(290px,calc(100%-5.5rem))] overflow-y-auto rounded-2xl px-3 py-2.5 text-[11.5px] leading-tight shadow-soft ring-1 ring-white/70', className)}
        role="region"
        aria-label="Legenda do mapa"
      >
        <div className="flex items-center justify-between gap-3">
          <span className="text-[10.5px] font-bold uppercase tracking-wider text-subtle">Legenda</span>
          <button onClick={() => setOpen(false)} className="-mr-1 inline-flex size-7 items-center justify-center rounded-lg hover:bg-black/5" aria-label="Recolher legenda">
            <X className="size-4" />
          </button>
        </div>
        {groups.map((g) => (
          <div key={g.title} className="mt-2">
            <div className="text-[10px] font-bold uppercase tracking-wide text-subtle">{g.title}</div>
            <div className="mt-1 flex flex-col gap-1">{g.items.map((it) => <Entry key={it.label} item={it} />)}</div>
          </div>
        ))}
        {note && <div className="mt-2 text-muted">{note}</div>}
      </div>
    );
  }

  return (
    <div className={clsx('border-t border-line bg-white px-3 py-2.5 text-[11.5px] leading-tight', className)} role="region" aria-label="Legenda do mapa">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        {groups.map((g) => (
          <div key={g.title} className="flex flex-wrap items-center gap-x-2.5 gap-y-1.5">
            <span className="text-[10px] font-bold uppercase tracking-wide text-subtle">{g.title}</span>
            {g.items.map((it) => <Entry key={it.label} item={it} />)}
          </div>
        ))}
        {note && <div className="ml-auto flex items-center gap-2 text-muted">{note}</div>}
      </div>
    </div>
  );
}

export default MapLegend;
