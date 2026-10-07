import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { AlarmClock, CircleCheck, Hammer, Plus, Star, TriangleAlert, Wrench } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmt1, fmtInt, timeAgo, timeLeft } from '@/lib/format';
import { CATEGORIA_MANUTENCAO, PRIORIDADE, SITUACAO_CHAMADO, fmtReais } from '@/lib/escola';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { BarList } from '@/components/charts';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';

const FILTROS = [
  { value: 'PENDENTES', label: 'Pendentes' }, { value: 'ATRASADOS', label: 'Atrasados' }, { value: 'A_VALIDAR', label: 'A validar' },
  { value: 'VALIDADO', label: 'Encerrados' }, { value: '', label: 'Todos' },
];

/** Manutenção e obras: a escola abre, a infraestrutura tria, vistoria, orça e executa; a escola confere e valida. */
export default function Manutencao() {
  const { me, can } = useSession();
  const [sp, setSp] = useSearchParams();
  const filtro = sp.get('f') ?? 'PENDENTES';
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const [busca, setBusca] = useState('');
  const db = useDebounced(busca, 300);
  const [abrir, setAbrir] = useState(false);
  const painel = useRpc<any>('manutencao_painel', { unit_id: unit });
  const lista = useRpc<any[]>('manutencao_lista', { unit_id: unit, situacao: filtro || null, busca: db });
  const p = painel.data;
  const itens = lista.data ?? [];
  const podeAbrir = can('manutencao.open') && me?.scope === 'UNIT';

  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · infraestrutura' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Manutenção e obras<Simulado detail="Chamados fictícios distribuídos pelas unidades reais da rede." /></span>}
        subtitle="Prazo pela prioridade: risco à segurança em 24 horas, alta em 3 dias, média em 10 e baixa em 30. A escola valida o serviço ou reabre."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{podeAbrir && <Button icon={Plus} onClick={() => setAbrir(true)}>Abrir chamado</Button>}</>} />

      {painel.error ? <ErrorState error={painel.error} onRetry={() => painel.refetch()} /> : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi compact icon={Wrench} tone="blue" label="Chamados pendentes" value={fmtInt(p?.pendentes)} sub={`${fmtInt(p?.urgentes)} urgente(s)`} onClick={() => setSp({ f: 'PENDENTES' })} />
          <Kpi compact icon={AlarmClock} tone="red" label="Fora do prazo" value={fmtInt(p?.atrasados)} onClick={() => setSp({ f: 'ATRASADOS' })} />
          <Kpi compact icon={CircleCheck} tone="green" label="No prazo (90 dias)" value={p?.no_prazo_pct != null ? `${fmt1(p.no_prazo_pct)}%` : '—'} sub={`${fmt1(p?.dias_medios)} dias em média · ${fmtInt(p?.concluidos_30d)} concluídos em 30 dias`} />
          <Kpi compact icon={Star} tone="amber" label="Nota das escolas" value={p?.nota_media != null ? fmt1(p.nota_media) : '—'} sub={`${fmtReais(Number(p?.custo_ano ?? 0))} executados no ano`} />
        </div>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {FILTROS.map((f) => <Chip key={f.value} active={filtro === f.value} onClick={() => setSp(f.value === 'PENDENTES' ? {} : { f: f.value }, { replace: true })}>{f.label}</Chip>)}
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Protocolo, local, unidade…" className={`${inputCls} h-9 max-w-[260px]`} aria-label="Buscar chamado" />
      </div>

      <div className="mt-3 grid grid-cols-1 gap-4 xl:grid-cols-[1fr_300px]">
        <div>
          {lista.isLoading ? <SkeletonList rows={6} /> : lista.error ? <ErrorState error={lista.error} onRetry={() => lista.refetch()} /> : <ListaChamados itens={itens} />}
        </div>
        {p && (
          <div className="space-y-4">
            <Section title="Pendentes por tipo" className="mt-0">
              <Card className="p-2">
                <BarList items={((p.por_categoria ?? []) as any[]).map((c) => ({ key: c.categoria, label: CATEGORIA_MANUTENCAO[c.categoria] ?? c.categoria, value: c.pendentes,
                  badge: c.atrasados ? <Badge tone="red">{c.atrasados} atrasado(s)</Badge> : undefined }))} />
              </Card>
            </Section>
            {p.unidades && (
              <Section title="Unidades com mais pendências" className="mt-0">
                <Card className="p-2">
                  <BarList items={((p.unidades ?? []) as any[]).slice(0, 8).map((u) => ({ key: String(u.unit_id), label: u.unidade, value: u.pendentes, onClick: () => setUnit(u.unit_id),
                    badge: u.atrasados ? <Badge tone="red">{u.atrasados}</Badge> : undefined }))} />
                </Card>
              </Section>
            )}
          </div>
        )}
      </div>
      <AbrirChamado open={abrir} onClose={() => setAbrir(false)} />
    </div>
  );
}

