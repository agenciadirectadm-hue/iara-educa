import { useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { CheckCircle2, Circle, Clock, FileCheck2, PartyPopper } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useSession } from '@/lib/session';
import { DOC, DOC_STATUS, OFFER_STATUS, SHIFT } from '@/lib/labels';
import { timeLeft } from '@/lib/format';
import { useConfirm, useToast } from './overlays';
import { Avatar, Badge, Button, Card } from './ui';

/** "O que falta para concluir esta matrícula?" — checklist de documentos + confirmação transacional. */
export function EnrollmentCard({ item }: { item: any }) {
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [busyDoc, setBusyDoc] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const docs = (item.documents ?? []) as { type: string; status: string }[];
  const missing = docs.filter((d) => d.status !== 'VALIDADO');
  const accepted = item.status === 'ACCEPTED';
  const refresh = () => ['dashboard_unidade', 'offers_list', 'student_detail', 'class_detail', 'unit_classes', 'units_map'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));

  const setDoc = async (type: string) => {
    setBusyDoc(type);
    try {
      await rpc('document_set', { student_id: item.student_id, doc_type: type, status: 'VALIDADO' });
      toast({ title: `${DOC[type] ?? type} validado`, tone: 'success' });
      refresh();
    } catch (e) {
      toast({ title: 'Não foi possível validar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusyDoc(null);
    }
  };

  const enroll = async () => {
    const ok = await confirm({
      title: 'Confirmar matrícula?',
      body: <>A matrícula de <b>{item.student}</b> em <b>{item.class}</b> será efetivada. A vaga reservada passa a ser ocupada e a família é notificada.</>,
      confirm: 'Confirmar matrícula',
      tone: 'success',
    });
    if (!ok) return;
    setBusy(true);
    try {
      const r = await rpc<any>('enrollment_confirm', { offer_id: item.offer_id });
      if (r.ok === false) {
        toast({ title: 'Matrícula pendente', description: r.message, tone: 'warning' });
      } else {
        toast({ title: 'Matrícula confirmada! 🎉', description: r.message, tone: 'success' });
      }
      refresh();
    } catch (e) {
      toast({ title: 'Matrícula não confirmada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card className="p-4">
      <div className="flex items-start gap-3">
        <Avatar name={item.student} seed={item.avatar_seed} size={44} />
        <div className="min-w-0 flex-1">
          <Link to={`/alunos/${item.student_id}`} className="block truncate font-semibold hover:text-purple-700">{item.student}</Link>
          <div className="text-[12.5px] text-muted">{item.unit ? `${item.unit} · ` : ''}{item.class} · {SHIFT[item.shift] ?? item.shift}</div>
          <Badge className="mt-1" tone={OFFER_STATUS[item.status]?.tone ?? 'gray'}>{OFFER_STATUS[item.status]?.label ?? item.status}</Badge>
        </div>
      </div>

      {!accepted ? (
        <div className="mt-3 flex items-center gap-2 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-900">
          <Clock className="size-4 shrink-0" /> Aguardando resposta da família · prazo: {timeLeft(item.expires_at)}
        </div>
      ) : (
        <>
          <div className="mt-3 text-[12px] font-bold uppercase tracking-wide text-subtle">
            {missing.length ? `Faltam ${missing.length} documento(s) validado(s)` : 'Documentação completa'}
          </div>
          <ul className="mt-2 space-y-1.5">
            {docs.map((d) => {
              const ok = d.status === 'VALIDADO';
              return (
                <li key={d.type} className={clsx('flex items-center gap-2 rounded-2xl px-3 py-2 ring-1', ok ? 'bg-green-50 ring-green-100' : 'bg-white ring-line')}>
                  {ok ? <CheckCircle2 className="size-5 text-green-700" /> : <Circle className="size-5 text-subtle" />}
                  <span className="flex-1 text-[14px] font-medium">{DOC[d.type] ?? d.type}</span>
                  {!ok && <Badge tone={DOC_STATUS[d.status]?.tone ?? 'gray'}>{DOC_STATUS[d.status]?.label ?? d.status}</Badge>}
                  {!ok && can('documents.manage') && (
                    <Button size="sm" variant="secondary" icon={FileCheck2} loading={busyDoc === d.type} onClick={() => setDoc(d.type)}>
                      Validar
                    </Button>
                  )}
                </li>
              );
            })}
          </ul>
          {can('enrollment.confirm') && (
            <Button className="mt-3" block size="lg" variant="success" icon={PartyPopper} loading={busy} disabled={missing.length > 0} onClick={enroll}>
              {missing.length ? 'Valide os documentos para matricular' : 'Confirmar matrícula'}
            </Button>
          )}
        </>
      )}
    </Card>
  );
}
