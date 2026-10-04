import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, Circle, FileCheck2, RefreshCw, ShieldCheck, Sparkles, Stethoscope } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt, fmtKm } from '@/lib/format';
import { OFFER_STATUS, QUEUE_CATEGORY, QUEUE_STATUS, SHIFT } from '@/lib/labels';
import { Avatar, Badge, Button, ButtonLink, Card, ErrorState, OccupancyBar, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { OfferSheet } from '@/components/OfferSheet';
import { useToast } from '@/components/overlays';

export default function QueueEntry() {
  const { id } = useParams();
  const res = useRpc<any>('queue_entry_detail', { entry_id: id });
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const [offer, setOffer] = useState(false);
  const [priority, setPriority] = useState(false);
  const [busy, setBusy] = useState(false);
  const [busyLaudo, setBusyLaudo] = useState(false);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const e = d.entry;
  const laudoItem = (e.breakdown as any[]).find((b) => b.code === 'PCD_TEA_AEE');
  const laudo: string | undefined = laudoItem?.laudo_status;
  const maxScore = (e.breakdown as any[]).reduce((a, b) => a + (b.analysis ? 0 : Number(b.weight) || 0), 0);
  const validateLaudo = async () => {
    setBusyLaudo(true);
    try {
      await rpc('document_set', { student_id: d.student.id, doc_type: 'LAUDO', status: 'VALIDADO' });
      toast({ title: 'Laudo validado', description: 'A prioridade sob análise pode ser decidida pela Central de Vagas.', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['queue_entry_detail'] });
    } catch (err) {
      toast({ title: 'Não foi possível validar', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusyLaudo(false);
    }
  };
  const recalc = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('queue_recalculate', { unit_id: d.unit.id, grade_level_id: e.grade_level_id });
      toast({ title: 'Fila recalculada', description: `${r.entries} criança(s) · ${r.changed} posição(ões) alterada(s) · regras ${r.rule_version}`, tone: 'success' });
      qc.invalidateQueries({ queryKey: ['queue_entry_detail'] });
    } catch (err) {
      toast({ title: 'Não foi possível recalcular', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <div>
      <Crumbs items={[{ label: 'Fila', to: '/fila' }, { label: d.unit.name, to: `/fila?unidade=${d.unit.id}` }, { label: d.student.name }]} />
      <PageHeader eyebrow={`${e.grade} · ${d.unit.name}`} title={d.student.name} subtitle={`${d.student.age} · entrou em ${fmtDateTime(e.entered_at)} · ${QUEUE_CATEGORY[e.category]?.label}`} />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1.2fr]">
        <Card className="overflow-hidden">
          <div className="bg-gradient-to-br from-purple-700 to-purple-900 p-5 text-white">
            <div className="text-[12px] font-bold uppercase tracking-wide text-purple-200">Posição atual</div>
            {e.position ? (
              <>
                <div className="font-display text-6xl font-black leading-none">{e.position}º</div>
                <div className="mt-1 text-[13px] text-purple-100">de {fmtInt(e.queue_size)} na fila de {e.grade} desta unidade</div>
              </>
            ) : (
              <>
                <div className="font-display text-4xl font-black leading-tight">{QUEUE_STATUS[e.status]?.label ?? e.status}</div>
                <div className="mt-1 text-[13px] text-purple-100">Saiu da contagem da fila de {e.grade} ({fmtInt(e.queue_size)} aguardando)</div>
              </>
            )}
            <div className="mt-3 flex flex-wrap gap-1.5">
              <Badge tone={QUEUE_STATUS[e.status]?.tone} solid>{QUEUE_STATUS[e.status]?.label}</Badge>
              <span className="rounded-full bg-white/15 px-2.5 py-0.5 text-xs font-semibold">Pontuação {fmtInt(e.score)} de {fmtInt(maxScore)}</span>
              <span className="rounded-full bg-white/15 px-2.5 py-0.5 text-xs font-semibold">Regras {e.rule_version}</span>
            </div>
          </div>
          <div className="p-4">
            <div className="mb-2 flex items-center justify-between text-[12px] font-bold uppercase tracking-wide text-subtle">Critérios aplicados <SourceChip kind="calculado" /></div>
            <ul className="space-y-2">
              {(e.breakdown as any[]).map((b) => (
                <li key={b.code} className={b.analysis && b.applied ? '-mx-2 flex items-start gap-2 rounded-2xl bg-purple-50 p-2 ring-1 ring-purple-100' : 'flex items-start gap-2'}>
                  {b.analysis ? (
                    <Stethoscope className={b.applied ? 'mt-0.5 size-5 shrink-0 text-purple-700' : 'mt-0.5 size-5 shrink-0 text-slate-300'} />
                  ) : b.applied ? <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-green-700" /> : <Circle className="mt-0.5 size-5 shrink-0 text-slate-300" />}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2 text-[14px] font-semibold">
                      <span className={b.applied ? '' : 'text-muted'}>{b.name}</span>
                      {b.analysis ? <Badge tone={b.applied ? 'purple' : 'gray'}>sob análise · fora da soma</Badge> : b.weight > 0 && <span className={b.applied ? 'text-green-700' : 'text-muted'}>+{b.weight}</span>}
                    </div>
                    <div className="text-[12.5px] text-muted">{b.evidence} · v{b.version}</div>
                  </div>
                </li>
              ))}
            </ul>
            <p className="mt-3 rounded-2xl bg-slate-50 p-3 text-[12.5px] text-muted"><ShieldCheck className="mr-1 inline size-4 text-purple-700" />Critérios da IN nº 025/2025-SEDUC, Anexo I. Empate: vale a data de entrada. Recalculada em {fmtDateTime(e.last_recalculated_at)}. O responsável vê exatamente estes critérios — nunca dados de outras crianças.</p>
          </div>
        </Card>
        <div className="space-y-4">
          <Card className="p-4">
            <div className="mb-3 flex items-center gap-3">
              <Avatar name={d.student.name} seed={d.student.avatar_seed} size={44} />
              <div className="min-w-0 flex-1"><Link to={`/alunos/${d.student.id}`} className="font-semibold hover:text-purple-700">{d.student.name}</Link><div className="text-[12.5px] text-muted">{d.student.address?.line ?? 'endereço restrito'} · {fmtKm(e.distance_m)} da unidade</div></div>
            </div>
            <div className="flex flex-wrap gap-2">
              {can('offers.create') && <Button variant="purple" icon={Sparkles} disabled={!d.can_offer_now} onClick={() => setOffer(true)}>{d.can_offer_now ? 'Ofertar vaga' : e.status === 'OFFERED' ? 'Oferta aguardando a família' : e.status === 'ACCEPTED' ? 'Aceita — aguardando matrícula' : e.status === 'MATRICULATED' ? 'Matrícula concluída' : e.position === 1 ? 'Sem vaga ofertável agora' : 'Oferta segue a ordem da fila'}</Button>}
              {can('offers.create') && d.can_offer_priority && (
                <Button variant="soft" icon={Stethoscope} disabled={laudo !== 'VALIDADO'} onClick={() => setPriority(true)}>
                  {laudo === 'VALIDADO' ? 'Ofertar por prioridade (laudo)' : 'Prioridade exige laudo validado'}
                </Button>
              )}
              {can('documents.manage') && laudoItem?.applied && laudo === 'RECEBIDO' && (
                <Button variant="secondary" icon={FileCheck2} loading={busyLaudo} onClick={validateLaudo}>Validar laudo</Button>
              )}
              {can('queue.recalculate') && <Button variant="secondary" icon={RefreshCw} loading={busy} onClick={recalc}>Recalcular fila</Button>}
              {e.case_id && <ButtonLink to={`/atendimentos/${e.case_id}`} variant="ghost">Protocolo de origem</ButtonLink>}
            </div>
            <p className="mt-2 text-[12px] text-muted">Preferência de turno: {e.shift ? SHIFT[e.shift] : 'indiferente'}{e.full_time ? ' · pede período integral' : ''}</p>
          </Card>
          <Section title="Turmas desta faixa na unidade" className="mt-0">
            <div className="space-y-2">
              {(d.classes as any[]).map((c) => (
                <Link key={c.id} to={`/turmas/${c.id}`} className="block rounded-2xl bg-white p-3 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
                  <div className="mb-1.5 flex justify-between text-[13.5px]"><span className="font-semibold">{c.name} · {SHIFT[c.shift]}</span><span className={c.offerable > 0 ? 'font-bold text-green-700' : 'text-muted'}>{c.offerable} ofertável(is)</span></div>
                  <OccupancyBar capacity={c.capacity} enrolled={c.enrolled} reserved={c.reserved} blocked={c.blocked} offerable={c.offerable} />
                </Link>
              ))}
            </div>
          </Section>
          {(d.offers as any[]).length > 0 && (
            <Section title="Histórico de ofertas" className="mt-0">
              <Card className="divide-y divide-line">
                {(d.offers as any[]).map((o) => (
                  <div key={o.id} className="flex items-center justify-between px-4 py-3 text-[14px]">
                    <span>{o.class} · {fmtDate(o.offered_at)}{o.decline_reason ? ` · ${o.decline_reason}` : ''}</span>
                    <Badge tone={OFFER_STATUS[o.status]?.tone}>{OFFER_STATUS[o.status]?.label}</Badge>
                  </div>
                ))}
              </Card>
            </Section>
          )}
        </div>
      </div>
      <OfferSheet open={offer} entryId={e.id} onClose={() => setOffer(false)} onDone={() => qc.invalidateQueries({ queryKey: ['queue_entry_detail'] })} />
      <OfferSheet open={priority} priority entryId={e.id} onClose={() => setPriority(false)} onDone={() => qc.invalidateQueries({ queryKey: ['queue_entry_detail'] })} />
    </div>
  );
}
