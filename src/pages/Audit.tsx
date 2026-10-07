import { useState } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import {
  BadgeCheck, ChevronDown, ClipboardCheck, Database, FileDown, Flag, Lock, LogIn, PartyPopper, RefreshCw, RotateCcw, Sparkles, ThumbsDown, ThumbsUp, TimerOff,
} from 'lucide-react';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDateTime, fmtInt, timeAgo } from '@/lib/format';
import { AUDIT_ACTION, ENTITY } from '@/lib/labels';
import { Badge, Card, Chip, EmptyState, ErrorState, PageHeader, SkeletonList } from '@/components/ui';

const ICON: Record<string, typeof Lock> = {
  OFFER_CREATED: Sparkles, OFFER_ACCEPTED: ThumbsUp, OFFER_DECLINED: ThumbsDown, OFFER_EXPIRED: TimerOff, ENROLLMENT_CONFIRMED: PartyPopper,
  CASE_CREATED: ClipboardCheck, QUEUE_RECALCULATED: RefreshCw, PRIORITY_FLAG: Flag, EXPORT: FileDown, LOGIN_DEMO: LogIn, DEMO_RESET: RotateCcw,
  DEMO_SEED: Database, DEMO_TIMESHIFT: RefreshCw,
};

function entityLink(type: string, id: string | null): string | null {
  if (!id) return null;
  switch (type) {
    case 'students': return `/alunos/${id}`;
    case 'service_cases': return `/atendimentos/${id}`;
    case 'waiting_list_entries': return `/fila/${id}`;
    case 'conversations': return `/conversas/${id}`;
    case 'guardians': return `/responsaveis/${id}`;
    case 'classes': return `/turmas/${id}`;
    default: return null;
  }
}

export default function Audit() {
  const { me } = useSession();
  const now = useNow(60_000);
  const [business, setBusiness] = useState(true);
  const [entity, setEntity] = useState<string>('');
  const [page, setPage] = useState(1);
  const unitId = me?.scope === 'UNIT' ? me.unit?.id : null;
  const res = useRpc<any>('audit_list', { business_only: business, entity_type: entity || null, unit_id: unitId, page });
  // corrente de hashes recalculada no servidor: qualquer alteração ou remoção na trilha aparece aqui
  const integ = useRpc<{ integra: boolean; verificados: number; primeira_quebra?: { seq: number; motivo: string } }>('auditoria_integridade', {}, { staleTime: 5 * 60_000 });
  return (
    <div>
      <PageHeader
        eyebrow="Transparência e controle"
        title="Trilha de auditoria"
        subtitle="Quem fez o quê, quando e por quê. O registro é imutável: não pode ser editado nem apagado — nem por administradores."
      />
      {integ.data && (
        <div className={clsx('mb-3 flex items-start gap-2 rounded-2xl px-3 py-2 text-[13px] ring-1', integ.data.integra ? 'bg-green-50 text-green-900 ring-green-100' : 'bg-red-50 text-red-900 ring-red-100')}>
          <Lock className="mt-0.5 size-4 shrink-0" />
          <span>
            {integ.data.integra
              ? <>Trilha íntegra: <b>{fmtInt(integ.data.verificados)}</b> registros conferidos agora pela corrente de hashes (cada registro carrega o hash do anterior).</>
              : <>Trilha com quebra no registro <b>{integ.data.primeira_quebra?.seq}</b>: {integ.data.primeira_quebra?.motivo}. Acione a equipe de segurança.</>}
          </span>
        </div>
      )}
      <Card className="mb-4 flex items-start gap-3 bg-gradient-to-br from-blue-50 to-purple-50 p-4 ring-1 ring-blue-100">
        <Lock className="mt-0.5 size-5 shrink-0 text-blue-800" />
        <p className="text-[13.5px] text-ink-2">
          Cada oferta, aceite, matrícula, recálculo de fila, critério de prioridade, exportação e alteração de dado pessoal gera um evento com antes/depois.
          Consultas a dados sensíveis também são registradas. {unitId ? 'Você vê os eventos da sua unidade.' : ''}
        </p>
      </Card>
      <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 pb-1">
        <Chip active={business} onClick={() => { setBusiness(true); setPage(1); }} icon={BadgeCheck}>Eventos de negócio</Chip>
        <Chip active={!business} onClick={() => { setBusiness(false); setPage(1); }}>Tudo (inclui alterações de registro)</Chip>
      </div>
      <div className="no-scrollbar -mx-4 mt-1 flex gap-2 overflow-x-auto px-4 pb-1">
        <Chip active={!entity} onClick={() => { setEntity(''); setPage(1); }}>Todas as entidades</Chip>
        {['vacancy_offers', 'enrollments', 'waiting_list_entries', 'service_cases', 'students', 'documents', 'conversations', 'report', 'app_user', 'demo'].map((e) => (
          <Chip key={e} active={entity === e} onClick={() => { setEntity(entity === e ? '' : e); setPage(1); }}>{ENTITY[e] ?? e}</Chip>
        ))}
      </div>
      <div className="mt-2 text-[13px] text-muted">{res.data ? `${fmtInt(res.data.total)} evento(s)` : ''}</div>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : !res.data.items.length ? (
          <Card><EmptyState title="Nenhum evento neste filtro" body="Faça uma oferta, aceite ou matrícula no cenário de demonstração e volte aqui." /></Card>
        ) : (
          <ol className="relative space-y-2 before:absolute before:bottom-2 before:left-[21px] before:top-2 before:w-0.5 before:bg-line">
            {(res.data.items as any[]).map((a) => <AuditRow key={a.id} a={a} now={now} />)}
          </ol>
        )}
        {res.data && res.data.total > 50 && (
          <div className="mt-4 flex items-center justify-center gap-2">
            <button disabled={page <= 1} onClick={() => setPage(page - 1)} className="h-10 rounded-xl bg-white px-4 text-sm font-semibold ring-1 ring-line disabled:opacity-40">Anteriores</button>
            <span className="text-sm text-muted">Página {page}</span>
            <button disabled={page * 50 >= res.data.total} onClick={() => setPage(page + 1)} className="h-10 rounded-xl bg-white px-4 text-sm font-semibold ring-1 ring-line disabled:opacity-40">Mais antigos</button>
          </div>
        )}
      </div>
    </div>
  );
}

