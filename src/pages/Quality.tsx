import { useState } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import { AlertOctagon, AlertTriangle, CheckCircle2, Info, MapPin, Phone, ScanSearch } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtInt } from '@/lib/format';
import { Badge, Card, Chip, EmptyState, ErrorState, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { BarList } from '@/components/charts';
import { IaraBubble } from '@/components/iara';
import { CargaDados } from '@/components/CargaDados';

const TYPE: Record<string, { label: string; hint: string }> = {
  GEO_APROXIMADA: { label: 'Localização aproximada', hint: 'Coordenada pelo bairro/logradouro, sem geocodificação oficial do endereço' },
  CONTATO_AUSENTE: { label: 'Contato ausente', hint: 'Telefone ou e-mail da unidade não encontrado em fonte pública' },
  PENDENCIA_SEDUC: { label: 'Pendente SEDUC', hint: 'Dado que só a SEDUC pode fornecer (capacidade autorizada, normas, quadro funcional)' },
  RECONCILIACAO_REDE: { label: 'Reconciliação da rede', hint: 'Divergência entre listas oficiais (Prefeitura × Censo × SEED)' },
  SITUACAO_OPERACIONAL: { label: 'Situação operacional', hint: 'Unidade em obra, paralisada, nova ou com mudança recente' },
  TURMA_SEM_CAPACIDADE: { label: 'Turma sem capacidade', hint: 'Capacidade autorizada não informada para a turma' },
  SEM_CRUZAMENTO_CENSO_2025: { label: 'Sem cruzamento com o Censo 2025', hint: 'Unidade da lista municipal sem correspondência no microdado do Censo' },
};
const SEV: Record<string, { label: string; tone: 'red' | 'amber' | 'blue'; icon: typeof Info }> = {
  ALTA: { label: 'Alta', tone: 'red', icon: AlertOctagon },
  MEDIA: { label: 'Média', tone: 'amber', icon: AlertTriangle },
  BAIXA: { label: 'Baixa', tone: 'blue', icon: Info },
};
const GEO: Record<string, string> = { EXATA: 'Exata (endereço)', ENDERECO: 'Endereço', LOGRADOURO: 'Logradouro', BAIRRO: 'Bairro (aproximada)', APROXIMADA: 'Aproximada' };

export default function Quality() {
  const res = useRpc<any>('data_quality', {}, { staleTime: 5 * 60_000 });
  const [sev, setSev] = useState<string>('');
  const [type, setType] = useState<string>('');
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const s = res.data.summary;
  const items = (res.data.items as any[]).filter((i) => (!sev || i.severity === sev) && (!type || i.type === type));
  const geo = Object.entries(s.geo ?? {}) as [string, number][];
  return (
    <div>
      <PageHeader
        eyebrow="Governança de dados"
        title="Qualidade de dados"
        subtitle="O que já é oficial, o que é aproximado e o que depende da SEDUC. Nada é inventado: lacunas aparecem como pendências com ação recomendada."
      />
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {(['ALTA', 'MEDIA', 'BAIXA'] as const).map((k) => {
          const I = SEV[k].icon;
          return (
            <button key={k} onClick={() => setSev(sev === k ? '' : k)} className={clsx('rounded-3xl p-4 text-left ring-1 transition active:scale-[0.98]', sev === k ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white ring-line hover:ring-purple-200')}>
              <I className={clsx('size-5', sev === k ? 'text-white' : SEV[k].tone === 'red' ? 'text-red-600' : SEV[k].tone === 'amber' ? 'text-amber-600' : 'text-blue-700')} />
              <div className="mt-2 font-display text-3xl font-black tabular">{fmtInt(s.by_severity?.[k] ?? 0)}</div>
              <div className={clsx('text-[13px] font-semibold', sev === k ? 'text-purple-100' : 'text-muted')}>Severidade {SEV[k].label.toLowerCase()}</div>
            </button>
          );
        })}
        <Card className="p-4">
          <CheckCircle2 className="size-5 text-green-700" />
          <div className="mt-2 font-display text-3xl font-black tabular">{fmtInt(s.units_census)}</div>
          <div className="text-[13px] font-semibold text-muted">unidades cruzadas com o Censo 2025</div>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Precisão da localização das unidades" action={<SourceChip kind="publico" detail="Coordenadas a partir de endereço público; precisão registrada por unidade." />}>
          <Card className="p-4">
            <BarList items={geo.map(([k, v]) => ({ key: k, label: GEO[k] ?? k, value: v, color: k === 'EXATA' || k === 'ENDERECO' ? 'linear-gradient(90deg,#16A36A,#008C72)' : 'linear-gradient(90deg,#F2B640,#F28C38)' }))} valueSuffix=" un." />
            <div className="mt-3 grid grid-cols-2 gap-2 text-[13px]">
              <div className="flex items-center gap-2 rounded-2xl bg-slate-50 p-3"><ScanSearch className="size-4 text-subtle" /> {fmtInt(s.without_inep)} sem código INEP</div>
              <div className="flex items-center gap-2 rounded-2xl bg-slate-50 p-3"><Phone className="size-4 text-subtle" /> {fmtInt(s.without_phone)} sem telefone</div>
            </div>
          </Card>
        </Section>
        <Section title="Pendências por tipo" subtitle="Toque para filtrar a lista">
          <Card className="p-4">
            <BarList items={Object.entries(s.by_type ?? {}).map(([k, v]) => ({ key: k, label: TYPE[k]?.label ?? k, value: v as number, onClick: () => setType(type === k ? '' : k), sub: TYPE[k]?.hint, color: type === k ? '#7A24C5' : undefined }))} />
          </Card>
        </Section>
      </div>

      <Section title={`Pendências (${items.length})`} action={(sev || type) ? <button onClick={() => { setSev(''); setType(''); }} className="text-[13px] font-semibold text-blue-700">Limpar filtros</button> : undefined}>
        <div className="no-scrollbar -mx-4 mb-2 flex gap-2 overflow-x-auto px-4 pb-1">
          <Chip active={!type} onClick={() => setType('')}>Todos os tipos</Chip>
          {Object.keys(s.by_type ?? {}).map((k) => <Chip key={k} active={type === k} onClick={() => setType(type === k ? '' : k)}>{TYPE[k]?.label ?? k}</Chip>)}
        </div>
        {items.length ? (
          <div className="space-y-2">
            {items.map((i) => {
              const sv = SEV[i.severity] ?? SEV.BAIXA;
              return (
                <Card key={i.id} className="p-4">
                  <div className="flex items-start gap-3">
                    <sv.icon className={clsx('mt-0.5 size-5 shrink-0', sv.tone === 'red' ? 'text-red-600' : sv.tone === 'amber' ? 'text-amber-600' : 'text-blue-700')} />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="font-semibold">{i.title}</span>
                        <Badge tone={sv.tone}>{sv.label}</Badge>
                        <Badge tone="gray">{TYPE[i.type]?.label ?? i.type}</Badge>
                      </div>
                      {i.description && <p className="mt-1 text-[13.5px] text-ink-2">{i.description}</p>}
                      {i.action && <p className="mt-2 rounded-2xl bg-purple-50 p-2.5 text-[13px] text-purple-900"><b>Ação recomendada:</b> {i.action}</p>}
                      <div className="mt-2 flex flex-wrap items-center gap-3 text-[12px] text-muted">
                        {i.source && <span>Fonte: {i.source}</span>}
                        {i.unit_id && <Link to={`/unidades/${i.unit_id}`} className="inline-flex items-center gap-1 font-semibold text-blue-700"><MapPin className="size-3.5" />{i.unit_name}</Link>}
                      </div>
                    </div>
                  </div>
                </Card>
              );
            })}
          </div>
        ) : <Card><EmptyState compact title="Nenhuma pendência neste filtro" /></Card>}
      </Section>
      <CargaDados />
      <IaraBubble compact className="mt-6">
        Quando a SEDUC enviar a extração oficial (capacidades, turmas, fila e normas), estas pendências são resolvidas na carga — e os números de demonstração dão lugar aos oficiais, com a mesma tela.
      </IaraBubble>
    </div>
  );
}
