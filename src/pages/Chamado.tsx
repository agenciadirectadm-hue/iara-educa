import { useState } from 'react';
import { useParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { CircleCheck, RotateCcw, Star, TriangleAlert } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, timeLeft } from '@/lib/format';
import { CATEGORIA_MANUTENCAO, EQUIPE, PRIORIDADE, SITUACAO_CHAMADO, fmtReais } from '@/lib/escola';
import { Badge, Button, Card, DataPair, ErrorState, Field, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { Sheet, useToast } from '@/components/overlays';

/** Um chamado: dados, linha do tempo e o próximo passo de quem pode dar (infraestrutura) ou conferir (escola). */
export default function Chamado() {
  const { id } = useParams();
  const res = useRpc<any>('manutencao_detalhe', { id });
  const [passo, setPasso] = useState<string | null>(null);
  const [validar, setValidar] = useState<boolean | null>(null);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const c = res.data;
  const aberto = !['VALIDADO', 'CANCELADO', 'CONCLUIDO'].includes(c.situacao);
  return (
    <div>
      <Crumbs items={[{ label: 'Manutenção', to: '/manutencao' }, { label: c.protocolo }]} />
      <PageHeader eyebrow={<span className="inline-flex items-center gap-1">{c.unidade}<Simulado detail="Chamado fictício." /></span>}
        title={`${CATEGORIA_MANUTENCAO[c.categoria]} · ${c.local}`} subtitle={`${c.protocolo} · aberto ${fmtDateTime(c.aberto_em)} por ${c.aberto_por ?? '—'}`} />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.2fr_1fr]">
        <Card className="p-4">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={SITUACAO_CHAMADO[c.situacao]?.tone}>{SITUACAO_CHAMADO[c.situacao]?.label}</Badge>
            <Badge tone={PRIORIDADE[c.prioridade]?.tone}>{c.afeta_seguranca && <TriangleAlert className="size-3" />}Prioridade {PRIORIDADE[c.prioridade]?.label.toLowerCase()}</Badge>
            {c.reaberturas > 0 && <Badge tone="red">Reaberto {c.reaberturas}×</Badge>}
            {c.atrasado && <Badge tone="red">Fora do prazo</Badge>}
          </div>
          <p className="mt-3 text-[15px]">{c.descricao}</p>
          <div className="mt-4 grid grid-cols-2 gap-3">
            <DataPair label="Prazo" value={<span className={clsx(c.atrasado && 'font-semibold text-red-700')}>{fmtDateTime(c.prazo)}{aberto ? ` · ${timeLeft(c.prazo)}` : ''}</span>} />
            <DataPair label="Equipe" value={c.equipe ? EQUIPE[c.equipe] : '—'} />
            <DataPair label="Custo estimado" value={c.custo_estimado != null ? fmtReais(Number(c.custo_estimado)) : '—'} />
            <DataPair label="Custo final" value={c.custo_final != null ? fmtReais(Number(c.custo_final)) : '—'} />
            {c.nota_escola && <DataPair label="Nota da escola" value={<span className="inline-flex gap-0.5">{Array.from({ length: c.nota_escola }).map((_, i) => <Star key={i} className="size-4 fill-amber-400 text-amber-400" />)}</span>} />}
          </div>
          {(c.proximos?.length > 0 || c.pode_validar) && (
            <div className="mt-4 flex flex-wrap gap-2 border-t border-line pt-4">
              {(c.proximos as string[]).map((s) => (
                <Button key={s} size="sm" variant={s === 'CANCELADO' ? 'secondary' : 'primary'} onClick={() => setPasso(s)}>{SITUACAO_CHAMADO[s]?.acao ?? s}</Button>
              ))}
              {c.pode_validar && (<>
                <Button size="sm" variant="success" icon={CircleCheck} onClick={() => setValidar(true)}>Serviço feito: validar</Button>
                <Button size="sm" variant="secondary" icon={RotateCcw} onClick={() => setValidar(false)}>Ainda com problema: reabrir</Button>
              </>)}
            </div>
          )}
        </Card>

        <Section title="Linha do tempo" className="mt-0">
          <Card className="p-4">
            <ol className="relative space-y-4 border-l-2 border-line pl-4">
              {(c.eventos as any[]).map((e, i) => (
                <li key={i} className="relative">
                  <span className={clsx('absolute -left-[23px] top-1 size-3 rounded-full ring-2 ring-white', e.situacao === 'REABERTO' ? 'bg-red-500' : e.situacao === 'VALIDADO' ? 'bg-green-600' : 'bg-purple-600')} />
                  <div className="text-[13.5px] font-semibold">{SITUACAO_CHAMADO[e.situacao]?.label ?? e.situacao}</div>
                  <div className="text-[12px] text-muted">{fmtDateTime(e.em)} · {e.autor}</div>
                  {e.texto && <div className="mt-0.5 text-[13px] text-ink-2">{e.texto}</div>}
                </li>
              ))}
            </ol>
          </Card>
        </Section>
      </div>
      <PassoSheet id={c.id} passo={passo} onClose={() => setPasso(null)} />
      <ValidarSheet id={c.id} aprovado={validar} onClose={() => setValidar(null)} />
    </div>
  );
}

