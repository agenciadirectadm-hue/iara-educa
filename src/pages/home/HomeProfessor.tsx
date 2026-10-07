import { Link } from 'react-router';
import { CalendarCheck, ChevronRight, Clock, IdCard } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { firstName, fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { hojeISO } from '@/lib/escola';
import { Badge, Card, EmptyState, LinkCard, Section, Skeleton, Simulado } from '@/components/ui';
import { GradeHorario, ProximosEventos, PublicacaoCard } from '@/components/escola';
import { IaraMascot } from '@/components/iara';

/** Início do professor: a chamada de hoje de cada turma, o horário da semana, o mural e o calendário. */
export default function HomeProfessor() {
  const { me } = useSession();
  const turmas = me?.turmas ?? [];
  const ficha = useRpc<any>('pessoal_ficha', { id: me?.staff?.id }, { enabled: !!me?.staff?.id });
  const mural = useRpc<any>('mural_feed', {});
  return (
    <div>
      <div className="flex items-end gap-2">
        <div className="min-w-0 flex-1 pb-2">
          <div className="text-[13px] font-bold uppercase tracking-[0.12em] text-purple-700">{me?.unit?.name}</div>
          <h1 className="mt-1 font-display text-[28px] font-black leading-[1.08] text-ink sm:text-4xl">
            Bom trabalho, {firstName(me?.staff?.name ?? me?.display_name)}!
          </h1>
          <p className="mt-1.5 text-[15px] text-muted">A chamada leva um minuto: toque em quem faltou e registre. A família vê no portal e pela IARA.</p>
        </div>
        <IaraMascot height={130} mood="wave" className="-mb-1 hidden shrink-0 sm:block" />
      </div>

      <Section title="Chamada de hoje" className="mt-4" action={<Simulado detail="Servidores, alunos e faltas são fictícios; turmas e unidades seguem o Censo 2025." />}>
        {turmas.length ? (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {turmas.map((t) => <TurmaHoje key={t.id} t={t} />)}
          </div>
        ) : <Card><EmptyState compact title="Nenhuma turma atribuída" body="Quando a direção atribuir aulas a você, as turmas aparecem aqui." /></Card>}
      </Section>

      <Section title="Meu horário" subtitle={ficha.data ? `${fmtInt(ficha.data.carga?.atribuidas)} aulas por semana · jornada de ${ficha.data.ch ?? '—'} h` : undefined}
        action={me?.staff?.id ? <Link to={`/pessoal/${me.staff.id}`} className="inline-flex items-center gap-1 text-[13px] font-semibold text-blue-700"><IdCard className="size-4" />Minha ficha</Link> : undefined}>
        <Card className="p-3">
          {ficha.isLoading ? <Skeleton className="h-48" /> : (
            <GradeHorario aulas={ficha.data?.horario ?? []} rotulo="Meu horário semanal" celula={(a) => ({ titulo: a.turma, sub: a.componente })} />
          )}
        </Card>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Mural da escola" action={<Link to="/mural" className="text-[13px] font-semibold text-blue-700">Ver tudo</Link>}>
          <div className="space-y-3">
            {mural.isLoading && <Skeleton className="h-40" />}
            {((mural.data?.publicacoes ?? []) as any[]).slice(0, 2).map((p) => <PublicacaoCard key={p.id} p={p} />)}
          </div>
        </Section>
        <Section title="Próximos dias">
          <ProximosEventos limite={7} />
        </Section>
      </div>
    </div>
  );
}

function TurmaHoje({ t }: { t: { id: string; name: string; shift: string; grade?: string } }) {
  const res = useRpc<any>('frequencia_turma', { class_id: t.id, data: hojeISO() });
  const d = res.data;
  const faltas = d ? (d.alunos as any[]).filter((a) => a.falta).length : 0;
  return (
    <LinkCard to={`/turmas/${t.id}/chamada`} className="p-4" ariaLabel={`Chamada de ${t.name}`}>
      <div className="flex items-start gap-3">
        <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-700 text-white shadow-sm">
          <CalendarCheck className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="truncate font-display text-[17px] font-extrabold">{t.name}</div>
          <div className="text-[12.5px] text-muted">{t.grade ?? ''} · {SHIFT[t.shift] ?? t.shift}{d ? ` · ${fmtInt(d.alunos.length)} alunos` : ''}</div>
        </div>
        <ChevronRight className="mt-1 size-5 text-subtle" />
      </div>
      <div className="mt-3">
        {res.isLoading ? <Skeleton className="h-6 w-40" /> : !d?.dia_letivo ? (
          <Badge tone="gray">{d?.evento?.titulo ?? 'Hoje não tem aula'}</Badge>
        ) : d.registrado ? (
          <Badge tone="green" icon={CalendarCheck}>Chamada feita · {faltas} falta(s)</Badge>
        ) : <Badge tone="amber" icon={Clock}>Fazer a chamada</Badge>}
      </div>
    </LinkCard>
  );
}
