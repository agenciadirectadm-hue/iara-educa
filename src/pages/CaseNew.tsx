import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { AnimatePresence, motion } from 'motion/react';
import clsx from 'clsx';
import { ArrowLeft, ArrowRight, Baby, CheckCircle2, MapPin, Search, UserPlus, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { CHANNEL } from '@/lib/labels';
import { Avatar, Badge, Button, ButtonLink, Card, Field, PageHeader, Simulado, Spinner, inputCls } from '@/components/ui';
import { useToast } from '@/components/overlays';
import { Crumbs } from '@/components/Crumbs';

type Step = 0 | 1 | 2 | 3;
const CHANNELS = ['PRESENCIAL', 'TELEFONE', 'WHATSAPP', 'WEB', 'ESCOLA', 'CMEI', 'EMAIL'];

/** Abertura de atendimento em etapas (fluxos extensos divididos para o celular — spec §75.4). */
export default function CaseNew() {
  const [sp] = useSearchParams();
  const navigate = useNavigate();
  const toast = useToast();
  const { me } = useSession();
  const catalog = useRpc<any>('service_catalog');
  const [step, setStep] = useState<Step>(0);
  const [type, setType] = useState(sp.get('tipo') ?? 'SOLICITACAO_VAGA');
  const [channel, setChannel] = useState('PRESENCIAL');
  const [student, setStudent] = useState<{ id: string; name: string } | null>(null);
  const [guardian, setGuardian] = useState<{ id: string; name: string } | null>(null);
  const [subject, setSubject] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState('NORMAL');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<any>(null);
  const idem = useMemo(() => crypto.randomUUID(), []);
  const preStudent = sp.get('aluno');
  const pre = useRpc<any>('student_detail', { student_id: preStudent }, { enabled: !!preStudent });
  useEffect(() => {
    if (pre.data && !student) {
      setStudent({ id: pre.data.student.id, name: pre.data.student.full_name });
      const g = pre.data.guardians?.[0];
      if (g) setGuardian({ id: g.id, name: g.full_name });
    }
  }, [pre.data, student]);
  const svc = (catalog.data?.items ?? []).find((s: any) => s.code === type);
  useEffect(() => {
    if (svc && !subject) setSubject(svc.name + (student ? ` — ${student.name.split(' ')[0]}` : ''));
  }, [svc, student, subject]);

  const submit = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('case_create', {
        case_type: type, channel, student_id: student?.id ?? null, guardian_id: guardian?.id ?? null, subject, description, priority,
        unit_id: me?.unit?.id ?? null, idempotency_key: idem,
      });
      setDone(r);
      toast({ title: `Protocolo ${r.protocol} registrado`, tone: 'success' });
    } catch (e) {
      toast({ title: 'Protocolo não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  if (done) {
    return (
      <div className="mx-auto max-w-lg py-6 text-center">
        <motion.div initial={{ scale: 0.6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="mx-auto inline-flex size-20 items-center justify-center rounded-full bg-green-100">
          <CheckCircle2 className="size-11 text-green-700" />
        </motion.div>
        <h1 className="mt-4 font-display text-2xl font-extrabold">Protocolo registrado</h1>
        <p className="mt-1 font-display text-3xl font-black tabular text-purple-800">{done.protocol}</p>
        <Card className="mt-5 p-4 text-left">
          <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Próximos passos</div>
          <ul className="mt-2 space-y-1.5 text-[14.5px]">{(done.next_steps ?? []).filter(Boolean).map((s: string) => <li key={s}>• {s}</li>)}</ul>
          <p className="mt-3 text-[12.5px] text-muted">O responsável recebeu a confirmação no portal<Simulado detail="Aviso simulado: nenhuma mensagem real é enviada." />. Tudo registrado na auditoria.</p>
        </Card>
        <div className="mt-5 flex flex-col gap-2">
          {type === 'SOLICITACAO_VAGA' && student && <ButtonLink to={`/vagas?aluno=${student.id}&protocolo=${done.case_id}`} variant="purple" size="lg">Buscar vaga agora</ButtonLink>}
          <ButtonLink to={`/atendimentos/${done.case_id}`} variant="secondary" size="lg">Abrir protocolo</ButtonLink>
          <Button variant="ghost" onClick={() => navigate(0)}>Registrar outro</Button>
        </div>
      </div>
    );
  }

  const steps = ['Serviço', 'Criança e responsável', 'Detalhes', 'Revisão'];
  const canNext = step === 0 ? !!type : step === 1 ? (type === 'DUVIDA' || type === 'RECLAMACAO' || !!guardian) : step === 2 ? subject.trim().length >= 4 : true;
  return (
    <div className="mx-auto max-w-2xl">
      <Crumbs items={[{ label: 'Atendimentos', to: '/atendimentos' }, { label: 'Novo' }]} />
      <PageHeader title="Novo atendimento" subtitle="Registre o pedido em poucos passos. Nada é salvo até a confirmação final." />
      <ol className="mb-5 grid grid-cols-4 gap-1.5">
        {steps.map((s, i) => (
          <li key={s} className="text-center">
            <div className={clsx('h-1.5 rounded-full', i <= step ? 'bg-purple-600' : 'bg-slate-200')} />
            <div className={clsx('mt-1.5 text-[11px] font-semibold', i === step ? 'text-purple-800' : 'text-muted')}>{s}</div>
          </li>
        ))}
      </ol>
      <AnimatePresence mode="wait">
        <motion.div key={step} initial={{ opacity: 0, x: 24 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -24 }} transition={{ duration: 0.2 }}>
          {step === 0 && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {(catalog.data?.items ?? []).map((s: any) => (
                  <button key={s.code} onClick={() => { setType(s.code); setSubject(''); }} className={clsx('rounded-2xl p-3 text-left ring-1 transition', type === s.code ? 'bg-purple-50 ring-2 ring-purple-500' : 'bg-white ring-line hover:bg-slate-50')}>
                    <div className="text-[14px] font-semibold leading-tight">{s.name}</div>
                    <div className="mt-1 text-[11.5px] text-muted">{s.sector} · {s.sla_days} dia(s)</div>
                  </button>
                ))}
                {catalog.isLoading && <Spinner />}
              </div>
              <Field label="Canal de entrada">
                <div className="no-scrollbar flex gap-2 overflow-x-auto pb-1">
                  {CHANNELS.map((c) => (
                    <button key={c} onClick={() => setChannel(c)} className={clsx('h-10 shrink-0 rounded-full px-4 text-[13px] font-semibold ring-1', channel === c ? 'bg-blue-900 text-white ring-blue-900' : 'bg-white ring-line')}>{CHANNEL[c]}</button>
                  ))}
                </div>
              </Field>
              {svc && <p className="rounded-2xl bg-slate-50 p-3 text-[13px] text-muted">{svc.description} {svc.requirements ? `Requisitos: ${svc.requirements}` : ''}</p>}
            </div>
          )}
          {step === 1 && <PeopleStep student={student} setStudent={setStudent} guardian={guardian} setGuardian={setGuardian} />}
          {step === 2 && (
            <div className="space-y-4">
              <Field label="Assunto"><input value={subject} onChange={(e) => setSubject(e.target.value)} className={inputCls} /></Field>
              <Field label="Descrição" hint="Linguagem simples; evite dados sensíveis desnecessários.">
                <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4} className={`${inputCls} h-auto py-3`} />
              </Field>
              <Field label="Prioridade">
                <div className="flex gap-2">
                  {['NORMAL', 'ALTA', 'URGENTE'].map((p) => (
                    <button key={p} onClick={() => setPriority(p)} className={clsx('h-11 flex-1 rounded-2xl text-[14px] font-semibold ring-1', priority === p ? (p === 'NORMAL' ? 'bg-blue-900 text-white' : 'bg-red-600 text-white') : 'bg-white ring-line')}>{p === 'NORMAL' ? 'Normal' : p === 'ALTA' ? 'Alta' : 'Urgente'}</button>
                  ))}
                </div>
              </Field>
            </div>
          )}
          {step === 3 && (
            <Card className="divide-y divide-line">
              {[
                ['Serviço', svc?.name], ['Canal', CHANNEL[channel]], ['Criança', student?.name ?? '—'], ['Responsável', guardian?.name ?? '—'],
                ['Assunto', subject], ['Prioridade', priority.toLowerCase()], ['Prazo (SLA)', `${svc?.sla_days ?? '—'} dia(s) · ${svc?.sector ?? ''}`],
              ].map(([k, v]) => (
                <div key={k} className="flex justify-between gap-3 px-4 py-3 text-[14px]"><span className="text-muted">{k}</span><span className="text-right font-semibold">{v}</span></div>
              ))}
            </Card>
          )}
        </motion.div>
      </AnimatePresence>
      <div className="sticky bottom-[84px] z-10 mt-6 flex gap-2 rounded-3xl bg-white/90 p-2 shadow-soft ring-1 ring-line backdrop-blur lg:bottom-4">
        {step > 0 && <Button variant="secondary" size="lg" icon={ArrowLeft} onClick={() => setStep((step - 1) as Step)}>Voltar</Button>}
        {step < 3 ? (
          <Button className="flex-1" size="lg" disabled={!canNext} onClick={() => setStep((step + 1) as Step)}>Continuar <ArrowRight className="size-4" /></Button>
        ) : (
          <Button className="flex-1" size="lg" variant="success" loading={busy} onClick={submit}>Registrar protocolo</Button>
        )}
      </div>
    </div>
  );
}

function PeopleStep({ student, setStudent, guardian, setGuardian }: any) {
  const toast = useToast();
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const search = useRpc<any>('global_search', { q: dq }, { enabled: dq.length >= 3 });
  const [newKid, setNewKid] = useState(false);
  const [newGuardian, setNewGuardian] = useState(false);
  const [form, setForm] = useState({ kid: '', birth: '', gender: '', gname: '', phone: '', cpf: '', bairro: '', cad: false, solo: false });
  const geo = useRpc<any>('geo_search', { q: form.bairro }, { enabled: form.bairro.length >= 3 && newGuardian });
  const [busy, setBusy] = useState(false);
  const [dups, setDups] = useState<any[] | null>(null);

  const createGuardian = async (force = false) => {
    setBusy(true);
    try {
      const hit = (geo.data?.items ?? []).find((i: any) => i.kind === 'BAIRRO');
      const r = await rpc<any>('guardian_create', {
        full_name: form.gname, phone: form.phone, cpf: form.cpf || null, cadunico: form.cad, single_mother: form.solo, force,
        address: hit ? { street: 'Endereço informado no atendimento', neighborhood: hit.label, lat: hit.lat, lng: hit.lng, precision: 'BAIRRO_CENTROIDE' } : undefined,
      });
      if (r.ok === false) { setDups(r.duplicates); return; }
      setGuardian({ id: r.guardian_id, name: form.gname });
      setNewGuardian(false);
      toast({ title: 'Responsável cadastrado', tone: 'success' });
    } catch (e) {
      toast({ title: 'Cadastro não concluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const createKid = async (force = false) => {
    setBusy(true);
    try {
      const r = await rpc<any>('student_create', { full_name: form.kid, birth_date: form.birth, gender: form.gender || null, guardian_id: guardian?.id ?? null, force });
      if (r.ok === false) { setDups(r.duplicates); return; }
      setStudent({ id: r.student_id, name: form.kid });
      setNewKid(false);
      toast({ title: 'Criança cadastrada e vinculada', description: r.grade_rule?.ok ? `Faixa pela regra: ${r.grade_rule.grade_name}` : r.grade_rule?.explanation, tone: 'success' });
    } catch (e) {
      toast({ title: 'Cadastro não concluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Card className={clsx('p-4', guardian && 'ring-2 ring-green-500')}>
          <div className="flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><Users className="size-4" />Responsável</div>
          {guardian ? <div className="mt-2 flex items-center gap-2"><Avatar name={guardian.name} size={34} /><span className="font-semibold">{guardian.name}</span><button className="ml-auto text-[13px] text-purple-700" onClick={() => setGuardian(null)}>trocar</button></div> : <p className="mt-1 text-[13px] text-muted">Busque ou cadastre abaixo.</p>}
        </Card>
        <Card className={clsx('p-4', student && 'ring-2 ring-green-500')}>
          <div className="flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><Baby className="size-4" />Criança</div>
          {student ? <div className="mt-2 flex items-center gap-2"><Avatar name={student.name} size={34} /><span className="font-semibold">{student.name}</span><button className="ml-auto text-[13px] text-purple-700" onClick={() => setStudent(null)}>trocar</button></div> : <p className="mt-1 text-[13px] text-muted">Opcional para dúvidas e reclamações.</p>}
        </Card>
      </div>
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar criança ou responsável já cadastrados…" className={clsx(inputCls, 'pl-11')} />
      </div>
      {dq.length >= 3 && (
        <Card className="max-h-72 divide-y divide-line overflow-y-auto">
          {search.isLoading && <div className="flex justify-center p-4"><Spinner /></div>}
          {(search.data?.students ?? []).map((s: any) => (
            <button key={s.id} onClick={async () => { setStudent({ id: s.id, name: s.name }); setQ(''); try { const d = await rpc<any>('student_detail', { student_id: s.id }); const g = d.guardians?.[0]; if (g) setGuardian({ id: g.id, name: g.full_name }); } catch { /* sem acesso */ } }} className="flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-purple-50">
              <Baby className="size-4 text-purple-700" /><div className="min-w-0 flex-1"><div className="truncate font-semibold">{s.name}</div><div className="text-[12px] text-muted">{s.sub}</div></div>
            </button>
          ))}
          {(search.data?.guardians ?? []).map((g: any) => (
            <button key={g.id} onClick={() => { setGuardian({ id: g.id, name: g.name }); setQ(''); }} className="flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-purple-50">
              <Users className="size-4 text-blue-700" /><div className="min-w-0 flex-1"><div className="truncate font-semibold">{g.name}</div><div className="text-[12px] text-muted">{g.sub}</div></div>
            </button>
          ))}
        </Card>
      )}
      <div className="flex flex-wrap gap-2">
        <Button variant="soft" icon={UserPlus} onClick={() => { setNewGuardian(true); setDups(null); }}>Novo responsável</Button>
        <Button variant="soft" icon={Baby} disabled={!guardian} onClick={() => { setNewKid(true); setDups(null); }}>Nova criança</Button>
      </div>
      {newGuardian && (
        <Card className="space-y-3 p-4">
          <Field label="Nome completo"><input value={form.gname} onChange={(e) => setForm({ ...form, gname: e.target.value })} className={inputCls} /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Telefone/WhatsApp"><input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} className={inputCls} inputMode="tel" /></Field>
            <Field label="CPF (opcional)"><input value={form.cpf} onChange={(e) => setForm({ ...form, cpf: e.target.value })} className={inputCls} inputMode="numeric" /></Field>
          </div>
          <Field label="Bairro" hint={geo.data?.items?.[0] ? `Será geocodificado pelo centro do bairro: ${geo.data.items.find((i: any) => i.kind === 'BAIRRO')?.label ?? '—'}` : 'Usado para territorialidade (distância até as unidades).'}>
            <div className="relative"><MapPin className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-subtle" /><input value={form.bairro} onChange={(e) => setForm({ ...form, bairro: e.target.value })} className={clsx(inputCls, 'pl-10')} /></div>
          </Field>
          <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={form.cad} onChange={(e) => setForm({ ...form, cad: e.target.checked })} className="size-5 accent-purple-700" />Família inscrita no CadÚnico</label>
          <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={form.solo} onChange={(e) => setForm({ ...form, solo: e.target.checked })} className="size-5 accent-purple-700" />Mãe solo (declaração do responsável)</label>
          <Button block loading={busy} disabled={form.gname.trim().length < 5} onClick={() => createGuardian(false)}>Cadastrar responsável</Button>
        </Card>
      )}
      {newKid && (
        <Card className="space-y-3 p-4">
          <Field label="Nome completo da criança"><input value={form.kid} onChange={(e) => setForm({ ...form, kid: e.target.value })} className={inputCls} /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Data de nascimento"><input type="date" value={form.birth} onChange={(e) => setForm({ ...form, birth: e.target.value })} className={inputCls} /></Field>
            <Field label="Sexo">
              <select value={form.gender} onChange={(e) => setForm({ ...form, gender: e.target.value })} className={inputCls}><option value="">Não informar</option><option value="F">Feminino</option><option value="M">Masculino</option></select>
            </Field>
          </div>
          <Button block loading={busy} disabled={form.kid.trim().length < 5 || !form.birth} onClick={() => createKid(false)}>Cadastrar e vincular</Button>
        </Card>
      )}
      {dups && (
        <Card className="p-4 ring-2 ring-amber-400">
          <div className="font-semibold text-amber-900">Possível cadastro duplicado</div>
          <p className="text-[13px] text-muted">Evite duplicidade: escolha um cadastro existente ou confirme que é outra pessoa.</p>
          <div className="mt-2 space-y-1.5">
            {dups.map((x: any) => <div key={x.id} className="flex items-center justify-between rounded-xl bg-amber-50 px-3 py-2 text-[13.5px]"><span>{x.name}</span><Badge tone="amber">{x.birth_date ?? x.phone ?? ''}</Badge></div>)}
          </div>
          <div className="mt-3 flex gap-2">
            <Button variant="secondary" onClick={() => setDups(null)}>Revisar</Button>
            <Button variant="danger" onClick={() => (newKid ? createKid(true) : createGuardian(true))}>É outra pessoa — cadastrar</Button>
          </div>
        </Card>
      )}
      <p className="text-[12px] text-muted">Dados de demonstração: use nomes fictícios. <Link to="/ajuda" className="underline">Por quê?</Link></p>
    </div>
  );
}
