import { useState } from 'react';
import { ArrowLeft, ArrowRight, ChevronRight, EyeOff, RefreshCw, X } from 'lucide-react';
import { Link } from 'react-router';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Card, ErrorState, SkeletonList, SourceChip } from '@/components/ui';
import { classe, corDe, cortes } from '@/components/map/semaforo';
import type { Quesito } from './catalogo';

/** Níveis do detalhamento: cidade → unidade → turma; região → microrregião (e, delas, as unidades onde as pessoas estudam). */
export type NivelDetalhe = 'cidade' | 'unidade' | 'turma' | 'area' | 'setor';

type Item = { rotulo: string; valor: number | null; n: number };
type Quebra = { titulo: string; mostra: 'valor' | 'n'; itens: Item[] };
type Filho = { id: string; nome: string; detalhe?: string; valor: number | null; n: number };
export type Detalhe = {
  camada: string; nivel: NivelDetalhe; id: string | null; nome: string; pai: { nivel: NivelDetalhe; id?: string; nome: string } | null;
  tipo: 'soma' | 'taxa'; sufixo: string; pior: 'maior' | 'menor'; pela_casa: boolean; sigilo: boolean; minimo?: number;
  valor?: number | null; linhas?: number; rede?: number | null; media?: number | null; referencia?: string | null;
  posicao?: { posicao: number; de: number } | null; quebras?: Quebra[]; filhos?: { nivel: NivelDetalhe; titulo: string; itens: Filho[] } | null;
  atualizado_em: string;
};

/** Quesitos do mapa com detalhamento (veículos agora e rotas abrem a própria rota). */
export const COM_DETALHE = new Set(['unidades', 'vagas', 'matriculas', 'fila', 'deficit', 'criancas_0a4', 'pessoas', 'fila_casa',
  'transporte_necessidade', 'transporte_oferta', 'transporte_efetividade', 'frequencia', 'faltas', 'ocorrencias',
  'alfa_esperado', 'alfa_precoce', 'alfa_abaixo', 'cadastros', 'formacao']);

const NIVEL_ROTULO: Record<NivelDetalhe, string> = { cidade: 'Cidade', unidade: 'Unidade', turma: 'Turma', area: 'Região', setor: 'Microrregião' };

const fmt = (v: number | null | undefined, sufixo = '') =>
  v == null ? '—' : `${Number.isInteger(Number(v)) ? fmtInt(Number(v)) : Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}${sufixo}`;

/** Para onde ir dali, conforme o quesito e a permissão de quem vê (o Prefeito fica no agregado; a Secretaria abre os casos). */
function linksDe(camada: string, nivel: NivelDetalhe, id: string | null, can: (p: string) => boolean): { rotulo: string; to: string }[] {
  const l: { rotulo: string; to: string }[] = [];
  if (nivel === 'unidade' && id) l.push({ rotulo: 'Ficha da unidade', to: `/unidades/${id}` });
  if (nivel === 'area' && id) l.push({ rotulo: 'Ficha da região', to: `/territorios/${id}` });
  if (nivel === 'turma' && id && can('students.read')) l.push({ rotulo: 'Abrir a turma', to: `/turmas/${id}` });
  if (nivel !== 'unidade' && nivel !== 'turma') return l;
  if (camada === 'ocorrencias' && can('ocorrencias.read')) l.push({ rotulo: 'Abrir as ocorrências', to: '/ocorrencias' });
  if ((camada === 'frequencia' || camada === 'faltas') && can('frequencia.read')) {
    l.push({ rotulo: 'Abrir a frequência', to: '/frequencia' }, { rotulo: 'Abrir a busca ativa', to: '/busca-ativa' });
  }
  if (['fila', 'fila_casa', 'deficit'].includes(camada) && nivel === 'unidade' && can('queue.read')) l.push({ rotulo: 'Abrir a fila da unidade', to: `/fila?unidade=${id}` });
  if (camada.startsWith('alfa_') && nivel === 'unidade' && can('students.read')) l.push({ rotulo: 'Abrir o desempenho', to: `/desempenho?unidade=${id}` });
  if (camada === 'formacao' && can('pessoal.read')) l.push({ rotulo: 'Abrir o quadro de pessoal', to: '/pessoal' });
  if (camada.startsWith('transporte_') && can('transporte.read')) l.push({ rotulo: 'Abrir o transporte', to: '/transporte' });
  return l;
}

