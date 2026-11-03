import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Info, RefreshCw } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { rpc } from '@/lib/api';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Button, Card, ErrorState, PageHeader, Section, SkeletonList } from '@/components/ui';

type Resumo = {
  ano: number; gerado_em: string; periodo_atual: number; rotulos: string[];
  familias: number; alunos: number; creche: number; acompanhados: number; assiduos: number; abaixo_1: number; abaixo_2: number; deixaram_de_receber: number;
  periodos: { periodo: number; acompanhados: number; abaixo: number }[];
  por_regiao: { nome: string; acompanhados: number; abaixo: number | null; assiduos: number }[];
  unidades_mais_abaixo: { nome: string; acompanhados: number; abaixo: number }[];
  nota: string;
};

const pct = (n: number, d: number) => (d ? `${Math.round((100 * n) / d)}%` : '—');

/** Bolsa Família na escola: quantos alunos vêm de famílias do programa e como está a frequência mínima que mantém o benefício.
 * Só números (nenhum nome); a conta é a mesma do Sistema Presença. "Deixaram de receber" = abaixo do mínimo em ao menos um período do ano. */
export default function BolsaFamilia() {
  const qc = useQueryClient();
  const q = useRpc<Resumo>('bolsa_familia_resumo', {});
  const [atualizando, setAtualizando] = useState(false);
  if (q.isLoading) return <SkeletonList rows={6} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const r = q.data!;
  const atualizar = async () => {
    setAtualizando(true);
    try { qc.setQueryData(['bolsa_familia_resumo', {}], await rpc<Resumo>('bolsa_familia_resumo', { atualizar: true })); } finally { setAtualizando(false); }
  };
  const maxReg = Math.max(1, ...r.por_regiao.map((x) => x.acompanhados));

  return (
    <div>
      <PageHeader eyebrow="Visão da cidade" title="Bolsa Família na escola"
        subtitle="Quantos alunos vêm de famílias do Bolsa Família e como está a frequência mínima que mantém o benefício. Só números, sem nomes." />

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <Card className="bg-purple-50 p-4 ring-purple-200">
          <div className="font-display text-[34px] font-black leading-none tabular text-purple-900">{fmtInt(r.alunos)}</div>
          <div className="mt-1 text-[13px] font-semibold text-ink-2">alunos em famílias que recebem o Bolsa Família</div>
          <div className="mt-1 text-[12px] text-muted">{fmtInt(r.familias)} responsáveis com o benefício · {fmtInt(r.acompanhados)} com a frequência acompanhada (4 a 17 anos) · {fmtInt(r.creche)} na creche, sem exigência</div>
        </Card>
        <Card className="p-4">
          <div className="font-display text-[34px] font-black leading-none tabular text-red-700">{fmtInt(r.deixaram_de_receber)}</div>
          <div className="mt-1 text-[13px] font-semibold text-ink-2">deixaram de receber por não alcançar a frequência mínima</div>
          <div className="mt-1 text-[12px] text-muted">{pct(r.deixaram_de_receber, r.acompanhados)} dos acompanhados em {r.ano}: {fmtInt(r.abaixo_1)} em um período, {fmtInt(r.abaixo_2)} em dois ou mais</div>
        </Card>
        <Card className="p-4">
          <div className="font-display text-[34px] font-black leading-none tabular text-green-700">{fmtInt(r.assiduos)}</div>
          <div className="mt-1 text-[13px] font-semibold text-ink-2">têm recebido assiduamente</div>
          <div className="mt-1 text-[12px] text-muted">{pct(r.assiduos, r.acompanhados)} dos acompanhados: sempre dentro do mínimo em {r.ano}</div>
        </Card>
      </div>
      <p className="mt-2 text-[12px] text-muted">
        “Deixaram de receber” conta quem ficou abaixo do mínimo em ao menos um período do ano. Quem aplica o efeito no benefício é o MDS: a primeira vez costuma ser advertência, e o corte vem com a repetição.
      </p>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title={`Frequência mínima por período (${r.ano})`}>
          <Card className="space-y-2.5 p-3">
            {r.periodos.map((x) => (
              <div key={x.periodo}>
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold">{r.rotulos[x.periodo - 1]}{x.periodo === r.periodo_atual ? ' · em andamento' : ''}</span>
                  <span className="tabular text-muted"><b className="text-red-700">{fmtInt(x.abaixo)}</b> abaixo de {fmtInt(x.acompanhados)} ({pct(x.abaixo, x.acompanhados)})</span>
                </div>
                <span className="mt-1 flex h-2 overflow-hidden rounded-full bg-green-500/80" aria-hidden>
                  <span className="ml-auto block h-full bg-red-500" style={{ width: `${x.acompanhados ? (100 * x.abaixo) / x.acompanhados : 0}%` }} />
                </span>
              </div>
            ))}
            <p className="text-[11.5px] text-muted">Verde: dentro do mínimo. Vermelho: abaixo do mínimo no período.</p>
          </Card>
        </Section>

        <Section title="Unidades com mais alunos abaixo do mínimo" subtitle="No ano, em ao menos um período.">
          <Card className="divide-y divide-line">
            {r.unidades_mais_abaixo.length === 0 ? <p className="p-3 text-[13px] text-muted">Nenhuma unidade com 3 ou mais alunos abaixo do mínimo.</p>
              : r.unidades_mais_abaixo.map((u) => (
                <div key={u.nome} className="flex items-center justify-between gap-2 px-3 py-2 text-[13px]">
                  <span className="truncate">{u.nome}</span>
                  <span className="shrink-0 tabular"><b className="text-red-700">{fmtInt(u.abaixo)}</b> <span className="text-muted">de {fmtInt(u.acompanhados)}</span></span>
                </div>
              ))}
          </Card>
        </Section>
      </div>

      <Section title="Por região" subtitle="Alunos acompanhados e quantos ficaram abaixo do mínimo no ano. Regiões com menos de 3 alunos ficam em sigilo.">
        <Card className="grid grid-cols-1 gap-x-6 gap-y-2 p-3 sm:grid-cols-2">
          {r.por_regiao.map((x) => (
            <div key={x.nome} className="text-[12.5px]">
              <div className="flex justify-between gap-2">
                <span className="truncate">{x.nome}</span>
                <span className="shrink-0 tabular text-muted">{x.abaixo == null ? 'menos de 3' : fmtInt(x.abaixo)} abaixo · {fmtInt(x.acompanhados)}</span>
              </div>
              <span className="mt-0.5 block h-1.5 rounded-full bg-slate-100"><span className="block h-full rounded-full bg-purple-500" style={{ width: `${(100 * x.acompanhados) / maxReg}%` }} /></span>
            </div>
          ))}
        </Card>
      </Section>

      <Section title="Quem envia a frequência ao MEC">
        <Card className="space-y-1.5 p-3 text-[13px] text-ink-2">
          <p>A <b>secretaria de cada escola e CMEI</b> (operador escolar) lança no Sistema Presença, a cada dois meses, a frequência de cada aluno do Bolsa Família e, abaixo do mínimo, o motivo.
            O <b>coordenador municipal do Bolsa Família na Educação</b>, indicado pela Secretaria, cadastra os operadores e acompanha o lançamento; em casos excepcionais, lança também.</p>
          <p>O MEC repassa os dados ao <b>MDS</b>, que aplica os efeitos no benefício. A <b>Assistência Social</b> (CRAS) acompanha as famílias que não cumpriram.
            No IARA, a tela Sistema Presença deixa a lista de cada escola pronta para lançar.</p>
        </Card>
      </Section>

      <div className="mt-3 flex flex-wrap items-center justify-between gap-2 text-[12px] text-muted">
        <p className="flex max-w-3xl items-start gap-1.5"><Info className="mt-0.5 size-3.5 shrink-0" />{r.nota}</p>
        <Button size="sm" variant="ghost" icon={RefreshCw} loading={atualizando} onClick={atualizar}>Atualizado em {fmtDateTime(r.gerado_em)}</Button>
      </div>
    </div>
  );
}
