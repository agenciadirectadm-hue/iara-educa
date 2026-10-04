import { forwardRef, type ButtonHTMLAttributes, type ComponentType, type ReactNode } from 'react';
import { Link, type LinkProps } from 'react-router';
import { motion } from 'motion/react';
import clsx from 'clsx';
import { AlertTriangle, ChevronRight, Info, Loader2, RefreshCw } from 'lucide-react';
import { TONE_CLASSES, type Tone } from '@/lib/labels';
import { colorFor, fmtInt, initials } from '@/lib/format';
import { useExplain } from './overlays';

type Icon = ComponentType<{ className?: string; strokeWidth?: number; 'aria-hidden'?: boolean }>;

// ---------------------------------------------------------------- Botões
type BtnVariant = 'primary' | 'purple' | 'success' | 'secondary' | 'ghost' | 'danger' | 'soft';
type BtnSize = 'sm' | 'md' | 'lg';
const btnBase =
  'relative inline-flex select-none items-center justify-center gap-2 rounded-2xl font-semibold transition-[background,box-shadow,transform,color] duration-150 active:scale-[0.97] disabled:pointer-events-none disabled:opacity-55';
const btnVariant: Record<BtnVariant, string> = {
  primary: 'bg-blue-700 text-white shadow-[0_8px_20px_-10px_rgb(8_109_182/0.8)] hover:bg-blue-900',
  purple: 'bg-purple-700 text-white shadow-[0_8px_20px_-10px_rgb(122_36_197/0.85)] hover:bg-purple-800',
  success: 'bg-green-700 text-white shadow-[0_8px_20px_-10px_rgb(0_140_114/0.85)] hover:bg-green-800',
  secondary: 'bg-white text-ink ring-1 ring-line hover:ring-blue-200 hover:bg-blue-50',
  ghost: 'text-blue-700 hover:bg-blue-50',
  danger: 'bg-red-600 text-white hover:bg-red-700',
  soft: 'bg-purple-100 text-purple-800 hover:bg-purple-200',
};
const btnSize: Record<BtnSize, string> = { sm: 'h-9 px-3 text-sm', md: 'h-11 px-4 text-[15px]', lg: 'h-14 px-6 text-base' };

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: BtnVariant; size?: BtnSize; loading?: boolean; icon?: Icon; block?: boolean;
}>(function Button({ variant = 'primary', size = 'md', loading, icon: I, block, className, children, disabled, ...rest }, ref) {
  return (
    <button ref={ref} className={clsx(btnBase, btnVariant[variant], btnSize[size], block && 'w-full', className)} disabled={disabled || loading} aria-busy={loading || undefined} {...rest}>
      {loading ? <Loader2 className="size-4 animate-spin" aria-hidden /> : I ? <I className="size-[18px]" aria-hidden /> : null}
      {children}
    </button>
  );
});

export function ButtonLink({ variant = 'primary', size = 'md', icon: I, block, className, children, ...rest }: LinkProps & {
  variant?: BtnVariant; size?: BtnSize; icon?: Icon; block?: boolean;
}) {
  return (
    <Link className={clsx(btnBase, btnVariant[variant], btnSize[size], block && 'w-full', className)} {...rest}>
      {I && <I className="size-[18px]" aria-hidden />}
      {children}
    </Link>
  );
}

export function IconButton({ icon: I, label, className, tone = 'default', ...rest }: ButtonHTMLAttributes<HTMLButtonElement> & {
  icon: Icon; label: string; tone?: 'default' | 'glass' | 'purple';
}) {
  return (
    <button
      aria-label={label}
      title={label}
      className={clsx(
        'inline-flex size-11 items-center justify-center rounded-2xl transition active:scale-95',
        tone === 'default' && 'bg-white text-ink ring-1 ring-line hover:bg-blue-50',
        tone === 'glass' && 'glass text-ink shadow-soft ring-1 ring-white/60',
        tone === 'purple' && 'bg-purple-700 text-white hover:bg-purple-800',
        className,
      )}
      {...rest}
    >
      <I className="size-5" aria-hidden />
    </button>
  );
}

// ---------------------------------------------------------------- Cartões
export function Card({ className, children, as: As = 'div', ...rest }: { className?: string; children: ReactNode; as?: any } & Record<string, any>) {
  return (
    <As className={clsx('min-w-0 rounded-3xl bg-white shadow-soft ring-1 ring-line/70', className)} {...rest}>
      {children}
    </As>
  );
}

