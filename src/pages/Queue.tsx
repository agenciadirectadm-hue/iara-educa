import { useState } from 'react';
import { useSearchParams } from 'react-router';
import clsx from 'clsx';
import { Check, Search, X } from 'lucide-react';
import { keepPreviousData } from '@tanstack/react-query';
import { useBootstrap } from '@/lib/data';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtInt, fmtKm } from '@/lib/format';
import { FLAG, QUEUE_CATEGORY, QUEUE_STATUS } from '@/lib/labels';
import type { MedidaDistancia } from '@/lib/api';
import { Avatar, Badge, Card, Chip, EmptyState, ErrorState, PageHeader, SkeletonList, SourceChip, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { LinkMetodologia, MEDIDA, MEDIDAS } from '@/components/distancias';
import { Paginacao } from './Alunos';

const CHAVE_DIST: Record<MedidaDistancia, 'linha_reta_m' | 'a_pe_m' | 'carro_m'> = { LINHA_RETA: 'linha_reta_m', A_PE: 'a_pe_m', CARRO: 'carro_m' };

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
  const res = useRpc<any>('queue_list', { unit_id: unit ? Number(unit) : null, grade_level_id: serie ? Number(serie) : null, category: cat, flag, status, q: dq || null, page, page_size: 40 },
    { placeholderData: keepPreviousData });
  const crit = res.data?.criterio_distancia as { medida: MedidaDistancia; limite_m: number } | undefined;
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
      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] text-muted">
        {res.data && <span className="inline-flex items-center gap-1">{fmtInt(res.data.total)} criança(s)<SourceChip kind="demo" /></span>}
        {crit && (
          <span>
            Distância da casa à unidade pretendida em linha reta, a pé e de carro (pelas ruas) · o critério “até {fmtKm(crit.limite_m)}” usa a medida <b className="text-purple-800">{MEDIDA[crit.medida].rotulo.toLowerCase()}</b> ·{' '}
            <LinkMetodologia>como medimos</LinkMetodologia>
          </span>
        )}
      </div>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : res.data.items.length === 0 ? <Card><EmptyState title="Ninguém neste filtro" /></Card> : (
          <Card className="overflow-hidden">
            <Tabela rotulo="Fila de espera" largura={1170} colunas="minmax(250px,1.6fr) 104px minmax(150px,1fr) 64px 104px 92px 96px minmax(150px,1fr) 58px">
              <TCabecalho>
                <span>Posição · criança</span><span>Faixa</span><span>Unidade pretendida</span><span className="text-right">Espera</span>
                {MEDIDAS.map((m) => {
                  const I = MEDIDA[m].icone;
                  return (
                    <span key={m} className={clsx('inline-flex items-center justify-end gap-1 whitespace-nowrap', crit?.medida === m && 'text-purple-800')} title={crit?.medida === m ? 'Medida usada pelo critério da fila' : undefined}>
                      <I className="size-3.5" style={{ color: MEDIDA[m].cor }} aria-hidden />{MEDIDA[m].rotulo}{crit?.medida === m && ' ★'}
                    </span>
                  );
                })}
                <span>Critérios</span><span className="text-right">Pontos</span>
              </TCabecalho>
              {(res.data.items as any[]).map((w) => (
                <TLinha key={w.id} to={`/fila/${w.id}`} rotulo={`${w.position ? `${w.position}º, ` : ''}${w.student}, ${w.unit}`}>
                  <TCelula fixa titulo={w.student}>
                    <span className={clsx('mr-2 inline-flex h-7 min-w-9 items-center justify-center rounded-xl px-1.5 align-middle font-display text-[13px] font-black tabular', w.position ? 'bg-purple-100 text-purple-800' : 'bg-slate-100 text-slate-500')}>{w.position ? `${w.position}º` : '—'}</span>
                    <Avatar name={w.student} seed={w.avatar_seed} size={24} className="mr-2 inline-flex align-middle" />
                    <span className="font-semibold">{w.student}</span>
                  </TCelula>
                  <TCelula className="text-muted">{w.grade}</TCelula>
                  <TCelula titulo={w.unit}>{w.unit}</TCelula>
                  <TCelula className="text-right tabular text-muted">{fmtInt(w.days_waiting)} d</TCelula>
                  {MEDIDAS.map((m) => {
                    const v = w.dist?.[CHAVE_DIST[m]] as number | null | undefined;
                    const eCrit = crit?.medida === m;
                    return (
                      <TCelula key={m} className={clsx('text-right tabular', eCrit ? 'font-semibold text-ink' : 'text-muted')}>
                        {v != null ? fmtKm(v) : '—'}
                        {eCrit && v != null && crit && (v <= crit.limite_m ? <Check className="ml-0.5 inline size-3.5 text-green-700" aria-label="até o limite" /> : <X className="ml-0.5 inline size-3.5 text-subtle" aria-label="acima do limite" />)}
                      </TCelula>
                    );
                  })}
                  <TCelula titulo={[QUEUE_CATEGORY[w.category]?.label, ...(w.flags ?? []).map((f: string) => FLAG[f]?.short ?? f)].filter(Boolean).join(' · ')}>
                    <span className="inline-flex gap-1">
                      {status !== 'WAITING' && <Badge tone={QUEUE_STATUS[w.status]?.tone}>{QUEUE_STATUS[w.status]?.label}</Badge>}
                      {(w.flags ?? []).map((f: string) => <Badge key={f} tone="purple">{FLAG[f]?.short}</Badge>)}
                      {!(w.flags ?? []).length && <span className="text-muted">{QUEUE_CATEGORY[w.category]?.short}</span>}
                    </span>
                  </TCelula>
                  <TCelula className="text-right font-display font-black tabular text-ink">{fmtInt(w.score)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
            <Paginacao pagina={page} total={res.data.total} porPagina={40} onPagina={(n) => set('pagina', String(n))} />
          </Card>
        )}
      </div>
    </div>
  );
}
