import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import {
  AlarmClock, ArrowRightLeft, CheckCircle2, ChevronRight, Eye, EyeOff, FileText, ListOrdered, MessageCircle, MessageSquarePlus, Search, Sparkles, UserCheck, UserMinus,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, timeLeft } from '@/lib/format';
import { CASE_STATUS, CHANNEL, DOC, DOC_STATUS, OFFER_STATUS, QUEUE_STATUS, LEVEL_LABEL, TEAM } from '@/lib/labels';
import { Avatar, Badge, Button, ButtonLink, Card, ErrorState, Field, PageHeader, Section, SkeletonList, SourceChip, inputCls } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { Sheet, useToast } from '@/components/overlays';

const MANUAL = ['NOVO', 'EM_ANALISE', 'AGUARDANDO_DOCUMENTOS', 'AGUARDANDO_FAMILIA', 'VAGA_ENCONTRADA', 'RECURSO', 'NAO_ATENDIDO', 'ENCERRADO'];

const DETAIL_LABEL: Record<string, string> = {
  evento: 'Evento', canal: 'Canal', origem: 'Vinda de', bairro: 'Bairro', de: 'Endereço anterior', para: 'Novo endereço', criancas: 'Crianças',
  impactos: 'Impacto na fila', alteracoes: 'Alterações', cadunico: 'CadÚnico', mae_solo: 'Mãe solo', nome: 'Nome', nascimento: 'Nascimento',
  parentesco: 'Parentesco', aee: 'Indicação de AEE', mora_junto: 'Mora com a família', unidade: 'Unidade', faixa: 'Faixa', posicao: 'Posição',
  pontos: 'Pontos', alternativas: 'Unidades alternativas', turno: 'Turno', motivo: 'Motivo', posicao_anterior: 'Posição anterior',
  verificacao: 'Verificação da IARA', verificacao_iara: 'Verificação da IARA', possivel_duplicidade: 'Possível duplicidade',
};
function fmtDetail(v: unknown): string {
  if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
  if (Array.isArray(v)) {
    return v.map((x) => {
      if (x && typeof x === 'object' && 'child' in (x as any)) {
        const i = x as any;
        return `${i.child} · ${i.unit}: ${i.position_before ?? '—'}º → ${i.position_after ?? '—'}º · ${Number(i.score_before ?? 0)} → ${Number(i.score_after ?? 0)} pts`;
      }
      if (x && typeof x === 'object') return Object.values(x as object).join(' · ');
      return String(x);
    }).join('; ');
  }
  if (v && typeof v === 'object') return Object.entries(v as object).filter(([, x]) => x != null && x !== '').map(([k, x]) => `${DETAIL_LABEL[k] ?? k}: ${typeof x === 'boolean' ? (x ? 'sim' : 'não') : x}`).join(' · ');
  return String(v);
}