const MotionLink = motion.create(Link);
export function LinkCard({ to, className, children, state, ariaLabel }: { to: string; className?: string; children: ReactNode; state?: any; ariaLabel?: string }) {
  return (
    <MotionLink
      to={to}
      state={state}
      aria-label={ariaLabel}
      whileTap={{ scale: 0.98 }}
      transition={{ type: 'spring', stiffness: 500, damping: 32 }}
      className={clsx('group block min-w-0 rounded-3xl bg-white shadow-soft ring-1 ring-line/70 transition-shadow hover:shadow-lift hover:ring-blue-200', className)}
    >
      {children}
    </MotionLink>
  );
}

export function PressCard({ onClick, className, children, ariaLabel, disabled }: { onClick: () => void; className?: string; children: ReactNode; ariaLabel?: string; disabled?: boolean }) {
  return (
    <motion.button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      disabled={disabled}
      whileTap={{ scale: 0.98 }}
      className={clsx('group block w-full min-w-0 rounded-3xl bg-white text-left shadow-soft ring-1 ring-line/70 transition-shadow hover:shadow-lift hover:ring-blue-200 disabled:opacity-60', className)}
    >
      {children}
    </motion.button>
  );
}

// ---------------------------------------------------------------- Selos e fontes
export function Badge({ tone = 'gray', children, dot, icon: I, className, solid }: { tone?: Tone; children: ReactNode; dot?: boolean; icon?: Icon; className?: string; solid?: boolean }) {
  const t = TONE_CLASSES[tone];
  return (
    <span className={clsx('inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold', solid ? t.solid : clsx(t.bg, t.text), className)}>
      {dot && <span className={clsx('size-1.5 rounded-full', t.dot)} aria-hidden />}
      {I && <I className="size-3.5" aria-hidden />}
      {children}
    </span>
  );
}

export type SourceKind = 'oficial' | 'publico' | 'demo' | 'projetado' | 'pendente' | 'calculado';
const SOURCE: Record<SourceKind, { label: string; cls: string; title: string; body: string }> = {
  oficial: {
    label: 'Fonte oficial', cls: 'bg-green-100 text-green-800 ring-green-200', title: 'Dado oficial',
    body: 'Número de fonte pública oficial (Censo Escolar 2025/INEP ou Consulta Escolas/SEED-PR 2026), com data de referência. Não é estimativa.',
  },
  publico: {
    label: 'Fonte pública', cls: 'bg-blue-100 text-blue-900 ring-blue-200', title: 'Dado público',
    body: 'Informação levantada em fontes públicas (Prefeitura, Câmara, SEED-PR). Pode precisar de confirmação pela SEDUC.',
  },
  demo: {
    label: 'Demonstração', cls: 'bg-amber-100 text-amber-900 ring-amber-200', title: 'Dado de demonstração',
    body: 'Valor da camada operacional fictícia (turmas, capacidade, fila, protocolos e pessoas). A estrutura de turmas segue o Censo 2025, mas capacidade, vagas e pessoas são simulados até a integração com a SEDUC.',
  },
  projetado: {
    label: 'Projetado', cls: 'bg-purple-100 text-purple-800 ring-purple-200', title: 'Projeção (cenário)',
    body: 'Resultado de modelo simples, separado dos fatos. Use como cenário para discussão, nunca como dado observado.',
  },
  pendente: {
    label: 'Pendente SEDUC', cls: 'bg-slate-100 text-slate-700 ring-slate-200', title: 'Pendente de integração',
    body: 'Dado ainda não disponível em fonte pública confiável. Aguarda extração oficial da SEDUC — nada foi inventado.',
  },
  calculado: {
    label: 'Calculado', cls: 'bg-teal-50 text-teal-800 ring-teal-200', title: 'Cálculo determinístico',
    body: 'Resultado de regra explícita e versionada (ex.: vagas ofertáveis = capacidade − matrículas − bloqueadas − reservadas).',
  },
};
export function SourceChip({ kind, detail, className }: { kind: SourceKind; detail?: string; className?: string }) {
  const explain = useExplain();
  const s = SOURCE[kind];
  return (
    <button
      type="button"
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        explain({ title: s.title, body: detail ? `${s.body}\n\n${detail}` : s.body, kind });
      }}
      className={clsx('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide ring-1 transition hover:brightness-95', s.cls, className)}
      aria-label={`${s.label}: o que significa?`}
    >
      {kind === 'demo' ? <AlertTriangle className="size-3" aria-hidden /> : <Info className="size-3" aria-hidden />}
      {s.label}
    </button>
  );
}

