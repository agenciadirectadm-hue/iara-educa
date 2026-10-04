import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import clsx from 'clsx';
import { Map as MapIcon, School, Search, X } from 'lucide-react';
import { useBootstrap } from '@/lib/data';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtInt, fmtPct } from '@/lib/format';
import { Badge, ButtonLink, Card, Chip, ErrorState, OccupancyBar, PageHeader, SkeletonList, SourceChip, inputCls } from '@/components/ui';

export default function Units() {
  const [sp, setSp] = useSearchParams();
  const boot = useBootstrap();
  const [q, setQ] = useState(sp.get('q') ?? '');
  const dq = useDebounced(q, 250);
  const type = sp.get('tipo') ?? '';
  const territory = sp.get('territorio') ?? '';
  const stage = sp.get('etapa') ?? '';
  const sort = sp.get('ordem') ?? 'name';
  const hasVacancy = sp.get('vaga') === '1';
  const res = useRpc<any>('units_list', { q: dq || null, type: type || null, territory_id: territory ? Number(territory) : null, stage: stage || null, sort, has_vacancy: hasVacancy });
  const set = (k: string, v: string | null) => {
    const n = new URLSearchParams(sp);
    if (!v) n.delete(k);
    else n.set(k, v);
    setSp(n, { replace: true });
  };

  return (
    <div>
      <PageHeader
        eyebrow="Rede municipal"
        title="Unidades"
        subtitle="118 registros investigados: endereço, direção, oferta e matrículas de fontes públicas; turmas, vagas e fila na camada de demonstração."
        actions={<ButtonLink to="/mapa" variant="secondary" icon={MapIcon}>Ver no mapa</ButtonLink>}
      />
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome, bairro ou endereço" className={clsx(inputCls, 'pl-11')} aria-label="Buscar unidade" />
        {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
      </div>
      <div className="no-scrollbar -mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1">
        <Chip active={!type} onClick={() => set('tipo', null)}>Todas</Chip>
        <Chip active={type === 'CMEI'} onClick={() => set('tipo', 'CMEI')}>CMEIs</Chip>
        <Chip active={type === 'ESCOLA'} onClick={() => set('tipo', 'ESCOLA')}>Escolas</Chip>
        <Chip active={hasVacancy} onClick={() => set('vaga', hasVacancy ? null : '1')}>Com vaga</Chip>
        <Chip active={stage === 'EJA'} onClick={() => set('etapa', stage === 'EJA' ? null : 'EJA')}>Com EJA</Chip>
        {(boot.data?.territories ?? []).map((t) => (
          <Chip key={t.id} active={territory === String(t.id)} onClick={() => set('territorio', territory === String(t.id) ? null : String(t.id))}>{t.name}</Chip>
        ))}
      </div>
      <div className="mt-2 flex items-center justify-between gap-2 text-[13px] text-muted">
        <span>{res.data ? `${fmtInt(res.data.total)} unidade(s)` : ''}</span>
        <label className="flex items-center gap-2">
          Ordenar
          <select value={sort} onChange={(e) => set('ordem', e.target.value)} className="h-9 rounded-xl bg-white px-2 text-[13px] font-semibold text-ink ring-1 ring-line">
            <option value="name">Nome</option>
            <option value="vacancy">Mais vagas</option>
            <option value="queue">Maior fila</option>
            <option value="occupancy">Maior ocupação</option>
          </select>
        </label>
      </div>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {res.data.items.map((u: any) => (
              <Link key={u.id} to={`/unidades/${u.id}`} className="group rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
                <div className="flex items-start gap-3">
                  <span className={clsx('inline-flex size-10 shrink-0 items-center justify-center rounded-2xl text-white', u.status !== 'ATIVA' ? 'bg-slate-400' : u.type === 'CMEI' ? 'bg-purple-500' : 'bg-blue-500')}><School className="size-5" /></span>
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-semibold group-hover:text-purple-700">{u.name}</div>
                    <div className="truncate text-[12.5px] text-muted">{u.neighborhood} · {u.territory}</div>
                  </div>
                </div>
                <div className="mt-3 flex flex-wrap gap-1.5">
                  <Badge tone={u.type === 'CMEI' ? 'purple' : 'blue'}>{u.type_label}</Badge>
                  {u.status !== 'ATIVA' && <Badge tone="gray">A validar</Badge>}
                  {u.geo_precision !== 'VALIDADO' && <Badge tone="amber">GEO {u.geo_precision.toLowerCase()}</Badge>}
                </div>
                <div className="mt-3 grid grid-cols-3 gap-2 text-center">
                  <div><div className="font-display text-lg font-black tabular">{fmtInt(u.public_enrollments)}</div><div className="text-[11px] text-muted">matrículas</div></div>
                  <div><div className={clsx('font-display text-lg font-black tabular', u.ops.offerable > 0 ? 'text-green-700' : '')}>{fmtInt(u.ops.offerable)}</div><div className="text-[11px] text-muted">vagas*</div></div>
                  <div><div className="font-display text-lg font-black tabular">{fmtInt(u.ops.queue)}</div><div className="text-[11px] text-muted">fila*</div></div>
                </div>
                {u.ops.capacity > 0 && <div className="mt-3"><OccupancyBar capacity={u.ops.capacity} enrolled={u.ops.enrolled} reserved={u.ops.reserved} blocked={u.ops.blocked} offerable={u.ops.offerable} height={7} /></div>}
                <div className="mt-2 text-[11.5px] text-muted">Ocupação {fmtPct(u.ops.occupancy)} · *demonstração</div>
              </Link>
            ))}
          </div>
        )}
      </div>
      <Card className="mt-6 flex items-start gap-3 p-4 text-[13px] text-muted">
        <SourceChip kind="oficial" /> <span>Matrículas e turmas: agregado público mais recente por unidade (SEED-PR 2026 quando disponível; senão Censo Escolar 2025). Vagas e fila: camada de demonstração.</span>
      </Card>
    </div>
  );
}
