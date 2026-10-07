import { Database, FileCheck2 } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Card, EmptyState, Section } from '@/components/ui';

type Cargas = {
  dominios: { codigo: string; nome: string; ordem: number; depende_de: string[]; campos: number; carregados: number }[];
  lotes: {
    codigo: string; dominio: string; situacao: string; ensaio: boolean; arquivo: string; origem: string; data_referencia: string;
    responsavel: string; linhas: number; ok: number | null; aviso: number | null; erro: number | null;
    resultado: { criados?: number; atualizados?: number } | null; recebido_em: string; promovido_em: string | null;
  }[];
};

const SITUACAO: Record<string, { label: string; tone: 'green' | 'amber' | 'red' | 'gray' | 'blue' | 'purple' }> = {
  RECEBIDO: { label: 'recebido', tone: 'blue' },
  VALIDADO: { label: 'validado', tone: 'purple' },
  COM_ERROS: { label: 'com erros', tone: 'red' },
  PROMOVIDO: { label: 'no sistema', tone: 'green' },
  REVERTIDO: { label: 'revertido', tone: 'amber' },
};

/**
 * Carga dos dados reais (seção 9 do documento de estrutura): domínios na ordem de carga, quantos registros oficiais
 * já entraram em cada um e os lotes recebidos. Sem dados pessoais — só contagens e situação.
 */
export function CargaDados() {
  const q = useRpc<Cargas>('cargas_lista', {}, { staleTime: 60_000 });
  if (!q.data) return null;
  const { dominios, lotes } = q.data;
  return (
    <Section title={<span className="inline-flex items-center gap-2"><Database className="size-5 text-purple-700" />Carga dos dados reais</span>}
      subtitle="Os dados oficiais entram por lotes validados e conciliados, um domínio por vez, nesta ordem. Nada é carregado por fora deste caminho.">
      <Card className="p-4">
        <ol className="grid grid-cols-2 gap-2 text-[13px] sm:grid-cols-4">
          {dominios.map((d) => (
            <li key={d.codigo} className="rounded-2xl bg-slate-50 px-3 py-2 ring-1 ring-line">
              <div className="text-[11px] font-bold uppercase tracking-wide text-subtle">{d.ordem}. {d.codigo}</div>
              <div className="font-semibold leading-tight">{d.nome}</div>
              <div className="text-[12px] text-muted">{d.carregados ? `${fmtInt(d.carregados)} carregado(s)` : 'nada carregado ainda'} · {d.campos} campos</div>
            </li>
          ))}
        </ol>
        {lotes.length ? (
          <ul className="mt-4 divide-y divide-line">
            {lotes.map((l) => {
              const s = SITUACAO[l.situacao] ?? { label: l.situacao.toLowerCase(), tone: 'gray' as const };
              return (
                <li key={l.codigo} className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 text-[13px]">
                  <FileCheck2 className="size-4 text-purple-700" />
                  <span className="font-mono text-[12px]">{l.codigo}</span>
                  <Badge tone={s.tone}>{s.label}</Badge>
                  {l.ensaio && <Badge tone="amber">ensaio</Badge>}
                  <span className="text-muted">{l.dominio} · {fmtInt(l.linhas)} linha(s){l.erro ? ` · ${fmtInt(l.erro)} com erro` : ''}{l.resultado ? ` · ${fmtInt(l.resultado.criados ?? 0)} criado(s), ${fmtInt(l.resultado.atualizados ?? 0)} atualizado(s)` : ''}</span>
                  <span className="ml-auto text-[12px] text-subtle">{l.origem} · ref. {l.data_referencia} · {fmtDateTime(l.promovido_em ?? l.recebido_em)}</span>
                </li>
              );
            })}
          </ul>
        ) : (
          <div className="mt-3"><EmptyState compact title="Nenhum lote recebido" body="A estrutura de carga está pronta e ensaiada com arquivos fictícios. Os dados reais entram no ambiente de produção." /></div>
        )}
      </Card>
    </Section>
  );
}