// ---------------------------------------------------------------- KPIs
const KPI_TONE: Record<string, string> = {
  blue: 'from-blue-500 to-blue-700', green: 'from-green-500 to-green-700', purple: 'from-purple-500 to-purple-700',
  amber: 'from-amber-400 to-orange-500', red: 'from-rose-500 to-red-600', teal: 'from-teal-400 to-teal-600', gray: 'from-slate-400 to-slate-600',
};
export function Kpi({ icon: I, label, value, sub, tone = 'blue', to, onClick, source, sourceDetail, compact, className }: {
  icon: Icon; label: string; value: ReactNode; sub?: ReactNode; tone?: keyof typeof KPI_TONE; to?: string; onClick?: () => void;
  source?: SourceKind; sourceDetail?: string; compact?: boolean; className?: string;
}) {
  const inner = (
    <div className={clsx('flex h-full flex-col gap-2', compact ? 'p-3.5' : 'p-4')}>
      <div className="flex items-start justify-between gap-2">
        <span className={clsx('inline-flex items-center justify-center rounded-2xl bg-gradient-to-br text-white shadow-sm', KPI_TONE[tone], compact ? 'size-9' : 'size-10')}>
          <I className={compact ? 'size-[18px]' : 'size-5'} aria-hidden />
        </span>
        {source && <SourceChip kind={source} detail={sourceDetail} />}
      </div>
      <div className="mt-auto">
        <div className={clsx('font-display font-extrabold leading-none tabular text-ink', compact ? 'text-2xl' : 'text-[28px]')}>{value}</div>
        <div className="mt-1 text-[13px] font-semibold text-ink-2">{label}</div>
        {sub && <div className="mt-0.5 text-xs text-muted">{sub}</div>}
      </div>
    </div>
  );
  if (to) return <LinkCard to={to} className={clsx('min-w-0', className)} ariaLabel={`${label}: ver detalhes`}>{inner}</LinkCard>;
  if (onClick) return <PressCard onClick={onClick} className={clsx('min-w-0', className)} ariaLabel={`${label}: ver detalhes`}>{inner}</PressCard>;
  return <Card className={clsx('min-w-0', className)}>{inner}</Card>;
}

// ---------------------------------------------------------------- Estrutura de página
export function PageHeader({ title, subtitle, eyebrow, actions, back }: { title: ReactNode; subtitle?: ReactNode; eyebrow?: ReactNode; actions?: ReactNode; back?: ReactNode }) {
  return (
    <header className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div className="min-w-0">
        {back}
        {eyebrow && <div className="mb-1 text-xs font-bold uppercase tracking-[0.12em] text-purple-700">{eyebrow}</div>}
        <h1 className="font-display text-[26px] font-extrabold leading-tight text-ink text-balance sm:text-3xl">{title}</h1>
        {subtitle && <p className="mt-1 text-[15px] text-muted text-balance">{subtitle}</p>}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap gap-2">{actions}</div>}
    </header>
  );
}

export function Section({ title, subtitle, action, children, className, id }: { title?: ReactNode; subtitle?: ReactNode; action?: ReactNode; children: ReactNode; className?: string; id?: string }) {
  return (
    <section className={clsx('mt-6', className)} id={id}>
      {(title || action) && (
        <div className="mb-3 flex items-end justify-between gap-3">
          <div className="min-w-0">
            {title && <h2 className="font-display text-lg font-extrabold text-ink">{title}</h2>}
            {subtitle && <p className="text-[13px] text-muted">{subtitle}</p>}
          </div>
          {action}
        </div>
      )}
      {children}
    </section>
  );
}

export function Tabs<T extends string>({ value, onChange, items, className }: { value: T; onChange: (v: T) => void; items: { value: T; label: string; count?: number | null }[]; className?: string }) {
  return (
    <div role="tablist" className={clsx('no-scrollbar -mx-4 flex gap-1.5 overflow-x-auto px-4 pb-1', className)}>
      {items.map((it) => {
        const active = it.value === value;
        return (
          <button
            key={it.value}
            role="tab"
            aria-selected={active}
            onClick={() => onChange(it.value)}
            className={clsx('relative flex h-10 shrink-0 items-center gap-1.5 rounded-full px-4 text-sm font-semibold transition', active ? 'text-white' : 'bg-white text-ink-2 ring-1 ring-line hover:bg-blue-50')}
          >
            {active && <motion.span layoutId={`tab-${items.map((i) => i.value).join('')}`} className="absolute inset-0 rounded-full bg-blue-900" transition={{ type: 'spring', stiffness: 420, damping: 34 }} />}
            <span className="relative">{it.label}</span>
            {it.count != null && <span className={clsx('relative rounded-full px-1.5 text-[11px] tabular', active ? 'bg-white/20' : 'bg-slate-100 text-muted')}>{fmtInt(it.count)}</span>}
          </button>
        );
      })}
    </div>
  );
}

