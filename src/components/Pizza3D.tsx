import { useState } from 'react';
import clsx from 'clsx';
import { fmtInt } from '@/lib/format';

export type Fatia = { chave: string; rotulo: string; valor: number; cor: string; detalhe?: string };

const escurecer = (hex: string, f = 0.72) => {
  const n = parseInt(hex.slice(1), 16);
  const c = (s: number) => Math.round(((n >> s) & 255) * f).toString(16).padStart(2, '0');
  return `#${c(16)}${c(8)}${c(0)}`;
};
const pct = (v: number, t: number) => (t ? `${((100 * v) / t).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%` : '—');

/** Pizza em 3D (elipse com espessura). A ordem e a cor das fatias são fixas por categoria (a cor segue o motivo, não o
 * tamanho). A perspectiva distorce as áreas: a legenda ao lado traz o percentual exato e é a leitura de referência. */
export function Pizza3D({ fatias, titulo, className }: { fatias: Fatia[]; titulo: string; className?: string }) {
  const [ativa, setAtiva] = useState<string | null>(null);
  const [dica, setDica] = useState<{ x: number; y: number; f: Fatia } | null>(null);
  const vis = fatias.filter((f) => f.valor > 0);
  const total = vis.reduce((s, f) => s + f.valor, 0);
  const W = 360, H = 232, cx = 180, cy = 98, rx = 164, ry = 88, prof = 26;
  const pt = (a: number, dy = 0) => [cx + rx * Math.cos(a), cy + ry * Math.sin(a) + dy] as const;

  let a = -Math.PI / 2;
  const geo = vis.map((f) => {
    const a0 = a;
    const a1 = a + (2 * Math.PI * f.valor) / total;
    a = a1;
    const [x0, y0] = pt(a0), [x1, y1] = pt(a1);
    const grande = a1 - a0 > Math.PI ? 1 : 0;
    const topo = vis.length === 1
      ? `M ${cx - rx} ${cy} A ${rx} ${ry} 0 1 1 ${cx + rx} ${cy} A ${rx} ${ry} 0 1 1 ${cx - rx} ${cy} Z`
      : `M ${cx} ${cy} L ${x0} ${y0} A ${rx} ${ry} 0 ${grande} 1 ${x1} ${y1} Z`;
    // parede da frente: só o trecho da fatia entre 0 e π (a metade de baixo da elipse)
    const s = Math.max(a0, 0), e = Math.min(a1, Math.PI);
    let lado: string | null = null;
    if (e > s) {
      const [sx, sy] = pt(s), [ex, ey] = pt(e);
      lado = `M ${sx} ${sy} A ${rx} ${ry} 0 0 1 ${ex} ${ey} L ${ex} ${ey + prof} A ${rx} ${ry} 0 0 0 ${sx} ${sy + prof} Z`;
    }
    return { f, topo, lado };
  });

  const mover = (e: React.MouseEvent, f: Fatia) => {
    const r = (e.currentTarget as SVGElement).ownerSVGElement!.getBoundingClientRect();
    setAtiva(f.chave);
    setDica({ x: e.clientX - r.left, y: e.clientY - r.top, f });
  };
  const sair = () => { setAtiva(null); setDica(null); };
  const resumo = vis.map((f) => `${f.rotulo}: ${pct(f.valor, total)}`).join('; ');

  return (
    <div className={clsx('grid grid-cols-1 items-center gap-4 sm:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]', className)}>
      <div className="relative">
        {total === 0 ? (
          <div className="flex h-48 items-center justify-center rounded-2xl bg-slate-50 text-[13px] text-muted">Sem faltas neste recorte.</div>
        ) : (
          <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={`${titulo}. ${resumo}`} onMouseLeave={sair}>
            {geo.map(({ f, lado }) => lado && (
              <path key={`l-${f.chave}`} d={lado} fill={escurecer(f.cor)} stroke="#fff" strokeWidth={1}
                opacity={ativa && ativa !== f.chave ? 0.4 : 1} onMouseMove={(e) => mover(e, f)} />
            ))}
            {geo.map(({ f, topo }) => (
              <path key={`t-${f.chave}`} d={topo} fill={f.cor} stroke="#fff" strokeWidth={2} strokeLinejoin="round"
                opacity={ativa && ativa !== f.chave ? 0.4 : 1} className="cursor-pointer transition-opacity"
                onMouseMove={(e) => mover(e, f)} onClick={(e) => mover(e, f)} />
            ))}
          </svg>
        )}
        {dica && (
          <div className="pointer-events-none absolute z-10 w-max max-w-[240px] -translate-x-1/2 -translate-y-full rounded-xl bg-ink px-3 py-2 text-[12px] text-white shadow-lift"
            style={{ left: dica.x, top: dica.y - 10 }}>
            <div className="font-semibold">{dica.f.rotulo}</div>
            <div className="tabular">{pct(dica.f.valor, total)} · {fmtInt(dica.f.valor)} faltas</div>
            {dica.f.detalhe && <div className="text-white/80">{dica.f.detalhe}</div>}
          </div>
        )}
      </div>
      <ul className="space-y-1.5" aria-label={`Legenda: ${titulo}`}>
        {fatias.map((f) => (
          <li key={f.chave} onMouseEnter={() => setAtiva(f.chave)} onMouseLeave={() => setAtiva(null)}
            className={clsx('flex items-center gap-2 rounded-lg px-2 py-1 text-[13px]', ativa === f.chave && 'bg-slate-50', f.valor === 0 && 'opacity-50')}>
            <span className="size-3 shrink-0 rounded-[3px]" style={{ background: f.cor }} aria-hidden />
            <span className="min-w-0 flex-1 truncate text-ink-2">{f.rotulo}</span>
            <span className="shrink-0 font-semibold tabular text-ink">{pct(f.valor, total)}</span>
            <span className="w-16 shrink-0 text-right text-[12px] tabular text-muted">{fmtInt(f.valor)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
