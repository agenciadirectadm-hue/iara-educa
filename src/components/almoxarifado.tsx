// Sprint 3: almoxarifado completo — pedidos (escola → almoxarifado → remessa → recebimento conferido), validade dos lotes e
// cobertura dos alimentos pelas refeições servidas.
import { useEffect, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { AlarmClock, CalendarX2, Check, PackageCheck, PackagePlus, Send, ShoppingCart, Truck, TriangleAlert, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, Segmented, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

export const SITUACAO_PEDIDO: Record<string, { label: string; tone: Tone }> = {
  ENVIADO: { label: 'Aguardando aprovação', tone: 'amber' }, APROVADO: { label: 'Em separação', tone: 'blue' },
  EM_TRANSPORTE: { label: 'A caminho', tone: 'purple' }, RECEBIDO: { label: 'Recebido', tone: 'green' },
  RECEBIDO_PARCIAL: { label: 'Recebido com divergência', tone: 'red' }, RECUSADO: { label: 'Recusado', tone: 'gray' }, CANCELADO: { label: 'Cancelado', tone: 'gray' },
};
const CAT: Record<string, string> = {
  PEDAGOGICO: 'Pedagógico', LIMPEZA: 'Limpeza', ESCRITORIO: 'Escritório', ALIMENTO: 'Alimentos', UNIFORME: 'Uniformes', EQUIPAMENTO: 'Equipamentos', MOBILIARIO: 'Mobiliário', OUTRO: 'Outros',
};
const num = (n: number | string | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('pt-BR', { maximumFractionDigits: 2 }));

export function useRecarregarAlmox() {
  const qc = useQueryClient();
  return () => ['pedidos_lista', 'pedido_detalhe', 'almoxarifado_painel', 'materiais_lista', 'material_detalhe', 'estoque_validade', 'cobertura_alimentos', 'produtos_catalogo']
    .forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

// ---------------------------------------------------------------- Pedidos
const FILTROS = [{ value: 'ABERTOS', label: 'Em andamento' }, { value: 'ENVIADO', label: 'Aguardando aprovação' }, { value: 'APROVADO', label: 'Em separação' },
  { value: 'EM_TRANSPORTE', label: 'A caminho' }, { value: 'ATRASADOS', label: 'Atrasados' }, { value: 'RECEBIDO_PARCIAL', label: 'Com divergência' }, { value: '', label: 'Todos' }];

export function PedidosAba({ unitId, rede }: { unitId: number | null; rede: boolean }) {
  const [sit, setSit] = useState('ABERTOS');
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  const res = useRpc<any>('pedidos_lista', { unit_id: unitId, situacao: sit || null });
  const painel = useRpc<any>('almoxarifado_painel', { unit_id: unitId });
  const p = painel.data;
  return (
    <div className="space-y-3">
      {p && (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi compact icon={ShoppingCart} tone="amber" label="Aguardando aprovação" value={fmtInt(p.aguardando_aprovacao)} sub={p.urgentes ? `${p.urgentes} urgente(s)` : undefined} onClick={() => setSit('ENVIADO')} />
          <Kpi compact icon={Truck} tone="purple" label="A caminho" value={fmtInt(p.pedidos?.EM_TRANSPORTE)} sub={`${fmtInt(p.atrasados)} atrasado(s)`} onClick={() => setSit('EM_TRANSPORTE')} />
          <Kpi compact icon={TriangleAlert} tone="red" label="Recebidos com divergência (60 dias)" value={fmtInt(p.divergencias_60d)} onClick={() => setSit('RECEBIDO_PARCIAL')} />
          <Kpi compact icon={AlarmClock} tone="blue" label="Tempo médio do pedido à entrega" value={p.tempo_medio_dias != null ? `${String(p.tempo_medio_dias).replace('.', ',')} dias` : '—'} />
        </div>
      )}
      {rede && p?.central_abaixo_minimo?.length > 0 && (
        <Card className="p-3 text-[13px]"><b className="text-red-700">Almoxarifado central abaixo do mínimo:</b> {(p.central_abaixo_minimo as any[]).map((m) => `${m.nome} (${num(m.quantidade)} de ${num(m.minimo)})`).join(' · ')}</Card>
      )}
      <Card className="flex flex-wrap items-center gap-2 p-3">
        {FILTROS.map((f) => <Chip key={f.value || 'todos'} active={sit === f.value} onClick={() => setSit(f.value)}>{f.label}</Chip>)}
        {res.data?.pode_pedir && <Button className="ml-auto" icon={PackagePlus} onClick={() => setNovo(true)}>Novo pedido</Button>}
      </Card>
      {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden">
          {(res.data.itens as any[]).length ? (
            <Tabela colunas="150px minmax(160px,1.4fr) minmax(150px,1.2fr) 100px 170px 110px 110px" largura={980} rotulo="Pedidos">
              <TCabecalho><TCelula fixa>Pedido</TCelula><TCelula>Unidade</TCelula><TCelula>Categorias</TCelula><TCelula>Itens</TCelula><TCelula>Situação</TCelula><TCelula>Pedido em</TCelula><TCelula>Entrega</TCelula></TCabecalho>
              {(res.data.itens as any[]).map((x) => {
                const st = SITUACAO_PEDIDO[x.situacao];
                return (
                  <TLinha key={x.id} onClick={() => setAberto(x.id)} alerta={x.atrasado || x.situacao === 'RECEBIDO_PARCIAL'} rotulo={`Pedido ${x.numero}`}>
                    <TCelula fixa className="font-mono text-[12.5px] font-semibold">{x.numero}{x.prioridade === 'URGENTE' && <span className="ml-1 text-red-700">!</span>}</TCelula>
                    <TCelula titulo={x.unidade}>{x.unidade}</TCelula>
                    <TCelula>{(x.categorias as string[]).map((c) => CAT[c] ?? c).join(', ')}{x.origem === 'FORNECEDOR' ? ' · entrega direta' : ''}</TCelula>
                    <TCelula>{x.n_itens}</TCelula>
                    <TCelula livre><Badge tone={st?.tone ?? 'gray'}>{x.atrasado ? 'A caminho · atrasado' : st?.label ?? x.situacao}</Badge></TCelula>
                    <TCelula>{fmtDate(x.solicitado_em)}</TCelula>
                    <TCelula className={x.atrasado ? 'font-semibold text-red-700' : ''}>{x.recebido_em ? fmtDate(x.recebido_em) : x.previsao_entrega ? `prev. ${fmtDate(x.previsao_entrega)}` : '—'}</TCelula>
                  </TLinha>
                );
              })}
            </Tabela>
          ) : <EmptyState compact title="Nenhum pedido nesta lista" />}
        </Card>
      )}
      <PedidoSheet id={aberto} onClose={() => setAberto(null)} />
      <NovoPedidoSheet open={novo} onClose={() => setNovo(false)} unitId={unitId} />
    </div>
  );
}

function PedidoSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const res = useRpc<any>('pedido_detalhe', { id }, { enabled: !!id });
  const toast = useToast();
  const recarregar = useRecarregarAlmox();
  const [qtd, setQtd] = useState<Record<string, string>>({});
  const [div, setDiv] = useState<Record<string, string>>({});
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const d = res.data;
  useEffect(() => {
    if (!d) return;
    setQtd(Object.fromEntries((d.itens as any[]).map((i) => [i.id, String(d.situacao === 'ENVIADO' ? i.pedida : d.situacao === 'EM_TRANSPORTE' ? i.enviada ?? '' : '')])));
    setDiv({});
    setMotivo('');
  }, [d?.id, d?.situacao]);
  const acao = async (fn: string, args: object, ok: string) => {
    setBusy(true);
    try {
      await rpc(fn, { id, ...args });
      toast({ title: ok, tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const st = d ? SITUACAO_PEDIDO[d.situacao] : null;
  const decidir = d?.pode_gerir && d.situacao === 'ENVIADO';
  const receber = d?.pode_receber;
  return (
    <Sheet open={!!id} onClose={onClose} size="lg" title={d ? `Pedido ${d.numero}` : 'Pedido'} subtitle={d ? `${d.unidade} · ${d.origem === 'FORNECEDOR' ? `entrega direta (${d.fornecedor ?? 'fornecedor'})` : 'almoxarifado central'}` : ''}
      footer={d && (decidir ? (
        <div className="flex gap-2">
          <Button block variant="success" icon={Check} loading={busy} onClick={() => acao('pedido_decidir', { aprovar: true, motivo, itens: (d.itens as any[]).map((i) => ({ id: i.id, aprovada: (qtd[i.id] ?? '').replace(',', '.') })) }, 'Pedido aprovado')}>Aprovar</Button>
          <Button block variant="secondary" icon={X} loading={busy} disabled={motivo.trim().length < 10} onClick={() => acao('pedido_decidir', { aprovar: false, motivo }, 'Pedido recusado')}>Recusar</Button>
        </div>
      ) : d.pode_gerir && d.situacao === 'APROVADO' ? (
        <Button block size="lg" icon={Send} loading={busy} onClick={() => acao('pedido_despachar', {}, 'Remessa despachada')}>Despachar a remessa</Button>
      ) : receber ? (
        <Button block size="lg" variant="success" icon={PackageCheck} loading={busy}
          onClick={() => acao('pedido_receber', { itens: (d.itens as any[]).filter((i) => i.enviada > 0).map((i) => ({ id: i.id, recebida: (qtd[i.id] ?? '').replace(',', '.'), divergencia: div[i.id] ?? '' })) }, 'Recebimento conferido')}>Conferir e receber</Button>
      ) : d.pode_cancelar ? (
        <Button block variant="secondary" loading={busy} onClick={() => acao('pedido_cancelar', { motivo: 'Cancelado pela unidade' }, 'Pedido cancelado')}>Cancelar o pedido</Button>
      ) : undefined)}>
      {!d ? <SkeletonList rows={4} /> : (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-2 text-[13px]">
            <Badge tone={st?.tone ?? 'gray'}>{d.atrasado ? 'A caminho · atrasado' : st?.label}</Badge>
            {d.prioridade === 'URGENTE' && <Badge tone="red">Urgente</Badge>}
            <span className="text-muted">pedido em {fmtDateTime(d.solicitado_em)} por {d.solicitado_por ?? '—'}</span>
          </div>
          {d.justificativa && <p className="text-[13.5px]"><b>Justificativa:</b> {d.justificativa}</p>}
          {d.motivo_recusa && <p className="text-[13.5px] text-red-800"><b>{d.situacao === 'RECUSADO' ? 'Motivo da recusa' : 'Observação do almoxarifado'}:</b> {d.motivo_recusa}</p>}
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,2fr) 80px 80px 80px 110px minmax(140px,1.2fr)" largura={760} rotulo="Itens do pedido">
              <TCabecalho><TCelula fixa>Produto</TCelula><TCelula>Pedida</TCelula><TCelula>Aprovada</TCelula><TCelula>Enviada</TCelula><TCelula>{receber ? 'Recebida' : decidir ? 'Aprovar' : 'Recebida'}</TCelula><TCelula>Lote / divergência</TCelula></TCabecalho>
              {(d.itens as any[]).map((i) => (
                <TLinha key={i.id} alerta={!!i.divergencia}>
                  <TCelula fixa titulo={i.nome} className="font-semibold">{i.nome} <span className="text-[11.5px] font-normal text-muted">{i.unidade_medida}</span></TCelula>
                  <TCelula>{num(i.pedida)}</TCelula>
                  <TCelula>{num(i.aprovada)}</TCelula>
                  <TCelula>{num(i.enviada)}</TCelula>
                  <TCelula livre>
                    {(decidir || (receber && i.enviada > 0)) ? (
                      <input inputMode="decimal" value={qtd[i.id] ?? ''} onChange={(e) => setQtd({ ...qtd, [i.id]: e.target.value })} aria-label={`Quantidade de ${i.nome}`}
                        className="h-8 w-20 rounded-xl bg-white text-center ring-1 ring-line" />
                    ) : num(i.recebida)}
                    {decidir && i.saldo_central != null && <div className="text-[11px] text-muted">central: {num(i.saldo_central)}</div>}
                  </TCelula>
                  <TCelula livre>
                    {receber && i.enviada > 0 && String(qtd[i.id] ?? '').replace(',', '.') !== String(i.enviada) ? (
                      <input value={div[i.id] ?? ''} onChange={(e) => setDiv({ ...div, [i.id]: e.target.value })} placeholder="O que houve?" className="h-8 w-full rounded-xl bg-white px-2 text-[12.5px] ring-1 ring-red-300" />
                    ) : (
                      <span className="text-[12px] text-muted">{i.divergencia ?? (i.lotes as any[]).map((l) => `${l.lote}${l.validade ? ` · val. ${fmtDate(l.validade)}` : ''}`).join('; ')}</span>
                    )}
                  </TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
          {decidir && <Field label="Observação ou motivo da recusa" hint="Para recusar, o motivo é obrigatório e vai para a unidade."><input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={inputCls} /></Field>}
          {receber && <p className="text-[12.5px] text-muted">Confira volume por volume. Se a quantidade for diferente da enviada, explique (avaria, falta, embalagem aberta). Os alimentos entram com o lote e a validade da remessa.</p>}
          <div className="text-[12px] text-muted">
            {d.decidido_em && <>Decidido por {d.decidido_por} em {fmtDateTime(d.decidido_em)}. </>}
            {d.despachado_em && <>Despachado em {fmtDateTime(d.despachado_em)}, previsão {fmtDate(d.previsao_entrega)}. </>}
            {d.recebido_em && <>Recebido em {fmtDateTime(d.recebido_em)} por {d.conferido_por}.</>}
          </div>
        </div>
      )}
    </Sheet>
  );
}

function NovoPedidoSheet({ open, onClose, unitId }: { open: boolean; onClose: () => void; unitId: number | null }) {
  const cat = useRpc<any[]>('produtos_catalogo', { unit_id: unitId }, { enabled: open });
  const [qtd, setQtd] = useState<Record<string, string>>({});
  const [direta, setDireta] = useState(false);
  const [urgente, setUrgente] = useState(false);
  const [just, setJust] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarAlmox();
  const lista = useMemo(() => (cat.data ?? []).filter((p) => !!p.entrega_direta === direta), [cat.data, direta]);
  const itens = Object.entries(qtd).filter(([, q]) => Number(q.replace(',', '.')) > 0);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('pedido_criar', { unit_id: unitId, prioridade: urgente ? 'URGENTE' : 'NORMAL', justificativa: just,
        itens: itens.map(([codigo, q]) => ({ codigo, quantidade: q.replace(',', '.') })) });
      toast({ title: `Pedido ${r.numero} enviado`, description: 'O almoxarifado aprova e despacha; você confere no recebimento.', tone: 'success' });
      recarregar();
      setQtd({}); setJust(''); setUrgente(false);
      onClose();
    } catch (e) {
      toast({ title: 'Pedido não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} size="lg" title="Novo pedido" subtitle="Marque as quantidades. Abaixo do mínimo aparece em vermelho."
      footer={<Button block size="lg" icon={Send} loading={busy} disabled={!itens.length || (urgente && just.trim().length < 10)} onClick={enviar}>Enviar pedido ({itens.length} item(ns))</Button>}>
      <div className="space-y-3">
        <Segmented value={direta ? 'D' : 'A'} onChange={(v) => { setDireta(v === 'D'); setQtd({}); }} items={[{ value: 'A', label: 'Almoxarifado central' }, { value: 'D', label: 'Frutas (agricultura familiar)' }]} />
        {cat.isLoading ? <SkeletonList rows={4} /> : (
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,2fr) 110px 110px 100px" largura={560} rotulo="Catálogo">
              <TCabecalho><TCelula fixa>Produto</TCelula><TCelula>Na escola</TCelula><TCelula>Central</TCelula><TCelula>Pedir</TCelula></TCabecalho>
              {lista.map((p) => {
                const baixo = p.minimo_unidade != null && p.saldo_unidade != null && Number(p.saldo_unidade) < Number(p.minimo_unidade);
                return (
                  <TLinha key={p.codigo} alerta={baixo}>
                    <TCelula fixa titulo={p.nome} className="font-semibold">{p.nome} <span className="text-[11.5px] font-normal text-muted">{CAT[p.categoria]}</span></TCelula>
                    <TCelula className={baixo ? 'font-bold text-red-700' : ''}>{num(p.saldo_unidade)} {p.unidade_medida}</TCelula>
                    <TCelula className="text-muted">{p.entrega_direta ? 'fornecedor' : num(p.saldo_central)}</TCelula>
                    <TCelula livre><input inputMode="decimal" value={qtd[p.codigo] ?? ''} onChange={(e) => setQtd({ ...qtd, [p.codigo]: e.target.value })} aria-label={`Quantidade de ${p.nome}`}
                      className="h-8 w-20 rounded-xl bg-white text-center ring-1 ring-line" /></TCelula>
                  </TLinha>
                );
              })}
            </Tabela>
          </Card>
        )}
        <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={urgente} onChange={(e) => setUrgente(e.target.checked)} />Urgente (precisa de justificativa)</label>
        <Field label="Justificativa"><input value={just} onChange={(e) => setJust(e.target.value)} maxLength={300} className={inputCls} /></Field>
      </div>
    </Sheet>
  );
}

// ---------------------------------------------------------------- Validade e cobertura
export function ValidadeAba({ unitId, central }: { unitId: number | null; central: boolean }) {
  const [dias, setDias] = useState('30');
  const res = useRpc<any[]>('estoque_validade', { unit_id: unitId, central, dias: Number(dias) });
  const [alvo, setAlvo] = useState<any | null>(null);
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarAlmox();
  const descartar = async () => {
    setBusy(true);
    try {
      await rpc('lote_descartar', { id: alvo.id, motivo });
      toast({ title: 'Lote descartado', description: 'A baixa fica na movimentação do produto.', tone: 'success' });
      recarregar();
      setAlvo(null); setMotivo('');
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="space-y-3">
      <Segmented value={dias} onChange={setDias} items={[{ value: '7', label: 'Vence em 7 dias' }, { value: '30', label: '30 dias' }, { value: '90', label: '90 dias' }]} />
      {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden">
          {res.data?.length ? (
            <Tabela colunas="minmax(200px,2fr) minmax(150px,1.2fr) 130px 110px 120px 110px" largura={860} rotulo="Lotes por validade">
              <TCabecalho><TCelula fixa>Produto</TCelula><TCelula>Onde</TCelula><TCelula>Lote</TCelula><TCelula>Quantidade</TCelula><TCelula>Validade</TCelula><TCelula /></TCabecalho>
              {res.data.map((l) => (
                <TLinha key={l.id} alerta={l.vencido}>
                  <TCelula fixa titulo={l.nome} className="font-semibold">{l.nome}</TCelula>
                  <TCelula titulo={l.unidade}>{l.unidade}</TCelula>
                  <TCelula className="font-mono text-[12.5px]">{l.lote}</TCelula>
                  <TCelula>{num(l.quantidade)} {l.unidade_medida}</TCelula>
                  <TCelula className={l.vencido ? 'font-bold text-red-700' : l.dias <= 7 ? 'font-semibold text-amber-700' : ''}>{fmtDate(l.validade)}{l.vencido ? ' · vencido' : ` · ${l.dias} d`}</TCelula>
                  <TCelula livre className="text-right"><button type="button" onClick={() => setAlvo(l)} className="inline-flex h-8 items-center gap-1 rounded-xl px-2 text-[12.5px] font-semibold text-red-700 hover:bg-red-50"><CalendarX2 className="size-4" />Descartar</button></TCelula>
                </TLinha>
              ))}
            </Tabela>
          ) : <EmptyState compact title="Nenhum lote vencendo neste prazo" />}
        </Card>
      )}
      <p className="text-[12.5px] text-muted">Na saída, o sistema usa primeiro o lote que vence antes (FEFO). Lote vencido não vai para o prato: descarte com o motivo.</p>
      <Sheet open={!!alvo} onClose={() => setAlvo(null)} title={`Descartar lote ${alvo?.lote ?? ''}`} subtitle={alvo ? `${alvo.nome} · ${num(alvo.quantidade)} ${alvo.unidade_medida} · ${alvo.unidade}` : ''}
        footer={<Button block size="lg" variant="danger" loading={busy} disabled={motivo.trim().length < 5} onClick={descartar}>Descartar</Button>}>
        <Field label="Motivo"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: vencido; embalagem violada" className={inputCls} /></Field>
      </Sheet>
    </div>
  );
}

export function CoberturaAba({ unitId }: { unitId: number | null }) {
  const res = useRpc<any[]>('cobertura_alimentos', { unit_id: unitId }, { enabled: unitId != null, retry: false });
  if (unitId == null) return <Card><EmptyState compact title="Escolha uma unidade" body="A cobertura é calculada por unidade, pelas refeições servidas." /></Card>;
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const tone = (d: number | null) => (d == null ? 'gray' : d < 7 ? 'red' : d < 14 ? 'amber' : 'green');
  return (
    <div className="space-y-3">
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,2fr) 120px 140px 130px 120px" largura={720} rotulo="Cobertura de alimentos">
          <TCabecalho><TCelula fixa>Alimento</TCelula><TCelula>Na despensa</TCelula><TCelula>Consumo por dia</TCelula><TCelula>Dá para</TCelula><TCelula>Próx. validade</TCelula></TCabecalho>
          {(res.data ?? []).map((a) => (
            <TLinha key={a.codigo} alerta={a.dias != null && a.dias < 7}>
              <TCelula fixa titulo={a.nome} className="font-semibold">{a.nome}</TCelula>
              <TCelula>{num(a.saldo)} {a.unidade_medida}</TCelula>
              <TCelula className="text-muted">{num(a.consumo_dia)} {a.unidade_medida}</TCelula>
              <TCelula livre><Badge tone={tone(a.dias) as Tone}>{a.dias != null ? `${String(a.dias).replace('.', ',')} dias` : 'sem consumo'}</Badge></TCelula>
              <TCelula>{fmtDate(a.proxima_validade)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <p className="text-[12.5px] text-muted">Consumo estimado pela média das refeições servidas nos últimos 20 dias de aula, vezes a quantidade por refeição de cada alimento (per capita da demonstração; a nutrição define a oficial).</p>
    </div>
  );
}
