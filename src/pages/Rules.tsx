import { useMemo, useState } from 'react';
import clsx from 'clsx';
import { Ban, Calculator, Check, ChevronDown, Clock, ExternalLink, FileText, FlaskConical, Gauge, History, ListOrdered, Scale, ScrollText, Stethoscope } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { Badge, Card, ErrorState, PageHeader, Section, SkeletonList, SourceChip, type SourceKind } from '@/components/ui';
import { IaraBubble } from '@/components/iara';

const GROUPS: { type: string; title: string; subtitle: string; icon: typeof Scale }[] = [
  { type: 'PRIORIDADE_FILA', title: 'Pontuação da fila', subtitle: 'Critérios de pontuação do Anexo I da IN nº 025/2025 — somam até 100 pontos. Maior pontuação vem primeiro.', icon: ListOrdered },
  { type: 'PRIORIDADE_ANALISE', title: 'Prioridade sob análise', subtitle: 'Fora da soma de pontos: mediante laudo médico com CID, a Central de Vagas analisa o caso e pode ofertar fora da ordem, com justificativa auditada.', icon: Stethoscope },
  { type: 'DESEMPATE', title: 'Desempate', subtitle: 'Com a mesma pontuação, vale a ordem de entrada.', icon: Scale },
  { type: 'ELIMINATORIA', title: 'Eliminatórias da busca de vaga', subtitle: 'Unidades que não passam nestas regras não aparecem como opção.', icon: Ban },
  { type: 'PONTUACAO_UNIDADE', title: 'Ordenação das unidades na busca', subtitle: 'Explicam por que uma unidade aparece antes da outra para a família.', icon: Gauge },
  { type: 'PARAMETRO', title: 'Prazos e consequências', subtitle: 'Parâmetros do fluxo de oferta e matrícula.', icon: Clock },
];

const KIND: Record<string, SourceKind> = { OFICIAL: 'oficial', PUBLICO: 'publico', PENDENTE: 'pendente', DEMO: 'demo' };

function describeCondition(code: string, c: any): string | null {
  if (!c || !Object.keys(c).length) return null;
  if (c.max_m) return `Raio de ${(c.max_m / 1000).toLocaleString('pt-BR')} km entre a residência e a unidade`;
  if (c.per === 'km') return 'Aplicado por quilômetro de distância (linha reta)';
  if (c.cap) return `Por criança à frente, limitado a ${c.cap}`;
  if (c.hours) return `${c.hours} horas para a família responder`;
  if (c.when === 'turno_obrigatorio') return 'Só elimina quando a família marca o turno como obrigatório';
  if (c.evidence === 'declaracao_responsavel') return 'Comprovação: declaração do responsável no cadastro';
  if (c.document === 'LAUDO') return 'Comprovação: laudo médico com informação do(s) CID(s) · não soma pontos';
  if (code === 'RECUSA_OFERTA') return `${c.returns_to_queue ? 'Volta para a fila' : 'Sai da fila'}${c.keeps_priority ? ' mantendo os critérios de prioridade' : ''}`;
  return JSON.stringify(c);
}

