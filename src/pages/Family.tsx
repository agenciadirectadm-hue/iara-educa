import { useMemo, useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import {
  ArrowRightLeft, Baby, Building2, CheckCircle2, ClipboardList, Home, MapPin, MessageCircle, PencilLine, Plane, Search, Send, UserPlus, Users, X,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtKm } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, ButtonLink, Card, EmptyState, ErrorState, Field, PageHeader, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { IaraBubble } from '@/components/iara';
import { WhatsAppCard } from '@/components/whatsapp';
import { VidaEscolarResumo } from './Escola';

const REL_CHILD = [['MAE', 'Mãe'], ['PAI', 'Pai'], ['AVO', 'Avó / avô'], ['RESPONSAVEL_LEGAL', 'Responsável legal']] as const;
const REL_ADULT = [['PAI', 'Pai'], ['MAE', 'Mãe'], ['AVO', 'Avó / avô'], ['PADRASTO', 'Padrasto / madrasta'], ['COMPANHEIRO', 'Companheiro(a)'], ['RESPONSAVEL_LEGAL', 'Responsável legal (guarda)'], ['OUTRO', 'Outro']] as const;
const REL_NAME: Record<string, string> = Object.fromEntries([...REL_CHILD, ...REL_ADULT]);
export const LEVEL: Record<string, { label: string; tone: 'green' | 'blue' | 'purple' }> = {
  IARA: { label: 'A IARA resolve', tone: 'green' },
  UNIDADE: { label: 'Unidade decide', tone: 'blue' },
  SECRETARIA: { label: 'SEDUC decide', tone: 'purple' },
};
const STUDENT_STATUS: Record<string, string> = {
  MATRICULADO: 'Matriculada(o)', AGUARDANDO_VAGA: 'Aguardando vaga', SEM_VINCULO: 'Sem vaga na rede', TRANSFERENCIA: 'Em transferência', INATIVO: 'Inativa(o)',
};

type Place = { label: string; lat: number; lng: number; kind: string };
type SheetKind = null | 'child' | 'origin' | 'adult' | 'move' | 'update' | 'service';

/** Bairro (ou unidade de referência) para localizar o endereço, sem geocodificador externo. */
function BairroPicker({ value, onPick }: { value: Place | null; onPick: (p: Place | null) => void }) {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 280);
  const geo = useRpc<any>('geo_search', { q: dq }, { enabled: dq.length >= 2 && !value });
  if (value) {
    return (
      <div className="flex items-center gap-2 rounded-2xl bg-green-50 px-3 py-2.5 ring-1 ring-green-200">
        <MapPin className="size-4 text-green-700" />
        <span className="flex-1 text-[14px] font-semibold text-green-900">{value.label}</span>
        <button onClick={() => onPick(null)} className="inline-flex size-9 items-center justify-center rounded-xl hover:bg-green-100" aria-label="Trocar bairro"><X className="size-4" /></button>
      </div>
    );
  }
  const items = ((geo.data?.items ?? []) as any[]).slice(0, 6);
  return (
    <div>
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Digite o bairro (ex.: Zona 7, Jardim Alvorada)" className={clsx(inputCls, 'pl-10')} aria-label="Bairro" />
      </div>
      {items.length > 0 && (
        <div className="mt-2 divide-y divide-line overflow-hidden rounded-2xl bg-white ring-1 ring-line">
          {items.map((i) => (
            <button key={`${i.kind}-${i.label}`} onClick={() => onPick({ label: i.label, lat: i.lat, lng: i.lng, kind: i.kind })} className="flex w-full items-center gap-2 px-3 py-2.5 text-left text-[14px] hover:bg-purple-50">
              {i.kind === 'BAIRRO' ? <MapPin className="size-4 text-purple-700" /> : <Building2 className="size-4 text-blue-700" />}
              <span className="min-w-0 flex-1 truncate">{i.label}</span>
              <span className="text-[11.5px] text-muted">{i.kind === 'BAIRRO' ? 'bairro' : 'perto da unidade'}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <label className="flex min-h-[48px] cursor-pointer items-start gap-3 rounded-2xl bg-white p-3 ring-1 ring-line">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="mt-0.5 size-5 accent-purple-700" />
      <span className="min-w-0"><span className="block text-[14.5px] font-semibold">{label}</span>{hint && <span className="block text-[12.5px] text-muted">{hint}</span>}</span>
    </label>
  );
}

function ResultBox({ children }: { children: ReactNode }) {
  return <div className="space-y-3 rounded-3xl bg-green-50 p-4 text-[14px] text-green-950 ring-1 ring-green-200">{children}</div>;
}

function Impacts({ impacts }: { impacts: any[] }) {
  if (!impacts?.length) return null;
  return (
    <div className="space-y-2">
      <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Fila recalculada na hora</div>
      {impacts.map((i) => (
        <div key={i.entry_id} className="rounded-2xl bg-white p-3 ring-1 ring-line">
          <div className="font-semibold">{i.child} · {i.grade}</div>
          <div className="text-[12.5px] text-muted">{i.unit}</div>
          <div className="mt-1 grid grid-cols-1 gap-1 text-[13px] sm:grid-cols-3">
            <span>Posição: {i.position_before ?? '—'}º → <b>{i.position_after ?? '—'}º</b></span>
            <span>Pontos: {Number(i.score_before ?? 0)} → <b>{Number(i.score_after ?? 0)}</b></span>
            {i.distance_after != null && <span>Distância: {fmtKm(i.distance_before)} → {fmtKm(i.distance_after)}</span>}
          </div>
        </div>
      ))}
    </div>
  );
}

// ============================================================================ cadastro da família (família nova)
export function FamilyOnboarding() {
  const { refreshMe } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const [name, setName] = useState('');
  const [place, setPlace] = useState<Place | null>(null);
  const [street, setStreet] = useState('');
  const [number, setNumber] = useState('');
  const [cad, setCad] = useState(false);
  const [solo, setSolo] = useState(false);
  const [city, setCity] = useState('');
  const [busy, setBusy] = useState(false);
  const valid = name.trim().split(/\s+/).length >= 2 && !!place;
  const submit = async () => {
    if (!place) return;
    setBusy(true);
    try {
      const r = await rpc<any>('family_register', {
        full_name: name.trim(), cadunico: cad, single_mother: solo, channel: 'WEB', origin: city.trim() ? { city: city.trim() } : null,
        address: { neighborhood: place.label, lat: place.lat, lng: place.lng, street: street.trim() || null, number: number.trim() || null, precision: place.kind === 'BAIRRO' ? 'BAIRRO' : 'UNIDADE_PROXIMA' },
      });
      toast({ title: 'Cadastro feito ✅', description: `Protocolo ${r.protocol}. Agora inclua as crianças.`, tone: 'success' });
      await refreshMe();
      qc.invalidateQueries();
    } catch (e) {
      toast({ title: 'Cadastro não realizado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="mx-auto max-w-xl">
      <PageHeader eyebrow="Bem-vindos a Maringá" title="Cadastro da família"
        subtitle="Leva 1 minuto e é o mesmo cadastro que a IARA faz pelo WhatsApp. Depois você inclui as crianças e já entra na fila on-line." />
      <IaraBubble compact className="mb-4">
        Prefere conversar? No <Link to="/iara" className="font-bold text-purple-700 underline">WhatsApp da IARA</Link> eu faço este cadastro e a inscrição na fila em poucas mensagens.
      </IaraBubble>
      <WhatsAppCard className="mb-4" title="Prefere fazer pelo WhatsApp?" subtitle="Escaneie o código ou abra a conversa: a IARA faz o cadastro, inclui as crianças e já inscreve na fila." />
      <Card className="space-y-4 p-4">
        <Field label="Seu nome completo (responsável)">
          <input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} placeholder="Nome e sobrenome" autoComplete="name" />
        </Field>
        <Field label="Bairro em Maringá" hint="Usado para a distância até as unidades (critério de até 2 km).">
          <BairroPicker value={place} onPick={setPlace} />
        </Field>
        <div className="grid grid-cols-[1fr_7rem] gap-2">
          <Field label="Rua (opcional)"><input value={street} onChange={(e) => setStreet(e.target.value)} className={inputCls} placeholder="Rua das Flores" /></Field>
          <Field label="Número"><input value={number} onChange={(e) => setNumber(e.target.value)} className={inputCls} placeholder="123" inputMode="numeric" /></Field>
        </div>
        <Toggle checked={cad} onChange={setCad} label="Família inscrita no CadÚnico" hint="Critério da fila: 25 pontos (comprovante conferido na matrícula)." />
        <Toggle checked={solo} onChange={setSolo} label="Sou mãe solo" hint="Critério da fila: 5 pontos (declaração conferida na matrícula)." />
        <Field label="Vieram de outra cidade? (opcional)" hint="Se sim, a vaga é pedida como transferência de outro município.">
          <input value={city} onChange={(e) => setCity(e.target.value)} className={inputCls} placeholder="Ex.: Londrina" />
        </Field>
        <Button block size="lg" variant="purple" icon={CheckCircle2} loading={busy} disabled={!valid} onClick={submit}>Fazer cadastro</Button>
        <p className="text-center text-[12px] text-muted">Dados usados só para o atendimento da rede (LGPD).</p>
      </Card>
    </div>
  );
}

// ============================================================================ página
export default function Family() {
  const { me } = useSession();
  const res = useRpc<any>('family_overview', {}, { enabled: me?.scope === 'GUARDIAN' });
  const [sheet, setSheet] = useState<SheetKind>(null);
  const [service, setService] = useState<string | null>(null);
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const refresh = () => ['family_overview', 'citizen_home', 'search_vacancies'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));

  if (me?.scope !== 'GUARDIAN') {
    return <Card><EmptyState title="Área do responsável" body="Esta página é do portal da família. Servidores acessam os cadastros pela ficha do responsável." /></Card>;
  }
  if (!me.guardian) return <FamilyOnboarding />;
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const g = d.guardian;
  const kids = (d.children ?? []) as any[];
  const adults = ((d.adults ?? []) as any[]).filter((a) => !a.is_me);
  const withdraw = async (entry: any, kid: any) => {
    const ok = await confirm({ title: `Tirar ${kid.first_name} da fila?`, body: `A posição ${entry.position ? `(${entry.position}º) ` : ''}${entry.unit} é perdida; se mudar de ideia, será uma nova inscrição.`, confirm: 'Desistir da fila', tone: 'danger' });
    if (!ok) return;
    try {
      const r = await rpc<any>('queue_withdraw', { entry_id: entry.id, reason: 'Desistência pelo portal', channel: 'WEB' });
      toast({ title: 'Desistência registrada', description: `${r.message} Protocolo ${r.protocol}.`, tone: 'success' });
      refresh();
    } catch (e) {
      toast({ title: 'Não foi possível desistir', description: (e as Error).message, tone: 'error' });
    }
  };
  const actions: { key: SheetKind; icon: typeof Baby; label: string; hint: string }[] = [
    { key: 'child', icon: Baby, label: 'Nasceu ou chegou uma criança', hint: 'Inclui na hora e já pode entrar na fila' },
    { key: 'adult', icon: UserPlus, label: 'Novo responsável', hint: 'Pai, mãe, avós, companheiro(a)…' },
    { key: 'move', icon: Home, label: 'Mudança de endereço', hint: 'Recalcula a fila e mostra unidades perto' },
    { key: 'origin', icon: Plane, label: 'Chegamos de outra cidade', hint: 'Vaga por transferência de outro município' },
    { key: 'update', icon: PencilLine, label: 'Atualizar dados', hint: 'Telefone, e-mail, CadÚnico, mãe solo' },
    { key: 'service', icon: ClipboardList, label: 'Outros pedidos', hint: 'Turno, transporte, declarações, AEE…' },
  ];
  return (
    <div>
      <PageHeader eyebrow="Minha família" title={g.name}
        subtitle="O que muda na família você resolve aqui ou pela IARA no WhatsApp — o resultado é o mesmo. A IARA resolve na hora o que é dela e encaminha o resto para quem decide." />
      <Card className="mb-4 p-4">
        <div className="flex items-start gap-3">
          <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-purple-100 text-purple-800"><Home className="size-5" /></span>
          <div className="min-w-0 flex-1">
            <div className="text-[11.5px] font-bold uppercase tracking-wide text-subtle">Endereço da família</div>
            <div className="font-semibold">{g.address?.street && g.address.street !== 'Endereço informado' ? `${g.address.street}${g.address.number ? ', ' + g.address.number : ''} · ` : ''}{g.address?.neighborhood ?? '—'}</div>
            <div className="mt-1.5 flex flex-wrap gap-1.5">
              <Badge tone={g.cadunico ? 'purple' : 'gray'}>{g.cadunico ? 'CadÚnico' : 'Sem CadÚnico'}</Badge>
              {g.single_mother && <Badge tone="purple">Mãe solo</Badge>}
              <Badge tone="gray">{g.whatsapp ?? g.phone ?? 'sem telefone'}</Badge>
            </div>
          </div>
        </div>
      </Card>

      <Section title="O que mudou na família?" className="mt-0">
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {actions.map((a) => (
            <button key={a.key} onClick={() => { setService(null); setSheet(a.key); }} className="flex min-h-[96px] flex-col items-start gap-1.5 rounded-3xl bg-white p-3 text-left shadow-soft ring-1 ring-line/70 transition hover:ring-purple-200 active:scale-[0.98]">
              <span className="inline-flex size-9 items-center justify-center rounded-2xl bg-purple-50 text-purple-700"><a.icon className="size-5" /></span>
              <span className="text-[13.5px] font-bold leading-tight">{a.label}</span>
              <span className="text-[11.5px] leading-tight text-muted">{a.hint}</span>
            </button>
          ))}
        </div>
      </Section>

      <Section title={`Crianças (${kids.length})`}>
        {kids.length ? (
          <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
            {kids.map((k) => {
              const q = (k.queue ?? [])[0];
              return (
                <Card key={k.id} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="font-display text-[16px] font-extrabold leading-tight">{k.name}</div>
                      <div className="text-[12.5px] text-muted">{k.age} · {REL_NAME[k.relationship] ?? k.relationship?.toLowerCase()}</div>
                    </div>
                    <Badge tone={k.school ? 'green' : q ? 'purple' : 'gray'}>{STUDENT_STATUS[k.status] ?? k.status}</Badge>
                  </div>
                  {k.school && <p className="mt-2 text-[13px] text-ink-2">Estuda {k.school.unit} · {k.school.class} · {SHIFT[k.school.shift] ?? k.school.shift}</p>}
                  {q && <p className="mt-2 text-[13px] text-ink-2">Fila de {q.grade} · {q.unit}: <b>{q.position ? `${q.position}º` : q.status === 'OFFERED' ? 'oferta aguardando você' : 'aceite registrado'}</b>{q.score != null ? ` · ${Number(q.score)} pontos` : ''}</p>}
                  {!k.school && !q && <p className="mt-2 text-[13px] text-muted">{k.grade_rule?.ok ? `Faixa pela data de corte: ${k.grade_rule.grade_name}.` : k.grade_rule?.explanation ?? ''}</p>}
                  <div className="mt-3 flex flex-wrap gap-2">
                    {!k.school && !q && k.grade_rule?.ok && <ButtonLink to={`/vagas?aluno=${k.id}`} size="sm" variant="purple" icon={Search}>Inscrever na fila</ButtonLink>}
                    {k.school && !q && <ButtonLink to={`/vagas?aluno=${k.id}`} size="sm" variant="secondary" icon={ArrowRightLeft}>Pedir transferência</ButtonLink>}
                    {q?.status === 'WAITING' && <Button size="sm" variant="ghost" onClick={() => withdraw(q, k)}>Desistir da fila</Button>}
                  </div>
                </Card>
              );
            })}
          </div>
        ) : <Card><EmptyState compact title="Nenhuma criança no cadastro" body="Inclua a criança para pedir vaga." action={<Button variant="purple" icon={Baby} onClick={() => setSheet('child')}>Incluir criança</Button>} /></Card>}
      </Section>

      <Section title="Vida escolar" subtitle="Frequência, justificativa de faltas, cardápio com as restrições e avisos da escola"
        action={<Link to="/escola" className="text-[13px] font-semibold text-blue-700">Abrir</Link>}>
        <VidaEscolarResumo />
      </Section>

      {adults.length > 0 && (
        <Section title="Outros responsáveis">
          <Card className="divide-y divide-line">
            {adults.map((a) => (
              <div key={a.id} className="flex items-center gap-3 px-4 py-3">
                <Users className="size-5 text-blue-700" />
                <div className="min-w-0 flex-1"><div className="truncate font-semibold">{a.name}</div><div className="text-[12.5px] text-muted">{((a.relationships ?? []) as string[]).map((r) => REL_NAME[r] ?? r.toLowerCase()).join(', ')}</div></div>
                {a.legal_authority === 'PENDENTE' && <Badge tone="amber">guarda em validação</Badge>}
              </div>
            ))}
          </Card>
        </Section>
      )}

      <Section title="Pedidos recentes" action={<Link to="/protocolos" className="text-[13px] font-semibold text-blue-700">Ver todos</Link>}>
        {(d.recent ?? []).length ? (
          <Card className="divide-y divide-line">
            {(d.recent as any[]).map((c) => (
              <Link key={c.id} to={`/atendimentos/${c.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <ClipboardList className="size-5 shrink-0 text-subtle" />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{c.subject}</div>
                  <div className="truncate text-[12.5px] text-muted">{c.protocol} · {fmtDate(c.opened_at)} · {c.resolution === 'RESOLVIDO_IARA' ? 'resolvido na hora' : c.team_label}</div>
                </div>
                <Badge tone={c.resolution === 'RESOLVIDO_IARA' ? 'green' : LEVEL[c.level]?.tone ?? 'gray'}>{c.resolution === 'RESOLVIDO_IARA' ? 'Resolvido' : LEVEL[c.level]?.label ?? c.status}</Badge>
              </Link>
            ))}
          </Card>
        ) : <Card><EmptyState compact title="Nenhum pedido ainda" /></Card>}
      </Section>

      <IaraBubble compact className="mt-6">
        No WhatsApp é igual: diga “mudei de endereço”, “nasceu meu filho” ou “chegamos de outra cidade” e eu resolvo na hora. <Link to="/iara" className="font-bold text-purple-700 underline">Conversar com a IARA</Link>
      </IaraBubble>
      <WhatsAppCard className="mt-4" title="Toda a família pode falar com a IARA" subtitle="Pai, mãe, avós ou quem cuida das crianças: compartilhe o número e o link de conversa. Quem não é responsável legal tem a guarda conferida pela unidade ou pela Central." />

      <ChildSheet open={sheet === 'child' || sheet === 'origin'} origin={sheet === 'origin'} onClose={() => setSheet(null)} onDone={refresh} />
      <AdultSheet open={sheet === 'adult'} kids={kids} singleMother={!!g.single_mother} onClose={() => setSheet(null)} onDone={refresh} onReviewSolo={() => setSheet('update')} />
      <MoveSheet open={sheet === 'move'} onClose={() => setSheet(null)} onDone={refresh} />
      <UpdateSheet open={sheet === 'update'} guardian={g} onClose={() => setSheet(null)} onDone={refresh} />
      <ServiceSheet open={sheet === 'service'} services={d.services ?? []} kids={kids} initial={service} onClose={() => setSheet(null)} onDone={refresh}
        onOpen={(k) => setSheet(k)} />
    </div>
  );
}

// ============================================================================ folhas (as mesmas funções da IARA)
function ChildSheet({ open, origin, onClose, onDone }: { open: boolean; origin: boolean; onClose: () => void; onDone: () => void }) {
  const toast = useToast();
  const [name, setName] = useState('');
  const [birth, setBirth] = useState('');
  const [rel, setRel] = useState('MAE');
  const [aee, setAee] = useState(false);
  const [city, setCity] = useState('');
  const [school, setSchool] = useState('');
  const [busy, setBusy] = useState(false);
  const [out, setOut] = useState<any>(null);
  const close = () => { setOut(null); setName(''); setBirth(''); setAee(false); setCity(''); setSchool(''); onClose(); };
  const submit = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('family_add_child', {
        full_name: name.trim(), birth_date: birth, relationship: rel, aee, channel: 'WEB',
        origin: origin && city.trim() ? { city: city.trim(), school: school.trim() || null } : null,
      });
      setOut(r);
      if (r.ok !== false) onDone();
    } catch (e) {
      toast({ title: 'Inclusão não realizada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const vagaLink = out?.student_id ? `/vagas?aluno=${out.student_id}${origin && city.trim() ? `&origem=${encodeURIComponent(city.trim())}` : ''}` : '';
  return (
    <Sheet open={open} onClose={close} title={origin ? 'Chegamos de outra cidade' : 'Nasceu ou chegou uma criança'}
      subtitle={origin ? 'Inclua a criança e faça a inscrição na fila como transferência de outro município.' : 'A faixa (creche, pré-escola ou ano) sai da data de nascimento.'}
      footer={out ? <Button block variant="secondary" onClick={close}>Fechar</Button>
        : <Button block size="lg" variant="purple" icon={Baby} loading={busy} disabled={name.trim().split(/\s+/).length < 2 || !birth} onClick={submit}>Incluir na família</Button>}>
      {out ? (
        out.ok === false ? (
          <div className="rounded-3xl bg-amber-50 p-4 text-[14px] text-amber-950 ring-1 ring-amber-200">{out.message}</div>
        ) : (
          <ResultBox>
            <div><b>{out.first_name}</b> {out.existing ? 'já estava' : 'foi incluída(o)'} na família ✅{out.protocol ? ` Protocolo ${out.protocol}.` : ''}</div>
            <div>{out.grade_rule?.ok ? <>Faixa pela data de corte: <b>{out.grade_rule.grade_name}</b>.</> : out.grade_rule?.explanation}</div>
            {aee && <div className="text-[13px]">Envie o laudo médico com CID: a prioridade fica sob análise da Central de Vagas, fora da soma de pontos (IN nº 025/2025).</div>}
            {out.grade_rule?.ok && <ButtonLink to={vagaLink} variant="purple" icon={Search} block>Escolher unidade e inscrever na fila</ButtonLink>}
          </ResultBox>
        )
      ) : (
        <div className="space-y-3 pt-1">
          <Field label="Nome completo da criança"><input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} placeholder="Nome e sobrenome" /></Field>
          <Field label="Data de nascimento"><input type="date" value={birth} onChange={(e) => setBirth(e.target.value)} className={inputCls} max={new Date().toISOString().slice(0, 10)} /></Field>
          <Field label="Seu parentesco com a criança">
            <select value={rel} onChange={(e) => setRel(e.target.value)} className={inputCls}>{REL_CHILD.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          </Field>
          <Toggle checked={aee} onChange={setAee} label="Deficiência, TEA, TGD ou altas habilidades (com laudo)" hint="Prioridade sob análise da Central de Vagas, fora da soma de pontos." />
          {origin && (
            <>
              <Field label="De qual cidade vieram?"><input value={city} onChange={(e) => setCity(e.target.value)} className={inputCls} placeholder="Ex.: Londrina" /></Field>
              <Field label="Escola ou CMEI anterior (opcional)"><input value={school} onChange={(e) => setSchool(e.target.value)} className={inputCls} placeholder="Nome da unidade" /></Field>
            </>
          )}
        </div>
      )}
    </Sheet>
  );
}

function AdultSheet({ open, kids, singleMother, onClose, onDone, onReviewSolo }: { open: boolean; kids: any[]; singleMother: boolean; onClose: () => void; onDone: () => void; onReviewSolo: () => void }) {
  const toast = useToast();
  const [name, setName] = useState('');
  const [rel, setRel] = useState('PAI');
  const [together, setTogether] = useState(true);
  const [busy, setBusy] = useState(false);
  const [out, setOut] = useState<any>(null);
  const close = () => { setOut(null); setName(''); onClose(); };
  const submit = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('family_add_adult', { full_name: name.trim(), relationship: rel, lives_together: together, channel: 'WEB', student_ids: kids.map((k) => k.id) });
      setOut(r);
      onDone();
    } catch (e) {
      toast({ title: 'Inclusão não realizada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={close} title="Novo responsável" subtitle="Quem não é pai nem mãe (ex.: avó com guarda) é validado pela unidade com o documento de guarda."
      footer={out ? <Button block variant="secondary" onClick={close}>Fechar</Button>
        : <Button block size="lg" variant="purple" icon={UserPlus} loading={busy} disabled={name.trim().split(/\s+/).length < 2} onClick={submit}>Incluir responsável</Button>}>
      {out ? (
        <ResultBox>
          <div>{out.message}</div>
          {out.escalated && <Badge tone="blue">Encaminhado: {out.routed_to?.team_label}</Badge>}
          {out.review_single_mother && singleMother && (
            <div className="rounded-2xl bg-white p-3 ring-1 ring-purple-200">
              Você tinha declarado <b>mãe solo</b>. Quer revisar essa informação? (critério de 5 pontos)
              <Button className="mt-2" size="sm" variant="soft" onClick={onReviewSolo}>Revisar declarações</Button>
            </div>
          )}
        </ResultBox>
      ) : (
        <div className="space-y-3 pt-1">
          <Field label="Nome completo"><input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} placeholder="Nome e sobrenome" /></Field>
          <Field label="Parentesco com as crianças">
            <select value={rel} onChange={(e) => setRel(e.target.value)} className={inputCls}>{REL_ADULT.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          </Field>
          <Toggle checked={together} onChange={setTogether} label="Mora com a família" />
        </div>
      )}
    </Sheet>
  );
}

function MoveSheet({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const toast = useToast();
  const [place, setPlace] = useState<Place | null>(null);
  const [street, setStreet] = useState('');
  const [number, setNumber] = useState('');
  const [busy, setBusy] = useState(false);
  const [out, setOut] = useState<any>(null);
  const close = () => { setOut(null); setPlace(null); setStreet(''); setNumber(''); onClose(); };
  const submit = async () => {
    if (!place) return;
    setBusy(true);
    try {
      const r = await rpc<any>('family_move', {
        channel: 'WEB',
        address: { neighborhood: place.label, lat: place.lat, lng: place.lng, street: street.trim() || null, number: number.trim() || null, precision: place.kind === 'BAIRRO' ? 'BAIRRO' : 'UNIDADE_PROXIMA' },
      });
      setOut(r);
      onDone();
    } catch (e) {
      toast({ title: 'Endereço não atualizado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={close} title="Mudança de endereço" subtitle="A fila é recalculada na hora (critério de até 2 km). O comprovante é conferido na matrícula."
      footer={out ? <Button block variant="secondary" onClick={close}>Fechar</Button>
        : <Button block size="lg" variant="purple" icon={Home} loading={busy} disabled={!place} onClick={submit}>Atualizar endereço</Button>}>
      {out ? (
        <ResultBox>
          <div>Endereço atualizado ✅ Protocolo <b>{out.protocol}</b>. {out.previous?.neighborhood ? `${out.previous.neighborhood} → ` : ''}<b>{out.address?.neighborhood}</b></div>
          <Impacts impacts={out.impacts ?? []} />
          {((out.enrolled ?? []) as any[]).map((e) => (
            <div key={e.student_id} className="rounded-2xl bg-white p-3 ring-1 ring-line">
              <div className="font-semibold">{e.child} estuda {e.unit}</div>
              <div className="text-[12.5px] text-muted">{fmtKm(e.distance_m)} da nova casa</div>
              {((e.nearby ?? []) as any[]).map((u: any) => <div key={u.unit_id} className="text-[13px]">• {u.unit} · {fmtKm(u.distance_m)} · {u.offerable} vaga(s)</div>)}
              {e.distance_m > 2000 && <ButtonLink className="mt-2" size="sm" variant="secondary" icon={ArrowRightLeft} to={`/vagas?aluno=${e.student_id}`}>Pedir transferência</ButtonLink>}
            </div>
          ))}
        </ResultBox>
      ) : (
        <div className="space-y-3 pt-1">
          <Field label="Novo bairro (Maringá)"><BairroPicker value={place} onPick={setPlace} /></Field>
          <div className="grid grid-cols-[1fr_7rem] gap-2">
            <Field label="Rua (opcional)"><input value={street} onChange={(e) => setStreet(e.target.value)} className={inputCls} /></Field>
            <Field label="Número"><input value={number} onChange={(e) => setNumber(e.target.value)} className={inputCls} inputMode="numeric" /></Field>
          </div>
          <p className="text-[12.5px] text-muted">Vai sair de Maringá? Use “Outros pedidos → Declarações” para pedir a declaração de transferência à unidade.</p>
        </div>
      )}
    </Sheet>
  );
}

function UpdateSheet({ open, guardian, onClose, onDone }: { open: boolean; guardian: any; onClose: () => void; onDone: () => void }) {
  const toast = useToast();
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [cad, setCad] = useState<boolean>(!!guardian?.cadunico);
  const [solo, setSolo] = useState<boolean>(!!guardian?.single_mother);
  const [busy, setBusy] = useState(false);
  const [out, setOut] = useState<any>(null);
  const close = () => { setOut(null); setPhone(''); setEmail(''); onClose(); };
  const payload = useMemo(() => {
    const p: Record<string, unknown> = { channel: 'WEB' };
    if (phone.trim()) p.phone = phone.trim();
    if (email.trim()) p.email = email.trim();
    if (cad !== !!guardian?.cadunico) p.cadunico = cad;
    if (solo !== !!guardian?.single_mother) p.single_mother = solo;
    return p;
  }, [phone, email, cad, solo, guardian]);
  const changed = Object.keys(payload).length > 1;
  const submit = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('family_update', payload);
      setOut(r);
      onDone();
    } catch (e) {
      toast({ title: 'Dados não atualizados', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={close} title="Atualizar dados" subtitle="Declarações entram na fila na hora e são conferidas com os comprovantes na matrícula."
      footer={out ? <Button block variant="secondary" onClick={close}>Fechar</Button>
        : <Button block size="lg" variant="purple" icon={PencilLine} loading={busy} disabled={!changed} onClick={submit}>Salvar</Button>}>
      {out ? (
        <ResultBox>
          <div>{out.protocol ? <>Atualizado ✅ Protocolo <b>{out.protocol}</b>.</> : out.message}</div>
          <Impacts impacts={((out.impacts ?? []) as any[]).filter((i) => i.changed)} />
          {out.documents_note && <div className="text-[13px]">{out.documents_note}</div>}
        </ResultBox>
      ) : (
        <div className="space-y-3 pt-1">
          <Field label="Novo telefone / WhatsApp (opcional)" hint={`Atual: ${guardian?.whatsapp ?? guardian?.phone ?? '—'}`}>
            <input value={phone} onChange={(e) => setPhone(e.target.value)} className={inputCls} placeholder="(44) 99999-1234" inputMode="tel" />
          </Field>
          <Field label="Novo e-mail (opcional)"><input value={email} onChange={(e) => setEmail(e.target.value)} className={inputCls} placeholder="nome@email.com" inputMode="email" /></Field>
          <Toggle checked={cad} onChange={setCad} label="Família inscrita no CadÚnico" hint="25 pontos na fila" />
          <Toggle checked={solo} onChange={setSolo} label="Mãe solo" hint="5 pontos na fila" />
        </div>
      )}
    </Sheet>
  );
}

const IARA_SHEET: Record<string, SheetKind> = { MUDANCA_ENDERECO: 'move', INCLUSAO_MEMBRO: 'child', ATUALIZACAO_CADASTRAL: 'update', TRANSFERENCIA_EXTERNA: 'origin' };
const ENROLLED_ONLY = new Set(['TROCA_TURNO', 'DOCUMENTO', 'INTEGRAL', 'ALIMENTACAO']);
const NO_CHILD = new Set(['RECLAMACAO', 'DUVIDA']);

function ServiceSheet({ open, services, kids, initial, onClose, onDone, onOpen }: {
  open: boolean; services: any[]; kids: any[]; initial: string | null; onClose: () => void; onDone: () => void; onOpen: (k: SheetKind) => void;
}) {
  const toast = useToast();
  const [code, setCode] = useState<string | null>(initial);
  const [kidId, setKidId] = useState<string>('');
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [out, setOut] = useState<any>(null);
  const svc = services.find((s) => s.code === code);
  const eligibleKids = kids.filter((k) => !code || !ENROLLED_ONLY.has(code) || k.school);
  const avail = useRpc<any>('shift_availability', { student_id: kidId }, { enabled: open && code === 'TROCA_TURNO' && !!kidId });
  const close = () => { setOut(null); setCode(null); setKidId(''); setText(''); onClose(); };
  const listed = services.filter((s) => !['SOLICITACAO_VAGA', 'TRANSFERENCIA', 'DESISTENCIA', 'MATRICULA'].includes(s.code));
  const submit = async () => {
    if (!code) return;
    setBusy(true);
    try {
      const k = kids.find((x) => x.id === kidId);
      const r = await rpc<any>('case_create', {
        case_type: code, channel: 'WEB', student_id: kidId || null, subject: `${svc?.name ?? code}${k ? ` — ${k.first_name}` : ''}`,
        description: text.trim() || `Pedido de ${String(svc?.name ?? code).toLowerCase()} pelo portal.`,
        details: { canal: 'WEB', verificacao: code === 'TROCA_TURNO' && avail.data ? avail.data.options : null },
      });
      setOut(r);
      onDone();
    } catch (e) {
      toast({ title: 'Pedido não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const needsKid = !!code && !NO_CHILD.has(code);
  const kid = kids.find((x) => x.id === kidId);
  return (
    <Sheet open={open} onClose={close} title={svc ? svc.name : 'Outros pedidos'}
      subtitle={svc ? svc.iara_action : 'O que é da alçada da IARA sai na hora; o resto vai direto para quem decide, com protocolo e prazo.'}
      footer={out ? <Button block variant="secondary" onClick={close}>Fechar</Button>
        : code ? <Button block size="lg" variant="purple" icon={Send} loading={busy} disabled={needsKid && !kidId} onClick={submit}>Enviar pedido</Button> : undefined}>
      {out ? (
        <ResultBox>
          <div>Pedido registrado ✅ Protocolo <b>{out.protocol}</b>.</div>
          <div>Encaminhado para a <b>{out.routed_to?.team_label}</b> — {out.routed_to?.level === 'UNIDADE' ? 'essa decisão é da unidade' : 'essa decisão é da Secretaria (SEDUC)'}. Prazo de até {out.routed_to?.sla_days} dia(s).</div>
          {out.escalation && <div className="text-[13px]">{out.escalation}</div>}
        </ResultBox>
      ) : !code ? (
        <div className="space-y-2 pt-1">
          {listed.map((s) => (
            <button key={s.code} onClick={() => (IARA_SHEET[s.code] ? onOpen(IARA_SHEET[s.code]) : setCode(s.code))}
              className="flex w-full items-start gap-3 rounded-2xl bg-white p-3 text-left ring-1 ring-line hover:bg-purple-50">
              <div className="min-w-0 flex-1">
                <div className="font-semibold">{s.name}</div>
                <div className="text-[12.5px] text-muted">{s.level === 'IARA' ? s.iara_action : s.escalation}</div>
              </div>
              <Badge tone={LEVEL[s.level]?.tone ?? 'gray'}>{LEVEL[s.level]?.label ?? s.level}</Badge>
            </button>
          ))}
        </div>
      ) : (
        <div className="space-y-3 pt-1">
          <div className="rounded-2xl bg-slate-50 p-3 text-[13px] text-ink-2">
            <Badge tone={LEVEL[svc?.level]?.tone ?? 'gray'}>{LEVEL[svc?.level]?.label}</Badge>
            <div className="mt-1.5"><b>A IARA faz na hora:</b> {svc?.iara_action}</div>
            {svc?.escalation && <div className="mt-1"><b>Quem decide:</b> {svc.escalation}</div>}
          </div>
          {needsKid && (
            <Field label="Para qual criança?">
              <select value={kidId} onChange={(e) => setKidId(e.target.value)} className={inputCls}>
                <option value="">Escolha</option>
                {eligibleKids.map((k) => <option key={k.id} value={k.id}>{k.first_name}</option>)}
              </select>
            </Field>
          )}
          {needsKid && !eligibleKids.length && <p className="text-[13px] text-amber-800">Esse pedido é para criança com matrícula ativa na rede.</p>}
          {code === 'TROCA_TURNO' && avail.data?.enrolled && (
            <div className="rounded-2xl bg-blue-50 p-3 text-[13px] text-blue-950 ring-1 ring-blue-100">
              {kid?.first_name} estuda à {SHIFT[avail.data.current_shift] ?? avail.data.current_shift} ({avail.data.class}).{' '}
              {(avail.data.options as any[]).filter((o) => o.offerable > 0).length
                ? <>Na mesma série há vaga: {(avail.data.options as any[]).filter((o) => o.offerable > 0).map((o) => `${SHIFT[o.shift] ?? o.shift} (${o.offerable})`).join(', ')}.</>
                : (avail.data.options as any[]).length ? 'No momento não há vaga no outro turno da mesma série.' : 'Essa série só tem turmas neste turno.'}
            </div>
          )}
          {code === 'DOCUMENTO' && kid?.school && (
            <div className="rounded-2xl bg-blue-50 p-3 text-[13px] text-blue-950 ring-1 ring-blue-100">
              Situação: <b>matrícula ativa</b> · {kid.school.unit} · {kid.school.class} · {SHIFT[kid.school.shift] ?? kid.school.shift}. A declaração oficial assinada é emitida pela secretaria da unidade.
            </div>
          )}
          <Field label="Conte em poucas palavras (opcional)">
            <textarea value={text} onChange={(e) => setText(e.target.value)} rows={3} className={clsx(inputCls, 'h-auto py-3')} placeholder="O que você precisa?" />
          </Field>
          <button onClick={() => setCode(null)} className="text-[13px] font-semibold text-blue-700">← outros pedidos</button>
        </div>
      )}
    </Sheet>
  );
}

export function FamilyShortcut() {
  return (
    <Link to="/familia" className="flex items-center gap-3 rounded-3xl bg-gradient-to-br from-purple-50 to-blue-50 p-4 ring-1 ring-purple-100 hover:ring-purple-300">
      <MessageCircle className="size-5 text-purple-700" />
      <span className="text-[14px] font-semibold">Mudou algo na família? Atualize aqui ou pela IARA</span>
    </Link>
  );
}
