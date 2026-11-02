import clsx from 'clsx';
import { ArrowRight, ChevronRight, EyeOff, RefreshCw, X } from 'lucide-react';
import { Link } from 'react-router';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Card, ErrorState, SkeletonList, SourceChip } from '@/components/ui';
import { RECORTE_ROTULO, type Quesito, type Recorte, type Tema } from './catalogo';

const num = (v: unknown, sufixo = '') =>
  v == null ? '—' : `${typeof v === 'number' && !Number.isInteger(v) ? v.toLocaleString('pt-BR', { maximumFractionDigits: 1 }) : fmtInt(Number(v))}${sufixo}`;

export type ItemRecorte = { chave: string; valor: number | null; n: number | null; oculto: boolean };
export type DadosRecorte = {
  tipo: 'soma' | 'taxa'; sufixo: string; pior: 'maior' | 'menor'; pela_casa: boolean; minimo: number | null;
  itens: ItemRecorte[]; total: number | null; ocultos: number; nota: string; atualizado_em: string;
};

/** Painel do quesito no mapa unificado: a pergunta, o resumo e o ranking — de pontos (api.mapa_calor) ou de áreas/setores
 * (api.mapa_recorte). No ranking, tocar numa área desce para os setores dela; tocar num setor aproxima o mapa. */
export function PainelQuesito({ tema, quesito, recorte, areaNome, areaId, calor, rec, nomes, onArea, onSetor, onVoltar }: {
  tema: Tema; quesito: Quesito; recorte: Recorte; areaNome: string | null; areaId: number | null;
  calor: { data?: any; isLoading: boolean; isFetching: boolean; error: any; refetch: () => void };
  rec: { data?: DadosRecorte; isLoading: boolean; isFetching: boolean; error: any; refetch: () => void };
  /** Nome de cada chave (id da área ou código do setor). */
  nomes: Map<string, string>;
  onArea: (chave: string) => void;
  onSetor: (chave: string) => void;
  onVoltar: () => void;
}) {
  const pergunta = recorte !== 'pontos' && quesito.perguntaRecorte ? quesito.perguntaRecorte : quesito.pergunta;
  const q = recorte === 'pontos' ? calor : rec;
  return (
    <div>
      <div className="flex items-center gap-2 text-[11.5px] font-bold uppercase tracking-wide text-purple-700">
        <span>{tema.label} · {RECORTE_ROTULO[recorte]}</span>
        <SourceChip kind={quesito.fonte} />
        {q.isFetching && <RefreshCw className="size-3.5 animate-spin text-subtle" aria-label="Atualizando" />}
      </div>
      <h2 className="mt-1 font-display text-lg font-extrabold leading-snug">{pergunta}</h2>
      {areaNome && (
        <div className="mt-2 flex flex-wrap items-center gap-2 rounded-2xl bg-purple-50 px-3 py-2 text-[13px] text-purple-900">
          <span className="min-w-0 flex-1">Setores da <b>{areaNome}</b></span>
          {areaId != null && <Link to={`/territorios/${areaId}`} className="inline-flex items-center gap-0.5 font-semibold underline">Ficha da área<ArrowRight className="size-3.5" /></Link>}
          <button type="button" onClick={onVoltar} className="inline-flex items-center gap-1 font-semibold" aria-label="Voltar para a cidade"><X className="size-4" />Cidade</button>
        </div>
      )}
      <div className="mt-3">
        {q.isLoading ? <SkeletonList rows={4} /> : q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : recorte === 'pontos'
          ? <PontosCalor d={calor.data} />
          : rec.data ? <Recortes d={rec.data} recorte={recorte} areaNome={areaNome} nomes={nomes} onArea={onArea} onSetor={onSetor} /> : null}
      </div>
    </div>
  );
}

function PontosCalor({ d }: { d: any }) {
  if (!d) return null;
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        {(d.resumo as any[]).map((k) => (
          <Card key={k.rotulo} className="p-3">
            <div className="font-display text-[22px] font-extrabold leading-none">{num(k.valor, k.sufixo ?? '')}</div>
            <div className="mt-1 text-[12px] leading-tight text-muted">{k.rotulo}</div>
          </Card>
        ))}
      </div>
      {(d.ranking?.itens ?? []).length > 0 && (
        <Lista titulo={d.ranking.titulo} itens={(d.ranking.itens as any[]).map((x) => ({ nome: x.nome, detalhe: x.detalhe, valor: num(x.valor, x.sufixo ?? '') }))} />
      )}
      {d.faixas && <Card className="p-3 text-[12.5px]"><div className="mb-1 font-semibold">Esperado para a idade</div><ul className="list-disc space-y-0.5 pl-4">{(d.faixas as string[]).map((f) => <li key={f}>{f}</li>)}</ul></Card>}
      {d.niveis && <Card className="divide-y divide-line text-[13px]">{(d.niveis as any[]).map((n) => <div key={n.rotulo} className="flex justify-between px-3 py-1.5"><span>{n.rotulo}</span><b>{fmtInt(n.n)}</b></div>)}</Card>}
      {d.pendencias && <Card className="divide-y divide-line text-[13px]">{(d.pendencias as any[]).map((n) => <div key={n.item} className="flex justify-between px-3 py-1.5"><span>{n.item}</span><b>{fmtInt(n.n)}</b></div>)}</Card>}
      <p className="text-[12px] leading-relaxed text-muted">{d.nota} Atualizado em {fmtDateTime(d.atualizado_em)}.</p>
    </div>
  );
}

