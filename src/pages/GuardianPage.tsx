import { Link, useParams } from 'react-router';
import { Bell, Home, IdCard, Lock, Mail, MapPin, MessageCircle, Pencil, Phone, ShieldCheck, Users, Wallet } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useUnitsMap } from '@/lib/data';
import { fmtDate, timeAgo } from '@/lib/format';
import { CASE_STATUS, CHANNEL, CONV_STATE } from '@/lib/labels';
import { ESTADO_CIVIL, NACIONALIDADE, PARENTESCO, PARENTESCO_DOMICILIO, fmtMoeda, precisaoRotulo } from '@/lib/cadastro';
import { Avatar, Badge, ButtonLink, Card, DataPair, EmptyState, ErrorState, ListRow, Section, SkeletonList, SourceChip } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { Completude } from '@/components/cadastro';
import MapView from '@/components/map/MapView';

export default function GuardianPage() {
  const { id } = useParams();
  const res = useRpc<any>('guardian_detail', { guardian_id: id });
  const units = useUnitsMap();
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const g = d.guardian;
  const a = d.address;
  const reg = d.registry;
  return (
    <div>
      <Crumbs items={[{ label: 'Responsáveis', to: '/responsaveis' }, { label: g.full_name }]} />
      <div className="mb-4 flex items-start gap-4">
        <Avatar name={g.full_name} seed={g.full_name} size={68} />
        <div className="min-w-0 flex-1">
          <div className="text-[12px] font-bold uppercase tracking-[0.12em] text-purple-700">Cadastro 360º do responsável</div>
          <h1 className="font-display text-[24px] font-extrabold leading-tight">{g.full_name}</h1>
          {g.social_name && <div className="text-[13px] text-muted">Nome social: <b className="text-ink-2">{g.social_name}</b></div>}
          <div className="mt-1 flex flex-wrap gap-1.5">
            {g.cadunico && <Badge tone="purple">CadÚnico</Badge>}
            {g.single_mother && <Badge tone="purple">Mãe solo</Badge>}
            <Badge tone="gray">Prefere {CHANNEL[g.preferred_channel] ?? g.preferred_channel}</Badge>
            {g.language && g.language !== 'Português' && <Badge tone="blue">Idioma: {g.language}</Badge>}
            {g.is_demo && <Badge tone="amber">Fictício</Badge>}
          </div>
        </div>
        {reg?.can_edit && <ButtonLink to={`/responsaveis/${g.id}/cadastro`} variant="secondary" icon={Pencil} className="hidden shrink-0 sm:inline-flex">Editar cadastro</ButtonLink>}
      </div>
      {reg && (
        <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-stretch">
          <Completude pct={reg.complete_pct} pendencias={reg.pending} className="flex-1" />
          {reg.can_edit && (
            <ButtonLink to={`/responsaveis/${g.id}/cadastro`} variant={reg.pending.length ? 'purple' : 'secondary'} icon={Pencil} className="sm:h-auto">
              {reg.pending.length ? 'Completar cadastro' : 'Editar cadastro'}
            </ButtonLink>
          )}
        </div>
      )}
      {g.contacts_masked && <p className="mb-3 flex items-center gap-2 rounded-2xl bg-slate-100 p-3 text-[13px] text-ink-2"><Lock className="size-4" />CPF, RG e contatos mascarados conforme o seu perfil (mínimo privilégio).</p>}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <div className="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><IdCard className="size-4" />Identificação e contatos</div>
          <dl className="grid grid-cols-2 gap-4">
            <DataPair label="CPF" value={g.cpf ?? '—'} />
            <DataPair label="RG" value={g.rg ?? '—'} />
            <DataPair label="Nascimento" value={fmtDate(g.birth_date)} />
            <DataPair label="Estado civil" value={ESTADO_CIVIL[g.marital_status] ?? '—'} />
            <DataPair label="Nacionalidade" value={NACIONALIDADE[g.nationality] ?? g.nationality ?? '—'} />
            <DataPair label="Escolaridade" value={g.education_level ?? '—'} />
            <DataPair label="Telefone" value={<span className="inline-flex items-center gap-1"><Phone className="size-3.5" />{g.phone ?? '—'}</span>} />
            <DataPair label="WhatsApp" value={<span className="inline-flex items-center gap-1"><MessageCircle className="size-3.5" />{g.whatsapp ?? '—'}</span>} />
            {g.phone2 && <DataPair label="Outro telefone" value={g.phone2} />}
            <DataPair label="E-mail" value={<span className="inline-flex items-center gap-1 break-all"><Mail className="size-3.5" />{g.email || '—'}</span>} className={g.phone2 ? '' : 'col-span-2'} />
          </dl>
        </Card>
        <Card className="p-4">
          <div className="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><Wallet className="size-4" />Trabalho, renda e programas <SourceChip kind="demo" /></div>
          <dl className="grid grid-cols-2 gap-4">
            <DataPair label="Ocupação" value={g.occupation ?? '—'} />
            <DataPair label="Situação de trabalho" value={g.employment_status ?? '—'} />
            <DataPair label="Renda individual" value={fmtMoeda(g.monthly_income)} />
            <DataPair label="Renda familiar" value={g.family_income != null ? `${fmtMoeda(g.family_income)} · ${g.income_bracket ?? ''}` : g.income_bracket ?? '—'} />
            <DataPair label="Pessoas no domicílio" value={g.household_size ?? '—'} />
            <DataPair label="Benefícios" value={(g.benefits ?? []).join(', ') || 'Nenhum'} />
            <DataPair label="NIS" value={g.nis ?? (g.contacts_masked ? 'restrito' : '—')} />
            <DataPair label="Consentimento" value={g.consent?.lgpd_ciencia ? `Ciente (LGPD)${g.consent?.whatsapp === false ? ' · sem WhatsApp' : ''}` : '—'} />
          </dl>
        </Card>
      </div>

      <Section title="Endereço e localização">
        <Card className="overflow-hidden">
          {a ? (
            <div className="grid grid-cols-1 lg:grid-cols-[1fr_340px]">
              <MapView className="h-56 lg:h-full lg:min-h-[240px]" units={units.data?.units ?? []} home={{ lat: a.lat, lng: a.lng, radius_m: 2000 }}
                fitKey={g.id} cooperative controls={false} homeLabel="Endereço do responsável" legend="overlay" legendClassName="bottom-2 left-2" />
              <div className="space-y-2 p-4 text-[13.5px]">
                <div className="flex items-start gap-2"><Home className="mt-0.5 size-4 shrink-0 text-ink-2" /><span className="font-semibold">{a.line}</span></div>
                <div className="flex flex-wrap items-center gap-x-2 text-muted"><MapPin className="size-4" />{a.territory ?? 'fora de Maringá'} · zona {a.zone?.toLowerCase() ?? 'urbana'}</div>
                <div className="text-muted">Localização: {precisaoRotulo(a.precision)}</div>
                {a.postal_code && <div className="text-muted">CEP {a.postal_code}</div>}
                {a.reference && <div className="text-muted">Referência: {a.reference}</div>}
                <p className="text-[12px] text-subtle">O círculo marca 2 km da residência (critério da fila).</p>
              </div>
            </div>
          ) : <p className="p-4 text-sm text-muted">Endereço não cadastrado ou fora do seu escopo.</p>}
        </Card>
      </Section>

      <Section title="Crianças vinculadas">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {(d.students as any[]).map((s) => (
            <Link key={s.id} to={`/alunos/${s.id}`} className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
              <Avatar name={s.name} seed={s.avatar_seed} size={44} />
              <div className="min-w-0 flex-1">
                <div className="truncate font-semibold">{s.name}</div>
                <div className="text-[12.5px] text-muted">{s.age} · {PARENTESCO[s.relationship] ?? s.relationship}{s.is_primary ? ' (principal)' : ''} · {s.unit ?? 'sem matrícula'}</div>
                {s.same_address === false && <div className="text-[12px] text-amber-700">mora em outro endereço</div>}
              </div>
            </Link>
          ))}
          {!d.students.length && <Card><EmptyState compact title="Nenhuma criança vinculada" /></Card>}
        </div>
      </Section>

      {((d.household as any[]).length > 0 || (d.household_members as any[]).length > 0) && (
        <Section title="Composição familiar">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.household as any[]).map((h) => (
              <ListRow key={h.id} to={`/responsaveis/${h.id}`} leading={<Avatar name={h.full_name} seed={h.full_name} size={36} />} title={h.full_name} subtitle={`Também responsável por ${h.shared_students} criança(s)`} />
            ))}
            {(d.household_members as any[]).map((m) => (
              <ListRow key={m.id} leading={<span className="inline-flex size-9 items-center justify-center rounded-full bg-slate-100"><Users className="size-4 text-ink-2" /></span>}
                title={m.name} subtitle={`${PARENTESCO_DOMICILIO[m.relationship] ?? m.relationship}${m.age ? ` · ${m.age}` : ''}${m.occupation ? ` · ${m.occupation}` : ''}${m.income != null ? ` · ${fmtMoeda(m.income)}` : ''} · mora no domicílio`} />
            ))}
          </Card>
        </Section>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Atendimentos">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.cases as any[]).map((c) => (
              <ListRow key={c.id} to={`/atendimentos/${c.id}`} title={c.subject} subtitle={`${c.protocol} · ${CHANNEL[c.channel] ?? c.channel} · ${fmtDate(c.opened_at)}`} meta={<Badge tone={CASE_STATUS[c.status]?.tone}>{CASE_STATUS[c.status]?.label}</Badge>} />
            ))}
            {!d.cases.length && <EmptyState compact title="Sem atendimentos" />}
          </Card>
        </Section>
        <Section title="Conversas e avisos">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.conversations as any[]).map((c) => (
              <ListRow key={c.id} to={`/conversas/${c.id}`} leading={<MessageCircle className="size-5 text-purple-700" />} title={c.summary ?? 'Conversa com a IARA'} subtitle={timeAgo(c.last_message_at)} meta={<Badge tone={CONV_STATE[c.state]?.tone}>{CONV_STATE[c.state]?.label}</Badge>} />
            ))}
            {(d.notifications as any[]).slice(0, 6).map((n) => (
              <div key={n.id} className="flex items-start gap-3 px-4 py-3">
                <Bell className="mt-0.5 size-5 text-subtle" />
                <div className="min-w-0 flex-1"><div className="font-semibold">{n.title}</div><div className="text-[12.5px] text-muted">{n.body}</div></div>
                <Badge tone="gray">{n.status.toLowerCase()}</Badge>
              </div>
            ))}
            {!d.conversations.length && !d.notifications.length && <EmptyState compact title="Sem conversas ou avisos" />}
          </Card>
        </Section>
      </div>
      <p className="mt-6 flex items-center justify-center gap-1 text-center text-[12px] text-muted"><ShieldCheck className="size-3.5" />Acesso registrado conforme LGPD · dados fictícios</p>
    </div>
  );
}
