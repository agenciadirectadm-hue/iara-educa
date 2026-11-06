import clsx from 'clsx';
import { ArrowRight, ChevronRight, EyeOff, ListTree, RefreshCw, X } from 'lucide-react';
import { Link } from 'react-router';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Card, ErrorState, SkeletonList, SourceChip } from '@/components/ui';
import { RECORTE_ROTULO, type Quesito, type Recorte, type Tema } from './catalogo';
import { SEMAFORO, corDe, type Classe } from '@/components/map/semaforo';
import { COM_DETALHE, DetalheQuesito, type NivelDetalhe } from './DetalheQuesito';

const num = (v: unknown, sufixo = '') =>
  v == null ? '—' : `${typeof v === 'number' && !Number.isInteger(v) ? v.toLocaleString('pt-BR', { maximumFractionDigits: 1 }) : fmtInt(Number(v))}${sufixo}`;

export type ItemRecorte = { chave: string; valor: number | null; n: number | null; oculto: boolean };
export type DadosRecorte = {
  tipo: 'soma' | 'taxa'; sufixo: string; pior: 'maior' | 'menor'; pela_casa: boolean; minimo: number | null;
  itens: ItemRecorte[]; total: number | null; ocultos: number; nota: string; atualizado_em: string;
};

/** Painel do quesito no mapa unificado: a pergunta, o resumo e o ranking — de pontos (api.mapa_calor) ou de áreas/setores
 * (api.mapa_recorte). No ranking, tocar numa área desce para os setores dela; tocar num setor aproxima o mapa e abre o detalhe dele.
 * Nos pontos, a lista das unidades vem do detalhamento (api.mapa_detalhe): tocar numa unidade desce para ela e dela para as turmas. */
export function PainelQuesito({ tema, quesito, recorte, areaNome, areaId, calor, rec, nomes, classes, onArea, onSetor, onVoltar, can, onDetalhe }: {
  tema: Tema; quesito: Quesito; recorte: Recorte; areaNome: string | null; areaId: number | null;
  calor: { data?: any; isLoading: boolean; isFetching: boolean; error: any; refetch: () => void };
  rec: { data?: DadosRecorte; isLoading: boolean; isFetching: boolean; error: any; refetch: () => void };
  /** Nome de cada chave (id da área ou código do setor). */
  nomes: Map<string, string>;
  /** Cor de cada área ou setor no semáforo (a mesma do mapa). */
  classes: Map<string, Classe | null> | null;
  onArea: (chave: string) => void;
  onSetor: (chave: string) => void;
  onVoltar: () => void;
  can: (perm: string) => boolean;
  /** Abre o detalhamento num nível (unidade, turma, região ou microrregião). */
  onDetalhe: (nivel: NivelDetalhe, id: string | null) => void;
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
          <span className="min-w-0 flex-1">Microrregiões da <b>{areaNome}</b></span>
          {areaId != null && COM_DETALHE.has(quesito.value) && (
            <button type="button" onClick={() => onDetalhe('area', String(areaId))} className="inline-flex items-center gap-0.5 font-semibold underline"><ListTree className="size-3.5" />Detalhar a região</button>
          )}
          {areaId != null && <Link to={`/territorios/${areaId}`} className="inline-flex items-center gap-0.5 font-semibold underline">Ficha da área<ArrowRight className="size-3.5" /></Link>}
          <button type="button" onClick={onVoltar} className="inline-flex items-center gap-1 font-semibold" aria-label="Voltar para a cidade"><X className="size-4" />Cidade</button>
        </div>
      )}
      <div className="mt-3">
        {q.isLoading ? <SkeletonList rows={4} /> : q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : recorte === 'pontos'
          ? <PontosCalor d={calor.data} quesito={quesito} can={can} onDetalhe={onDetalhe} />
          : rec.data ? <Recortes d={rec.data} recorte={recorte} areaNome={areaNome} nomes={nomes} classes={classes} onArea={onArea} onSetor={onSetor} /> : null}
      </div>
    </div>
  );
}

