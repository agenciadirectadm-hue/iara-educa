import { useParams } from 'react-router';
import { Bell, Home, IdCard, Lock, Mail, MapPin, MessageCircle, Pencil, Phone, ShieldCheck, Users, Wallet } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useUnitsMap } from '@/lib/data';
import { fmtDate, timeAgo } from '@/lib/format';
import { CASE_STATUS, CHANNEL, CONV_STATE } from '@/lib/labels';
import { ESTADO_CIVIL, NACIONALIDADE, PARENTESCO, PARENTESCO_DOMICILIO, fmtMoeda, precisaoRotulo } from '@/lib/cadastro';
import { Avatar, Badge, ButtonLink, Card, DataPair, EmptyState, ErrorState, ListRow, Section, Simulado, SkeletonList, SourceChip } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { Crumbs } from '@/components/Crumbs';
import { Completude } from '@/components/cadastro';
import MapView from '@/components/map/MapView';
import { ExcluirCadastro } from '@/components/documentos';

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
            {g.is_demo && <Simulado detail="Pessoa fictícia (simulação)." />}
          </div>
        </div>
        {reg?.can_edit && (
          <div className="hidden shrink-0 flex-col gap-2 sm:flex">
            <ButtonLink to={`/responsaveis/${g.id}/cadastro`} variant="secondary" icon={Pencil}>Editar cadastro</ButtonLink>
            <ExcluirCadastro fn="responsavel_excluir" id={g.id} nome={g.full_name ?? g.name ?? 'responsável'} voltarPara="/responsaveis" />
          </div>
        )}
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
        <Card className="overflow-hidden">
          <Tabela rotulo="Crianças vinculadas" largura={720} colunas="minmax(200px,1.6fr) 84px 150px minmax(150px,1.3fr) 130px">
            <TCabecalho><span>Criança</span><span>Idade</span><span>Parentesco</span><span>Unidade</span><span>Endereço</span></TCabecalho>
            {(d.students as any[]).map((s) => (
              <TLinha key={s.id} to={`/alunos/${s.id}`} rotulo={`${s.name}, ${s.age}`}>
                <TCelula fixa titulo={s.name}><Avatar name={s.name} seed={s.avatar_seed} size={24} className="mr-2 inline-flex align-middle" /><span className="font-semibold">{s.name}</span></TCelula>
                <TCelula className="text-muted">{s.age}</TCelula>
                <TCelula className={s.is_primary ? 'font-semibold text-purple-800' : ''}>{PARENTESCO[s.relationship] ?? s.relationship}{s.is_primary ? ' · principal' : ''}</TCelula>
                <TCelula titulo={s.unit ?? undefined} className="text-muted">{s.unit ?? 'sem matrícula'}</TCelula>
                <TCelula className={s.same_address === false ? 'font-semibold text-amber-700' : 'text-muted'}>{s.same_address === false ? 'mora em outro' : 'mesmo endereço'}</TCelula>
              </TLinha>
            ))}
            {!d.students.length && <p className="px-3 py-3 text-[13px] text-muted">Nenhuma criança vinculada.</p>}
          </Tabela>
        </Card>
      </Section>

      {((d.household as any[]).length > 0 || (d.household_members as any[]).length > 0) && (
        <Section title="Composição familiar">
          <Card className="overflow-hidden">
            <Tabela rotulo="Composição familiar" largura={680} colunas="minmax(200px,1.6fr) minmax(170px,1.3fr) 84px minmax(120px,1fr) 112px">
              <TCabecalho><span>Pessoa</span><span>Relação</span><span>Idade</span><span>Ocupação</span><span className="text-right">Renda</span></TCabecalho>
              {(d.household as any[]).map((h) => (
                <TLinha key={h.id} to={`/responsaveis/${h.id}`}>
                  <TCelula fixa titulo={h.full_name}><Avatar name={h.full_name} seed={h.full_name} size={24} className="mr-2 inline-flex align-middle" /><span className="font-semibold">{h.full_name}</span></TCelula>
                  <TCelula className="text-muted">responsável por {h.shared_students} criança(s)</TCelula>
                  <TCelula className="text-muted">—</TCelula>
                  <TCelula className="text-muted">{h.occupation ?? '—'}</TCelula>
                  <TCelula className="text-right tabular text-muted">{h.monthly_income != null ? fmtMoeda(h.monthly_income) : '—'}</TCelula>
                </TLinha>
              ))}
              {(d.household_members as any[]).map((m) => (
                <TLinha key={m.id}>
                  <TCelula fixa titulo={m.name}><span className="mr-2 inline-flex size-6 items-center justify-center rounded-full bg-slate-100 align-middle"><Users className="size-3.5 text-ink-2" /></span><span className="font-semibold">{m.name}</span></TCelula>
                  <TCelula className="text-muted">{PARENTESCO_DOMICILIO[m.relationship] ?? m.relationship} · mora na casa</TCelula>
                  <TCelula className="text-muted">{m.age ?? '—'}</TCelula>
                  <TCelula className="text-muted">{m.occupation ?? '—'}</TCelula>
                  <TCelula className="text-right tabular text-muted">{m.income != null ? fmtMoeda(m.income) : '—'}</TCelula>
                </TLinha>
              ))}
            </Tabela>
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
      <p className="mt-6 flex items-center justify-center gap-1 text-center text-[12px] text-muted"><ShieldCheck className="size-3.5" />Acesso registrado conforme LGPD</p>
    </div>
  );
}