function AuditRow({ a, now }: { a: any; now: number }) {
  const [open, setOpen] = useState(false);
  const I = ICON[a.action] ?? Database;
  const link = entityLink(a.entity_type, a.entity_id);
  const diff = changed(a.before, a.after);
  const business = !['INSERT', 'UPDATE', 'DELETE'].includes(a.action);
  return (
    <li className="relative pl-12">
      <span className={clsx('absolute left-1 top-3 inline-flex size-9 items-center justify-center rounded-2xl ring-4 ring-canvas', business ? 'bg-purple-700 text-white' : 'bg-white text-slate-600 ring-1')}>
        <I className="size-4" />
      </span>
      <Card className="overflow-hidden">
        <button onClick={() => setOpen(!open)} className="w-full px-4 py-3 text-left hover:bg-slate-50" aria-expanded={open}>
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="font-semibold">{AUDIT_ACTION[a.action] ?? a.action} <span className="font-normal text-muted">· {ENTITY[a.entity_type] ?? a.entity_type}</span></div>
              {a.summary && <div className="mt-0.5 text-[13.5px] text-ink-2">{a.summary}</div>}
              <div className="mt-1 text-[12px] text-muted">{a.actor ?? 'Sistema'}{a.role ? ` · ${a.role}` : ''} · {fmtDateTime(a.at)} ({timeAgo(a.at, now)})</div>
            </div>
            <ChevronDown className={clsx('mt-1 size-4 shrink-0 text-subtle transition', open && 'rotate-180')} />
          </div>
        </button>
        {open && (
          <div className="space-y-2 border-t border-line bg-slate-50 p-3 text-[12px]">
            <div className="flex flex-wrap gap-2">
              <Badge tone="gray">id {a.id}</Badge>
              {a.request_id && <Badge tone="gray">requisição {String(a.request_id).slice(0, 8)}</Badge>}
              {link && <Link to={link} className="font-semibold text-blue-700 underline">Abrir registro</Link>}
            </div>
            {diff.length > 0 ? (
              <table className="w-full overflow-hidden rounded-xl bg-white text-left ring-1 ring-line">
                <thead className="bg-slate-100 text-[11px] uppercase text-subtle"><tr><th className="px-2 py-1">Campo</th><th className="px-2 py-1">Antes</th><th className="px-2 py-1">Depois</th></tr></thead>
                <tbody className="divide-y divide-line">
                  {diff.map((d) => (
                    <tr key={d.key}><td className="px-2 py-1 font-mono">{d.key}</td><td className="px-2 py-1 text-red-700">{fmtVal(d.before)}</td><td className="px-2 py-1 text-green-800">{fmtVal(d.after)}</td></tr>
                  ))}
                </tbody>
              </table>
            ) : <div className="text-muted">Sem diferença de campos registrada (evento de negócio).</div>}
          </div>
        )}
      </Card>
    </li>
  );
}

const IGNORE = new Set(['updated_at', 'created_at', 'search_text', 'location']);
function changed(before: any, after: any) {
  const b = before ?? {};
  const a = after ?? {};
  const keys = Array.from(new Set([...Object.keys(b), ...Object.keys(a)])).filter((k) => !IGNORE.has(k));
  return keys.filter((k) => JSON.stringify(b[k]) !== JSON.stringify(a[k])).slice(0, 24).map((k) => ({ key: k, before: b[k], after: a[k] }));
}
function fmtVal(v: unknown) {
  if (v == null) return '—';
  if (typeof v === 'object') return JSON.stringify(v);
  const s = String(v);
  return s.length > 60 ? s.slice(0, 57) + '…' : s;
}
