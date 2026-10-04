import { Link } from 'react-router';
import { Clock } from 'lucide-react';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { timeLeft } from '@/lib/format';
import { OFFER_STATUS, SHIFT } from '@/lib/labels';
import { Avatar, Badge, Card, EmptyState, ErrorState, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { EnrollmentCard } from '@/components/EnrollmentCard';

export default function Offers() {
  const { me } = useSession();
  const unitId = me?.scope === 'UNIT' ? me.unit?.id : undefined;
  const res = useRpc<any>('offers_list', { unit_id: unitId ?? null }, { refetchInterval: 30_000 });
  const now = useNow(30_000);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const items = res.data.items as any[];
  const accepted = items.filter((o) => o.status === 'ACCEPTED');
  const pending = items.filter((o) => o.status === 'OFFERED');
  return (
    <div>
      <PageHeader
        eyebrow="Ofertas e matrículas"
        title={unitId ? 'Matrículas para concluir' : 'Ofertas em andamento'}
        subtitle="Aceite não é matrícula: a unidade confere os documentos e confirma. Silêncio não é aceite nem recusa — no fim do prazo a vaga é liberada e a criança volta à fila."
      />
      <Section title={`Aceitas · aguardando matrícula (${accepted.length})`} className="mt-0" action={<SourceChip kind="demo" />}>
        {accepted.length ? (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            {accepted.map((o) => (
              <EnrollmentCard key={o.id} item={o} />
            ))}
          </div>
        ) : <Card><EmptyState compact title="Nenhum aceite pendente" /></Card>}
      </Section>
      <Section title={`Aguardando resposta da família (${pending.length})`}>
        <Card className="divide-y divide-line overflow-hidden">
          {pending.map((o) => (
            <Link key={o.id} to={`/alunos/${o.student_id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
              <Avatar name={o.student} seed={o.avatar_seed} size={40} />
              <div className="min-w-0 flex-1">
                <div className="truncate font-semibold">{o.student}</div>
                <div className="truncate text-[12.5px] text-muted">{o.unit} · {o.class} · {SHIFT[o.shift]}</div>
              </div>
              <Badge tone={o.hours_left < 12 ? 'red' : 'amber'} icon={Clock}>{timeLeft(o.expires_at, now)}</Badge>
            </Link>
          ))}
          {!pending.length && <EmptyState compact title="Nenhuma oferta aguardando" />}
        </Card>
      </Section>
      <p className="mt-4 text-center text-[12px] text-muted">{OFFER_STATUS.OFFERED.label}: vaga reservada até a resposta · prazo de 72 h para efetivar a matrícula (IN nº 025/2025, Anexo II)</p>
    </div>
  );
}