function useRecarregar() {
  const qc = useQueryClient();
  return () => ['manutencao_detalhe', 'manutencao_lista', 'manutencao_painel'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

function PassoSheet({ id, passo, onClose }: { id: string; passo: string | null; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [texto, setTexto] = useState('');
  const [equipe, setEquipe] = useState('EQUIPE_PROPRIA');
  const [custo, setCusto] = useState('');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('manutencao_avancar', {
        id, situacao: passo, texto, equipe: ['EM_EXECUCAO', 'AGUARDANDO_EXECUCAO'].includes(passo ?? '') ? equipe : null,
        custo_estimado: ['ORCAMENTO', 'AGUARDANDO_EXECUCAO'].includes(passo ?? '') && custo ? Number(custo) : null,
        custo_final: passo === 'CONCLUIDO' && custo ? Number(custo) : null,
      });
      toast({ title: SITUACAO_CHAMADO[passo ?? '']?.label ?? 'Atualizado', description: 'A escola acompanha cada passo.', tone: 'success' });
      recarregar();
      setTexto(''); setCusto('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!passo} onClose={onClose} title={SITUACAO_CHAMADO[passo ?? '']?.acao ?? ''}
      footer={<Button block size="lg" loading={busy} disabled={passo === 'CANCELADO' && texto.trim().length < 5} onClick={enviar}>Confirmar</Button>}>
      <div className="space-y-4 pt-1">
        {['EM_EXECUCAO', 'AGUARDANDO_EXECUCAO'].includes(passo ?? '') && (
          <Field label="Quem executa">
            <select value={equipe} onChange={(e) => setEquipe(e.target.value)} className={inputCls}>
              {Object.entries(EQUIPE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
        )}
        {['ORCAMENTO', 'AGUARDANDO_EXECUCAO', 'CONCLUIDO'].includes(passo ?? '') && (
          <Field label={passo === 'CONCLUIDO' ? 'Custo final (R$)' : 'Custo estimado (R$)'}>
            <input type="number" min={0} value={custo} onChange={(e) => setCusto(e.target.value)} className={inputCls} />
          </Field>
        )}
        <Field label={passo === 'CANCELADO' ? 'Motivo do cancelamento' : 'Observação (opcional)'}>
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} />
        </Field>
      </div>
    </Sheet>
  );
}

function ValidarSheet({ id, aprovado, onClose }: { id: string; aprovado: boolean | null; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [nota, setNota] = useState(5);
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('manutencao_validar', { id, aprovado, nota: aprovado ? nota : null, texto });
      toast({ title: aprovado ? 'Serviço validado' : 'Chamado reaberto', description: aprovado ? 'Obrigado: a nota ajuda a avaliar as equipes e as empresas.' : 'A infraestrutura volta ao chamado.', tone: 'success' });
      recarregar();
      setTexto('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={aprovado != null} onClose={onClose} title={aprovado ? 'Validar o serviço' : 'Reabrir o chamado'}
      footer={<Button block size="lg" variant={aprovado ? 'success' : 'danger'} loading={busy} disabled={!aprovado && texto.trim().length < 5} onClick={enviar}>{aprovado ? 'Validar' : 'Reabrir'}</Button>}>
      <div className="space-y-4 pt-1">
        {aprovado && (
          <Field label="Como ficou o serviço?">
            <div className="flex gap-1">
              {[1, 2, 3, 4, 5].map((n) => (
                <button key={n} type="button" onClick={() => setNota(n)} aria-label={`${n} estrela(s)`} className="p-1">
                  <Star className={clsx('size-8', n <= nota ? 'fill-amber-400 text-amber-400' : 'text-slate-300')} />
                </button>
              ))}
            </div>
          </Field>
        )}
        <Field label={aprovado ? 'Comentário (opcional)' : 'O que ficou pendente'}>
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} />
        </Field>
      </div>
    </Sheet>
  );
}