export function Segmented<T extends string>({ value, onChange, items, className }: { value: T; onChange: (v: T) => void; items: { value: T; label: string }[]; className?: string }) {
  return (
    <div className={clsx('inline-flex rounded-2xl bg-white p-1 ring-1 ring-line', className)} role="radiogroup">
      {items.map((it) => (
        <button
          key={it.value}
          role="radio"
          aria-checked={it.value === value}
          onClick={() => onChange(it.value)}
          className={clsx('relative h-9 rounded-xl px-3 text-sm font-semibold transition', it.value === value ? 'text-white' : 'text-ink-2 hover:text-blue-700')}
        >
          {it.value === value && <motion.span layoutId={`seg-${items.map((i) => i.value).join('')}`} className="absolute inset-0 rounded-xl bg-purple-700" transition={{ type: 'spring', stiffness: 420, damping: 34 }} />}
          <span className="relative">{it.label}</span>
        </button>
      ))}
    </div>
  );
}

export function Chip({ active, onClick, children, icon: I }: { active?: boolean; onClick?: () => void; children: ReactNode; icon?: Icon }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={!!active}
      className={clsx('inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-semibold transition', active ? 'bg-purple-700 text-white shadow-glow' : 'bg-white text-ink-2 ring-1 ring-line hover:bg-purple-50')}
    >
      {I && <I className="size-4" aria-hidden />}
      {children}
    </button>
  );
}

// ---------------------------------------------------------------- Estados
export function Skeleton({ className }: { className?: string }) {
  return <div className={clsx('skeleton rounded-2xl', className)} aria-hidden />;
}
export function SkeletonList({ rows = 4 }: { rows?: number }) {
  return (
    <div className="space-y-3" aria-busy="true" aria-label="Carregando">
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} className="h-20" />
      ))}
    </div>
  );
}

