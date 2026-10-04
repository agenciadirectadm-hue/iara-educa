import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import clsx from 'clsx';
import { Search, X } from 'lucide-react';
import { useBootstrap } from '@/lib/data';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtInt, fmtKm } from '@/lib/format';
import { FLAG, QUEUE_CATEGORY, QUEUE_STATUS } from '@/lib/labels';
import { Avatar, Badge, Card, Chip, EmptyState, ErrorState, PageHeader, SkeletonList, SourceChip, inputCls } from '@/components/ui';

export default function Queue() {
  const [sp, setSp] = useSearchParams();
  const boot = useBootstrap();
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const unit = sp.get('unidade');
  const serie = sp.get('serie');
  const cat = sp.get('categoria');
  const flag = sp.get('criterio');
  const status = sp.get('status') ?? 'WAITING';
  const page = Number(sp.get('pagina') ?? 1);
  const res = useRpc<any>('queue_list', { unit_id: unit ? Number(unit) : null, grade_level_id: serie ? Number(serie) : null, category: cat, flag, status, q: dq || null, page, page_size: 40 });
  const set = (k: string, v: string | null) => {
    const n = new URLSearchParams(sp);
    if (!v) n.delete(k);
    else n.set(k, v);
    if (k !== 'pagina') n.delete('pagina');
    setSp(n, { replace: true });
  };
  const grades = (boot.data?.grades ?? []) as any[];
  const unitName = (res.data?.items ?? [])[0]?.unit;
  return (
    <div>
      <PageHeader
        eyebrow="Fila de espera"
        title={unit && unitName ? `Fila · ${unitName}` : 'Fila de espera'}
        subtitle="Ordem pela IN nº 025/2025-SEDUC (Anexo I): irmão na mesma unidade 55, CadÚnico 25, até 2 km 15, mãe solo 5 — máximo 100; empate pela data. Laudo PCD/TEA/TGD/AH-SD: prioridade sob análise, fora da soma."
      />
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome da criança" className={clsx(inputCls, 'pl-11')} aria-label="Buscar na fila" />
        {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
      </div>
      <div className="no-scrollbar -mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1">
        <Chip active={flag === 'PCD_TEA_AEE'} onClick={() => set('criterio', flag === 'PCD_TEA_AEE' ? null : 'PCD_TEA_AEE')}>
          Laudo · prioridade sob análise {res.data?.by_flag?.PCD_TEA_AEE ? `· ${fmtInt(res.data.by_flag.PCD_TEA_AEE)}` : ''}
        </Chip>
        <Chip active={!cat} onClick={() => set('categoria', null)}>Todas as categorias</Chip>
        {Object.entries(QUEUE_CATEGORY).map(([k, v]) => (
          <Chip key={k} active={cat === k} onClick={() => set('categoria', cat === k ? null : k)}>{v.short} {res.data?.by_category?.[k] ? `· ${fmtInt(res.data.by_category[k])}` : ''}</Chip>
        ))}
      </div>
      <div className="no-scrollbar -mx-4 mt-1 flex gap-2 overflow-x-auto px-4 pb-1">
        <Chip active={!serie} onClick={() => set('serie', null)}>Todas as faixas</Chip>
        {grades.map((g) => <Chip key={g.id} active={serie === String(g.id)} onClick={() => set('serie', serie === String(g.id) ? null : String(g.id))}>{g.short_name}</Chip>)}
        {unit && <Chip active onClick={() => set('unidade', null)}>Unidade ✕</Chip>}
        <select value={status} onChange={(e) => set('status', e.target.value === 'WAITING' ? null : e.target.value)} className="h-9 shrink-0 rounded-full bg-white px-3 text-[13px] font-semibold ring-1 ring-line">
          <option value="WAITING">Aguardando</option><option value="OFFERED">Com oferta</option><option value="ACCEPTED">Aceitaram</option><option value="MATRICULATED">Matriculadas</option><option value="ALL">Todas</option>
        </select>
      </div>
      <div className="mt-2 flex items-center gap-2 text-[13px] text-muted">{res.data && <span>{fmtInt(res.data.total)} criança(s)</span>}<SourceChip kind="demo" /></div>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : res.data.items.length === 0 ? <Card><EmptyState title="Ninguém neste filtro" /></Card> : (
          <Card className="divide-y divide-line overflow-hidden">
            {(res.data.items as any[]).map((w) => (
              <Link key={w.id} to={`/fila/${w.id}`} className="flex items-center gap-3 px-4 py-3 transition hover:bg-purple-50/50">
                <span className={clsx('inline-flex size-11 shrink-0 items-center justify-center rounded-2xl font-display text-[15px] font-black', w.position ? 'bg-purple-100 text-purple-800' : 'bg-slate-100 text-slate-500')}>{w.position ? `${w.position}º` : '—'}</span>
                <span className="hidden sm:block"><Avatar name={w.student} seed={w.avatar_seed} size={38} /></span>
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{w.student}</div>
                  <div className="truncate text-[12.5px] text-muted">{w.grade} · {w.unit} · {w.days_waiting} dias · {fmtKm(w.distance_m)}</div>
                  <div className="mt-1 flex flex-wrap gap-1">
                    <Badge tone={QUEUE_CATEGORY[w.category]?.tone}>{QUEUE_CATEGORY[w.category]?.short}</Badge>
                    {status !== 'WAITING' && <Badge tone={QUEUE_STATUS[w.status]?.tone}>{QUEUE_STATUS[w.status]?.label}</Badge>}
                    {(w.flags ?? []).map((f: string) => <Badge key={f} tone="purple">{FLAG[f]?.short}</Badge>)}
                  </div>
                </div>
                <div className="text-right"><div className="font-display font-black tabular text-ink">{fmtInt(w.score)}</div><div className="text-[10.5px] text-muted">pontos</div></div>
              </Link>
            ))}
          </Card>
        )}
        {res.data && res.data.total > 40 && (
          <div className="mt-4 flex items-center justify-center gap-2">
            <button disabled={page <= 1} onClick={() => set('pagina', String(page - 1))} className="h-10 rounded-xl bg-white px-4 text-sm font-semibold ring-1 ring-line disabled:opacity-40">Anterior</button>
            <span className="text-sm text-muted">Página {page}</span>
            <button disabled={page * 40 >= res.data.total} onClick={() => set('pagina', String(page + 1))} className="h-10 rounded-xl bg-white px-4 text-sm font-semibold ring-1 ring-line disabled:opacity-40">Próxima</button>
          </div>
        )}
      </div>
    </div>
  );
}