export default function Rules() {
  const res = useRpc<any>('rules_list', {}, { staleTime: 10 * 60_000 });
  const [history, setHistory] = useState(false);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const items = res.data.items as any[];
  const active = items.filter((r) => r.active);
  const inactive = items.filter((r) => !r.active);
  const official = active.find((r) => r.source_kind === 'OFICIAL' && r.source_url);
  return (
    <div>
      <PageHeader
        eyebrow={`Regras públicas · versão ${res.data.version}`}
        title="Regras e critérios"
        subtitle="Determinísticas, versionadas e auditáveis: a mesma situação sempre gera o mesmo resultado, e cada decisão registra a versão usada."
      />
      {official && (
        <Card className="mb-2 flex items-start gap-3 bg-green-50 p-4 ring-1 ring-green-100">
          <FileText className="mt-0.5 size-5 shrink-0 text-green-800" />
          <div className="min-w-0 text-[13.5px] text-green-950">
            <b>A ordem da fila segue a norma oficial:</b> {official.source} — critérios de equidade e justiça social da Rede Municipal de Ensino para 2026.
            <a href={official.source_url} target="_blank" rel="noreferrer" className="mt-1 flex items-center gap-1 font-semibold text-green-800 underline">
              <ExternalLink className="size-3.5" /> Ver a Instrução Normativa (Prefeitura de Maringá)
            </a>
          </div>
        </Card>
      )}
      <Card className="mb-2 flex items-start gap-3 bg-amber-50 p-4 ring-1 ring-amber-100">
        <FlaskConical className="mt-0.5 size-5 shrink-0 text-amber-700" />
        <p className="text-[13.5px] text-amber-950">
          As demais regras (ordenação das unidades na busca, desempate e prazos) são <b>parametrização de referência</b> para a demonstração e precisam ser
          validadas pela SEDUC. Cada regra registra fonte, justificativa e vigência.
        </p>
      </Card>
      <Simulator rules={active.filter((r) => r.type === 'PRIORIDADE_FILA')} analysis={active.find((r) => r.type === 'PRIORIDADE_ANALISE')} />
      {GROUPS.map((g) => {
        const rs = active.filter((r) => r.type === g.type);
        if (!rs.length) return null;
        return (
          <Section key={g.type} title={<span className="inline-flex items-center gap-2"><g.icon className="size-5 text-purple-700" />{g.title}</span>} subtitle={g.subtitle}>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              {rs.map((r) => <RuleCard key={r.code + r.version} r={r} />)}
            </div>
          </Section>
        );
      })}
      {inactive.length > 0 && (
        <Section title={<span className="inline-flex items-center gap-2"><History className="size-5 text-purple-700" />Histórico de versões</span>} subtitle="Versões substituídas continuam guardadas: decisões antigas mostram a versão com que foram tomadas.">
          <Card className="overflow-hidden">
            <button onClick={() => setHistory(!history)} className="flex min-h-[52px] w-full items-center justify-between px-4 text-left text-[14px] font-semibold hover:bg-slate-50" aria-expanded={history}>
              {inactive.length} regra(s) em versões anteriores
              <ChevronDown className={clsx('size-4 text-subtle transition', history && 'rotate-180')} />
            </button>
            {history && (
              <div className="divide-y divide-line border-t border-line">
                {inactive.map((r) => (
                  <div key={r.code + r.version} className="flex items-center gap-3 px-4 py-2.5 text-[13px]">
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-semibold text-muted line-through decoration-slate-300">{r.name}</div>
                      <div className="font-mono text-[11px] text-subtle">{r.code} · v{r.version}{r.valid_to ? ` · até ${fmtDate(r.valid_to)}` : ''}</div>
                    </div>
                    {Number(r.weight) !== 0 && <span className="font-display font-black tabular text-subtle">{Number(r.weight) > 0 ? '+' : ''}{Number(r.weight)}</span>}
                  </div>
                ))}
              </div>
            )}
          </Card>
        </Section>
      )}
      <IaraBubble compact className="mt-6">
        Quando uma família me pergunta “por que estou nesta posição?”, eu mostro exatamente estes critérios — os que foram aplicados à criança dela, com a versão da regra. Nunca exponho dados de outras famílias.
      </IaraBubble>
    </div>
  );
}