export default function CasePage() {
  const { id } = useParams();
  const res = useRpc<any>('case_detail', { case_id: id });
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const now = useNow(60_000);
  const [statusOpen, setStatusOpen] = useState(false);
  const [noteOpen, setNoteOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const c = d.case;
  const st = CASE_STATUS[c.status];

  const update = async (args: object, ok: string) => {
    setBusy(true);
    try {
      await rpc('case_update', { case_id: c.id, ...args });
      toast({ title: ok, tone: 'success' });
      qc.invalidateQueries({ queryKey: ['case_detail'] });
      qc.invalidateQueries({ queryKey: ['cases_list'] });
      qc.invalidateQueries({ queryKey: ['dashboard_analista'] });
      return true;
    } catch (e) {
      toast({ title: 'Não foi possível atualizar', description: (e as Error).message, tone: 'error' });
      return false;
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <Crumbs items={[{ label: 'Atendimentos', to: '/atendimentos' }, { label: c.protocol }]} />
      <PageHeader
        eyebrow={`${d.service.name} · ${d.service.sector}`}
        title={c.subject}
        subtitle={<span className="tabular">{c.protocol} · aberto em {fmtDateTime(c.opened_at)} · {CHANNEL[c.channel] ?? c.channel}</span>}
      />
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Badge tone={st?.tone ?? 'gray'} dot>{st?.label ?? c.status}</Badge>
        {c.priority !== 'NORMAL' && <Badge tone="red">{c.priority === 'URGENTE' ? 'Urgente' : 'Prioridade alta'}</Badge>}
        <Badge tone={c.overdue ? 'red' : 'gray'} icon={AlarmClock}>{c.open ? (c.overdue ? 'Prazo vencido' : `SLA ${timeLeft(c.sla_due_at, now)}`) : `Encerrado ${fmtDate(c.closed_at)}`}</Badge>
        <Badge tone="blue" icon={UserCheck}>{c.assigned ?? 'Sem responsável'}</Badge>
        {c.level && <Badge tone={c.resolution_code === 'RESOLVIDO_IARA' ? 'green' : LEVEL_LABEL[c.level]?.tone ?? 'gray'}>{c.resolution_code === 'RESOLVIDO_IARA' ? 'Resolvido na hora pela IARA' : LEVEL_LABEL[c.level]?.label ?? c.level}</Badge>}
        <Badge tone="gray">{c.level === 'UNIDADE' && c.unit_name ? `Secretaria · ${c.unit_name}` : TEAM[c.team] ?? c.team}</Badge>
        <SourceChip kind="demo" />
      </div>

      {c.open && (can('cases.write') || can('cases.assign')) && (
        <div className="no-scrollbar -mx-4 mb-4 flex gap-2 overflow-x-auto px-4 pb-1">
          {can('cases.assign') && (c.assigned_to_me
            ? <Button variant="secondary" icon={UserMinus} loading={busy} onClick={() => update({ assign: 'none' }, 'Atendimento devolvido à equipe')}>Devolver</Button>
            : <Button variant="primary" icon={UserCheck} loading={busy} onClick={() => update({ assign: 'me' }, 'Atendimento assumido')}>Assumir</Button>)}
          {can('cases.write') && <Button variant="secondary" icon={ArrowRightLeft} onClick={() => setStatusOpen(true)}>Mudar status</Button>}
          {can('cases.write') && <Button variant="secondary" icon={MessageSquarePlus} onClick={() => setNoteOpen(true)}>Nota</Button>}
          {d.student && (c.type === 'SOLICITACAO_VAGA' || c.type === 'TRANSFERENCIA') && (
            <ButtonLink to={`/vagas?aluno=${d.student.id}&protocolo=${c.id}`} variant="purple" icon={Search}>Buscar vaga</ButtonLink>
          )}
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.25fr_1fr]">
        <div>
          <Section title="Histórico" className="mt-0" subtitle="Cada passo registrado — o cidadão vê as etapas marcadas como públicas">
            <Card className="p-4">
              <ol className="relative space-y-4 border-l-2 border-purple-100 pl-5">
                {(d.events as any[]).map((e) => (
                  <li key={e.id} className="relative">
                    <span className={clsx('absolute -left-[27px] top-1 inline-flex size-4 items-center justify-center rounded-full ring-4 ring-white', e.type === 'OFERTA' || e.type === 'MATRICULA' ? 'bg-green-500' : e.type === 'STATUS' ? 'bg-purple-500' : 'bg-slate-300')} />
                    <div className="flex flex-wrap items-center gap-2 text-[12px] text-muted">
                      <span className="font-semibold text-ink-2">{e.actor ?? 'Sistema'}</span>
                      <span>{fmtDateTime(e.at)}</span>
                      {e.visibility === 'CIDADAO' ? <Badge tone="green" icon={Eye}>visível ao cidadão</Badge> : <Badge tone="gray" icon={EyeOff}>interna</Badge>}
                    </div>
                    <p className="mt-0.5 text-[14.5px]">{e.message}</p>
                    {e.new && e.type === 'STATUS' && <div className="mt-1 text-[12px] text-muted">{CASE_STATUS[e.old]?.label ?? e.old ?? '—'} → <b>{CASE_STATUS[e.new]?.label ?? e.new}</b></div>}
                  </li>
                ))}
              </ol>
              {c.resolution_notes && <p className="mt-4 rounded-2xl bg-slate-50 p-3 text-[13px]"><b>Resolução:</b> {c.resolution_notes}</p>}
            </Card>
          </Section>
        </div>
        <div className="space-y-4">
          {c.details && Object.keys(c.details).length > 0 && (
            <Card className="p-4">
              <div className="mb-2 text-[11.5px] font-bold uppercase tracking-wide text-subtle">Detalhes do pedido</div>
              <dl className="grid grid-cols-1 gap-2 text-[13px]">
                {Object.entries(c.details as Record<string, unknown>).filter(([, v]) => v != null && v !== '' && !(Array.isArray(v) && !v.length)).map(([k, v]) => (
                  <div key={k}><dt className="text-[11.5px] font-semibold text-subtle">{DETAIL_LABEL[k] ?? k}</dt><dd className="break-words">{fmtDetail(v)}</dd></div>
                ))}
              </dl>
            </Card>
          )}
          {d.student && (
            <Link to={`/alunos/${d.student.id}`} className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
              <Avatar name={d.student.name} seed={d.student.avatar_seed} size={46} />
              <div className="min-w-0 flex-1">
                <div className="text-[11.5px] font-bold uppercase tracking-wide text-subtle">Criança</div>
                <div className="truncate font-semibold">{d.student.name}</div>
                <div className="truncate text-[12.5px] text-muted">{d.student.age} · {d.student.address?.neighborhood ?? ''}</div>
              </div>
              <ChevronRight className="size-5 text-subtle" />
            </Link>
          )}
          {d.guardian && (
            <Link to={`/responsaveis/${d.guardian.id}`} className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
              <Avatar name={d.guardian.full_name} seed={d.guardian.full_name} size={46} />
              <div className="min-w-0 flex-1">
                <div className="text-[11.5px] font-bold uppercase tracking-wide text-subtle">Responsável</div>
                <div className="truncate font-semibold">{d.guardian.full_name}</div>
                <div className="truncate text-[12.5px] text-muted">{d.guardian.whatsapp ?? d.guardian.phone} {d.guardian.cadunico ? '· CadÚnico' : ''}{d.guardian.single_mother ? ' · Mãe solo' : ''}</div>
              </div>
              <ChevronRight className="size-5 text-subtle" />
            </Link>
          )}
          {d.unit && <Link to={`/unidades/${d.unit.id}`} className="block rounded-3xl bg-white p-4 text-[14px] font-semibold shadow-soft ring-1 ring-line/70 hover:shadow-lift">🏫 {d.unit.name}</Link>}
          {d.conversation && (
            <Link to={`/conversas/${d.conversation.id}`} className="flex items-center gap-3 rounded-3xl bg-purple-50 p-4 ring-1 ring-purple-100">
              <MessageCircle className="size-5 text-purple-700" /><span className="flex-1 text-[14px] font-semibold text-purple-900">Conversa com a IARA vinculada</span><ChevronRight className="size-5 text-purple-700" />
            </Link>
          )}
          {(d.queue as any[]).length > 0 && (
            <Card className="p-4">
              <div className="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><ListOrdered className="size-4" />Fila</div>
              {(d.queue as any[]).map((q) => (
                <Link key={q.id} to={`/fila/${q.id}`} className="flex items-center justify-between rounded-xl px-2 py-2 hover:bg-slate-50">
                  <span className="text-[14px]">{q.grade} · {q.unit}</span>
                  <span className="flex items-center gap-2">{q.position && <b className="text-purple-800">{q.position}º</b>}<Badge tone={QUEUE_STATUS[q.status]?.tone}>{QUEUE_STATUS[q.status]?.label}</Badge></span>
                </Link>
              ))}
            </Card>
          )}
          {(d.offers as any[]).length > 0 && (
            <Card className="p-4">
              <div className="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><Sparkles className="size-4" />Ofertas</div>
              {(d.offers as any[]).map((o) => (
                <div key={o.id} className="flex items-center justify-between rounded-xl px-2 py-2 text-[14px]">
                  <span className="truncate">{o.unit} · {o.class}</span>
                  <Badge tone={OFFER_STATUS[o.status]?.tone}>{OFFER_STATUS[o.status]?.label}</Badge>
                </div>
              ))}
            </Card>
          )}
          <Card className="p-4">
            <div className="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><FileText className="size-4" />Documentos</div>
            {(d.documents as any[]).length ? (d.documents as any[]).map((doc) => (
              <div key={doc.id} className="flex items-center justify-between py-1.5 text-[14px]">
                <span className="flex items-center gap-2">{doc.status === 'VALIDADO' && <CheckCircle2 className="size-4 text-green-700" />}{DOC[doc.type] ?? doc.type}</span>
                <Badge tone={DOC_STATUS[doc.status]?.tone}>{DOC_STATUS[doc.status]?.label}</Badge>
              </div>
            )) : <p className="text-[13px] text-muted">Nenhum documento vinculado.</p>}
            {d.service.documents?.length > 0 && <p className="mt-2 text-[12px] text-muted">Exigidos neste serviço: {(d.service.documents as string[]).map((x) => DOC[x] ?? x).join(', ')}</p>}
          </Card>
        </div>
      </div>

      <StatusSheet open={statusOpen} onClose={() => setStatusOpen(false)} current={c.status} busy={busy} onSubmit={async (s, note) => { if (await update({ status: s, note }, 'Status atualizado')) setStatusOpen(false); }} />
      <NoteSheet open={noteOpen} onClose={() => setNoteOpen(false)} busy={busy} onSubmit={async (note, visibility) => { if (await update({ note, visibility }, 'Nota registrada')) setNoteOpen(false); }} />
    </div>
  );
}

function StatusSheet({ open, onClose, current, busy, onSubmit }: { open: boolean; onClose: () => void; current: string; busy: boolean; onSubmit: (s: string, note: string) => void }) {
  const [s, setS] = useState(current);
  const [note, setNote] = useState('');
  const closing = s === 'ENCERRADO' || s === 'NAO_ATENDIDO';
  return (
    <Sheet open={open} onClose={onClose} title="Mudar status" subtitle="Ofertas e matrículas mudam o status pelo próprio fluxo — aqui só os status manuais." footer={<Button block size="lg" loading={busy} disabled={s === current || (closing && note.trim().length < 3)} onClick={() => onSubmit(s, note)}>Salvar</Button>}>
      <div className="grid grid-cols-2 gap-2 pt-1">
        {MANUAL.map((m) => (
          <button key={m} onClick={() => setS(m)} className={clsx('rounded-2xl p-3 text-left text-[14px] font-semibold ring-1', s === m ? 'bg-purple-50 ring-2 ring-purple-500' : 'bg-white ring-line')}>{CASE_STATUS[m].label}</button>
        ))}
      </div>
      <Field label={closing ? 'Resolução (obrigatória)' : 'Comentário (opcional, visível ao cidadão)'}>
        <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3} className={`${inputCls} mt-1 h-auto py-3`} />
      </Field>
    </Sheet>
  );
}

function NoteSheet({ open, onClose, busy, onSubmit }: { open: boolean; onClose: () => void; busy: boolean; onSubmit: (n: string, v: string) => void }) {
  const [note, setNote] = useState('');
  const [vis, setVis] = useState('INTERNA');
  return (
    <Sheet open={open} onClose={onClose} title="Adicionar nota" footer={<Button block size="lg" loading={busy} disabled={note.trim().length < 3} onClick={() => onSubmit(note, vis)}>Registrar nota</Button>}>
      <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={4} className={`${inputCls} h-auto py-3`} placeholder="Ex.: contato telefônico realizado com a responsável…" />
      <div className="mt-3 flex gap-2">
        <button onClick={() => setVis('INTERNA')} className={clsx('flex-1 rounded-2xl p-3 text-[14px] font-semibold ring-1', vis === 'INTERNA' ? 'bg-slate-100 ring-2 ring-slate-500' : 'ring-line')}><EyeOff className="mr-1 inline size-4" />Interna</button>
        <button onClick={() => setVis('CIDADAO')} className={clsx('flex-1 rounded-2xl p-3 text-[14px] font-semibold ring-1', vis === 'CIDADAO' ? 'bg-green-50 ring-2 ring-green-600' : 'ring-line')}><Eye className="mr-1 inline size-4" />Visível ao cidadão</button>
      </div>
    </Sheet>
  );
}