function PontosCalor({ d, quesito, can, onDetalhe }: {
  d: any; quesito: Quesito; can: (perm: string) => boolean; onDetalhe: (nivel: NivelDetalhe, id: string | null) => void;
}) {
  if (!d) return null;
  // com detalhamento: as quebras da cidade e todas as unidades (tocar desce para a unidade e dela para as turmas)
  const detalhe = COM_DETALHE.has(quesito.value);
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
      {!detalhe && (d.ranking?.itens ?? []).length > 0 && (
        <Lista titulo={d.ranking.titulo} itens={(d.ranking.itens as any[]).map((x) => ({ nome: x.nome, detalhe: x.detalhe, valor: num(x.valor, x.sufixo ?? '') }))} />
      )}
      {d.faixas && <Card className="p-3 text-[12.5px]"><div className="mb-1 font-semibold">Esperado para a idade</div><ul className="list-disc space-y-0.5 pl-4">{(d.faixas as string[]).map((f) => <li key={f}>{f}</li>)}</ul></Card>}
      {detalhe && <DetalheQuesito quesito={quesito} nivel="cidade" id={null} can={can} onIr={onDetalhe} embutido />}
      {!detalhe && d.niveis_titulo && d.niveis && <div className="mb-[-6px] text-[12.5px] font-semibold text-ink-2">{d.niveis_titulo}</div>}
      {!detalhe && d.niveis && <Card className="divide-y divide-line text-[13px]">{(d.niveis as any[]).map((n) => <div key={n.rotulo} className="flex justify-between px-3 py-1.5"><span>{n.rotulo}</span><b>{fmtInt(n.n)}</b></div>)}</Card>}
      {!detalhe && d.pendencias && <Card className="divide-y divide-line text-[13px]">{(d.pendencias as any[]).map((n) => <div key={n.item} className="flex justify-between px-3 py-1.5"><span>{n.item}</span><b>{fmtInt(n.n)}</b></div>)}</Card>}
      <p className="text-[12px] leading-relaxed text-muted">{d.nota} Atualizado em {fmtDateTime(d.atualizado_em)}.</p>
    </div>
  );
}

function Recortes({ d, recorte, areaNome, nomes, classes, onArea, onSetor }: {
  d: DadosRecorte; recorte: Recorte; areaNome: string | null; nomes: Map<string, string>; classes: Map<string, Classe | null> | null;
  onArea: (c: string) => void; onSetor: (c: string) => void;
}) {
  const visiveis = d.itens.filter((i) => !i.oculto && i.valor != null);
  const ordem = [...visiveis].sort((a, b) => (d.pior === 'maior' ? (b.valor! - a.valor!) : (a.valor! - b.valor!)));
  const unidade = recorte === 'area' ? 'região(ões)' : 'microrregião(ões)';
  const conta = (k: Classe) => [...(classes?.values() ?? [])].filter((x) => x === k).length;
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
      {classes && (
        <div className="flex flex-wrap gap-1.5 text-[12.5px] font-semibold">
          {(['vermelho', 'amarelo', 'verde'] as Classe[]).map((k) => (
            <span key={k} className="inline-flex items-center gap-1.5 rounded-full bg-slate-50 px-2.5 py-1 ring-1 ring-line">
              <span className="size-2.5 rounded-full" style={{ background: SEMAFORO[k] }} />{conta(k)} {k === 'vermelho' ? 'para agir primeiro' : k === 'amarelo' ? 'intermediária(s)' : 'melhor(es)'}
            </span>
          ))}
        </div>
      )}
      {ordem.length > 0 && (
        <Lista
          titulo={`Onde agir primeiro · toque para ${recorte === 'area' ? 'ver as microrregiões' : 'aproximar'}`}
          itens={ordem.slice(0, 10).map((i) => ({
            nome: nomes.get(i.chave) ?? i.chave,
            detalhe: i.n != null && d.tipo === 'taxa' ? `base ${fmtInt(i.n)}` : undefined,
            valor: num(i.valor, d.sufixo),
            cor: corDe(classes?.get(i.chave) ?? null),
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

function Lista({ titulo, itens }: { titulo: string; itens: { nome: string; detalhe?: string; valor: string; cor?: string; onClick?: () => void }[] }) {
  return (
    <div>
      <div className="mb-1 text-[12.5px] font-semibold text-ink-2">{titulo}</div>
      <Card className="divide-y divide-line">
        {itens.map((x, i) => {
          const conteudo = (
            <>
              {x.cor ? <span className="size-3 shrink-0 rounded-full" style={{ background: x.cor }} aria-hidden /> : null}
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
