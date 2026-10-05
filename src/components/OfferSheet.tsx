import { useEffect, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Simulado } from '@/components/ui';
import { CheckCircle2, Clock, ShieldCheck, Sparkles, Stethoscope } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { FLAG, SHIFT } from '@/lib/labels';
import { fmtInt } from '@/lib/format';
import { Sheet, useToast } from './overlays';
import { Avatar, Badge, Button, OccupancyBar, Spinner } from './ui';

/**
 * Registro de oferta de vaga (transacional): revalida a vaga e a ordem da fila no servidor,
 * usa chave de idempotência e só confirma após a resposta do backend.
 */
export function OfferSheet({ entryId, open, onClose, onDone, priority }: {
  entryId: string | null; open: boolean; onClose: () => void; onDone?: () => void;
  /** Oferta fora da ordem por prioridade sob análise (laudo PCD/TEA/TGD/AH-SD — IN nº 025/2025, Anexo I). */
  priority?: boolean;
}) {
  const detail = useRpc<any>('queue_entry_detail', { entry_id: entryId }, { enabled: open && !!entryId });
  const qc = useQueryClient();
  const toast = useToast();
  const [classId, setClassId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [reason, setReason] = useState('');
  const idem = useMemo(() => (open ? crypto.randomUUID() : ''), [open]);

  const d = detail.data;
  const classes = (d?.classes ?? []) as any[];
  useEffect(() => {
    if (!open) {
      setResult(null);
      setClassId(null);
      setReason('');
    } else if (classes.length && !classId) {
      setClassId(classes.find((c) => c.offerable > 0)?.id ?? null);
    }
  }, [open, classes, classId]);

  const submit = async () => {
    if (!entryId || !classId) return;
    setBusy(true);
    try {
      const r = await rpc('offer_create', { entry_id: entryId, class_id: classId, idempotency_key: idem, ...(priority ? { priority_reason: reason.trim() } : {}) });
      setResult(r);
      ['dashboard_analista', 'queue_list', 'queue_entry_detail', 'class_detail', 'unit_classes', 'dashboard_unidade', 'offers_list', 'units_map', 'student_detail', 'case_detail', 'network_kpis', 'dashboard_secretario']
        .forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
      toast({ title: 'Oferta registrada', description: r.message, tone: 'success' });
      onDone?.();
    } catch (e) {
      toast({ title: 'Oferta não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  const applied = ((d?.entry?.breakdown ?? []) as any[]).filter((b) => b.applied && b.weight > 0);
  const analysis = ((d?.entry?.breakdown ?? []) as any[]).find((b) => b.applied && b.analysis);
  const allowed = priority ? !!d?.can_offer_priority && reason.trim().length >= 20 : !!d?.can_offer_now;
  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={result ? 'Oferta registrada ✅' : priority ? 'Ofertar por prioridade sob análise' : 'Ofertar vaga'}
      subtitle={result ? undefined : priority
        ? 'IN nº 025/2025, Anexo I: PCD/TEA/TGD/AH-SD com laudo — fora da ordem de pontuação, com justificativa auditada.'
        : 'A oferta segue a ordem da fila e reserva a vaga por 72 horas (IN nº 025/2025, Anexo II).'}
      footer={
        result ? (
          <Button block onClick={onClose} variant="secondary">Fechar</Button>
        ) : (
          <Button block size="lg" variant="purple" icon={Sparkles} loading={busy} disabled={!allowed || !classId} onClick={submit}>
            Registrar oferta
          </Button>
        )
      }
    >
      {detail.isLoading || !d ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : result ? (
        <div className="space-y-3 pt-2">
          <div className="flex items-start gap-3 rounded-3xl bg-green-50 p-4 ring-1 ring-green-200">
            <CheckCircle2 className="mt-0.5 size-6 text-green-700" />
            <div className="text-[14.5px] text-green-900">
              <b>{d.student.name}</b> recebeu a oferta. A família foi notificada<Simulado detail="Aviso simulado: nenhuma mensagem real é enviada." /> e tem até{' '}
              <b>{new Date(result.expires_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}</b> para responder.
            </div>
          </div>
          <p className="text-[13px] text-muted">Vaga reservada: a turma passa a ter {fmtInt(result.class_after?.reserved)} reserva(s) e {fmtInt(result.class_after?.offerable)} vaga(s) ofertável(is). Tudo registrado na auditoria.</p>
        </div>
      ) : (
        <div className="space-y-4 pt-1">
          <div className="flex items-center gap-3 rounded-3xl bg-purple-50 p-3 ring-1 ring-purple-100">
            <Avatar name={d.student.name} seed={d.student.avatar_seed} size={48} />
            <div className="min-w-0 flex-1">
              <div className="truncate font-display text-[17px] font-extrabold">{d.student.name}</div>
              <div className="text-[13px] text-muted">{d.student.age} · {d.entry.grade} · {d.unit.name}</div>
            </div>
            <Badge tone={d.entry.position === 1 ? 'green' : 'amber'}>{d.entry.position ? `${d.entry.position}º da fila` : d.entry.status}</Badge>
          </div>

          <div>
            <div className="mb-1.5 text-[12px] font-bold uppercase tracking-wide text-subtle">Critérios aplicados · regras {d.entry.rule_version}</div>
            <div className="flex flex-wrap gap-1.5">
              {applied.length ? applied.map((b) => <Badge key={b.code} tone="purple" icon={ShieldCheck}>{FLAG[b.code === 'TERRITORIO_2KM' ? 'TERRITORIO' : b.code]?.short ?? b.name} +{b.weight}</Badge>) : <span className="text-[13px] text-muted">Nenhum critério de prioridade — ordem por data de entrada.</span>}
              {analysis && <Badge tone="purple" icon={Stethoscope}>Laudo · prioridade sob análise</Badge>}
              <Badge tone="gray">Pontuação {fmtInt(d.entry.score)}</Badge>
            </div>
          </div>

          {priority && (
            <div className="space-y-2 rounded-2xl bg-purple-50 p-3 ring-1 ring-purple-100">
              <p className="text-[13.5px] text-purple-950">
                {d.entry.position > 1 ? `Há ${d.entry.position - 1} criança(s) à frente pela pontuação. ` : ''}
                A prioridade por laudo não soma pontos: ela é decidida pela equipe, com o laudo validado. Registre a análise — o texto vai para a auditoria.
              </p>
              <textarea
                value={reason}
                onChange={(ev) => setReason(ev.target.value)}
                rows={3}
                maxLength={600}
                placeholder="Ex.: laudo com CID validado; equipe de inclusão recomenda atendimento imediato nesta unidade."
                aria-label="Justificativa da prioridade sob análise"
                className="w-full rounded-2xl bg-white p-3 text-[14px] ring-1 ring-purple-200 outline-none focus:ring-2 focus:ring-purple-500"
              />
              <div className="text-right text-[11.5px] text-muted">{reason.trim().length}/20 caracteres mínimos</div>
            </div>
          )}

          {!priority && !d.can_offer_now && (
            <div className="rounded-2xl bg-amber-50 p-3 text-[13.5px] text-amber-900 ring-1 ring-amber-200">
              {d.entry.position > 1
                ? `Há ${d.entry.position - 1} criança(s) à frente na fila desta unidade/faixa. A oferta deve seguir a ordem de classificação.`
                : 'Não há vaga ofertável nas turmas desta faixa agora.'}
            </div>
          )}

          <div>
            <div className="mb-1.5 text-[12px] font-bold uppercase tracking-wide text-subtle">Escolha a turma</div>
            <div className="space-y-2">
              {classes.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  disabled={c.offerable < 1}
                  onClick={() => setClassId(c.id)}
                  className={clsx('w-full rounded-2xl p-3 text-left ring-1 transition disabled:opacity-50', classId === c.id ? 'bg-purple-50 ring-2 ring-purple-500' : 'bg-white ring-line hover:bg-slate-50')}
                >
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <span className="font-semibold">{c.name} · {SHIFT[c.shift] ?? c.shift}</span>
                    <Badge tone={c.offerable > 0 ? 'green' : 'gray'}>{c.offerable} ofertável(is)</Badge>
                  </div>
                  <OccupancyBar capacity={c.capacity} enrolled={c.enrolled} reserved={c.reserved} blocked={c.blocked} offerable={c.offerable} />
                </button>
              ))}
            </div>
          </div>
          <div className="flex items-center gap-2 rounded-2xl bg-slate-50 p-3 text-[13px] text-muted">
            <Clock className="size-4 shrink-0" /> Prazo: 72 h desde a oferta para efetivar a matrícula (IN nº 025/2025, Anexo II). Aceite não é matrícula: a unidade confirma depois de validar os documentos.
          </div>
        </div>
      )}
    </Sheet>
  );
}
