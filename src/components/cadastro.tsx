import type { ComponentType, ReactNode } from 'react';
import clsx from 'clsx';
import { AlertCircle, CheckCircle2, Lock, Save } from 'lucide-react';
import { Button, Card, Meter, inputCls } from './ui';

type Icon = ComponentType<{ className?: string }>;

/** Seção do formulário de cadastro: cartão com título, ícone e explicação curta. */
export function Secao({ icon: I, titulo, descricao, acao, children, id, className }: {
  icon: Icon; titulo: string; descricao?: ReactNode; acao?: ReactNode; children: ReactNode; id?: string; className?: string;
}) {
  return (
    <Card as="section" id={id} className={clsx('scroll-mt-24 p-4 sm:p-5', className)} aria-labelledby={id ? `${id}-titulo` : undefined}>
      <div className="mb-4 flex items-start gap-3">
        <span className="inline-flex size-10 shrink-0 items-center justify-center rounded-2xl bg-purple-50 text-purple-700"><I className="size-5" /></span>
        <div className="min-w-0 flex-1">
          <h2 id={id ? `${id}-titulo` : undefined} className="font-display text-lg font-extrabold leading-tight">{titulo}</h2>
          {descricao && <p className="mt-0.5 text-[13px] text-muted">{descricao}</p>}
        </div>
        {acao}
      </div>
      {children}
    </Card>
  );
}

/** Campo com rótulo, obrigatório (*), dica e erro. */
export function Campo({ label, obrigatorio, dica, erro, children, className }: {
  label: string; obrigatorio?: boolean; dica?: ReactNode; erro?: string | null; children: ReactNode; className?: string;
}) {
  return (
    <label className={clsx('block min-w-0', className)}>
      <span className="mb-1 block text-[13px] font-semibold text-ink-2">
        {label}{obrigatorio && <span className="text-red-600" aria-hidden> *</span>}
      </span>
      {children}
      {erro ? <span className="mt-1 block text-xs font-semibold text-red-700">{erro}</span> : dica ? <span className="mt-1 block text-xs text-muted">{dica}</span> : null}
    </label>
  );
}

export function Texto({ value, onChange, erro, className, ...rest }: Omit<React.InputHTMLAttributes<HTMLInputElement>, 'onChange' | 'value'> & {
  value: string; onChange: (v: string) => void; erro?: boolean;
}) {
  return (
    <input {...rest} value={value} onChange={(e) => onChange(e.target.value)} aria-invalid={erro || undefined}
      className={clsx(inputCls, erro && 'ring-2 ring-red-400', rest.readOnly && 'bg-slate-50 text-muted', className)} />
  );
}