export function EmptyState({ title, body, action, compact }: { title: string; body?: ReactNode; action?: ReactNode; compact?: boolean }) {
  return (
    <div className={clsx('flex flex-col items-center text-center', compact ? 'py-6' : 'py-10')}>
      <img src="./iara/iara-avatar.webp" alt="" className={clsx('rounded-full shadow-soft ring-4 ring-white', compact ? 'size-16' : 'size-24')} />
      <h3 className="mt-3 font-display text-lg font-extrabold">{title}</h3>
      {body && <p className="mt-1 max-w-sm text-sm text-muted">{body}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function ErrorState({ error, onRetry }: { error: { message?: string; status?: number } | null; onRetry?: () => void }) {
  const denied = error?.status === 403;
  return (
    <Card className="flex items-start gap-3 p-4">
      <span className={clsx('inline-flex size-10 shrink-0 items-center justify-center rounded-2xl', denied ? 'bg-slate-100 text-slate-600' : 'bg-red-100 text-red-700')}>
        <AlertTriangle className="size-5" aria-hidden />
      </span>
      <div className="min-w-0 flex-1">
        <div className="font-semibold">{denied ? 'Sem permissão para este conteúdo' : 'Não foi possível carregar'}</div>
        <p className="text-sm text-muted">{denied ? 'Seu perfil não tem acesso a esta informação. Isso é controlado pelo servidor (perfil e escopo).' : error?.message}</p>
        {onRetry && !denied && (
          <Button variant="secondary" size="sm" className="mt-2" icon={RefreshCw} onClick={onRetry}>
            Tentar de novo
          </Button>
        )}
      </div>
    </Card>
  );
}

export function Spinner({ className }: { className?: string }) {
  return <Loader2 className={clsx('size-5 animate-spin text-purple-700', className)} aria-label="Carregando" />;
}

// ---------------------------------------------------------------- Pessoas, barras e linhas
export function Avatar({ name, seed, size = 40, className }: { name: string; seed?: number | string; size?: number; className?: string }) {
  return (
    <span
      className={clsx('inline-flex shrink-0 select-none items-center justify-center rounded-full font-display font-extrabold text-white ring-2 ring-white', className)}
      style={{ width: size, height: size, fontSize: size * 0.38, background: `linear-gradient(135deg, ${colorFor(seed ?? name)}, ${colorFor((Number(seed) || name.length) + 3)})` }}
      aria-hidden
    >
      {initials(name)}
    </span>
  );
}

export function OccupancyBar({ capacity, enrolled, reserved = 0, blocked = 0, offerable, showLegend, height = 10 }: {
  capacity: number; enrolled: number; reserved?: number; blocked?: number; offerable?: number; showLegend?: boolean; height?: number;
}) {
  const cap = Math.max(capacity, 1);
  const off = offerable ?? Math.max(capacity - enrolled - reserved - blocked, 0);
  const seg = [
    { v: enrolled, c: 'bg-blue-700', l: 'Matrículas' },
    { v: reserved, c: 'bg-purple-500', l: 'Reservadas (oferta)' },
    { v: blocked, c: 'bg-amber-400', l: 'Bloqueadas' },
    { v: off, c: 'bg-green-500', l: 'Ofertáveis' },
  ];
  return (
    <div>
      <div className="flex w-full overflow-hidden rounded-full bg-slate-100" style={{ height }} role="img" aria-label={`Capacidade ${capacity}: ${enrolled} matrículas, ${reserved} reservadas, ${blocked} bloqueadas, ${off} ofertáveis`}>
        {seg.map((s) => s.v > 0 && <div key={s.l} className={clsx(s.c, 'h-full')} style={{ width: `${(s.v / cap) * 100}%` }} />)}
      </div>
      {showLegend && (
        <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-[11.5px] text-muted">
          {seg.map((s) => (
            <span key={s.l} className="inline-flex items-center gap-1">
              <span className={clsx('size-2 rounded-full', s.c)} aria-hidden />
              {s.l}: <b className="tabular text-ink">{fmtInt(s.v)}</b>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

export function Meter({ value, max = 100, tone = 'purple', className }: { value: number; max?: number; tone?: 'purple' | 'blue' | 'green' | 'amber' | 'red'; className?: string }) {
  const pct = Math.max(0, Math.min(100, (value / Math.max(max, 1)) * 100));
  const c = { purple: 'bg-purple-500', blue: 'bg-blue-500', green: 'bg-green-500', amber: 'bg-amber-400', red: 'bg-red-500' }[tone];
  return (
    <div className={clsx('h-2 w-full overflow-hidden rounded-full bg-slate-100', className)}>
      <motion.div className={clsx('h-full rounded-full', c)} initial={{ width: 0 }} animate={{ width: `${pct}%` }} transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }} />
    </div>
  );
}

export function ListRow({ to, onClick, leading, title, subtitle, meta, trailing, className }: {
  to?: string; onClick?: () => void; leading?: ReactNode; title: ReactNode; subtitle?: ReactNode; meta?: ReactNode; trailing?: ReactNode; className?: string;
}) {
  const body = (
    <>
      {leading}
      <div className="min-w-0 flex-1">
        <div className="truncate text-[15px] font-semibold text-ink">{title}</div>
        {subtitle && <div className="truncate text-[13px] text-muted">{subtitle}</div>}
      </div>
      {meta && <div className="shrink-0 text-right text-[13px]">{meta}</div>}
      {trailing ?? ((to || onClick) && <ChevronRight className="size-5 shrink-0 text-subtle transition group-hover:translate-x-0.5 group-hover:text-blue-700" aria-hidden />)}
    </>
  );
  const cls = clsx('group flex min-h-[64px] w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-blue-50/60', className);
  if (to) return <Link to={to} className={cls}>{body}</Link>;
  if (onClick) return <button type="button" onClick={onClick} className={cls}>{body}</button>;
  return <div className={cls}>{body}</div>;
}

export function DataPair({ label, value, className }: { label: string; value: ReactNode; className?: string }) {
  return (
    <div className={clsx('min-w-0', className)}>
      <dt className="text-[11.5px] font-semibold uppercase tracking-wide text-subtle">{label}</dt>
      <dd className="mt-0.5 break-words text-[14.5px] font-medium text-ink">{value ?? '—'}</dd>
    </div>
  );
}

// ---------------------------------------------------------------- Formulários
export function Field({ label, hint, children, error }: { label: string; hint?: string; children: ReactNode; error?: string | null }) {
  return (
    <label className="block">
      <span className="mb-1 block text-[13px] font-semibold text-ink-2">{label}</span>
      {children}
      {hint && !error && <span className="mt-1 block text-xs text-muted">{hint}</span>}
      {error && <span className="mt-1 block text-xs font-semibold text-red-700">{error}</span>}
    </label>
  );
}
export const inputCls =
  'h-12 w-full rounded-2xl bg-white px-4 text-[15px] text-ink ring-1 ring-line outline-none transition placeholder:text-subtle focus:ring-2 focus:ring-purple-500';