export function ListaChamados({ itens }: { itens: any[] }) {
  return (
    <Card className="overflow-hidden">
      <Tabela colunas="118px minmax(150px,1fr) minmax(200px,1.5fr) 96px 170px 120px" largura={920} rotulo="Chamados de manutenção">
        <TCabecalho><TCelula>Protocolo</TCelula><TCelula>Unidade</TCelula><TCelula>Problema</TCelula><TCelula>Prioridade</TCelula><TCelula>Situação</TCelula><TCelula>Prazo</TCelula></TCabecalho>
        {itens.map((c) => (
          <TLinha key={c.id} to={`/manutencao/${c.id}`} alerta={c.atrasado && !['VALIDADO', 'CONCLUIDO', 'CANCELADO'].includes(c.situacao)} rotulo={`${c.protocolo} · ${c.unidade}`}>
            <TCelula fixa><span className="font-mono text-[12.5px] font-semibold">{c.protocolo}</span></TCelula>
            <TCelula titulo={c.unidade}>{c.unidade}</TCelula>
            <TCelula titulo={`${c.local}: ${c.descricao}`}><span className="font-semibold">{CATEGORIA_MANUTENCAO[c.categoria]}</span> <span className="text-muted">· {c.local} · {c.descricao}</span></TCelula>
            <TCelula><Badge tone={PRIORIDADE[c.prioridade]?.tone}>{c.afeta_seguranca && <TriangleAlert className="size-3" />}{PRIORIDADE[c.prioridade]?.label}</Badge></TCelula>
            <TCelula><Badge tone={SITUACAO_CHAMADO[c.situacao]?.tone}>{SITUACAO_CHAMADO[c.situacao]?.label}</Badge></TCelula>
            <TCelula className={c.atrasado ? 'font-semibold text-red-700' : 'text-muted'}>
              {['VALIDADO', 'CONCLUIDO'].includes(c.situacao) ? `${c.dias_aberto} dia(s)` : c.situacao === 'CANCELADO' ? '—' : c.atrasado ? `atrasado ${timeAgo(c.prazo).replace('há ', '')}` : timeLeft(c.prazo)}
            </TCelula>
          </TLinha>
        ))}
      </Tabela>
      {!itens.length && <EmptyState compact title="Nenhum chamado neste filtro" />}
    </Card>
  );
}

function AbrirChamado({ open, onClose }: { open: boolean; onClose: () => void }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const toast = useToast();
  const [cat, setCat] = useState('HIDRAULICA');
  const [local, setLocal] = useState('');
  const [desc, setDesc] = useState('');
  const [prio, setPrio] = useState('MEDIA');
  const [seg, setSeg] = useState(false);
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('manutencao_abrir', { categoria: cat, local, descricao: desc, prioridade: prio, afeta_seguranca: seg });
      toast({ title: `Chamado ${r.protocolo} aberto`, description: `Prazo: ${PRIORIDADE[r.prioridade]?.prazo}. Você acompanha cada passo aqui.`, tone: 'success' });
      ['manutencao_lista', 'manutencao_painel'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
      onClose();
      setLocal(''); setDesc(''); setSeg(false);
      navigate(`/manutencao/${r.id}`);
    } catch (e) {
      toast({ title: 'Chamado não aberto', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Abrir chamado de manutenção" subtitle="Descreva o problema e onde ele está. Fotos entram na próxima versão."
      footer={<Button block size="lg" icon={Hammer} loading={busy} disabled={desc.trim().length < 10} onClick={enviar}>Abrir chamado</Button>}>
      <div className="space-y-4 pt-1">
        <Field label="Tipo de serviço">
          <select value={cat} onChange={(e) => setCat(e.target.value)} className={inputCls}>
            {Object.entries(CATEGORIA_MANUTENCAO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
        <Field label="Onde"><input value={local} onChange={(e) => setLocal(e.target.value)} placeholder="Ex.: banheiro infantil do bloco B" className={inputCls} /></Field>
        <Field label="O que está acontecendo" hint="Mínimo de 10 caracteres. Não cite nomes de alunos.">
          <textarea value={desc} onChange={(e) => setDesc(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} />
        </Field>
        <label className="flex items-start gap-3 rounded-2xl bg-red-50 p-3 ring-1 ring-red-200">
          <input type="checkbox" checked={seg} onChange={(e) => setSeg(e.target.checked)} className="mt-1 size-5 accent-red-600" />
          <span className="text-[13.5px]"><b>Há risco à segurança das crianças</b><br /><span className="text-muted">Fiação exposta, brinquedo quebrado, portão sem tranca… vira urgente (24 horas).</span></span>
        </label>
        {!seg && (
          <Field label="Prioridade sugerida">
            <select value={prio} onChange={(e) => setPrio(e.target.value)} className={inputCls}>
              {Object.entries(PRIORIDADE).filter(([k]) => k !== 'URGENTE').map(([k, v]) => <option key={k} value={k}>{v.label} · prazo de {v.prazo}</option>)}
            </select>
          </Field>
        )}
      </div>
    </Sheet>
  );
}