export function Selecao({ value, onChange, opcoes, vazio = 'Selecione', className, ...rest }: Omit<React.SelectHTMLAttributes<HTMLSelectElement>, 'onChange' | 'value'> & {
  value: string; onChange: (v: string) => void; opcoes: [string, string][] | string[]; vazio?: string | false;
}) {
  const ops = (opcoes as (string | [string, string])[]).map((o) => (Array.isArray(o) ? o : [o, o])) as [string, string][];
  return (
    <select {...rest} value={value} onChange={(e) => onChange(e.target.value)} className={clsx(inputCls, 'appearance-none bg-[length:16px] pr-9', className)}
      style={{ backgroundImage: "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2364748b' stroke-width='2'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E\")", backgroundRepeat: 'no-repeat', backgroundPosition: 'right 12px center' }}>
      {vazio !== false && <option value="">{vazio}</option>}
      {ops.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
    </select>
  );
}

/** Escolha única em botões (rádio visual). */
export function Escolha<T extends string>({ value, onChange, opcoes, nome, className }: {
  value: T | '' | null; onChange: (v: T) => void; opcoes: [T, string][]; nome: string; className?: string;
}) {
  return (
    <div role="radiogroup" aria-label={nome} className={clsx('flex flex-wrap gap-2', className)}>
      {opcoes.map(([v, l]) => (
        <button key={v} type="button" role="radio" aria-checked={value === v} onClick={() => onChange(v)}
          className={clsx('min-h-11 rounded-2xl px-3.5 text-[14px] font-semibold ring-1 transition',
            value === v ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white text-ink-2 ring-line hover:bg-purple-50')}>
          {l}
        </button>
      ))}
    </div>
  );
}

export function Alternar({ checked, onChange, label, dica, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; dica?: ReactNode; disabled?: boolean }) {
  return (
    <label className={clsx('flex min-h-[52px] items-start gap-3 rounded-2xl bg-white p-3 ring-1 ring-line', disabled ? 'opacity-60' : 'cursor-pointer hover:bg-slate-50')}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} className="mt-0.5 size-5 shrink-0 accent-purple-700" />
      <span className="min-w-0"><span className="block text-[14.5px] font-semibold">{label}</span>{dica && <span className="block text-[12.5px] text-muted">{dica}</span>}</span>
    </label>
  );
}

/** Quanto do cadastro está completo e o que falta. */
export function Completude({ pct, pendencias, className, compacto }: { pct: number; pendencias: string[]; className?: string; compacto?: boolean }) {
  const ok = pendencias.length === 0;
  return (
    <div className={clsx('rounded-2xl p-3 ring-1', ok ? 'bg-green-50 ring-green-200' : 'bg-amber-50 ring-amber-200', className)}>
      <div className="flex items-center gap-2">
        {ok ? <CheckCircle2 className="size-5 shrink-0 text-green-700" /> : <AlertCircle className="size-5 shrink-0 text-amber-700" />}
        <span className={clsx('text-[14px] font-bold', ok ? 'text-green-900' : 'text-amber-950')}>
          {ok ? 'Cadastro completo' : `Cadastro ${Math.round(pct)}% completo`}
        </span>
        <span className="ml-auto tabular text-[13px] font-bold text-ink-2">{Math.round(pct)}%</span>
      </div>
      <Meter value={pct} tone={ok ? 'green' : 'amber'} className="mt-2" />
      {!ok && !compacto && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          <span className="text-[12.5px] text-amber-950">Falta:</span>
          {pendencias.map((p) => <span key={p} className="rounded-full bg-white px-2 py-0.5 text-[12px] font-semibold text-amber-900 ring-1 ring-amber-200">{p}</span>)}
        </div>
      )}
    </div>
  );
}

export function AvisoRestrito({ children }: { children: ReactNode }) {
  return (
    <p className="flex items-start gap-2 rounded-2xl bg-slate-100 p-3 text-[13px] text-ink-2">
      <Lock className="mt-0.5 size-4 shrink-0" /><span>{children}</span>
    </p>
  );
}

/** Pequeno anel com o percentual de completude (listas). */
export function AnelCompleto({ pct, size = 40 }: { pct: number; size?: number }) {
  const r = size / 2 - 4;
  const c = 2 * Math.PI * r;
  const cor = pct >= 100 ? '#15803d' : pct >= 70 ? '#d97706' : '#dc2626';
  return (
    <span className="relative inline-flex shrink-0 items-center justify-center" style={{ width: size, height: size }} title={`Cadastro ${Math.round(pct)}% completo`}>
      <svg width={size} height={size} className="-rotate-90" aria-hidden>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="#e2e8f0" strokeWidth={4} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={cor} strokeWidth={4} strokeDasharray={c} strokeDashoffset={c * (1 - Math.min(pct, 100) / 100)} strokeLinecap="round" />
      </svg>
      <span className="absolute text-[10.5px] font-bold tabular" style={{ color: cor }}>{Math.round(pct)}</span>
    </span>
  );
}

/** Barra fixa de salvar: percentual do cadastro e o que falta, em uma linha (cabe no celular). */
export function BarraSalvar({ pct, pendencias, rotulo, busy, onSalvar }: { pct: number; pendencias: string[]; rotulo: string; busy: boolean; onSalvar: () => void }) {
  const ok = pendencias.length === 0;
  return (
    <div className="sticky bottom-20 z-30 mt-4 lg:bottom-4">
      <div className="glass flex items-center gap-3 rounded-3xl p-2.5 shadow-lift ring-1 ring-line">
        <div className="min-w-0 flex-1 px-1">
          <div className={clsx('flex items-center gap-1.5 text-[13px] font-bold', ok ? 'text-green-800' : 'text-amber-900')}>
            {ok ? <CheckCircle2 className="size-4 shrink-0" /> : <AlertCircle className="size-4 shrink-0" />}
            <span className="truncate">{ok ? 'Cadastro completo' : `Cadastro ${Math.round(pct)}% · falta ${pendencias.length}`}</span>
          </div>
          <Meter value={pct} tone={ok ? 'green' : 'amber'} className="mt-1.5" />
          {!ok && <div className="mt-1 hidden truncate text-[12px] text-muted sm:block">Falta: {pendencias.join(', ')}</div>}
        </div>
        <Button size="lg" variant="purple" icon={Save} loading={busy} onClick={onSalvar} className="shrink-0 px-4 sm:min-w-[200px]">{rotulo}</Button>
      </div>
    </div>
  );
}
