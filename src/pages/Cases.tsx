import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import clsx from 'clsx';
import { AlarmClock, ClipboardPlus, Search, UserCheck, X } from 'lucide-react';
import { useDebounced, useNow, useRpc } from '@/lib/hooks';
import { fmtInt, timeAgo, timeLeft } from '@/lib/format';
import { CASE_STATUS, CASE_STATUS_ORDER, CHANNEL } from '@/lib/labels';
import { Avatar, Badge, ButtonLink, Card, Chip, EmptyState, ErrorState, PageHeader, SkeletonList, SourceChip, Tabs, inputCls } from '@/components/ui';
import { useSession } from '@/lib/session';

export default function Cases() {
  const [sp, setSp] = useSearchParams();
  const { can } = useSession();
  const now = useNow(60_000);
  const [q, setQ] = useState(sp.get('q') ?? '');
  const dq = useDebounced(q, 300);
  const status = sp.get('status') ?? '';
  const mine = sp.get('mine') === '1';
  const overdue = sp.get('overdue') === '1';
  const unit = sp.get('unidade');
  const page = Number(sp.get('pagina') ?? 1);
  const res = useRpc<any>('cases_list', { status: status || null, mine, overdue, unit_id: unit ? Number(unit) : null, q: dq || null, page, page_size: 30 });
  const set = (k: string, v: string | null) => {
    const n = new URLSearchParams(sp);
    if (!v) n.delete(k);
    else n.set(k, v);
    if (k !== 'pagina') n.delete('pagina');
    setSp(n, { replace: true });
  };
  const counts = res.data?.counts ?? {};
  const totalOpen = Object.entries(counts).filter(([k]) => CASE_STATUS_ORDER.includes(k)).reduce((a, [, v]) => a + (v as number), 0);

  return (
    <div>
      <PageHeader
        eyebrow="CRM público"
        title="Atendimentos"
        subtitle="Protocolos de todos os canais — portal, WhatsApp, presencial, telefone e unidades — com prazo (SLA) e histórico."
        actions={can('cases.write') ? <ButtonLink to="/atendimentos/novo" icon={ClipboardPlus}>Novo atendimento</ButtonLink> : undefined}
      />
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Protocolo ou assunto (ex.: MGA-2026-…)" className={clsx(inputCls, 'pl-11')} aria-label="Buscar atendimento" />
        {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
      </div>
      <Tabs
        className="mt-3"
        value={status}
        onChange={(v) => set('status', v || null)}
        items={[{ value: '', label: 'Abertos', count: totalOpen || null }, ...CASE_STATUS_ORDER.map((s) => ({ value: s, label: CASE_STATUS[s].label, count: counts[s] ?? 0 })), { value: 'ENCERRADO', label: 'Encerrados' }]}
      />
      <div className="no-scrollbar -mx-4 mt-2 flex gap-2 overflow-x-auto px-4 pb-1">
        <Chip icon={UserCheck} active={mine} onClick={() => set('mine', mine ? null : '1')}>Comigo</Chip>
        <Chip icon={AlarmClock} active={overdue} onClick={() => set('overdue', overdue ? null : '1')}>Prazo vencido</Chip>
        {unit && <Chip active onClick={() => set('unidade', null)}>Unidade #{unit} ✕</Chip>}
        <SourceChip kind="demo" className="self-center" />
      </div>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : res.data.items.length === 0 ? (
          <Card><EmptyState title="Nenhum atendimento neste filtro" body="Ajuste os filtros ou abra um novo atendimento." /></Card>
        ) : (
          <>
            <div className="mb-2 text-[13px] text-muted">{fmtInt(res.data.total)} atendimento(s)</div>
            <div className="space-y-2.5">
              {(res.data.items as any[]).map((c) => {
                const st = CASE_STATUS[c.status];
                return (
                  <Link key={c.id} to={`/atendimentos/${c.id}`} className="block rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
                    <div className="flex items-start gap-3">
                      {c.student ? <Avatar name={c.student.name} seed={c.student.avatar_seed} size={42} /> : <span className="inline-flex size-[42px] items-center justify-center rounded-full bg-slate-100 text-slate-500"><ClipboardPlus className="size-5" /></span>}
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-1.5">
                          <span className="text-[12px] font-bold tabular text-muted">{c.protocol}</span>
                          {c.priority !== 'NORMAL' && <Badge tone="red">{c.priority === 'URGENTE' ? 'Urgente' : 'Alta'}</Badge>}
                          {c.assigned_to_me && <Badge tone="blue">Comigo</Badge>}
                        </div>
                        <div className="mt-0.5 truncate font-semibold">{c.subject}</div>
                        <div className="truncate text-[12.5px] text-muted">{c.type_name} · {c.student?.name ?? c.guardian ?? 'sem criança vinculada'}{c.unit ? ` · ${c.unit.name}` : ''}</div>
                      </div>
                      <Badge tone={st?.tone ?? 'gray'}>{st?.label ?? c.status}</Badge>
                    </div>
                    <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2 text-[12px]">
                      <span className="text-muted">{CHANNEL[c.channel] ?? c.channel} · aberto {timeAgo(c.opened_at, now)}{c.assigned ? ` · ${c.assigned}` : ' · sem responsável'}</span>
                      <span className={clsx('inline-flex items-center gap-1 font-semibold', c.overdue ? 'text-red-700' : 'text-ink-2')}>
                        <AlarmClock className="size-3.5" />{c.overdue ? 'Prazo vencido' : `SLA: ${timeLeft(c.sla_due_at, now)}`}
                      </span>
                    </div>
                  </Link>
                );
              })}
            </div>
            <div className="mt-4 flex items-center justify-center gap-2">
              <button disabled={page <= 1} onClick={() => set('pagina', String(page - 1))} className="h-10 rounded-xl bg-white px-4 text-sm font-semibold ring-1 ring-line disabled:opacity-40">Anterior</button>
              <span className="text-sm text-muted">Página {page} de {Math.max(1, Math.ceil(res.data.total / 30))}</span>
              <button disabled={page * 30 >= res.data.total} onClick={() => set('pagina', String(page + 1))} className="h-10 rounded-xl bg-white px-4 text-sm font-semibold ring-1 ring-line disabled:opacity-40">Próxima</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
