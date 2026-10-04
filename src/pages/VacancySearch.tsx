import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { AnimatePresence, motion } from 'motion/react';
import clsx from 'clsx';
import {
  Accessibility, Baby, CheckCircle2, ChevronDown, Info, ListPlus, MapPin, MousePointerClick, Navigation, Search, Sparkles, Users, X,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { useUnitsMap } from '@/lib/data';
import { fmtDate, fmtInt, fmtKm } from '@/lib/format';
import { SHIFT, DOC } from '@/lib/labels';
import { Badge, Button, ButtonLink, Card, Chip, EmptyState, Field, OccupancyBar, PageHeader, SourceChip, Spinner, inputCls } from '@/components/ui';
import { useConfirm, useToast } from '@/components/overlays';
import { IaraBubble } from '@/components/iara';
import { OfferSheet } from '@/components/OfferSheet';
import MapView from '@/components/map/MapView';

const RULE_LABEL: Record<string, string> = {
  VAGA_OFERTAVEL: 'Vaga ofertável', TERRITORIO_2KM: 'Reside até 2 km', DISTANCIA: 'Distância', IRMAO_NA_UNIDADE: 'Irmão(ã) na unidade',
  AEE_UNIDADE: 'AEE na unidade', TURNO_PREFERIDO: 'Turno preferido', FILA_PRESSAO: 'Crianças à frente na fila',
};

export default function VacancySearch() {
  const [sp] = useSearchParams();
  const { me, can } = useSession();
  const studentId = sp.get('aluno');
  const caseId = sp.get('protocolo');
  const student = useRpc<any>('student_detail', { student_id: studentId }, { enabled: !!studentId });
  const citizen = useRpc<any>('citizen_home', {}, { enabled: me?.scope === 'GUARDIAN' && !!me?.guardian });
  const origin = sp.get('origem');
  const [enrolled, setEnrolled] = useState<any>(null);
  const boot = useRpc<any>('bootstrap', {}, { staleTime: 300_000 });
  const units = useUnitsMap();
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();

  const [birth, setBirth] = useState('');
  const [grade, setGrade] = useState<number | null>(null);
  const [home, setHome] = useState<{ lat: number; lng: number; label: string } | null>(null);
  const [shift, setShift] = useState<string>('');
  const [shiftRequired, setShiftRequired] = useState(false);
  const [aee, setAee] = useState(false);
  const [kid, setKid] = useState<{ id: string; name: string } | null>(null);
  const [args, setArgs] = useState<any>(null);
  const [pickOnMap, setPickOnMap] = useState(false);
  const [bairro, setBairro] = useState('');
  const dBairro = useDebounced(bairro, 280);
  const geo = useRpc<any>('geo_search', { q: dBairro }, { enabled: dBairro.length >= 2 });
  const rule = useRpc<any>('grade_for_birthdate', { birth_date: birth }, { enabled: /^\d{4}-\d{2}-\d{2}$/.test(birth) });
  const result = useRpc<any>('search_vacancies', args ?? {}, { enabled: !!args });
  const [expanded, setExpanded] = useState<number | null>(null);
  const [offerEntry, setOfferEntry] = useState<string | null>(null);
  const [busyUnit, setBusyUnit] = useState<number | null>(null);

  // pré-preenchimento: aluno do protocolo
  useEffect(() => {
    const d = student.data;
    if (!d) return;
    setKid({ id: d.student.id, name: d.student.full_name });
    setBirth(d.student.birth_date);
    setAee(!!d.student.aee);
    if (d.address?.lat) setHome({ lat: d.address.lat, lng: d.address.lng, label: `${d.address.street}, ${d.address.number} · ${d.address.neighborhood ?? ''}` });
  }, [student.data]);
  useEffect(() => {
    if (rule.data?.ok) setGrade(rule.data.grade_level_id);
  }, [rule.data]);

  const kids = (citizen.data?.children ?? []) as any[];
  const chooseKid = (c: any) => {
    setKid({ id: c.id, name: c.name });
    setBirth(c.birth_date);
    const a = citizen.data?.guardian?.address;
    if (a?.lat) setHome({ lat: a.lat, lng: a.lng, label: 'Endereço cadastrado' });
  };
  // família: a criança indicada no link (ex.: vindo de "Minha família") já vem selecionada
  useEffect(() => {
    if (me?.scope !== 'GUARDIAN' || !studentId || kid) return;
    const c = kids.find((x) => x.id === studentId);
    if (c) chooseKid(c);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [studentId, kids.length]);

  const search = () => {
    if (!grade || !home) return;
    setArgs({ grade_level_id: grade, lat: home.lat, lng: home.lng, shift: shift || null, shift_required: shiftRequired && !!shift, aee, student_id: kid?.id ?? null, limit: 8 });
    setExpanded(null);
    setTimeout(() => document.getElementById('resultados')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 150);
  };

  const res = result.data;
  const ranked = (res?.results ?? []) as any[];
  const highlight = useMemo(() => ranked.map((r) => ({ id: r.unit_id, label: String(r.rank) })), [ranked]);
  const queueByUnit = useMemo(() => {
    const m = new Map<number, any>();
    for (const q of (student.data?.queue ?? []) as any[]) if (q.status === 'WAITING') m.set(q.unit_id, q);
    return m;
  }, [student.data]);

  const insertQueue = async (r: any) => {
    if (!kid) return;
    const ok = await confirm({
      title: `Inserir na fila ${r.unit_type === 'CMEI' ? 'do' : 'da'} ${r.name}?`,
      body: <>A posição será calculada pelas regras {res?.rule_version} da IN nº 025/2025 (irmão na mesma unidade, CadÚnico, até 2 km e mãe solo; laudo em análise à parte; empate pela data). {caseId ? 'O protocolo será encerrado como "inserido na fila".' : ''}</>,
      confirm: 'Inserir na fila', tone: 'purple',
    });
    if (!ok) return;
    setBusyUnit(r.unit_id);
    try {
      const out = await rpc<any>('queue_entry_create', { student_id: kid.id, preferred_unit_id: r.unit_id, grade_level_id: grade, case_id: caseId, preferred_shift: shift || null });
      toast({ title: `Inserido na fila — posição ${out.entry.position}`, description: `${out.entry.queue_size} criança(s) nesta fila.`, tone: 'success' });
      ['student_detail', 'search_vacancies', 'case_detail', 'queue_list', 'dashboard_analista'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
    } catch (e) {
      toast({ title: 'Não foi possível inserir', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusyUnit(null);
    }
  };

  const citizenRequest = async (r: any) => {
    if (!kid) return;
    const ok = await confirm({
      title: `Inscrever ${kid.name.split(' ')[0]} na fila ${r.unit_type === 'CMEI' ? 'do' : 'da'} ${r.name}?`,
      body: <>É a inscrição na fila de espera on-line{origin ? ' (transferência de outro município)' : ''}. A posição segue a pontuação oficial da IN nº 025/2025; quando a vaga for ofertada, você terá 72 h para efetivar a matrícula na unidade.</>,
      confirm: 'Inscrever na fila', tone: 'purple',
    });
    if (!ok) return;
    setBusyUnit(r.unit_id);
    try {
      const out = await rpc<any>('queue_self_register', { student_id: kid.id, unit_id: r.unit_id, shift: shift || null, channel: 'WEB', origin: origin ? { city: origin } : null });
      setEnrolled(out);
      toast({ title: `Inscrição feita — ${out.position}º de ${out.queue_size}`, description: `Protocolo ${out.protocol} · ${Number(out.score)} de 100 pontos.`, tone: 'success' });
      ['citizen_home', 'family_overview', 'search_vacancies'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
      setTimeout(() => document.getElementById('inscricao')?.scrollIntoView({ behavior: 'smooth', block: 'center' }), 120);
    } catch (e) {
      toast({ title: 'Inscrição não realizada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusyUnit(null);
    }
  };

  const grades = (boot.data?.grades ?? []) as any[];
  return (
    <div>
      <PageHeader
        eyebrow="Busca inteligente de vaga"
        title={kid ? `Vaga para ${kid.name.split(' ')[0]}` : 'Onde há vaga perto de casa?'}
        subtitle="Ranking determinístico e explicável: cada ponto vem de uma regra com versão, fonte e evidência — nunca “recomendado por IA”."
      />

      <Card className="p-4">
        {me?.scope === 'GUARDIAN' && kids.length > 0 && (
          <div className="mb-4">
            <div className="mb-2 text-[13px] font-semibold text-ink-2">Para qual criança?</div>
            <div className="no-scrollbar flex gap-2 overflow-x-auto">
              {kids.map((c) => <Chip key={c.id} icon={Baby} active={kid?.id === c.id} onClick={() => chooseKid(c)}>{c.first_name}</Chip>)}
            </div>
          </div>
        )}
        {kid && studentId && <div className="mb-4 flex items-center gap-2 rounded-2xl bg-purple-50 p-3 text-[13.5px] text-purple-900"><Users className="size-4" />Criança do protocolo: <b>{kid.name}</b>{caseId && <Badge tone="purple">protocolo vinculado</Badge>}</div>}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Data de nascimento" hint={rule.data?.explanation}>
            <input type="date" value={birth} onChange={(e) => { setBirth(e.target.value); setGrade(null); }} className={inputCls} />
          </Field>
          <Field label="Série/faixa (pela regra da data de corte)">
            <select value={grade ?? ''} onChange={(e) => setGrade(e.target.value ? Number(e.target.value) : null)} className={inputCls}>
              <option value="">Selecione…</option>
              {grades.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
            </select>
          </Field>
        </div>
        <div className="mt-4">
          <Field label="Residência" hint={home ? 'Distâncias em linha reta a partir deste ponto.' : 'Busque o bairro ou toque no mapa para marcar o ponto.'}>
            {home ? (
              <div className="flex items-center gap-2 rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
                <MapPin className="size-5 text-purple-700" /><span className="min-w-0 flex-1 truncate text-[14px] font-semibold">{home.label}</span>
                <button onClick={() => setHome(null)} className="text-[13px] font-semibold text-purple-700">trocar</button>
              </div>
            ) : (
              <div className="relative">
                <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
                <input value={bairro} onChange={(e) => setBairro(e.target.value)} placeholder="Bairro (ex.: Jardim Alvorada)" className={clsx(inputCls, 'pl-11')} />
                {dBairro.length >= 2 && (
                  <div className="absolute inset-x-0 top-14 z-20 max-h-64 overflow-y-auto rounded-2xl bg-white shadow-lift ring-1 ring-line">
                    {geo.isLoading ? <div className="flex justify-center p-3"><Spinner /></div> : (geo.data?.items ?? []).map((it: any, i: number) => (
                      <button key={i} onClick={() => { setHome({ lat: it.lat, lng: it.lng, label: it.label }); setBairro(''); }} className="flex w-full items-center gap-2 border-b border-line px-4 py-2.5 text-left last:border-0 hover:bg-purple-50">
                        <MapPin className="size-4 text-blue-700" /><span className="truncate text-[14px]">{it.label}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </Field>
          {!home && <button onClick={() => setPickOnMap(!pickOnMap)} className="mt-2 inline-flex items-center gap-1.5 text-[13px] font-semibold text-purple-700"><MousePointerClick className="size-4" />{pickOnMap ? 'Fechar mapa' : 'Marcar no mapa'}</button>}
          {pickOnMap && !home && (
            <div className="mt-2 overflow-hidden rounded-2xl ring-1 ring-line">
              <MapView className="h-64" units={units.data?.units ?? []} showUnits onMapClick={(lat, lng) => { setHome({ lat, lng, label: 'Ponto marcado no mapa' }); setPickOnMap(false); }} fitKey="pick" cooperative />
              <p className="bg-white px-3 py-2 text-[12.5px] text-muted">Toque no mapa para marcar a residência (localização do aparelho não é usada).</p>
            </div>
          )}
        </div>
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="text-[13px] font-semibold text-ink-2">Turno:</span>
          {[['', 'Indiferente'], ['MANHA', 'Manhã'], ['TARDE', 'Tarde']].map(([v, l]) => <Chip key={v} active={shift === v} onClick={() => setShift(v)}>{l}</Chip>)}
          {shift && <label className="flex items-center gap-1.5 text-[13px]"><input type="checkbox" checked={shiftRequired} onChange={(e) => setShiftRequired(e.target.checked)} className="size-4 accent-purple-700" />obrigatório</label>}
          <Chip icon={Accessibility} active={aee} onClick={() => setAee(!aee)}>Precisa de AEE</Chip>
        </div>
        <Button className="mt-5" block size="lg" variant="purple" icon={Search} disabled={!grade || !home} loading={result.isFetching} onClick={search}>Buscar unidades</Button>
      </Card>

      <div id="resultados" className="scroll-mt-20">
        {result.error && <p className="mt-4 rounded-2xl bg-red-50 p-3 text-sm text-red-800">{result.error.message}</p>}
        {res && res.ok === false && <p className="mt-4 rounded-2xl bg-amber-50 p-3 text-sm text-amber-900">{res.grade_rule?.explanation}</p>}
        {res?.ok && (
          <div className="mt-5">
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <h2 className="font-display text-xl font-extrabold">Unidades para {res.grade.name}</h2>
              <Badge tone="purple">regras {res.rule_version}</Badge>
              <SourceChip kind="calculado" detail="Pontuação = soma das regras vigentes (tabela iara.rules). Vagas ofertáveis da camada de demonstração." />
            </div>
            <Card className="overflow-hidden">
              <MapView className="h-[42vh] min-h-[280px]" units={units.data?.units ?? []} home={{ lat: home!.lat, lng: home!.lng, radius_m: res.territory_radius_m }} highlight={highlight} highlightLabel="Resultado da busca (número = posição)" lines fitKey={JSON.stringify(args)} cooperative colorMode="vacancy" />
            </Card>
            <p className="mt-2 flex items-start gap-2 text-[12.5px] text-muted"><Info className="mt-0.5 size-4 shrink-0" />{res.disclaimer}</p>

            <div className="mt-3 space-y-3">
              {ranked.length === 0 && <Card><EmptyState compact title="Nenhuma unidade compatível no raio de busca" body="Amplie a busca ou registre a solicitação para análise da Central." /></Card>}
              {ranked.map((r) => {
                const entry = queueByUnit.get(r.unit_id);
                return (
                  <motion.div key={r.unit_id} layout initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
                    <Card className={clsx('p-4', r.rank === 1 && 'ring-2 ring-purple-400')}>
                      <div className="flex items-start gap-3">
                        <span className={clsx('inline-flex size-10 shrink-0 items-center justify-center rounded-2xl font-display text-lg font-black text-white', r.rank === 1 ? 'bg-purple-700' : 'bg-slate-500')}>{r.rank}</span>
                        <div className="min-w-0 flex-1">
                          <Link to={`/unidades/${r.unit_id}`} className="font-display text-[17px] font-extrabold leading-tight hover:text-purple-700">{r.name}</Link>
                          <div className="text-[12.5px] text-muted"><Navigation className="mr-1 inline size-3.5" />{fmtKm(r.distance_m)} · {r.territory} · {(r.shifts ?? []).map((s: string) => SHIFT[s]).join('/')}</div>
                          <div className="mt-1.5 flex flex-wrap gap-1.5">
                            <Badge tone={r.offerable_effective > 0 ? 'green' : 'gray'}>{r.offerable_effective} vaga(s) ofertável(is)</Badge>
                            {r.within_territory && <Badge tone="purple">território prioritário</Badge>}
                            {r.queue_ahead > 0 && <Badge tone="amber">{r.queue_ahead} à frente na fila</Badge>}
                            {r.my_position && <Badge tone="blue">{r.my_position}º desta fila</Badge>}
                            {r.sibling && <Badge tone="teal">irmão(ã) na unidade</Badge>}
                            {r.has_aee && <Badge tone="purple">AEE</Badge>}
                          </div>
                        </div>
                        <div className="text-right"><div className="font-display text-xl font-black tabular text-purple-800">{fmtInt(r.score)}</div><div className="text-[10.5px] font-semibold text-muted">pontos</div></div>
                      </div>
                      <ul className="mt-3 space-y-1">
                        {(r.reasons as string[]).map((x) => <li key={x} className="flex items-start gap-2 text-[13.5px]"><CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" />{x}</li>)}
                      </ul>
                      <button onClick={() => setExpanded(expanded === r.unit_id ? null : r.unit_id)} className="mt-2 inline-flex items-center gap-1 text-[13px] font-semibold text-purple-700">
                        Por que esta posição? <ChevronDown className={clsx('size-4 transition', expanded === r.unit_id && 'rotate-180')} />
                      </button>
                      <AnimatePresence>
                        {expanded === r.unit_id && (
                          <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="overflow-hidden">
                            <div className="mt-2 rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
                              {(r.score_detail as any[]).map((sd) => (
                                <div key={sd.code} className="flex items-center justify-between py-1 text-[13px]">
                                  <span className={sd.points === 0 ? 'text-muted' : ''}>{RULE_LABEL[sd.code] ?? sd.code}</span>
                                  <b className={clsx('tabular', sd.points > 0 ? 'text-green-700' : sd.points < 0 ? 'text-red-700' : 'text-muted')}>{sd.points > 0 ? '+' : ''}{sd.points}</b>
                                </div>
                              ))}
                              <div className="mt-1 flex justify-between border-t border-line pt-1.5 text-[13px] font-bold"><span>Total</span><span className="tabular">{r.score}</span></div>
                              <div className="mt-3 space-y-2">
                                {(r.top_classes as any[]).map((c) => (
                                  <Link key={c.class_id} to={`/turmas/${c.class_id}`} className="block rounded-xl bg-white p-2 ring-1 ring-line">
                                    <div className="mb-1 flex justify-between text-[12.5px]"><span className="font-semibold">{c.class_name} · {SHIFT[c.shift]}</span><span>{c.enrolled}/{c.capacity} · {c.offerable} vaga(s)</span></div>
                                    <OccupancyBar capacity={c.capacity} enrolled={c.enrolled} offerable={c.offerable} height={6} />
                                  </Link>
                                ))}
                              </div>
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {kid && can('queue.manage') && !entry && (
                          <Button variant="secondary" icon={ListPlus} loading={busyUnit === r.unit_id} onClick={() => insertQueue(r)}>Inserir na fila</Button>
                        )}
                        {kid && entry && can('offers.create') && r.can_offer_now && (
                          <Button variant="purple" icon={Sparkles} onClick={() => setOfferEntry(entry.id)}>Ofertar vaga (1º da fila)</Button>
                        )}
                        {kid && me?.scope === 'GUARDIAN' && (
                          <Button variant="purple" icon={ListPlus} loading={busyUnit === r.unit_id} onClick={() => citizenRequest(r)}>Inscrever na fila</Button>
                        )}
                        <ButtonLink to={`/unidades/${r.unit_id}`} variant="ghost">Ver unidade</ButtonLink>
                      </div>
                    </Card>
                  </motion.div>
                );
              })}
            </div>
            {enrolled && (
              <Card id="inscricao" className="mt-4 bg-green-50 p-4 ring-1 ring-green-200">
                <div className="flex items-start gap-3">
                  <CheckCircle2 className="mt-0.5 size-6 shrink-0 text-green-700" />
                  <div className="min-w-0 text-[14px] text-green-950">
                    <b>{enrolled.child}</b> está na fila de espera on-line de {enrolled.grade} · {enrolled.unit}: <b>{enrolled.position}º de {enrolled.queue_size}</b>, {Number(enrolled.score)} de 100 pontos. Protocolo {enrolled.protocol}.
                    <div className="mt-1 text-[13px]">{enrolled.message}</div>
                    {(enrolled.documents ?? []).length > 0 && <div className="mt-1 text-[12.5px]">Leve na matrícula: {(enrolled.documents as string[]).map((x) => DOC[x] ?? x).join(', ')}.</div>}
                    <ButtonLink to="/familia" size="sm" variant="secondary" className="mt-2">Ver minha família</ButtonLink>
                  </div>
                </div>
              </Card>
            )}
            <Card className="mt-4 p-4 text-[13px] text-muted">
              <b className="text-ink">Filtro eliminatório:</b> {res.excluded.ELIM_ETAPA_SERIE} unidade(s) não atendem {res.grade.name}; {res.excluded.ELIM_UNIDADE_ATIVA} em situação operacional a validar
              {res.filters.shift_required ? `; ${res.excluded.ELIM_TURNO} sem turma no turno` : ''}; {res.excluded.FORA_DO_RAIO_DE_BUSCA} fora do raio de busca ({res.filters.max_km} km).
            </Card>
          </div>
        )}
        {!res && (
          <div className="mt-6">
            <IaraBubble compact>Informe a data de nascimento e a residência. Eu mostro as unidades da faixa da criança, a distância, as vagas e quantas crianças estão na frente — com a explicação de cada ponto.</IaraBubble>
          </div>
        )}
      </div>
      {student.data && <p className="mt-6 text-center text-[12px] text-muted">Nascimento considerado: {fmtDate(student.data.student.birth_date)} · <X className="inline size-3" /> nenhum dado é enviado a terceiros</p>}
      <OfferSheet open={!!offerEntry} entryId={offerEntry} onClose={() => setOfferEntry(null)} onDone={() => qc.invalidateQueries({ queryKey: ['search_vacancies'] })} />
    </div>
  );
}
