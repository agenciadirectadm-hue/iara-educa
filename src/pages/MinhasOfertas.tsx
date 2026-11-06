import { Link } from 'react-router';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { OFFER_STATUS, SHIFT } from '@/lib/labels';
import { Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonList, SourceChip } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

type Oferta = {
  id: string; crianca: string; unit_id: number; unidade: string; turma: string; turno: string; ofertada_em: string; expira_em: string;
  situacao: string; respondida_em: string | null; motivo: string | null; texto: string | null; canal: string | null;
};

/** A família vê todas as vagas oferecidas às próprias crianças: a unidade, a data e a resposta, com o motivo quando recusou. */
export default function MinhasOfertas() {
  const res = useRpc<{ ofertas: Oferta[] }>('familia_ofertas');
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const ofertas = res.data!.ofertas;
  return (
    <div>
      <PageHeader
        eyebrow="Matrícula"
        title="Ofertas de vaga"
        subtitle="As vagas oferecidas às suas crianças: a unidade, a data e a sua resposta. Pela regra vigente, quem recusa volta à fila sem perder a pontuação."
        actions={<SourceChip kind="demo" />}
      />
      <Card className="overflow-hidden">
        {ofertas.length ? (
          <Tabela rotulo="Ofertas de vaga" largura={960} colunas="80px minmax(200px,1.3fr) 180px minmax(220px,1.4fr) 100px 130px 140px">
            <TCabecalho><span>Criança</span><span>Unidade oferecida</span><span>Situação</span><span>Motivo</span><span>Oferecida em</span><span>Resposta</span><span>Turma</span></TCabecalho>
            {ofertas.map((o) => {
              const motivo = o.motivo ? (o.texto ? `${o.motivo}: ${o.texto}` : o.motivo) : null;
              return (
                <TLinha key={o.id} to={`/unidades/${o.unit_id}`} rotulo={`${o.crianca}, ${o.unidade}, ${OFFER_STATUS[o.situacao]?.label ?? o.situacao}`}>
                  <TCelula fixa className="font-semibold">{o.crianca}</TCelula>
                  <TCelula titulo={o.unidade}>{o.unidade}</TCelula>
                  <TCelula livre><Badge tone={OFFER_STATUS[o.situacao]?.tone ?? 'gray'}>{OFFER_STATUS[o.situacao]?.label ?? o.situacao}</Badge></TCelula>
                  <TCelula titulo={motivo ?? undefined}>{motivo ?? '—'}</TCelula>
                  <TCelula className="tabular text-muted">{fmtDate(o.ofertada_em)}</TCelula>
                  <TCelula className="tabular text-muted">{o.respondida_em ? fmtDateTime(o.respondida_em) : '—'}</TCelula>
                  <TCelula className="text-muted" titulo={`${o.turma} · ${SHIFT[o.turno] ?? o.turno}`}>{o.turma} · {SHIFT[o.turno] ?? o.turno}</TCelula>
                </TLinha>
              );
            })}
          </Tabela>
        ) : (
          <EmptyState title="Nenhuma oferta de vaga até agora" body="Quando houver uma vaga para sua criança, avisamos no portal e pela IARA, com a unidade, o turno e o prazo." />
        )}
      </Card>
      {ofertas.some((o) => o.situacao === 'OFFERED') && (
        <p className="mt-3 text-center text-[13px] text-ink-2">Há oferta aguardando sua resposta. <Link to="/inicio" className="font-semibold text-purple-700 underline">Responder no início</Link></p>
      )}
    </div>
  );
}
