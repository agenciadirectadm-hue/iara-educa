import { Link, useParams } from 'react-router';
import { Bell, Home, Lock, Mail, MessageCircle, Phone, ShieldCheck, Wallet } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtDate, timeAgo } from '@/lib/format';
import { CASE_STATUS, CHANNEL, CONV_STATE } from '@/lib/labels';
import { Avatar, Badge, Card, DataPair, EmptyState, ErrorState, ListRow, Section, SkeletonList, SourceChip } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';

export default function GuardianPage() {
  const { id } = useParams();
  const res = useRpc<any>('guardian_detail', { guardian_id: id });
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const g = d.guardian;
  return (
    <div>
      <Crumbs items={[{ label: 'Responsáveis' }, { label: g.full_name }]} />
      <div className="mb-4 flex items-start gap-4">
        <Avatar name={g.full_name} seed={g.full_name} size={68} />
        <div className="min-w-0">
          <div className="text-[12px] font-bold uppercase tracking-[0.12em] text-purple-700">Cadastro 360º do responsável</div>
          <h1 className="font-display text-[24px] font-extrabold leading-tight">{g.full_name}</h1>
          <div className="mt-1 flex flex-wrap gap-1.5">
            {g.cadunico && <Badge tone="purple">CadÚnico</Badge>}
            {g.single_mother && <Badge tone="purple">Mãe solo</Badge>}
            <Badge tone="gray">Prefere {CHANNEL[g.preferred_channel] ?? g.preferred_channel}</Badge>
            {g.is_demo && <Badge tone="amber">Fictício</Badge>}
          </div>
        </div>
      </div>
      {g.contacts_masked && <p className="mb-3 flex items-center gap-2 rounded-2xl bg-slate-100 p-3 text-[13px] text-ink-2"><Lock className="size-4" />CPF e contatos mascarados conforme o seu perfil (mínimo privilégio).</p>}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <dl className="grid grid-cols-2 gap-4">
            <DataPair label="CPF" value={g.cpf ?? '—'} />
            <DataPair label="Nascimento" value={fmtDate(g.birth_date)} />
            <DataPair label="Telefone" value={<span className="inline-flex items-center gap-1"><Phone className="size-3.5" />{g.phone ?? '—'}</span>} />
            <DataPair label="WhatsApp" value={<span className="inline-flex items-center gap-1"><MessageCircle className="size-3.5" />{g.whatsapp ?? '—'}</span>} />
            <DataPair label="E-mail" value={<span className="inline-flex items-center gap-1 break-all"><Mail className="size-3.5" />{g.email ?? '—'}</span>} />
            <DataPair label="Ocupação" value={g.occupation ?? '—'} />
          </dl>
        </Card>
        <Card className="p-4">
          <div className="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><Wallet className="size-4" />Situação socioeconômica <SourceChip kind="demo" /></div>
          <dl className="grid grid-cols-2 gap-4">
            <DataPair label="Faixa de renda" value={g.income_bracket ?? '—'} />
            <DataPair label="Pessoas no domicílio" value={g.household_size ?? '—'} />
            <DataPair label="Situação de trabalho" value={g.employment_status ?? '—'} />
            <DataPair label="Benefícios" value={(g.benefits ?? []).join(', ') || 'Nenhum'} />
            <DataPair label="Escolaridade" value={g.education_level ?? '—'} />
            <DataPair label="Consentimento" value={g.consent?.lgpd_ciencia ? 'Ciente (LGPD)' : '—'} />
          </dl>
          {d.address && <p className="mt-3 flex items-start gap-2 text-[13px] text-ink-2"><Home className="mt-0.5 size-4 shrink-0" />{d.address.line}</p>}
        </Card>
      </div>

      <Section title="Crianças vinculadas">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {(d.students as any[]).map((s) => (
            <Link key={s.id} to={`/alunos/${s.id}`} className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
              <Avatar name={s.name} seed={s.avatar_seed} size={44} />
              <div className="min-w-0 flex-1">
                <div className="truncate font-semibold">{s.name}</div>
                <div className="text-[12.5px] text-muted">{s.age} · {s.relationship?.toLowerCase()} · {s.unit ?? 'sem matrícula'}</div>
              </div>
            </Link>
          ))}
        </div>
      </Section>

      {(d.household as any[]).length > 0 && (
        <Section title="Composição familiar">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.household as any[]).map((h) => (
              <ListRow key={h.id} to={`/responsaveis/${h.id}`} leading={<Avatar name={h.full_name} seed={h.full_name} size={36} />} title={h.full_name} subtitle={`Também responsável por ${h.shared_students} criança(s)`} />
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