function RuleCard({ r }: { r: any }) {
  const cond = describeCondition(r.code, r.condition);
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="font-display text-[16px] font-extrabold leading-tight">{r.name}</div>
          <div className="mt-0.5 font-mono text-[11.5px] text-muted">{r.code} · v{r.version}</div>
        </div>
        {r.type === 'PRIORIDADE_ANALISE' ? (
          <Badge tone="purple" icon={Stethoscope}>sob análise</Badge>
        ) : Number(r.weight) !== 0 ? (
          <span className={clsx('shrink-0 rounded-2xl px-2.5 py-1 font-display text-lg font-black tabular', Number(r.weight) > 0 ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-700')}>
            {Number(r.weight) > 0 ? '+' : ''}{Number(r.weight)}
          </span>
        ) : <Badge tone="green">ativa</Badge>}
      </div>
      {r.description && <p className="mt-2 text-[13.5px] text-ink-2">{r.description}</p>}
      {cond && <p className="mt-2 rounded-2xl bg-slate-50 px-3 py-2 text-[13px] text-ink-2">{cond}</p>}
      {r.justification && r.source_kind !== 'OFICIAL' && <p className="mt-2 text-[12.5px] text-muted"><b>Justificativa:</b> {r.justification}</p>}
      <div className="mt-3 flex flex-wrap items-center gap-2 text-[11.5px] text-muted">
        <SourceChip kind={KIND[r.source_kind] ?? 'demo'} detail={[r.source, r.source_kind === 'OFICIAL' ? r.justification : null].filter(Boolean).join('\n\n')} />
        {r.source_kind === 'OFICIAL' && <span className="font-semibold text-green-800">{r.source}</span>}
        {r.valid_from && <span>vigente no sistema desde {fmtDate(r.valid_from)}</span>}
        {r.test && <span className="inline-flex items-center gap-1"><Check className="size-3.5 text-green-700" />teste {r.test}</span>}
      </div>
    </Card>
  );
}

/** Simulador transparente: calcula a pontuação de fila com os pesos vigentes. */
function Simulator({ rules, analysis }: { rules: any[]; analysis?: any }) {
  const [on, setOn] = useState<Record<string, boolean>>({});
  const [laudo, setLaudo] = useState(false);
  const total = useMemo(() => rules.reduce((a, r) => a + (on[r.code] ? Number(r.weight) : 0), 0), [rules, on]);
  const max = useMemo(() => rules.reduce((a, r) => a + Number(r.weight), 0), [rules]);
  if (!rules.length) return null;
  return (
    <Section title={<span className="inline-flex items-center gap-2"><Calculator className="size-5 text-purple-700" />Simule a pontuação na fila</span>} subtitle="Marque as situações da criança. O cálculo usa os mesmos pesos do sistema.">
      <Card className="overflow-hidden">
        <div className="grid grid-cols-1 gap-0 md:grid-cols-[1.4fr_1fr]">
          <div className="divide-y divide-line">
            {rules.map((r) => (
              <label key={r.code} className="flex min-h-[56px] cursor-pointer items-center gap-3 px-4 py-2.5 hover:bg-purple-50/50">
                <input type="checkbox" checked={!!on[r.code]} onChange={(e) => setOn({ ...on, [r.code]: e.target.checked })} className="size-5 accent-purple-700" />
                <span className="flex-1 text-[14.5px] font-semibold">{r.name}</span>
                <span className="font-display font-black tabular text-green-700">+{Number(r.weight)}</span>
              </label>
            ))}
            {analysis && (
              <label className="flex min-h-[56px] cursor-pointer items-center gap-3 bg-purple-50/40 px-4 py-2.5 hover:bg-purple-50">
                <input type="checkbox" checked={laudo} onChange={(e) => setLaudo(e.target.checked)} className="size-5 accent-purple-700" />
                <span className="flex-1 text-[14.5px] font-semibold">{analysis.name} <span className="font-normal text-muted">(com laudo)</span></span>
                <Badge tone="purple">sob análise</Badge>
              </label>
            )}
          </div>
          <div className="flex flex-col items-center justify-center gap-1 bg-gradient-to-br from-purple-700 to-purple-900 p-6 text-white">
            <ScrollText className="size-6 text-purple-200" />
            <div className="font-display text-6xl font-black tabular">{total}</div>
            <div className="text-[13px] text-purple-100">de {max} pontos possíveis</div>
            {laudo && (
              <div className="mt-2 rounded-2xl bg-white/15 px-3 py-2 text-center text-[12.5px] text-white">
                + prioridade sob análise: a equipe avalia o laudo e pode ofertar fora da ordem de pontuação.
              </div>
            )}
            <p className="mt-2 text-center text-[12px] text-purple-200">Empate? Vale a data de entrada na fila. A posição final depende de quem mais está na mesma fila.</p>
          </div>
        </div>
      </Card>
    </Section>
  );
}
