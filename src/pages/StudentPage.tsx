import { useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import clsx from 'clsx';
import {
  AlertTriangle, Bus, CheckCircle2, ClipboardPlus, HeartPulse, Home, IdCard, Lock, MapPin, Pencil, Phone, School, Search, ShieldCheck, Sparkles, Users,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt, fmtKm, timeAgo } from '@/lib/format';
import { AUDIT_ACTION, CASE_STATUS, CHANNEL, ENTITY, OFFER_STATUS, QUEUE_CATEGORY, QUEUE_STATUS, SHIFT } from '@/lib/labels';
import { Avatar, Badge, Button, ButtonLink, Card, DataPair, EmptyState, ErrorState, ListRow, Section, Simulado, SkeletonList, SourceChip, Tabs } from '@/components/ui';
import { Completude } from '@/components/cadastro';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { NACIONALIDADE, PARENTESCO, RACA, SITUACAO_ALUNO, SITUACAO_LEGAL, mascaraCertidao, mascaraNis, mascaraSus, mascarado, precisaoRotulo } from '@/lib/cadastro';
import { Crumbs } from '@/components/Crumbs';
import { useToast } from '@/components/overlays';
import MapView from '@/components/map/MapView';
import { LinkMetodologia, TresDistanciasInscricao } from '@/components/distancias';
import QuadroDistancias from '@/components/QuadroDistancias';
import { AgendaLista, NovaOcorrenciaSheet, NovoRecadoSheet, OcorrenciaSheet, OcorrenciasTabela, useRecarregarVidaEscolar } from '@/components/vida-escolar';
import { MOTIVO_RESTRICAO, SITUACAO_RESTRICAO } from '@/lib/escola';
import { Foto, TrocarFoto } from '@/components/arquivos';
import { DocumentosAluno, ExcluirCadastro } from '@/components/documentos';

type Tab = 'resumo' | 'responsaveis' | 'matriculas' | 'documentos' | 'atendimentos' | 'fila' | 'aee' | 'auditoria' | 'frequencia'
  | 'alimentacao' | 'ocorrencias' | 'agenda';

export default function StudentPage() {
  const { id } = useParams();
  const [sp, setSp] = useSearchParams();
  const tab = (sp.get('aba') as Tab) ?? 'resumo';
  const res = useRpc<any>('student_detail', { student_id: id });
  const ve = useRpc<any>('aluno_vida_escolar', { student_id: id }, { enabled: !!id, retry: false });
  const docs = useRpc<any>('aluno_documentos', { student_id: id }, { enabled: !!id, retry: false });
  const { can } = useSession();
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const s = d.student;
  const primary = (d.guardians as any[])[0];
  const tabs: { value: Tab; label: string; count?: number | null }[] = [
    { value: 'resumo', label: 'Resumo' },
    { value: 'responsaveis', label: 'Responsáveis', count: d.guardians.length },
    { value: 'matriculas', label: 'Matrículas', count: d.enrollments.length },
    { value: 'documentos', label: 'Documentos', count: d.documents.length },
    { value: 'atendimentos', label: 'Atendimentos', count: d.cases.length },
    { value: 'fila', label: 'Fila e vagas', count: d.queue.length + d.offers.length },
    ...(d.school && can('frequencia.read') ? [{ value: 'frequencia' as Tab, label: 'Frequência' }] : []),
    ...(ve.data ? [
      { value: 'alimentacao' as Tab, label: 'Alimentação', count: (ve.data.restricoes as any[]).filter((r) => r.situacao !== 'RECUSADA').length || null },
      { value: 'ocorrencias' as Tab, label: 'Ocorrências', count: (ve.data.ocorrencias as any[]).filter((o) => o.situacao !== 'ENCERRADA').length || null },
      ...(ve.data.class_id ? [{ value: 'agenda' as Tab, label: 'Agenda' }] : []),
    ] : []),
    { value: 'aee', label: 'AEE/Inclusão' },
    ...(d.audit ? [{ value: 'auditoria' as Tab, label: 'Auditoria' }] : []),
  ];
  const crumbs = d.school
    ? [{ label: d.school.unit_name, to: `/unidades/${d.school.unit_id}` }, { label: d.school.class_name, to: `/turmas/${d.school.class_id}` }, { label: s.full_name }]
    : [{ label: 'Alunos' }, { label: s.full_name }];
  return (
    <div>
      <Crumbs items={crumbs} />
      <div className="mb-4 flex items-start gap-4">
        <div className="flex shrink-0 flex-col items-center gap-1">
          <Foto arquivoId={docs.data?.foto_arquivo_id} name={s.full_name} seed={s.avatar_seed} size={72} className="shadow-soft" />
          {docs.data?.pode_enviar && <TrocarFoto finalidade="FOTO_ALUNO" alvo={s.id} rotulo="Foto" variant="ghost" />}
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-[12px] font-bold uppercase tracking-[0.12em] text-purple-700">Ficha do aluno · 360º</div>
          <h1 className="font-display text-[24px] font-extrabold leading-tight sm:text-3xl">{s.full_name}</h1>
          {s.social_name && <div className="text-[13px] text-muted">Nome social: <b className="text-ink-2">{s.social_name}</b></div>}
          <div className="mt-1 flex flex-wrap gap-1.5">
            <Badge tone="gray">{s.age}</Badge>
            <Badge tone="blue">Código {s.registry}</Badge>
            <Badge tone={SITUACAO_ALUNO[s.status]?.tone ?? 'gray'}>{SITUACAO_ALUNO[s.status]?.label ?? s.status}</Badge>
            {s.is_demo && <Simulado detail="Criança fictícia (simulação)." />}
            {((ve.data?.restricoes ?? []) as any[]).filter((r) => r.situacao !== 'RECUSADA').map((r) => (
              <button key={r.id} onClick={() => setSp({ aba: 'alimentacao' }, { replace: true })} title={r.orientacao}>
                <Badge tone={r.situacao === 'VALIDADA' ? 'red' : 'amber'}>{r.descricao.split(' (')[0]}{r.situacao === 'INFORMADA' ? ' · a validar' : ''}</Badge>
              </button>
            ))}
            {((ve.data?.ocorrencias ?? []) as any[]).some((o) => o.situacao !== 'ENCERRADA') && (
              <button onClick={() => setSp({ aba: 'ocorrencias' }, { replace: true })}>
                <Badge tone="amber" icon={AlertTriangle}>{((ve.data?.ocorrencias ?? []) as any[]).filter((o) => o.situacao !== 'ENCERRADA').length} ocorrência(s) em aberto</Badge>
              </button>
            )}
          </div>
        </div>
        <div className="hidden shrink-0 flex-col gap-2 sm:flex">
          {d.registry?.can_edit && <ButtonLink to={`/alunos/${s.id}/cadastro`} variant="secondary" icon={Pencil}>Editar cadastro</ButtonLink>}
          {can('students.write') && <ExcluirCadastro fn="aluno_excluir" id={s.id} nome={s.full_name} voltarPara="/alunos" />}
        </div>
      </div>
      <Tabs value={tab} onChange={(t) => setSp({ aba: t }, { replace: true })} items={tabs} />
      <div className="mt-4">
        {tab === 'resumo' && <Resumo d={d} primary={primary} />}
        {tab === 'responsaveis' && <Guardians d={d} />}
        {tab === 'matriculas' && <Enrollments d={d} />}
        {tab === 'documentos' && <DocumentosAluno studentId={s.id} />}
        {tab === 'atendimentos' && <Cases d={d} canCreate={can('cases.write')} />}
        {tab === 'fila' && <QueueOffers d={d} />}
        {tab === 'aee' && <Aee d={d} />}
        {tab === 'frequencia' && <FrequenciaAluno id={s.id} />}
        {tab === 'alimentacao' && ve.data && <AlimentacaoAluno v={ve.data} studentId={s.id} />}
        {tab === 'ocorrencias' && ve.data && <OcorrenciasAluno v={ve.data} aluno={{ id: s.id, nome: s.full_name }} />}
        {tab === 'agenda' && ve.data && <AgendaAluno v={ve.data} aluno={{ id: s.id, nome: s.full_name }} />}
        {tab === 'auditoria' && <Audit d={d} />}
      </div>
    </div>
  );
}

function Resumo({ d, primary }: { d: any; primary: any }) {
  const s = d.student;
  const a = d.address;
  const alerts: { icon: any; text: string; tone: string }[] = [];
  if (s.aee) alerts.push({ icon: ShieldCheck, text: d.sensitive ? 'Atendimento educacional especializado — ver aba AEE' : 'Necessita AEE/inclusão (detalhe com acesso restrito)', tone: 'purple' });
  if (s.transport_need) alerts.push({ icon: Bus, text: 'Necessita transporte escolar', tone: 'blue' });
  if (d.age_grade_distortion) alerts.push({ icon: AlertTriangle, text: `Distorção idade-série: pela data de nascimento, a faixa seria ${d.grade_rule?.grade_name}`, tone: 'amber' });
  if (s.accessibility) alerts.push({ icon: AlertTriangle, text: s.accessibility, tone: 'amber' });
  const reg = d.registry;
  // distâncias (linha reta, a pé e de carro) até a escola onde estuda ou, sem matrícula, até a unidade pedida na fila
  const naFila = (d.queue as any[]).find((q) => ['WAITING', 'OFFERED', 'ACCEPTED'].includes(q.status));
  const alvo = d.school
    ? { id: d.school.unit_id as number, titulo: 'Distância de casa até a escola', rotulo: 'Unidade onde estuda' }
    : naFila ? { id: naFila.unit_id as number, titulo: 'Distância de casa até a unidade pedida', rotulo: 'Unidade pedida na fila' } : null;
  const enderecoInfo = a && (
    <div className="text-[13px]">
      <div className="flex items-start gap-2"><Home className="mt-0.5 size-4 shrink-0 text-ink-2" /><span>{a.line}</span></div>
      <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-muted"><MapPin className="size-4" />{a.territory ?? 'fora de Maringá'} · zona {a.zone?.toLowerCase() ?? 'urbana'} · {precisaoRotulo(a.precision)} <SourceChip kind="demo" detail="Endereço fictício; coordenada aproximada." /></div>
      {a.reference && <div className="mt-1 text-[12.5px] text-muted">Referência: {a.reference}</div>}
    </div>
  );
  return (
    <div className="space-y-4">
      {reg && (
        <div className="flex flex-col gap-2 sm:flex-row sm:items-stretch">
          <Completude pct={reg.complete_pct} pendencias={reg.pending} className="flex-1" />
          {reg.can_edit && (
            <ButtonLink to={`/alunos/${s.id}/cadastro`} variant={reg.pending.length ? 'purple' : 'secondary'} icon={Pencil} className="sm:h-auto">
              {reg.pending.length ? 'Completar cadastro' : 'Editar cadastro'}
            </ButtonLink>
          )}
        </div>
      )}
      {d.school ? (
        <Link to={`/turmas/${d.school.class_id}`} className="flex items-center gap-3 rounded-3xl bg-gradient-to-br from-blue-700 to-blue-900 p-4 text-white shadow-lift">
          <span className="inline-flex size-12 items-center justify-center rounded-2xl bg-white/15"><School className="size-6" /></span>
          <div className="min-w-0 flex-1">
            <div className="text-[12px] font-bold uppercase tracking-wide text-blue-100">Matrícula ativa</div>
            <div className="truncate font-display text-lg font-extrabold">{d.school.unit_name}</div>
            <div className="text-[13px] text-blue-100">{d.school.class_name} · {SHIFT[d.school.shift]} · {fmtKm(d.school.distance_m)} de casa em linha reta</div>
          </div>
        </Link>
      ) : (
        <Card className="flex items-center gap-3 p-4">
          <Search className="size-6 text-purple-700" />
          <div className="flex-1"><div className="font-semibold">Sem matrícula ativa</div><div className="text-[13px] text-muted">{d.grade_rule?.ok ? `Faixa pela data de nascimento: ${d.grade_rule.grade_name}` : d.grade_rule?.explanation}</div></div>
          <ButtonLink to={`/vagas?aluno=${s.id}`} variant="purple" size="sm">Buscar vaga</ButtonLink>
        </Card>
      )}
      {alerts.length > 0 && (
        <div className="space-y-2">
          {alerts.map((al, i) => (
            <div key={i} className={clsx('flex items-center gap-2 rounded-2xl p-3 text-[13.5px] font-medium ring-1', al.tone === 'purple' ? 'bg-purple-50 text-purple-900 ring-purple-100' : al.tone === 'blue' ? 'bg-blue-50 text-blue-900 ring-blue-100' : 'bg-amber-50 text-amber-900 ring-amber-100')}>
              <al.icon className="size-4 shrink-0" />{al.text}
            </div>
          ))}
        </div>
      )}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <dl className="grid grid-cols-2 gap-4">
            <DataPair label="Nascimento" value={fmtDate(s.birth_date)} />
            <DataPair label="Sexo" value={s.gender === 'F' ? 'Feminino' : s.gender === 'M' ? 'Masculino' : '—'} />
            <DataPair label="Responsável principal" value={primary ? <Link className="text-purple-700 underline" to={`/responsaveis/${primary.id}`}>{primary.full_name}</Link> : '—'} />
            <DataPair label="Contato" value={<span className="inline-flex items-center gap-1"><Phone className="size-3.5" />{primary?.whatsapp ?? primary?.phone ?? '—'}{primary?.contacts_masked && <Lock className="size-3 text-subtle" />}</span>} />
            <DataPair label="Renda familiar" value={primary?.income_bracket ?? '—'} />
            <DataPair label="CadÚnico" value={primary?.cadunico ? 'Sim' : 'Não'} />
            <DataPair label="Mãe solo" value={primary?.single_mother ? 'Sim (declarado)' : 'Não'} />
            <DataPair label="Irmãos na rede" value={d.siblings.length ? d.siblings.map((x: any) => <Link key={x.id} className="block text-purple-700 underline" to={`/alunos/${x.id}`}>{x.name.split(' ')[0]} ({x.unit ?? 'sem matrícula'})</Link>) : 'Nenhum'} />
            <DataPair label="Faixa pela regra" value={d.grade_rule?.grade_name ?? '—'} />
            <DataPair label="Situação legal" value={primary ? SITUACAO_LEGAL[primary.legal_status]?.label ?? primary.legal_status : '—'} />
          </dl>
          <p className="mt-3 text-[12px] text-muted">{d.grade_rule?.explanation}</p>
        </Card>
        {a && a.lat != null && alvo ? (
          <div className="space-y-2">
            <QuadroDistancias origem={{ lat: a.lat, lng: a.lng }} unidadeId={alvo.id} titulo={alvo.titulo} homeLabel="Endereço da criança" unidadeLabel={alvo.rotulo} />
            <Card className="p-3">{enderecoInfo}</Card>
          </div>
        ) : (
          <Card className="overflow-hidden">
            {a ? (
              <>
                {a.lat != null && (
                  <MapView
                    className="h-56"
                    units={[]}
                    home={{ lat: a.lat, lng: a.lng, radius_m: 2000 }}
                    homeLabel="Endereço da criança"
                    fitKey={s.id}
                    cooperative
                    controls={false}
                  />
                )}
                <div className="p-3">{enderecoInfo}</div>
              </>
            ) : <p className="p-4 text-sm text-muted">Endereço não disponível no seu escopo.</p>}
          </Card>
        )}
      </div>
      <DadosPessoais s={s} />
    </div>
  );
}

function DadosPessoais({ s }: { s: any }) {
  const doc = (v: string | null, f: (x: string) => string) => (v ? (mascarado(v) ? v : f(v)) : '—');
  return (
    <Card className="p-4">
      <div className="mb-3 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><IdCard className="size-4" />Dados pessoais e documentos{s.docs_masked && <span className="inline-flex items-center gap-1 font-semibold normal-case tracking-normal"><Lock className="size-3" />mascarados para o seu perfil</span>}</div>
      <dl className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
        <DataPair label="Cor/raça" value={RACA[s.race_color] ?? '—'} />
        <DataPair label="Nacionalidade" value={`${NACIONALIDADE[s.nationality] ?? s.nationality}${s.birth_country ? ` · ${s.birth_country}` : ''}`} />
        <DataPair label="Naturalidade" value={s.birth_city ? `${s.birth_city}/${s.birth_state ?? ''}` : '—'} />
        <DataPair label="Uso de imagem" value={s.image_consent == null ? 'Não informado' : s.image_consent ? 'Autoriza' : 'Não autoriza'} />
        <DataPair label="Filiação 1" value={s.parent1 ?? '—'} />
        <DataPair label="Filiação 2" value={s.parent2 ?? 'Não declarada'} />
        <DataPair label="CPF" value={s.cpf ?? '—'} />
        <DataPair label="NIS" value={doc(s.nis, mascaraNis)} />
        <DataPair label="Certidão de nascimento" value={<span className="break-all text-[13px]">{doc(s.birth_certificate, mascaraCertidao)}</span>} className="col-span-2" />
        <DataPair label="Cartão SUS" value={doc(s.sus_card, mascaraSus)} />
        <DataPair label="Código INEP" value={s.inep_id ?? '—'} />
      </dl>
    </Card>
  );
}

function Guardians({ d }: { d: any }) {
  return (
    <div className="space-y-3">
    {d.registry?.can_edit && (
      <div className="flex flex-wrap items-center gap-2 text-[13px] text-muted">
        <ButtonLink to={`/alunos/${d.student.id}/cadastro`} size="sm" variant="secondary" icon={Pencil}>Gerenciar responsáveis</ButtonLink>
        vincular, mudar o principal, quem pode buscar, encerrar vínculo
      </div>
    )}
    <Card className="overflow-hidden">
      <Tabela rotulo="Responsáveis" largura={900} colunas="minmax(190px,1.5fr) 140px minmax(160px,1.2fr) 112px 140px 130px">
        <TCabecalho><span>Responsável</span><span>Parentesco</span><span>Papéis</span><span>Situação legal</span><span>Telefone</span><span>CPF</span></TCabecalho>
        {(d.guardians as any[]).map((g) => (
          <TLinha key={g.id} to={`/responsaveis/${g.id}`} rotulo={`${g.full_name}, ${PARENTESCO[g.relationship] ?? g.relationship}`}>
            <TCelula fixa titulo={g.full_name}><Avatar name={g.full_name} seed={g.full_name} size={24} className="mr-2 inline-flex align-middle" /><span className="font-semibold">{g.full_name}</span></TCelula>
            <TCelula>{PARENTESCO[g.relationship] ?? g.relationship}</TCelula>
            <TCelula className={clsx('text-[12.5px]', g.is_primary ? 'font-semibold text-purple-800' : 'text-muted')}>
              {[g.is_primary && 'principal', g.can_pick_up && 'pode buscar', g.can_notify === false ? 'sem avisos' : 'recebe avisos'].filter(Boolean).join(' · ')}
            </TCelula>
            <TCelula livre><Badge tone={SITUACAO_LEGAL[g.legal_status]?.tone ?? 'gray'}>{SITUACAO_LEGAL[g.legal_status]?.label ?? g.legal_status}</Badge></TCelula>
            <TCelula className="tabular text-muted">{g.whatsapp ?? g.phone ?? '—'}{g.contacts_masked && <Lock className="ml-1 inline size-3 text-subtle" />}</TCelula>
            <TCelula className="tabular text-muted">{g.cpf ?? '—'}</TCelula>
          </TLinha>
        ))}
        {!d.guardians.length && <p className="px-3 py-3 text-[13px] text-muted">Nenhum responsável vinculado.</p>}
      </Tabela>
    </Card>
    {(d.former_guardians ?? []).length > 0 && (
      <Card className="overflow-hidden">
        <Tabela rotulo="Vínculos encerrados" largura={560} colunas="minmax(190px,1.6fr) 140px 120px 120px">
          <TCabecalho><span>Vínculo encerrado</span><span>Parentesco</span><span>Desde</span><span>Até</span></TCabecalho>
          {(d.former_guardians as any[]).map((g) => (
            <TLinha key={g.id} to={`/responsaveis/${g.id}`} className="opacity-70">
              <TCelula fixa titulo={g.full_name}><Avatar name={g.full_name} seed={g.full_name} size={24} className="mr-2 inline-flex align-middle" />{g.full_name}</TCelula>
              <TCelula>{PARENTESCO[g.relationship] ?? g.relationship}</TCelula>
              <TCelula className="text-muted">{fmtDate(g.start_date)}</TCelula>
              <TCelula className="text-muted">{fmtDate(g.end_date)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
    )}
    </div>
  );
}

function Enrollments({ d }: { d: any }) {
  if (!d.enrollments.length) return <Card><EmptyState compact title="Sem matrículas registradas" /></Card>;
  return (
    <Card className="divide-y divide-line overflow-hidden">
      {(d.enrollments as any[]).map((e) => (
        <ListRow key={e.id} to={`/turmas/${e.class_id}`} leading={<School className="size-5 text-blue-700" />} title={`${e.unit} · ${e.class}`}
          subtitle={`${e.school_year} · ${SHIFT[e.shift]} · ${e.entry_type?.toLowerCase().replace('_', ' ')} em ${fmtDate(e.enrollment_date)}${e.end_date ? ` · até ${fmtDate(e.end_date)}` : ''}`}
          meta={<Badge tone={e.status === 'ACTIVE' ? 'green' : 'gray'}>{e.status === 'ACTIVE' ? 'Ativa' : e.status.toLowerCase()}</Badge>} />
      ))}
    </Card>
  );
}

function Cases({ d, canCreate }: { d: any; canCreate: boolean }) {
  return (
    <div>
      {canCreate && <ButtonLink to={`/atendimentos/novo?aluno=${d.student.id}`} icon={ClipboardPlus} className="mb-3">Novo atendimento</ButtonLink>}
      <Card className="divide-y divide-line overflow-hidden">
        {(d.cases as any[]).map((c) => (
          <ListRow key={c.id} to={`/atendimentos/${c.id}`} title={c.subject} subtitle={`${c.protocol} · ${c.type_name} · ${CHANNEL[c.channel] ?? c.channel} · ${fmtDate(c.opened_at)}`}
            meta={<Badge tone={CASE_STATUS[c.status]?.tone}>{CASE_STATUS[c.status]?.label}</Badge>} />
        ))}
        {!d.cases.length && <EmptyState compact title="Sem atendimentos" />}
      </Card>
    </div>
  );
}

function QueueOffers({ d }: { d: any }) {
  return (
    <div className="space-y-4">
      {(d.queue as any[]).map((q) => (
        <Card key={q.id} className="p-4">
          <div className="flex items-start justify-between gap-2">
            <div>
              <Link to={`/fila/${q.id}`} className="font-display text-lg font-extrabold hover:text-purple-700">{q.grade} · {q.unit}</Link>
              <div className="text-[12.5px] text-muted">{QUEUE_CATEGORY[q.category]?.label} · entrada {fmtDate(q.entered_at)} · regras {q.rule_version}</div>
            </div>
            <div className="text-right">
              {q.position ? <div className="font-display text-3xl font-black text-purple-800">{q.position}º</div> : null}
              <Badge tone={QUEUE_STATUS[q.status]?.tone}>{QUEUE_STATUS[q.status]?.label}</Badge>
            </div>
          </div>
          {(q.breakdown ?? []).some((b: any) => b.code === 'TERRITORIO_2KM' && b.distancias) && (
            <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 rounded-2xl bg-slate-50 px-3 py-2 text-[12.5px]">
              <span className="font-semibold text-ink-2">Distância de casa:</span>
              <TresDistanciasInscricao breakdown={q.breakdown} />
              <LinkMetodologia className="text-[12px]">como medimos</LinkMetodologia>
            </div>
          )}
          <ul className="mt-3 grid grid-cols-1 gap-1 sm:grid-cols-2">
            {(q.breakdown ?? []).map((b: any) => (
              <li key={b.code} className="flex items-start gap-2 text-[13px]">
                {b.applied ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" /> : <span className="mt-1 size-3 shrink-0 rounded-full border-2 border-slate-300" />}
                <span className={b.applied ? '' : 'text-muted'}>{b.name}{b.analysis ? ' (prioridade sob análise)' : b.weight ? (b.applied ? ` (+${b.weight})` : ' (não aplicado)') : ''}</span>
              </li>
            ))}
          </ul>
        </Card>
      ))}
      {(d.offers as any[]).length > 0 && (
        <Section title="Ofertas">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.offers as any[]).map((o) => (
              <ListRow key={o.id} to={`/turmas/${o.class_id}`} leading={<Sparkles className="size-5 text-green-700" />} title={`${o.unit} · ${o.class}`}
                subtitle={`Ofertada ${fmtDateTime(o.offered_at)}${o.decline_reason ? ` · motivo: ${o.decline_reason}` : ''}`}
                meta={<Badge tone={OFFER_STATUS[o.status]?.tone}>{OFFER_STATUS[o.status]?.label}</Badge>} />
            ))}
          </Card>
        </Section>
      )}
      {!d.queue.length && !d.offers.length && <Card><EmptyState compact title="Sem fila ou ofertas" action={<ButtonLink to={`/vagas?aluno=${d.student.id}`} variant="purple">Buscar vaga</ButtonLink>} /></Card>}
    </div>
  );
}

function Aee({ d }: { d: any }) {
  if (d.sensitive) {
    return (
      <Card className="p-4">
        <div className="mb-3 flex items-center gap-2 rounded-2xl bg-purple-50 p-3 text-[13px] text-purple-900"><Lock className="size-4" />Dado sensível (LGPD): esta consulta foi registrada na trilha de auditoria.</div>
        <dl className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <DataPair label="Necessidade educacional" value={d.sensitive.special_education_need ?? '—'} />
          <DataPair label="Alertas de saúde" value={<span className="inline-flex items-center gap-1"><HeartPulse className="size-4 text-red-600" />{d.sensitive.medical_alerts ?? 'Nenhum registrado'}</span>} />
          <DataPair label="Restrições alimentares" value={d.sensitive.food_allergies ?? 'Nenhuma registrada'} />
        </dl>
        <SourceChip kind="demo" className="mt-3" detail="Informações fictícias para demonstrar o controle de acesso." />
      </Card>
    );
  }
  return (
    <Card className="flex items-start gap-3 p-4">
      <Lock className="mt-0.5 size-5 text-slate-500" />
      <div className="text-[14px]">
        <b>{d.student.aee ? 'Há registro de AEE/inclusão para este aluno.' : 'Sem registro de AEE.'}</b>
        <p className="text-muted">Laudos, saúde e restrições exigem permissão específica (perfis da unidade autorizada). Seu perfil não tem acesso ao detalhe.</p>
      </div>
    </Card>
  );
}

function Audit({ d }: { d: any }) {
  return (
    <Card className="divide-y divide-line overflow-hidden">
      {(d.audit as any[]).map((a, i) => (
        <div key={i} className="px-4 py-3">
          <div className="flex items-center justify-between gap-2">
            <span className="font-semibold">{AUDIT_ACTION[a.action] ?? a.action} · {ENTITY[a.entity] ?? a.entity}</span>
            <span className="text-[12px] text-muted">{timeAgo(a.at)}</span>
          </div>
          <div className="text-[12.5px] text-muted">{a.actor}{a.summary ? ` · ${a.summary}` : ''}</div>
        </div>
      ))}
      {!d.audit.length && <EmptyState compact title="Sem eventos" body="Toda alteração nesta ficha gera registro imutável." />}
      <p className="flex items-center gap-1 bg-slate-50 px-4 py-2 text-[12px] text-muted"><Users className="size-3.5" />{fmtInt(d.audit.length)} eventos recentes · trilha imutável</p>
    </Card>
  );
}

/** Frequência do aluno: percentual no ano, mês a mês, faltas recentes, alertas e justificativas da família. */
function FrequenciaAluno({ id }: { id: string }) {
  const res = useRpc<any>('frequencia_aluno', { student_id: id });
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const f = res.data;
  const pct = Number(f.percentual);
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <Card className="p-4">
        <div className="flex items-end justify-between">
          <div>
            <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Presença no ano</div>
            <div className={`font-display text-4xl font-black tabular ${pct < Number(f.minimo) ? 'text-red-700' : 'text-green-700'}`}>{String(f.percentual ?? '—').replace('.', ',')}%</div>
          </div>
          <div className="text-right text-[13px] text-muted">mínimo {f.minimo}%<br />{f.faltas} falta(s) em {f.dias} dias · {f.justificadas} justificada(s)</div>
        </div>
        <div className="mt-4 space-y-1.5">
          {(f.por_mes as any[]).map((m) => {
            const p = m.dias ? Math.round(1000 - (1000 * m.faltas) / m.dias) / 10 : null;
            return (
              <div key={m.mes} className="flex items-center gap-2 text-[12.5px]">
                <span className="w-16 font-semibold">{m.mes.slice(5, 7)}/{m.mes.slice(0, 4)}</span>
                <span className="h-2 flex-1 overflow-hidden rounded-full bg-slate-100"><span className={`block h-full rounded-full ${p != null && p < Number(f.minimo) ? 'bg-red-500' : 'bg-green-600'}`} style={{ width: `${p ?? 0}%` }} /></span>
                <span className="w-24 text-right tabular text-muted">{m.faltas} falta(s)</span>
              </div>
            );
          })}
        </div>
      </Card>
      <div className="space-y-4">
        {(f.alertas as any[]).length > 0 && (
          <Card className="border-l-4 border-red-500 p-4">
            <div className="font-semibold text-red-800">Alerta de frequência em aberto</div>
            {(f.alertas as any[]).map((a, i) => <p key={i} className="mt-1 text-[13px] text-ink-2">{a.tipo === 'AUSENCIA_CONSECUTIVA' ? 'Faltas seguidas' : 'Abaixo do mínimo'} · {a.situacao === 'ABERTO' ? 'aberto' : 'em acompanhamento'}{a.acao ? ` · ${a.acao}` : ''}</p>)}
          </Card>
        )}
        <Card className="divide-y divide-line overflow-hidden">
          <div className="px-4 py-2.5 text-[12px] font-bold uppercase tracking-wide text-subtle">Faltas recentes</div>
          {(f.faltas_recentes as any[]).length ? (f.faltas_recentes as any[]).map((x) => (
            <div key={x.data} className="flex items-center gap-3 px-4 py-2 text-[13px]">
              <span className="w-24 font-semibold">{fmtDate(x.data)}</span>
              <span className="min-w-0 flex-1 truncate text-muted">{x.tipo === 'FALTA_JUSTIFICADA' ? `Justificada${x.justificativa ? ' · ' + x.justificativa : ''}` : 'Falta'}</span>
            </div>
          )) : <p className="px-4 py-3 text-[13px] text-muted">Sem faltas registradas.</p>}
        </Card>
      </div>
    </div>
  );
}

/** Restrições alimentares: o que a cozinha recebe, quem validou e o registro trazido ao balcão (a nutrição valida). */
function AlimentacaoAluno({ v, studentId }: { v: any; studentId: string }) {
  const toast = useToast();
  const recarregar = useRecarregarVidaEscolar();
  const [codigo, setCodigo] = useState('');
  const [laudo, setLaudo] = useState(false);
  const [busy, setBusy] = useState(false);
  const registrar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('aluno_restricao_registrar', { student_id: studentId, codigo, laudo_entregue: laudo });
      toast({ title: 'Restrição registrada', description: r.mensagem, tone: 'success' });
      setCodigo(''); setLaudo(false);
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const itens = v.restricoes as any[];
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.4fr_1fr]">
      <Card className="overflow-hidden">
        {itens.length ? (
          <Tabela colunas="minmax(220px,1.6fr) 120px 150px minmax(200px,1.4fr)" largura={760} rotulo="Restrições alimentares">
            <TCabecalho><TCelula>Restrição</TCelula><TCelula>Motivo</TCelula><TCelula>Situação</TCelula><TCelula>Instrução para a cozinha</TCelula></TCabecalho>
            {itens.map((r) => (
              <TLinha key={r.id}>
                <TCelula fixa titulo={r.descricao}><span className="font-semibold">{r.descricao}</span>{r.detalhe ? ` (${r.detalhe})` : ''}</TCelula>
                <TCelula><Badge tone={MOTIVO_RESTRICAO[r.motivo]?.tone}>{MOTIVO_RESTRICAO[r.motivo]?.label}</Badge></TCelula>
                <TCelula titulo={r.validada_por ? `${r.validada_por} · ${fmtDate(r.validada_em)}` : `informada em ${fmtDate(r.informada_em)}`}>
                  <Badge tone={SITUACAO_RESTRICAO[r.situacao]?.tone}>{SITUACAO_RESTRICAO[r.situacao]?.label}</Badge>
                </TCelula>
                <TCelula titulo={r.orientacao} className="text-muted">{r.orientacao}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : <EmptyState compact title="Sem restrição alimentar registrada" body="A família informa pelo portal ou pela IARA; a secretaria pode registrar o que for trazido ao balcão." />}
      </Card>
      {v.pode_restricao && (
        <Card className="space-y-3 p-4">
          <div className="font-semibold">Registrar restrição trazida pela família</div>
          <select value={codigo} onChange={(e) => setCodigo(e.target.value)} className="h-11 w-full rounded-2xl bg-white px-3 ring-1 ring-line" aria-label="Restrição">
            <option value="">Escolha a restrição…</option>
            {(v.catalogo_restricoes as any[]).map((r) => <option key={r.codigo} value={r.codigo}>{r.descricao}</option>)}
          </select>
          <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={laudo} onChange={(e) => setLaudo(e.target.checked)} className="size-5 accent-purple-700" />Laudo entregue na secretaria</label>
          <Button block loading={busy} disabled={!codigo} onClick={registrar}>Registrar para a nutrição validar</Button>
          <p className="text-[12px] text-muted">A cozinha recebe só a instrução de preparo, nunca o laudo.</p>
        </Card>
      )}
    </div>
  );
}

function OcorrenciasAluno({ v, aluno }: { v: any; aluno: { id: string; nome: string } }) {
  const [aberta, setAberta] = useState<string | null>(null);
  const [nova, setNova] = useState(false);
  return (
    <>
      {v.pode_ocorrencia && <div className="mb-3 flex justify-end"><Button icon={ClipboardPlus} onClick={() => setNova(true)}>Registrar ocorrência</Button></div>}
      <Card className="overflow-hidden"><OcorrenciasTabela itens={v.ocorrencias} onAbrir={setAberta} mostrarAluno={false} /></Card>
      <p className="mt-2 text-[12px] text-muted">Registradas pela escola ou relatadas pela família (portal e IARA). A família dá ciência do que a escola registra.</p>
      <OcorrenciaSheet id={aberta} onClose={() => setAberta(null)} />
      <NovaOcorrenciaSheet open={nova} onClose={() => setNova(false)} alunos={[aluno]} />
    </>
  );
}

function AgendaAluno({ v, aluno }: { v: any; aluno: { id: string; nome: string } }) {
  const [novo, setNovo] = useState(false);
  return (
    <>
      {v.pode_agenda && <div className="mb-3 flex justify-end"><Button icon={Pencil} onClick={() => setNovo(true)}>Bilhete para a família</Button></div>}
      <Card className="overflow-hidden"><AgendaLista itens={v.agenda} /></Card>
      <p className="mt-2 text-[12px] text-muted">Recados e tarefas da turma, bilhetes individuais e o que a família escreveu (últimos 30 dias e próximos 30).</p>
      {v.class_id && <NovoRecadoSheet open={novo} onClose={() => setNovo(false)} classId={v.class_id} alunos={[]} alunoFixo={aluno} />}
    </>
  );
}
