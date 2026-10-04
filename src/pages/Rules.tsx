import { useMemo, useState } from 'react';
import clsx from 'clsx';
import { Ban, Calculator, Check, Clock, FlaskConical, Gauge, ListOrdered, Scale, ScrollText } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { Badge, Card, ErrorState, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { IaraBubble } from '@/components/iara';

const GROUPS: { type: string; title: string; subtitle: string; icon: typeof Scale }[] = [
  { type: 'PRIORIDADE_FILA', title: 'Prioridade na fila', subtitle: 'Somam pontos para a criança na fila de uma unidade/faixa. Maior pontuação vem primeiro.', icon: ListOrdered },
  { type: 'DESEMPATE', title: 'Desempate', subtitle: 'Com a mesma pontuação, vale a ordem de entrada.', icon: Scale },
  { type: 'ELIMINATORIA', title: 'Eliminatórias da busca de vaga', subtitle: 'Unidades que não passam nestas regras não aparecem como opção.', icon: Ban },
  { type: 'PONTUACAO_UNIDADE', title: 'Ordenação das unidades na busca', subtitle: 'Explicam por que uma unidade aparece antes da outra para a família.', icon: Gauge },
  { type: 'PARAMETRO', title: 'Prazos e consequências', subtitle: 'Parâmetros do fluxo de oferta e matrícula.', icon: Clock },
];

function describeCondition(code: string, c: any): string | null {
  if (!c || !Object.keys(c).length) return null;
  if (c.max_m) return `Raio de ${(c.max_m / 1000).toLocaleString('pt-BR')} km entre a residência e a unidade`;
  if (c.per === 'km') return 'Aplicado por quilômetro de distância (linha reta)';
  if (c.cap) return `Por criança à frente, limitado a ${c.cap}`;
  if (c.hours) return `${c.hours} horas para a família responder`;
  if (c.when === 'turno_obrigatorio') return 'Só elimina quando a família marca o turno como obrigatório';
  if (code === 'RECUSA_OFERTA') return `${c.returns_to_queue ? 'Volta para a fila' : 'Sai da fila'}${c.keeps_priority ? ' mantendo os critérios de prioridade' : ''}`;
  return JSON.stringify(c);
}

export default function Rules() {
  const res = useRpc<any>('rules_list', {}, { staleTime: 10 * 60_000 });
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const items = res.data.items as any[];
  return (
    <div>
      <PageHeader
        eyebrow={`Regras públicas · versão ${res.data.version}`}
        title="Regras e critérios"
        subtitle="Determinísticas, versionadas e auditáveis: a mesma situação sempre gera o mesmo resultado, e cada decisão registra a versão usada."
      />
      <Card className="mb-2 flex items-start gap-3 bg-amber-50 p-4 ring-1 ring-amber-100">
        <FlaskConical className="mt-0.5 size-5 shrink-0 text-amber-700" />
        <p className="text-[13.5px] text-amber-950">
          Pesos e parâmetros abaixo são uma <b>parametrização de referência</b> para a demonstração. Antes do uso real, cada regra precisa ser validada pela SEDUC
          contra a norma municipal vigente — o sistema já registra fonte, justificativa e vigência de cada uma.
        </p>
      </Card>
      <Simulator rules={items.filter((r) => r.type === 'PRIORIDADE_FILA' && r.active)} />
      {GROUPS.map((g) => {
        const rs = items.filter((r) => r.type === g.type);
        if (!rs.length) return null;
        return (
          <Section key={g.type} title={<span className="inline-flex items-center gap-2"><g.icon className="size-5 text-purple-700" />{g.title}</span>} subtitle={g.subtitle}>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              {rs.map((r) => (
                <Card key={r.code} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="font-display text-[16px] font-extrabold leading-tight">{r.name}</div>
                      <div className="mt-0.5 font-mono text-[11.5px] text-muted">{r.code} · v{r.version}</div>
                    </div>
                    {Number(r.weight) !== 0 ? (
                      <span className={clsx('shrink-0 rounded-2xl px-2.5 py-1 font-display text-lg font-black tabular', Number(r.weight) > 0 ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-700')}>
                        {Number(r.weight) > 0 ? '+' : ''}{Number(r.weight)}
                      </span>
                    ) : <Badge tone={r.active ? 'green' : 'gray'}>{r.active ? 'ativa' : 'inativa'}</Badge>}
                  </div>
                  {r.description && <p className="mt-2 text-[13.5px] text-ink-2">{r.description}</p>}
                  {describeCondition(r.code, r.condition) && <p className="mt-2 rounded-2xl bg-slate-50 px-3 py-2 text-[13px] text-ink-2">{describeCondition(r.code, r.condition)}</p>}
                  {r.justification && <p className="mt-2 text-[12.5px] text-muted"><b>Justificativa:</b> {r.justification}</p>}
                  <div className="mt-3 flex flex-wrap items-center gap-2 text-[11.5px] text-muted">
                    <SourceChip kind="demo" detail={r.source} />
                    {r.valid_from && <span>vigente desde {fmtDate(r.valid_from)}</span>}
                    {r.test && <span className="inline-flex items-center gap-1"><Check className="size-3.5 text-green-700" />teste {r.test}</span>}
                  </div>
                </Card>
              ))}
            </div>
          </Section>
        );
      })}
      <IaraBubble compact className="mt-6">
        Quando uma família me pergunta “por que estou nesta posição?”, eu mostro exatamente estes critérios — os que foram aplicados à criança dela, com a versão da regra. Nunca exponho dados de outras famílias.
      </IaraBubble>
    </div>
  );
}

/** Simulador transparente: calcula a pontuação de fila com os pesos vigentes. */
function Simulator({ rules }: { rules: any[] }) {
  const [on, setOn] = useState<Record<string, boolean>>({});
  const total = useMemo(() => rules.reduce((a, r) => a + (on[r.code] ? Number(r.weight) : 0), 0), [rules, on]);
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
          </div>
          <div className="flex flex-col items-center justify-center gap-1 bg-gradient-to-br from-purple-700 to-purple-900 p-6 text-white">
            <ScrollText className="size-6 text-purple-200" />
            <div className="font-display text-6xl font-black tabular">{total}</div>
            <div className="text-[13px] text-purple-100">pontos de prioridade</div>
            <p className="mt-2 text-center text-[12px] text-purple-200">Empate? Vale a data de entrada na fila. A posição final depende de quem mais está na mesma fila.</p>
          </div>
        </div>
      </Card>
    </Section>
  );
}