/** Detalhamento de um quesito do mapa num nível (api.mapa_detalhe): o valor ao lado da referência e da posição entre os
 * pares, as quebras (tipo, gravidade, série, turno, mês…) e os filhos para descer mais um nível. Embutido (cidade, no painel
 * do quesito), mostra só as quebras e as unidades. */
export function DetalheQuesito({ quesito, nivel, id, can, onIr, embutido = false }: {
  quesito: Quesito; nivel: NivelDetalhe; id: string | null; can: (p: string) => boolean;
  onIr: (nivel: NivelDetalhe, id: string | null) => void; embutido?: boolean;
}) {
  const q = useRpc<Detalhe>('mapa_detalhe', { camada: quesito.value, nivel, id }, { staleTime: 60_000 });
  const d = q.data;
  if (q.isLoading) return <SkeletonList rows={4} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  if (!d) return null;
  const links = linksDe(quesito.value, nivel, id, can);

  return (
    <div className="space-y-3">
      {!embutido && (
        <div>
          <div className="flex items-center gap-2 text-[11.5px] font-bold uppercase tracking-wide text-purple-700">
            <span>{quesito.label} · {NIVEL_ROTULO[nivel]}</span>
            <SourceChip kind={quesito.fonte} />
            {q.isFetching && <RefreshCw className="size-3.5 animate-spin text-subtle" aria-label="Atualizando" />}
          </div>
          <div className="mt-1 flex items-start gap-2">
            <h2 className="min-w-0 flex-1 font-display text-lg font-extrabold leading-snug">{d.nome}</h2>
            <button type="button" onClick={() => onIr('cidade', null)} className="inline-flex size-9 shrink-0 items-center justify-center rounded-xl bg-slate-100" aria-label="Fechar o detalhe e voltar para a cidade">
              <X className="size-5" />
            </button>
          </div>
          {d.pai && d.pai.nivel !== 'cidade' && (
            <button type="button" onClick={() => onIr(d.pai!.nivel, d.pai!.id ?? null)} className="mt-1 inline-flex items-center gap-1 text-[13px] font-semibold text-purple-700">
              <ArrowLeft className="size-4" />Voltar para {d.pai.nome}
            </button>
          )}
        </div>
      )}

      {d.sigilo ? (
        <p className="flex items-start gap-1.5 rounded-2xl bg-slate-50 p-3 text-[13px] text-muted ring-1 ring-line">
          <EyeOff className="mt-0.5 size-4 shrink-0" />Menos de {d.minimo} pessoas aqui: por sigilo, o detalhe não aparece. Veja a região inteira.
        </p>
      ) : (
        <>
          {!embutido && <Destaque d={d} quesito={quesito} />}
          {(d.quebras ?? []).filter((x) => x.itens.length > 0).map((x) => <QuebraCard key={x.titulo} q={x} d={d} />)}
          {d.filhos && d.filhos.itens.length > 0 && <Filhos d={d} onIr={onIr} />}
        </>
      )}

      {links.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {links.map((l) => (
            <Link key={l.to + l.rotulo} to={l.to} className="inline-flex items-center gap-1 rounded-full bg-purple-50 px-3 py-1.5 text-[13px] font-semibold text-purple-800 ring-1 ring-purple-100 hover:bg-purple-100">
              {l.rotulo}<ArrowRight className="size-3.5" />
            </Link>
          ))}
        </div>
      )}
      {!embutido && (
        <p className="text-[12px] leading-relaxed text-muted">
          {d.pela_casa && (nivel === 'area' || nivel === 'setor') ? 'Pela casa das pessoas; grupos com menos de 3 pessoas não aparecem. ' : ''}
          Sem nome de pessoa: só contagens. Atualizado em {fmtDateTime(d.atualizado_em)}.
        </p>
      )}
    </div>
  );
}

function Destaque({ d, quesito }: { d: Detalhe; quesito: Quesito }) {
  const ref = d.tipo === 'taxa' ? d.rede : d.media;
  const pior = d.valor != null && ref != null && (d.pior === 'maior' ? d.valor > ref : d.valor < ref);
  return (
    <div className="grid grid-cols-2 gap-2">
      <Card className="p-3">
        <div className="font-display text-[26px] font-extrabold leading-none">{fmt(d.valor, d.sufixo)}</div>
        <div className="mt-1 text-[12px] leading-tight text-muted">{quesito.label}</div>
      </Card>
      <Card className="p-3">
        {ref != null && d.referencia ? (
          <>
            <div className="font-display text-[20px] font-extrabold leading-none text-ink-2">{fmt(ref, d.sufixo)}</div>
            <div className="mt-1 text-[12px] leading-tight text-muted">
              {d.referencia}{d.valor != null && <> · <b className={pior ? 'text-red-700' : 'text-green-700'}>{pior ? 'pior' : 'melhor ou igual'}</b></>}
            </div>
          </>
        ) : (
          <div className="text-[12px] text-muted">Sem referência para comparar.</div>
        )}
        {d.posicao && (
          <div className="mt-1.5 text-[12px] leading-tight text-muted"><b className="text-ink">{d.posicao.posicao}º</b> de {fmtInt(d.posicao.de)} · 1º = agir primeiro</div>
        )}
      </Card>
    </div>
  );
}

