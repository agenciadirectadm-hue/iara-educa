import { Link } from 'react-router';
import { Activity, ChevronRight, Database, MapPin, PlugZap, ShieldCheck } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useBootstrap } from '@/lib/data';
import { fmtInt } from '@/lib/format';
import { Badge, Card, ErrorState, Kpi, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { BarList } from '@/components/charts';

const INTEGRATIONS = [
  { name: 'Censo Escolar / INEP', status: 'Carregado (seed)', tone: 'green' as const, detail: 'Microdados 2025: turmas e matrículas por série, turnos por etapa, docentes.' },
  { name: 'Consulta Escolas / SEED-PR', status: 'Carregado (seed)', tone: 'green' as const, detail: 'Oferta e quantitativos 2026 de parte das unidades.' },
  { name: 'Conecta SEDUC (matrícula)', status: 'Adapter simulado', tone: 'amber' as const, detail: 'Fonte transacional prevista para matrículas e turmas nominais.' },
  { name: 'Central de Vagas', status: 'Adapter simulado', tone: 'amber' as const, detail: 'Fila, bloqueios, reservas e movimentações oficiais.' },
  { name: 'RH / lotação', status: 'Pendente', tone: 'gray' as const, detail: 'Professor e auxiliar por turma.' },
];

/** WhatsApp: ponte de teste real (Baileys), ligada só em apresentações; a API oficial com número próprio é da produção. */
const whatsapp = (ativo?: boolean) => ({
  name: 'WhatsApp (ponte de teste)',
  status: ativo ? 'Ligado agora' : 'Desligado',
  tone: ativo ? ('green' as const) : ('gray' as const),
  detail: ativo
    ? 'Ponte de teste ligada: quem conversa com o número de teste recebe respostas de verdade. Produção: API oficial com número próprio da Educação (pendente).'
    : 'Ponte de teste desligada: nenhuma mensagem sai agora. Liga só em apresentações e testes. Produção: API oficial com número próprio da Educação (pendente).',
});

export default function HomeInovacao() {
  const q = useRpc<any>('data_quality');
  const boot = useBootstrap();
  if (q.isLoading) return <SkeletonList rows={5} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const s = q.data.summary;
  const geo = s.geo ?? {};
  return (
    <div>
      <PageHeader eyebrow="Diretoria de Inovação Educacional" title="Os dados estão completos e confiáveis?" subtitle="Cobertura das fontes, pendências para a SEDUC, precisão geográfica e situação das integrações." />
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi icon={Database} tone="purple" label="Pendências abertas" value={fmtInt(s.total)} sub={`${s.by_severity?.ALTA ?? 0} de prioridade alta`} to="/qualidade" />
        <Kpi icon={MapPin} tone="green" label="Coordenadas validadas" value={`${fmtInt(geo.VALIDADO ?? 0)}/118`} sub={`${(geo.APROXIMADO ?? 0) + (geo.PROVISORIO ?? 0)} aproximadas/provisórias`} source="publico" to="/qualidade" />
        <Kpi icon={Activity} tone="blue" label="Unidades no Censo 2025" value={`${fmtInt(s.units_census)}/118`} sub={`${s.without_inep} sem código INEP`} source="oficial" to="/qualidade" />
        <Kpi icon={ShieldCheck} tone="teal" label="Regras vigentes" value={boot.data?.rule_version ?? '—'} sub="motor determinístico" to="/regras" />
      </div>
      <Section title="Pendências por tipo" action={<Link className="text-sm font-semibold text-purple-700" to="/qualidade">Abrir painel</Link>}>
        <Card className="p-3">
          <BarList items={Object.entries(s.by_type ?? {}).map(([k, v]) => ({ key: k, label: k.replaceAll('_', ' ').toLowerCase().replace(/^./, (c) => c.toUpperCase()), value: v as number, to: '/qualidade' }))} />
        </Card>
      </Section>
      <Section title="Integrações" subtitle="Adapters substituíveis — nenhuma integração é dada como concluída sem existir">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {[...INTEGRATIONS, whatsapp(boot.data?.whatsapp?.canal_ativo)].map((i) => (
            <Card key={i.name} className="flex items-start gap-3 p-4">
              <span className="inline-flex size-10 items-center justify-center rounded-2xl bg-slate-100 text-slate-700"><PlugZap className="size-5" /></span>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold">{i.name}</span>
                  <Badge tone={i.tone}>{i.status}</Badge>
                </div>
                <p className="mt-1 text-[13px] text-muted">{i.detail}</p>
              </div>
            </Card>
          ))}
        </div>
      </Section>
      <Section title="Uso da plataforma">
        <Link to="/auditoria" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
          <ShieldCheck className="size-6 text-purple-700" />
          <div className="flex-1"><div className="font-semibold">Trilha de auditoria</div><div className="text-[12.5px] text-muted">Acessos, alterações, exportações e consultas a dados sensíveis</div></div>
          <SourceChip kind="calculado" />
          <ChevronRight className="size-5 text-subtle" />
        </Link>
      </Section>
    </div>
  );
}
