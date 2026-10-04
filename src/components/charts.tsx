// Gráficos em SVG próprio: leves, acessíveis e clicáveis (barra/segmento/legenda filtram ou navegam — spec §75.2).
import { useMemo, useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { motion } from 'motion/react';
import clsx from 'clsx';
import { fmtInt } from '@/lib/format';

type Clickable = { to?: string; onClick?: () => void };

function Wrap({ to, onClick, className, children, label }: Clickable & { className?: string; children: ReactNode; label?: string }) {
  if (to) return <Link to={to} className={className} aria-label={label}>{children}</Link>;
  if (onClick) return <button type="button" onClick={onClick} className={clsx('w-full text-left', className)} aria-label={label}>{children}</button>;
  return <div className={className}>{children}</div>;
}

/** Barras horizontais com rótulo — cada linha é um destino. */
export function BarList({ items, max, format = fmtInt, valueSuffix }: {
  items: ({ key: string; label: ReactNode; value: number; sub?: ReactNode; color?: string; badge?: ReactNode } & Clickable)[];
  max?: number; format?: (n: number) => string; valueSuffix?: string;
}) {
  const m = max ?? Math.max(1, ...items.map((i) => Math.abs(i.value)));
  return (
    <ul className="space-y-1">
      {items.map((it, idx) => (
        <li key={it.key}>
          <Wrap to={it.to} onClick={it.onClick} className={clsx('group block rounded-2xl px-2 py-2 transition', (it.to || it.onClick) && 'hover:bg-blue-50/70')} label={typeof it.label === 'string' ? `${it.label}: ${format(it.value)}` : undefined}>
            <div className="mb-1 flex items-center justify-between gap-3 text-[13.5px]">
              <span className="min-w-0 truncate font-semibold text-ink">{it.label}</span>
              <span className="flex shrink-0 items-center gap-2">
                {it.badge}
                <b className="tabular text-ink">{format(it.value)}{valueSuffix}</b>
              </span>
            </div>
            <div className="h-2.5 overflow-hidden rounded-full bg-slate-100">
              <motion.div
                className="h-full rounded-full"
                style={{ background: it.color ?? 'linear-gradient(90deg, #A846E8, #7A24C5)' }}
                initial={{ width: 0 }}
                animate={{ width: `${(Math.abs(it.value) / m) * 100}%` }}
                transition={{ duration: 0.55, delay: idx * 0.03, ease: [0.22, 1, 0.36, 1] }}
              />
            </div>
            {it.sub && <div className="mt-1 text-[12px] text-muted">{it.sub}</div>}
          </Wrap>
        </li>
      ))}
    </ul>
  );
}

/** Demanda × oferta por categoria (barras agrupadas verticais). */
export function GroupedBars({ data, series, height = 190 }: {
  data: ({ key: string; label: string } & Record<string, any> & Clickable)[];
  series: { key: string; label: string; color: string }[];
  height?: number;
}) {
  const max = Math.max(1, ...data.flatMap((d) => series.map((s) => Number(d[s.key]) || 0)));
  return (
    <div>
      <div className="mb-3 flex flex-wrap gap-3 text-[12.5px]">
        {series.map((s) => (
          <span key={s.key} className="inline-flex items-center gap-1.5 font-semibold text-ink-2">
            <span className="size-2.5 rounded-sm" style={{ background: s.color }} aria-hidden />
            {s.label}
          </span>
        ))}
      </div>
      <div className="no-scrollbar -mx-1 overflow-x-auto">
        <div className="flex min-w-full items-end gap-1 px-1" style={{ height }}>
          {data.map((d, i) => (
            <Wrap key={d.key} to={d.to} onClick={d.onClick} className="group flex h-full min-w-[54px] flex-1 flex-col items-center justify-end rounded-2xl pt-2 transition hover:bg-blue-50/70" label={`${d.label}: ${series.map((s) => `${s.label} ${fmtInt(d[s.key])}`).join(', ')}`}>
              <div className="flex w-full flex-1 items-end justify-center gap-1 px-1.5">
                {series.map((s) => {
                  const v = Number(d[s.key]) || 0;
                  return (
                    <div key={s.key} className="flex h-full flex-1 flex-col items-center justify-end">
                      <span className="mb-1 text-[10.5px] font-bold tabular text-ink-2">{fmtInt(v)}</span>
                      <motion.div
                        className="w-full max-w-[22px] rounded-t-lg"
                        style={{ background: s.color }}
                        initial={{ height: 0 }}
                        animate={{ height: `${(v / max) * 100}%` }}
                        transition={{ duration: 0.6, delay: i * 0.04, ease: [0.22, 1, 0.36, 1] }}
                      />
                    </div>
                  );
                })}
              </div>
              <div className="mt-1.5 h-8 px-1 text-center text-[11px] font-semibold leading-tight text-muted group-hover:text-blue-700">{d.label}</div>
            </Wrap>
          ))}
        </div>
      </div>
    </div>
  );
}

/** Rosca com legenda clicável. */
export function Donut({ segments, size = 168, center, onSelect, selected }: {
  segments: { key: string; label: string; value: number; color: string }[];
  size?: number; center?: ReactNode; onSelect?: (key: string) => void; selected?: string | null;
}) {
  const total = Math.max(1, segments.reduce((a, s) => a + s.value, 0));
  const r = 42;
  const c = 2 * Math.PI * r;
  let acc = 0;
  return (
    <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-center">
      <div className="relative shrink-0" style={{ width: size, height: size }}>
        <svg viewBox="0 0 100 100" className="h-full w-full -rotate-90" role="img" aria-label="Distribuição">
          <circle cx="50" cy="50" r={r} fill="none" stroke="#EEF2F8" strokeWidth="14" />
          {segments.map((s) => {
            const len = (s.value / total) * c;
            const el = (
              <motion.circle
                key={s.key}
                cx="50" cy="50" r={r} fill="none" stroke={s.color} strokeWidth={selected === s.key ? 17 : 14}
                strokeDasharray={`${len} ${c - len}`} strokeDashoffset={-acc}
                initial={{ opacity: 0 }} animate={{ opacity: selected && selected !== s.key ? 0.35 : 1 }}
                className={onSelect ? 'cursor-pointer' : ''}
                onClick={() => onSelect?.(s.key)}
              />
            );
            acc += len;
            return el;
          })}
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center text-center">{center ?? <b className="font-display text-2xl tabular">{fmtInt(total)}</b>}</div>
      </div>
      <ul className="w-full space-y-1">
        {segments.map((s) => (
          <li key={s.key}>
            <button
              type="button"
              onClick={() => onSelect?.(s.key)}
              aria-pressed={selected === s.key}
              className={clsx('flex w-full items-center gap-2 rounded-xl px-2 py-1.5 text-left text-[13px] transition hover:bg-slate-50', selected === s.key && 'bg-purple-50 ring-1 ring-purple-200')}
            >
              <span className="size-3 shrink-0 rounded-full" style={{ background: s.color }} aria-hidden />
              <span className="min-w-0 flex-1 truncate font-semibold text-ink-2">{s.label}</span>
              <b className="tabular">{fmtInt(s.value)}</b>
              <span className="w-10 text-right text-[11.5px] tabular text-muted">{Math.round((s.value / total) * 100)}%</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Série temporal (área + pontos). Projeções aparecem tracejadas. */
export function AreaChart({ points, height = 150, color = '#7A24C5', projected = [], format = fmtInt }: {
  points: { label: string; value: number }[]; height?: number; color?: string; projected?: { label: string; value: number }[]; format?: (n: number) => string;
}) {
  const all = [...points, ...projected];
  const max = Math.max(1, ...all.map((p) => p.value)) * 1.15;
  const W = 320;
  const H = 100;
  const step = all.length > 1 ? W / (all.length - 1) : W;
  const xy = (i: number, v: number) => [i * step, H - (v / max) * H] as const;
  const line = points.map((p, i) => xy(i, p.value).join(',')).join(' ');
  const area = points.length ? `0,${H} ${line} ${xy(points.length - 1, 0)[0]},${H}` : '';
  const proj = projected.length ? [xy(points.length - 1, points[points.length - 1]?.value ?? 0), ...projected.map((p, i) => xy(points.length + i, p.value))].map((q) => q.join(',')).join(' ') : '';
  const [hover, setHover] = useState<number | null>(null);
  const id = useMemo(() => 'g' + Math.random().toString(36).slice(2, 8), []);
  return (
    <div>
      <svg viewBox={`-6 -12 ${W + 12} ${H + 30}`} className="w-full" style={{ height }} role="img" aria-label="Série histórica">
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={color} stopOpacity="0.35" />
            <stop offset="1" stopColor={color} stopOpacity="0" />
          </linearGradient>
        </defs>
        {area && <polygon points={area} fill={`url(#${id})`} />}
        {line && <polyline points={line} fill="none" stroke={color} strokeWidth="2.4" strokeLinejoin="round" strokeLinecap="round" />}
        {proj && <polyline points={proj} fill="none" stroke={color} strokeWidth="2" strokeDasharray="5 5" opacity="0.8" />}
        {all.map((p, i) => {
          const [x, y] = xy(i, p.value);
          const isProj = i >= points.length;
          return (
            <g key={i} onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)} onClick={() => setHover(i)} className="cursor-pointer">
              <circle cx={x} cy={y} r={hover === i ? 5 : 3.4} fill={isProj ? '#fff' : color} stroke={color} strokeWidth="2" />
              <rect x={x - step / 2} y={-12} width={step} height={H + 24} fill="transparent" />
              <text x={x} y={H + 14} textAnchor="middle" fontSize="8.5" fill="#5B6B80" fontWeight="600">{p.label}</text>
              {(hover === i || (all.length <= 8)) && (
                <text x={x} y={y - 8} textAnchor="middle" fontSize="9" fontWeight="800" fill={isProj ? '#7A24C5' : '#0E1A2B'}>{format(p.value)}</text>
              )}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

/** Funil de ofertas. */
export function Funnel({ steps }: { steps: ({ key: string; label: string; value: number; color: string } & Clickable)[] }) {
  const max = Math.max(1, ...steps.map((s) => s.value));
  return (
    <div className="space-y-2">
      {steps.map((s, i) => (
        <Wrap key={s.key} to={s.to} onClick={s.onClick} className="group flex items-center gap-3 rounded-2xl p-1 transition hover:bg-slate-50">
          <div className="w-28 shrink-0 text-[13px] font-semibold text-ink-2">{s.label}</div>
          <div className="relative h-9 flex-1">
            <motion.div
              className="absolute inset-y-0 left-0 flex items-center rounded-xl px-3 text-[13px] font-extrabold text-white"
              style={{ background: s.color }}
              initial={{ width: 0 }}
              animate={{ width: `${Math.max(12, (s.value / max) * 100)}%` }}
              transition={{ duration: 0.6, delay: i * 0.08, ease: [0.22, 1, 0.36, 1] }}
            >
              {fmtInt(s.value)}
            </motion.div>
          </div>
        </Wrap>
      ))}
    </div>
  );
}