function QuebraCard({ q, d }: { q: Quebra; d: Detalhe }) {
  const [todos, setTodos] = useState(false);
  const porN = q.mostra === 'n';
  const taxa = d.tipo === 'taxa' && !porN;
  const valorDe = (i: Item) => (porN ? i.n : i.valor ?? 0);
  const max = Math.max(1, ...q.itens.map((i) => Math.abs(valorDe(i))));
  const itens = todos ? q.itens : q.itens.slice(0, 8);
  return (
    <div>
      <div className="mb-1 text-[12.5px] font-semibold text-ink-2">{q.titulo}</div>
      <Card className="space-y-1.5 p-3">
        {itens.map((i) => {
          const v = valorDe(i);
          const largura = taxa ? Math.max(0, Math.min(100, v)) : (100 * Math.abs(v)) / max;
          return (
            <div key={i.rotulo} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-2 text-[13px]">
              <span className="truncate" title={i.rotulo}>{i.rotulo}</span>
              <span className="text-right font-semibold tabular">
                {porN ? fmtInt(i.n) : fmt(i.valor, taxa ? '%' : '')}
                {taxa && <span className="ml-1 text-[11.5px] font-normal text-muted">({fmtInt(i.n)})</span>}
              </span>
              <span className="col-span-2 h-1.5 overflow-hidden rounded-full bg-slate-100" aria-hidden>
                <span className={`block h-full rounded-full ${v < 0 ? 'bg-red-500' : 'bg-purple-500'}`} style={{ width: `${largura}%` }} />
              </span>
            </div>
          );
        })}
        {q.itens.length > 8 && (
          <button type="button" onClick={() => setTodos(!todos)} className="text-[12.5px] font-semibold text-purple-700">
            {todos ? 'Ver menos' : `Ver todos (${q.itens.length})`}
          </button>
        )}
      </Card>
    </div>
  );
}

function Filhos({ d, onIr }: { d: Detalhe; onIr: (nivel: NivelDetalhe, id: string | null) => void }) {
  const [todos, setTodos] = useState(false);
  const f = d.filhos!;
  // as mesmas cores do mapa: terços dos valores, vermelho na ponta ruim
  const c = cortes(f.itens.map((i) => i.valor), d.pior);
  const itens = todos ? f.itens : f.itens.slice(0, 10);
  return (
    <div>
      <div className="mb-1 text-[12.5px] font-semibold text-ink-2">{f.titulo} · toque para detalhar</div>
      <Card className="divide-y divide-line">
        {itens.map((i, k) => (
          <button key={i.id} type="button" onClick={() => onIr(f.nivel, i.id)} className="flex w-full items-center gap-2 px-3 py-2 text-left text-[13px] hover:bg-purple-50">
            <span className="size-3 shrink-0 rounded-full" style={{ background: corDe(classe(i.valor, c)) }} aria-hidden />
            <span className="w-5 shrink-0 text-right font-bold text-subtle">{k + 1}</span>
            <span className="min-w-0 flex-1 truncate" title={`${i.nome}${i.detalhe ? ` · ${i.detalhe}` : ''}`}>
              <b>{i.nome}</b>{i.detalhe && <span className="text-muted"> · {i.detalhe}</span>}
            </span>
            <span className="shrink-0 font-semibold tabular">{fmt(i.valor, d.sufixo)}</span>
            <ChevronRight className="size-4 shrink-0 text-subtle" />
          </button>
        ))}
      </Card>
      {f.itens.length > 10 && (
        <button type="button" onClick={() => setTodos(!todos)} className="mt-1 text-[12.5px] font-semibold text-purple-700">
          {todos ? 'Ver menos' : `Ver todas (${f.itens.length})`}
        </button>
      )}
    </div>
  );
}