function Recortes({ d, recorte, areaNome, nomes, onArea, onSetor }: {
  d: DadosRecorte; recorte: Recorte; areaNome: string | null; nomes: Map<string, string>; onArea: (c: string) => void; onSetor: (c: string) => void;
}) {
  const visiveis = d.itens.filter((i) => !i.oculto && i.valor != null);
  const ordem = [...visiveis].sort((a, b) => (d.pior === 'maior' ? (b.valor! - a.valor!) : (a.valor! - b.valor!)));
  const unidade = recorte === 'area' ? 'área(s)' : 'setor(es)';
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        <Card className="p-3">
          <div className="font-display text-[22px] font-extrabold leading-none">{num(d.total, d.sufixo)}</div>
          <div className="mt-1 text-[12px] leading-tight text-muted">{d.tipo === 'taxa' ? 'Taxa' : 'Total'} {areaNome ? 'na área' : 'na cidade'}</div>
        </Card>
        <Card className="p-3">
          <div className="font-display text-[22px] font-extrabold leading-none">{fmtInt(visiveis.length)}</div>
          <div className="mt-1 text-[12px] leading-tight text-muted">{unidade} com valor{d.ocultos ? ` · ${d.ocultos} em sigilo` : ''}</div>
        </Card>
      </div>
      {ordem.length > 0 && (
        <Lista
          titulo={`${d.pior === 'maior' ? 'Maiores valores' : 'Menores valores'} · toque para ${recorte === 'area' ? 'ver os setores' : 'aproximar'}`}
          itens={ordem.slice(0, 10).map((i) => ({
            nome: nomes.get(i.chave) ?? i.chave,
            detalhe: i.n != null && d.tipo === 'taxa' ? `base ${fmtInt(i.n)}` : undefined,
            valor: num(i.valor, d.sufixo),
            onClick: () => (recorte === 'area' ? onArea(i.chave) : onSetor(i.chave)),
          }))}
        />
      )}
      {d.ocultos > 0 && (
        <p className="flex items-start gap-1.5 text-[12px] text-muted"><EyeOff className="mt-0.5 size-3.5 shrink-0" />{d.ocultos} {unidade} sem valor no mapa (cinza): {d.pela_casa ? `menos de ${d.minimo} pessoas, por sigilo` : 'sigilo do IBGE'}.</p>
      )}
      <p className="text-[12px] leading-relaxed text-muted">{d.nota} Atualizado em {fmtDateTime(d.atualizado_em)}.</p>
    </div>
  );
}

function Lista({ titulo, itens }: { titulo: string; itens: { nome: string; detalhe?: string; valor: string; onClick?: () => void }[] }) {
  return (
    <div>
      <div className="mb-1 text-[12.5px] font-semibold text-ink-2">{titulo}</div>
      <Card className="divide-y divide-line">
        {itens.map((x, i) => {
          const conteudo = (
            <>
              <span className="w-5 shrink-0 text-right font-bold text-subtle">{i + 1}</span>
              <span className="min-w-0 flex-1 truncate" title={`${x.nome}${x.detalhe ? ` · ${x.detalhe}` : ''}`}><b>{x.nome}</b>{x.detalhe && <span className="text-muted"> · {x.detalhe}</span>}</span>
              <span className="shrink-0 font-semibold tabular">{x.valor}</span>
              {x.onClick && <ChevronRight className="size-4 shrink-0 text-subtle" />}
            </>
          );
          return x.onClick
            ? <button key={i} type="button" onClick={x.onClick} className={clsx('flex w-full items-center gap-2 px-3 py-2 text-left text-[13px] hover:bg-purple-50')}>{conteudo}</button>
            : <div key={i} className="flex items-center gap-2 px-3 py-2 text-[13px]">{conteudo}</div>;
        })}
      </Card>
    </div>
  );
}
