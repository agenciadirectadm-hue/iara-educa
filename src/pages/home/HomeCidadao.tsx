import { Suspense, lazy, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { motion } from 'motion/react';
import clsx from 'clsx';
import {
  Bell, Check, CheckCircle2, ChevronRight, Circle, ClipboardList, FilePen, MapPin, MessageCircle, Route, School, Search, ShieldCheck, Sparkles, Upload, X,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import { fmtDate, fmtKm, timeAgo, timeLeft } from '@/lib/format';
import { CASE_STATUS, DOC, DOC_STATUS, SHIFT } from '@/lib/labels';
import { Avatar, Badge, Button, ButtonLink, Card, ErrorState, Section, Simulado, SkeletonList } from '@/components/ui';
import { IaraMascot } from '@/components/iara';
import { useSession } from '@/lib/session';
import { FamilyOnboarding } from '@/pages/Family';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { WhatsAppCard } from '@/components/whatsapp';
import { LinkMetodologia, TresDistancias, TresDistanciasInscricao, useDistancias } from '@/components/distancias';
import { PontosCriterio } from '@/components/PontosCriterio';
import { AVISO_FAMILIA_FICTICIA } from '@/lib/avisos';
import { VidaEscolarResumo } from '@/pages/Escola';

// o quadro tem mapa: só carrega quando a família abre "ver o caminho"
const QuadroDistancias = lazy(() => import('@/components/QuadroDistancias'));

export default function HomeCidadao() {
  const { me } = useSession();
  if (!me?.guardian) return <FamilyOnboarding />;
  return <CitizenHome />;
}

function CitizenHome() {
  const home = useRpc<any>('citizen_home', {}, { refetchInterval: 20_000 });
  const now = useNow(30_000);
  const navigate = useNavigate();
  if (home.isLoading) return <SkeletonList rows={5} />;
  if (home.error) return <ErrorState error={home.error} onRetry={() => home.refetch()} />;
  const d = home.data;
  const offers = d.children.flatMap((c: any) => (c.offers ?? []).map((o: any) => ({ ...o, child: c })));
  const pendingOffer = offers.find((o: any) => o.status === 'OFFERED');

  const actions = [
    { icon: Search, label: 'Encontrar uma vaga', to: '/vagas', tone: 'from-purple-500 to-purple-700' },
    { icon: ClipboardList, label: 'Acompanhar protocolo', to: '/protocolos', tone: 'from-blue-500 to-blue-700' },
    { icon: Sparkles, label: 'Minha fila', to: '#fila', tone: 'from-fuchsia-500 to-purple-600' },
    { icon: School, label: 'Minhas matrículas', to: '#criancas', tone: 'from-teal-500 to-green-700' },
    { icon: MapPin, label: 'Unidades próximas', to: '/mapa?perto=1', tone: 'from-sky-500 to-blue-700' },
    { icon: FilePen, label: 'Minha família', to: '/familia', tone: 'from-orange-400 to-rose-500' },
  ];

  return (
    <div>
      <div className="relative -mx-4 overflow-hidden px-4 pb-2 pt-1 sm:mx-0 sm:rounded-4xl sm:px-6">
        <div className="flex items-end gap-2">
          <div className="min-w-0 flex-1 pb-3">
            <div className="text-[13px] font-bold uppercase tracking-[0.12em] text-purple-700">Portal da família</div>
            <h1 className="mt-1 font-display text-[28px] font-black leading-[1.08] text-ink sm:text-4xl">Oi, {d.guardian.first_name}! 💜</h1>
            <p className="mt-1.5 text-[15px] text-muted text-balance">Eu sou a IARA. Posso ajudar você a encontrar uma unidade, acompanhar uma solicitação ou entender sua posição na fila.</p>
          </div>
          <IaraMascot height={150} mood="wave" className="-mb-1 shrink-0" />
        </div>
      </div>

      {pendingOffer && <OfferHero offer={pendingOffer} now={now} />}

      <div className="mt-4 grid grid-cols-3 gap-2.5 sm:grid-cols-6">
        {actions.map((a) => (
          <motion.div key={a.label} whileTap={{ scale: 0.95 }}>
            <Link
              to={a.to.startsWith('#') ? '/inicio' : a.to}
              onClick={(e) => {
                if (a.to.startsWith('#')) {
                  e.preventDefault();
                  document.getElementById(a.to.slice(1))?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }
              }}
              className="flex h-full flex-col items-center gap-2 rounded-3xl bg-white p-3 text-center shadow-soft ring-1 ring-line/70"
            >
              <span className={clsx('inline-flex size-11 items-center justify-center rounded-2xl bg-gradient-to-br text-white shadow-sm', a.tone)}>
                <a.icon className="size-5" />
              </span>
              <span className="text-[12px] font-semibold leading-tight">{a.label}</span>
            </Link>
          </motion.div>
        ))}
      </div>

      <WhatsAppCard className="mt-4" subtitle="Tudo o que você faz aqui, a IARA faz pelo WhatsApp: vaga, fila, documentos e mudanças da família. Compartilhe com quem também cuida das crianças." />

      <Section title="Minhas crianças" id="criancas">
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {d.children.map((c: any) => <ChildCard key={c.id} c={c} />)}
        </div>
      </Section>

      <Section title="Vida escolar" subtitle="Avisos da escola, frequência e cardápio — também pela IARA"
        action={<Link to="/escola" className="text-sm font-semibold text-purple-700">Abrir</Link>}>
        <VidaEscolarResumo />
      </Section>

      <Section title="Protocolos" action={<Link to="/protocolos" className="text-sm font-semibold text-purple-700">Ver todos</Link>}>
        <Card className="divide-y divide-line">
          {d.cases.slice(0, 3).map((c: any) => (
            <Link key={c.id} to="/protocolos" className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
              <div className="min-w-0 flex-1">
                <div className="truncate font-semibold">{c.type_name}</div>
                <div className="truncate text-[12.5px] text-muted">{c.protocol} · {c.last_event}</div>
              </div>
              <Badge tone={CASE_STATUS[c.status]?.tone ?? 'gray'}>{CASE_STATUS[c.status]?.label ?? c.status}</Badge>
            </Link>
          ))}
        </Card>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <UnidadesPerto d={d} />
        <Section title={<span className="inline-flex items-center gap-1">Avisos<Simulado detail={AVISO_FAMILIA_FICTICIA} /></span>} subtitle="Notificações da rede para a sua família">
          <Card className="divide-y divide-line">
            {d.notifications.length ? d.notifications.slice(0, 5).map((n: any) => (
              <div key={n.id} className="flex items-start gap-3 px-4 py-3">
                <Bell className="mt-0.5 size-5 text-purple-700" />
                <div className="min-w-0 flex-1">
                  <div className="font-semibold">{n.title}</div>
                  <div className="text-[13px] text-muted">{n.body}</div>
                </div>
                <span className="shrink-0 text-[11.5px] text-muted">{timeAgo(n.at, now)}</span>
              </div>
            )) : <p className="p-4 text-sm text-muted">Nenhum aviso por enquanto.</p>}
          </Card>
        </Section>
      </div>

      <button onClick={() => navigate('/iara')} className="fixed bottom-24 right-4 z-30 flex items-center gap-2 rounded-full bg-purple-700 py-2 pl-2 pr-4 font-semibold text-white shadow-glow lg:bottom-8 lg:right-8" aria-label="Conversar com a IARA">
        <img src="./iara/iara-avatar.webp" alt="" className="size-10 rounded-full ring-2 ring-white/70" />
        <MessageCircle className="size-4" /> Falar com a IARA
      </button>
    </div>
  );
}

function OfferHero({ offer, now }: { offer: any; now: number }) {
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [declineOpen, setDeclineOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const respond = async (accept: boolean, reason?: string) => {
    setBusy(true);
    try {
      const r = await rpc<any>('offer_respond', { offer_id: offer.id, accept, reason, channel: 'PORTAL' });
      toast({ title: accept ? 'Aceite registrado ✅' : 'Recusa registrada', description: r.message, tone: accept ? 'success' : 'info' });
      qc.invalidateQueries({ queryKey: ['citizen_home'] });
      setDeclineOpen(false);
    } catch (e) {
      toast({ title: 'Não foi possível registrar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} className="mt-3 overflow-hidden rounded-4xl bg-gradient-to-br from-green-700 via-teal-700 to-blue-900 p-5 text-white shadow-lift">
      <div className="flex items-center gap-2 text-[13px] font-bold uppercase tracking-wide text-green-100"><Sparkles className="size-4" /> Vaga ofertada para {offer.child.first_name}</div>
      <div className="mt-2 font-display text-[22px] font-black leading-tight">{offer.unit}</div>
      <div className="text-[14px] text-white/85">{offer.class} · turno {SHIFT[offer.shift]?.toLowerCase()} · {offer.address}</div>
      <div className="mt-3 inline-flex items-center gap-2 rounded-full bg-white/15 px-3 py-1.5 text-[13px] font-semibold">⏳ Responda em {timeLeft(offer.expires_at, now)}</div>
      <p className="mt-3 text-[13px] text-white/80">Aceitar não é a matrícula: depois do aceite, a unidade confere os documentos e confirma.</p>
      <div className="mt-4 flex gap-2">
        <Button
          className="flex-[1.5] bg-white text-green-800 hover:bg-green-50"
          size="lg"
          icon={Check}
          loading={busy}
          onClick={async () => {
            const ok = await confirm({ title: `Aceitar a vaga de ${offer.child.first_name}?`, body: <>Unidade: <b>{offer.unit}</b> ({offer.class}). A unidade vai conferir os documentos e confirmar a matrícula.</>, confirm: 'Sim, aceito a vaga', tone: 'success' });
            if (ok) respond(true);
          }}
        >
          Aceitar vaga
        </Button>
        <Button className="flex-1 bg-white/15 text-white ring-1 ring-white/30 hover:bg-white/25" size="lg" icon={X} onClick={() => setDeclineOpen(true)}>Recusar</Button>
      </div>
      <Sheet open={declineOpen} onClose={() => setDeclineOpen(false)} title="Por que você vai recusar?" subtitle="Pela regra vigente, a criança volta para a fila sem perder a pontuação.">
        <div className="space-y-2 pt-1">
          {['Unidade distante do trabalho', 'Turno incompatível', 'Prefiro aguardar outra unidade', 'Outro motivo'].map((r) => (
            <Button key={r} block variant="secondary" size="lg" disabled={busy} onClick={() => respond(false, r)}>{r}</Button>
          ))}
        </div>
      </Sheet>
    </motion.div>
  );
}

function ChildCard({ c }: { c: any }) {
  const q = (c.queue ?? []).find((x: any) => x.status === 'WAITING');
  const accepted = (c.offers ?? []).find((o: any) => o.status === 'ACCEPTED');
  const docs = (c.documents ?? []) as any[];
  const qc = useQueryClient();
  const toast = useToast();
  const [sending, setSending] = useState<string | null>(null);
  const [caminho, setCaminho] = useState(false);
  const missing = docs.filter((d) => !['VALIDADO', 'RECEBIDO'].includes(d.status));
  const showDocs = (q || accepted) && missing.length > 0;
  const send = async (type: string) => {
    setSending(type);
    try {
      await rpc('document_set', { student_id: c.id, doc_type: type, status: 'RECEBIDO' });
      toast({ title: `${DOC[type]} enviado`, description: 'A unidade fará a validação.', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['citizen_home'] });
    } catch (e) {
      toast({ title: 'Envio não concluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setSending(null);
    }
  };
  return (
    <Card className="p-4" id={q ? 'fila' : undefined}>
      <div className="flex items-center gap-3">
        <Avatar name={c.name} seed={c.avatar_seed} size={50} />
        <div className="min-w-0 flex-1">
          <div className="truncate font-display text-lg font-extrabold">{c.name}</div>
          <div className="text-[13px] text-muted">{c.age} · {c.grade_rule?.grade_name ?? '—'}</div>
        </div>
      </div>
      {c.school && (
        <Link to={`/unidades/${c.school.unit_id}`} className="mt-3 flex items-center gap-3 rounded-2xl bg-blue-50 p-3 ring-1 ring-blue-100">
          <School className="size-5 text-blue-800" />
          <div className="min-w-0 flex-1 text-[13.5px]">
            <div className="font-semibold text-blue-950">Matriculada · {c.school.unit}</div>
            <div className="text-blue-900/80">{c.school.class} · {SHIFT[c.school.shift]}</div>
          </div>
          <ChevronRight className="size-4 text-blue-800" />
        </Link>
      )}
      {q && (
        <div className="mt-3 rounded-3xl bg-gradient-to-br from-purple-50 to-white p-4 ring-1 ring-purple-100">
          <div className="flex items-end justify-between gap-3">
            <div>
              <div className="text-[12px] font-bold uppercase tracking-wide text-purple-700">Posição atual na fila</div>
              <div className="font-display text-5xl font-black leading-none text-purple-800 tabular">{q.position}º</div>
            </div>
            <div className="text-right text-[12.5px] text-muted">
              <div className="font-semibold text-ink">{q.grade}</div>
              <div className="max-w-[160px] truncate">{q.unit}</div>
              <div>entre {q.queue_size} crianças</div>
            </div>
          </div>
          <div className="mt-3 text-[12px] font-bold uppercase tracking-wide text-subtle">Critérios aplicados</div>
          <ul className="mt-1.5 space-y-1">
            {(q.breakdown ?? []).filter((b: any) => b.weight > 0 || b.code === 'DATA_SOLICITACAO' || (b.analysis && b.applied)).map((b: any) => (
              <li key={b.code} className="flex items-start gap-2 text-[13.5px]">
                {b.applied ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" /> : <Circle className="mt-0.5 size-4 shrink-0 text-subtle" />}
                <span className={b.applied ? 'flex-1 text-ink' : 'flex-1 text-muted'}>{b.name}<span className="block text-[12px] text-muted">{b.evidence}</span>
                  {b.code === 'TERRITORIO_2KM' && b.distancias && (
                    <span className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5">
                      <TresDistanciasInscricao breakdown={q.breakdown} />
                      <button type="button" onClick={() => setCaminho(true)} className="inline-flex items-center gap-1 text-[12px] font-semibold text-purple-700 hover:underline"><Route className="size-3.5" />ver o caminho</button>
                    </span>
                  )}
                </span>
                {b.analysis ? <span className="shrink-0 text-[11.5px] font-bold text-purple-700">sob análise</span>
                  : <PontosCriterio weight={b.weight} applied={b.applied} />}
              </li>
            ))}
          </ul>
          <div className="mt-3 flex items-start gap-2 rounded-2xl bg-white p-2.5 text-[12px] text-muted ring-1 ring-line">
            <ShieldCheck className="mt-0.5 size-4 shrink-0 text-purple-700" />
            Pontuação {Number(q.score ?? 0)} de 100 (IN nº 025/2025-SEDUC). Entrada em {fmtDate(q.entered_at)} · regras {q.rule_version}. Você vê só os seus critérios — nunca dados de outras crianças. Não há previsão de data sem fonte oficial.
          </div>
        </div>
      )}
      {accepted && (
        <div className="mt-3 rounded-2xl bg-teal-50 p-3 text-[13.5px] text-teal-900 ring-1 ring-teal-100">
          <b>Aceite registrado</b> para {accepted.unit}. A unidade vai conferir os documentos e confirmar a matrícula.
        </div>
      )}
      {showDocs && (
        <div className="mt-3">
          <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Documentos pendentes</div>
          <div className="mt-1.5 space-y-1.5">
            {missing.map((d) => (
              <div key={d.type} className="flex items-center gap-2 rounded-2xl bg-white px-3 py-2 ring-1 ring-line">
                <span className="flex-1 text-[14px] font-medium">{DOC[d.type]}</span>
                <Badge tone={DOC_STATUS[d.status]?.tone ?? 'gray'}>{DOC_STATUS[d.status]?.label}</Badge>
                <Button size="sm" variant="soft" icon={Upload} loading={sending === d.type} onClick={() => send(d.type)}>Enviar</Button>
              </div>
            ))}
          </div>
        </div>
      )}
      {!c.school && !q && !accepted && (
        <ButtonLink to="/vagas" className="mt-3" block variant="soft" icon={Search}>Procurar vaga para {c.first_name}</ButtonLink>
      )}
      {q && <CaminhoSheet open={caminho} onClose={() => setCaminho(false)} criancaId={c.id} nome={c.first_name} unidadeId={q.unit_id} unidade={q.unit} />}
    </Card>
  );
}

/** O caminho de casa até a unidade pedida: linha reta, a pé e de carro, desenhados no mapa. */
function CaminhoSheet({ open, onClose, criancaId, nome, unidadeId, unidade }: {
  open: boolean; onClose: () => void; criancaId: string; nome: string; unidadeId: number; unidade: string;
}) {
  const det = useRpc<any>('student_detail', { student_id: criancaId }, { enabled: open });
  const a = det.data?.address;
  return (
    <Sheet open={open} onClose={onClose} title={`De casa até ${unidade}`} subtitle={`Endereço de ${nome} · as três formas de medir`} size="lg">
      {det.isLoading ? <SkeletonList rows={3} /> : a?.lat != null ? (
        <Suspense fallback={<SkeletonList rows={3} />}>
          <QuadroDistancias origem={{ lat: a.lat, lng: a.lng }} unidadeId={unidadeId} titulo="Distância até a unidade pedida" homeLabel={`Casa de ${nome}`} unidadeLabel="Unidade pedida" className="shadow-none ring-0" />
        </Suspense>
      ) : <p className="text-[14px] text-muted">Endereço sem localização no mapa. Atualize o endereço em “Minha família”.</p>}
      <p className="mt-3 text-[12.5px] text-muted">A pontuação “até 2 km” usa a medida indicada na regra; as outras duas ficam registradas para conferência. <LinkMetodologia /></p>
    </Sheet>
  );
}

/** Unidades perto de casa, com a distância em linha reta, a pé e de carro. */
function UnidadesPerto({ d }: { d: any }) {
  const a = d.guardian?.address;
  const perto = (d.nearby ?? []).slice(0, 4) as any[];
  const dist = useDistancias(a?.lat != null && perto.length ? { lat: a.lat, lng: a.lng, unidades: perto.map((u) => u.id) } : null);
  return (
    <Section title="Unidades perto de casa" action={<Link to="/mapa?perto=1" className="text-sm font-semibold text-purple-700">Ver no mapa</Link>}>
      <Card className="divide-y divide-line">
        {perto.map((u: any) => {
          const x = dist.data?.unidades.find((y) => y.id === u.id);
          return (
            <Link key={u.id} to={`/unidades/${u.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
              <span className={clsx('inline-flex size-9 shrink-0 items-center justify-center rounded-xl text-white', u.type === 'CMEI' ? 'bg-purple-500' : 'bg-blue-500')}><School className="size-4" /></span>
              <div className="min-w-0 flex-1">
                <div className="truncate font-semibold">{u.name}</div>
                {x ? <TresDistancias variante="linha" u={x} criterio={dist.data?.criterio} calculando={dist.calculando} />
                  : <div className="text-[12.5px] text-muted">{fmtKm(u.distance_m)} em linha reta · {u.neighborhood}</div>}
              </div>
              <ChevronRight className="size-5 shrink-0 text-subtle" />
            </Link>
          );
        })}
        <p className="flex flex-wrap items-center gap-x-2 px-4 py-2 text-[12px] text-muted">Linha reta, a pé e de carro (pelas ruas) a partir do seu endereço · <LinkMetodologia className="text-[12px]" /></p>
      </Card>
    </Section>
  );
}
