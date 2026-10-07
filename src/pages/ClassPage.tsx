import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { Ban, Calculator, CalendarCheck, Clock, Lock, NotebookPen, Sparkles, Unlock, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt, timeAgo, timeLeft } from '@/lib/format';
import { BLOCK_REASON, FLAG, OFFER_STATUS, QUEUE_CATEGORY, SHIFT, VACANCY_EVENT } from '@/lib/labels';
import {
  Avatar, Badge, Button, ButtonLink, Card, EmptyState, ErrorState, Field, ListRow, OccupancyBar, PageHeader, Section, SkeletonList, SourceChip, inputCls,
} from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { OfferSheet } from '@/components/OfferSheet';
import { GradeHorario } from '@/components/escola';

export default function ClassPage() {
  const { id } = useParams();
  const res = useRpc<any>('class_detail', { class_id: id });
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [blockOpen, setBlockOpen] = useState(false);
  const [offerEntry, setOfferEntry] = useState<string | null>(null);

  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const c = d.class;
  const k = d.kpis;
  const refresh = () => ['class_detail', 'unit_classes', 'dashboard_unidade', 'unit_detail', 'units_map'].forEach((x) => qc.invalidateQueries({ queryKey: [x] }));

  const unblock = async (b: any) => {
    const ok = await confirm({ title: 'Liberar vaga bloqueada?', body: `${b.seats} vaga(s) voltam a ser ofertáveis. Motivo original: ${BLOCK_REASON[b.reason]}.`, confirm: 'Liberar', tone: 'success' });
    if (!ok) return;
    try {
      await rpc('vacancy_unblock', { block_id: b.id });
      toast({ title: 'Vaga liberada', description: 'Registrado na movimentação de vagas e na auditoria.', tone: 'success' });
      refresh();
    } catch (e) {
      toast({ title: 'Não foi possível liberar', description: (e as Error).message, tone: 'error' });
    }
  };

  return (
    <div>
      <Crumbs items={[{ label: 'Mapa', to: '/mapa' }, { label: d.unit.short_name, to: `/unidades/${d.unit.id}` }, { label: c.stage, to: `/unidades/${d.unit.id}?aba=turmas` }, { label: c.grade, to: `/unidades/${d.unit.id}?aba=turmas&serie=${c.grade_level_id}` }, { label: c.name }]} />
      <PageHeader
        eyebrow={`${d.unit.name} · ${c.stage}`}
        title={c.name}
        subtitle={`${c.grade} · turno ${SHIFT[c.shift]?.toLowerCase()} · ${c.room} · ano letivo ${c.school_year}`}
        actions={<>
          {can('frequencia.read') && <ButtonLink to={`/turmas/${c.id}/chamada`} variant="success" icon={CalendarCheck}>Chamada</ButtonLink>}
          {can('ocorrencias.read') && <ButtonLink to={`/turmas/${c.id}/diario`} variant="secondary" icon={NotebookPen}>Agenda e ocorrências</ButtonLink>}
          {can('vacancy.block') && <Button variant="secondary" icon={Ban} onClick={() => setBlockOpen(true)} disabled={k.offerable < 1}>Bloquear vaga</Button>}
        </>}
      />

      <Card className="p-4">
        <div className="mb-3 flex items-center justify-between">
          <div className="flex items-center gap-2 text-[13px] font-bold uppercase tracking-wide text-subtle"><Calculator className="size-4" />Vagas desta turma</div>
          <SourceChip kind="demo" detail={c.source} />
        </div>
        <div className="grid grid-cols-3 gap-2 text-center sm:grid-cols-7">
          {[
            ['Capacidade', k.capacity, 'text-ink'], ['Matriculados', k.enrolled, 'text-blue-800'], ['Vagas físicas', k.physical, 'text-ink'],
            ['Bloqueadas', k.blocked, 'text-amber-700'], ['Reservadas', k.reserved, 'text-purple-700'], ['Ofertáveis', k.offerable, 'text-green-700'], ['Fila vinculada', k.queue, 'text-red-700'],
          ].map(([l, v, cls]) => (
            <div key={l as string} className="rounded-2xl bg-slate-50 p-2.5 ring-1 ring-line">
              <div className={`font-display text-2xl font-black tabular ${cls}`}>{fmtInt(v as number)}</div>
              <div className="text-[11px] font-semibold text-muted">{l}</div>
            </div>
          ))}
        </div>
        <div className="mt-4"><OccupancyBar capacity={k.capacity} enrolled={k.enrolled} reserved={k.reserved} blocked={k.blocked} offerable={k.offerable} showLegend height={12} /></div>
        <p className="mt-3 rounded-2xl bg-teal-50 p-2.5 text-[12.5px] text-teal-900">{k.formula}. Nunca calculada por média histórica.</p>
      </Card>

      <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
        {(d.staff as any[]).map((s) => (
          <Card key={s.name} className="flex items-center gap-3 p-3">
            <Avatar name={s.name} seed={s.name} size={40} />
            <div className="min-w-0 flex-1">
              <div className="truncate font-semibold">{s.name}</div>
              <div className="text-[12.5px] text-muted">{s.role === 'REGENTE' ? (s.staff_role === 'EDUCADOR' ? 'Educador(a) regente' : 'Professor(a) regente') : 'Auxiliar'} · {s.bond} · {s.hours}h/sem</div>
            </div>
          </Card>
        ))}
      </div>

      <HorarioTurma classId={c.id} />

      <Section title={`Alunos (${fmtInt(k.enrolled)})`} subtitle="Toque para abrir a ficha 360º" action={<SourceChip kind="demo" detail="Nomes e dados pessoais fictícios." />}>
        {d.students_visible ? (
          <Card className="divide-y divide-line overflow-hidden">
            {(d.students as any[]).map((s) => (
              <ListRow key={s.id} to={`/alunos/${s.id}`} leading={<Avatar name={s.name} seed={s.avatar_seed} />} title={s.name}
                subtitle={`${s.age} · resp.: ${s.guardian ?? '—'} · ${s.contact ?? ''}`}
                meta={<span className="flex gap-1">{s.aee && <Badge tone="purple">AEE</Badge>}{s.transport && <Badge tone="blue">Transporte</Badge>}</span>} />
            ))}
          </Card>
        ) : (
          <Card className="flex items-start gap-3 p-4">
            <Lock className="mt-0.5 size-5 text-slate-500" />
            <p className="text-[14px] text-muted">Seu perfil vê apenas números agregados desta turma ({fmtInt(k.enrolled)} matrículas). Dados pessoais de alunos ficam restritos às equipes autorizadas.</p>
          </Card>
        )}
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Fila vinculada (série na unidade)" subtitle="Ordem pelas regras vigentes">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.queue_top as any[]).length ? (d.queue_top as any[]).map((w) => (
              <div key={w.entry_id} className="flex items-center gap-3 px-4 py-3">
                <span className="inline-flex size-9 shrink-0 items-center justify-center rounded-xl bg-purple-100 font-display font-black text-purple-800">{w.position}º</span>
                <Link to={`/fila/${w.entry_id}`} className="min-w-0 flex-1">
                  <div className="truncate font-semibold hover:text-purple-700">{w.student}</div>
                  <div className="truncate text-[12px] text-muted">{QUEUE_CATEGORY[w.category]?.short} · {(w.flags ?? []).map((f: string) => FLAG[f]?.short).join(', ') || 'sem critérios'} · {fmtDate(w.entered_at)}</div>
                </Link>
                {w.position === 1 && k.offerable > 0 && can('offers.create') && (
                  <Button size="sm" variant="purple" icon={Sparkles} onClick={() => setOfferEntry(w.entry_id)}>Ofertar</Button>
                )}
              </div>
            )) : <EmptyState compact title="Ninguém aguardando esta série" />}
          </Card>
        </Section>
        <Section title="Vagas bloqueadas e ofertas">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.blocks as any[]).map((b) => (
              <div key={b.id} className="flex items-start gap-3 px-4 py-3">
                <Ban className="mt-0.5 size-5 text-amber-600" />
                <div className="min-w-0 flex-1">
                  <div className="font-semibold">{b.seats} vaga(s) · {BLOCK_REASON[b.reason]}</div>
                  <div className="text-[12.5px] text-muted">{b.justification}{b.valid_until ? ` · até ${fmtDate(b.valid_until)}` : ''}</div>
                </div>
                {can('vacancy.block') && <Button size="sm" variant="secondary" icon={Unlock} onClick={() => unblock(b)}>Liberar</Button>}
              </div>
            ))}
            {(d.offers as any[]).map((o) => (
              <Link key={o.id} to={`/alunos/${o.student_id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <Clock className="size-5 text-purple-600" />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{o.student}</div>
                  <div className="text-[12.5px] text-muted">{OFFER_STATUS[o.status]?.label}{o.status === 'OFFERED' ? ` · ${timeLeft(o.expires_at)}` : ''}</div>
                </div>
                <Badge tone={OFFER_STATUS[o.status]?.tone}>reserva</Badge>
              </Link>
            ))}
            {!d.blocks.length && !d.offers.length && <p className="p-4 text-sm text-muted">Nenhum bloqueio ou reserva ativa.</p>}
          </Card>
        </Section>
      </div>

      <Section title="Movimentação de vagas" subtitle="Cada evento registra antes e depois">
        <Card className="divide-y divide-line overflow-hidden">
          {(d.events as any[]).map((e, i) => (
            <div key={i} className="px-4 py-3">
              <div className="flex items-center justify-between gap-2">
                <span className="font-semibold">{VACANCY_EVENT[e.type] ?? e.type}</span>
                <span className="text-[12px] text-muted">{timeAgo(e.at)}</span>
              </div>
              <div className="text-[12.5px] text-muted">{e.reference} · {e.actor}</div>
              {e.before && e.after && (
                <div className="mt-1 text-[12px] text-ink-2">Ofertáveis: <b>{e.before.offerable}</b> → <b>{e.after.offerable}</b> · matrículas {e.before.enrolled} → {e.after.enrolled} · reservas {e.before.reserved} → {e.after.reserved}</div>
              )}
            </div>
          ))}
          {!d.events.length && <p className="p-4 text-sm text-muted">Sem movimentações registradas.</p>}
        </Card>
      </Section>

      <BlockSheet open={blockOpen} onClose={() => setBlockOpen(false)} classId={c.id} max={k.offerable} onDone={refresh} />
      <OfferSheet open={!!offerEntry} entryId={offerEntry} onClose={() => setOfferEntry(null)} onDone={refresh} />
      <p className="mt-6 text-center text-[12px] text-muted"><Users className="mr-1 inline size-3.5" />Estrutura de turmas: Censo 2025 · divisão por turma e capacidade: demonstração.</p>
    </div>
  );
}

function BlockSheet({ open, onClose, classId, max, onDone }: { open: boolean; onClose: () => void; classId: string; max: number; onDone: () => void }) {
  const toast = useToast();
  const [seats, setSeats] = useState(1);
  const [reason, setReason] = useState('INCLUSAO');
  const [just, setJust] = useState('');
  const [until, setUntil] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    setBusy(true);
    try {
      await rpc('vacancy_block', { class_id: classId, seats, reason, justification: just, valid_until: until || null });
      toast({ title: 'Vaga bloqueada', description: 'Motivo e justificativa registrados na auditoria.', tone: 'success' });
      onDone();
      onClose();
      setJust('');
    } catch (e) {
      toast({ title: 'Bloqueio não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Bloquear vaga" subtitle="Motivo obrigatório. A vaga continua física, mas deixa de ser ofertável." footer={<Button block size="lg" loading={busy} disabled={just.trim().length < 10} onClick={submit} icon={Ban}>Registrar bloqueio</Button>}>
      <div className="space-y-4 pt-1">
        <Field label={`Quantidade (máximo ${max})`}>
          <input type="number" min={1} max={max} value={seats} onChange={(e) => setSeats(Math.max(1, Math.min(max, Number(e.target.value) || 1)))} className={inputCls} />
        </Field>
        <Field label="Motivo">
          <select value={reason} onChange={(e) => setReason(e.target.value)} className={inputCls}>
            {Object.entries(BLOCK_REASON).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
        <Field label="Justificativa" hint="Mínimo de 10 caracteres. Evite dados pessoais sensíveis.">
          <textarea value={just} onChange={(e) => setJust(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} />
        </Field>
        <Field label="Válido até (opcional)">
          <input type="date" value={until} onChange={(e) => setUntil(e.target.value)} className={inputCls} />
        </Field>
      </div>
    </Sheet>
  );
}

/** Grade da turma: componente e professor de cada aula; aula sem professor fica em vermelho. */
function HorarioTurma({ classId }: { classId: string }) {
  const res = useRpc<any>('turma_horario', { class_id: classId });
  if (res.isLoading || res.error || !(res.data?.aulas ?? []).length) return null;
  const semProf = (res.data.aulas as any[]).filter((a) => a.sem_professor).length;
  return (
    <Section title="Horário da turma" subtitle={semProf ? `${semProf} aula(s) ainda sem professor` : 'Todas as aulas com professor'}>
      <Card className="p-3">
        <GradeHorario aulas={res.data.aulas} rotulo="Horário da turma"
          celula={(a) => ({ titulo: a.componente, sub: a.professor ?? 'Sem professor', alerta: a.sem_professor })} />
      </Card>
    </Section>
  );
}
