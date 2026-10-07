import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { keepPreviousData, useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { ArrowDownToLine, ArrowUpFromLine, Boxes, PackagePlus, Pencil, Scale, Trash2, TriangleAlert } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, PageHeader, Segmented, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { CoberturaAba, PedidosAba, ValidadeAba } from '@/components/almoxarifado';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { Paginacao } from './Alunos';

export const CATEGORIA_MATERIAL: Record<string, string> = {
  PEDAGOGICO: 'Pedagógico', LIMPEZA: 'Limpeza e higiene', ESCRITORIO: 'Escritório', ALIMENTO: 'Alimentos', UNIFORME: 'Uniformes',
  EQUIPAMENTO: 'Equipamentos', MOBILIARIO: 'Mobiliário', OUTRO: 'Outros',
};
const ESTADO: Record<string, string> = { NOVO: 'Novo', BOM: 'Bom', REGULAR: 'Regular', RUIM: 'Ruim', INSERVIVEL: 'Inservível' };
const POR_PAGINA = 60;
const num = (n: number | string | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('pt-BR', { maximumFractionDigits: 2 }));

type Aba = 'estoque' | 'pedidos' | 'validade' | 'alimentos';

/** Materiais e almoxarifado: estoque e patrimônio, pedidos (escola → almoxarifado → remessa → recebimento), validade e cobertura de alimentos. */
export default function Materiais() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? (me?.role === 'ALMOXARIFADO' ? 'pedidos' : 'estoque')) as Aba;
  const [unit, setUnit] = useState<number | null>(null);
  const [central, setCentral] = useState(false);
  const [cat, setCat] = useState('');
  const [baixo, setBaixo] = useState(false);
  const [busca, setBusca] = useState('');
  const [pagina, setPagina] = useState(1);
  const db = useDebounced(busca, 300);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  const res = useRpc<any>('materiais_lista', { unit_id: unit, central, categoria: cat || null, abaixo_minimo: baixo, busca: db, limite: POR_PAGINA, offset: (pagina - 1) * POR_PAGINA },
    { placeholderData: keepPreviousData });
  const d = res.data;
  const filtro = (f: () => void) => { f(); setPagina(1); };
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · almoxarifado e patrimônio' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">{me?.role === 'ALMOXARIFADO' ? 'Almoxarifado' : 'Materiais'}<Simulado detail="Itens, pedidos, lotes e quantidades de demonstração." /></span>}
        subtitle="Estoque de material pedagógico, limpeza, escritório, alimentos e uniformes; pedidos ao almoxarifado com remessa e recebimento conferido; lotes e validade; patrimônio."
        actions={<>
          {rede && (aba === 'estoque' || aba === 'validade') && <Segmented value={central ? 'C' : 'U'} onChange={(v) => filtro(() => setCentral(v === 'C'))} items={[{ value: 'U', label: 'Unidades' }, { value: 'C', label: 'Almoxarifado central' }]} />}
          {rede && !(central && (aba === 'estoque' || aba === 'validade')) && <UnitSelect value={unit} onChange={(v) => filtro(() => setUnit(v))} />}
          {aba === 'estoque' && d?.pode_editar && <Button icon={PackagePlus} onClick={() => setNovo(true)}>Novo material</Button>}
        </>} />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} className="mb-3"
        items={[{ value: 'estoque', label: 'Estoque e patrimônio' }, { value: 'pedidos', label: 'Pedidos e remessas' }, { value: 'validade', label: 'Validade' }, { value: 'alimentos', label: 'Alimentos (cobertura)' }]} />
      {aba === 'pedidos' && <PedidosAba unitId={rede ? unit : me?.unit?.id ?? null} rede={rede} />}
      {aba === 'validade' && <ValidadeAba unitId={rede ? (central ? null : unit) : me?.unit?.id ?? null} central={rede && central} />}
      {aba === 'alimentos' && <CoberturaAba unitId={rede ? unit : me?.unit?.id ?? null} />}
      {aba === 'estoque' && <>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <Kpi compact icon={Boxes} tone="blue" label="Itens cadastrados" value={fmtInt(d?.total)} />
        <Kpi compact icon={TriangleAlert} tone="red" label="Abaixo do mínimo" value={fmtInt(d?.abaixo_minimo)} onClick={() => filtro(() => setBaixo(!baixo))} />
        <Kpi compact icon={Scale} tone="purple" label="Patrimônio (equipamentos e mobiliário)" value={fmtInt((d?.por_categoria?.EQUIPAMENTO ?? 0) + (d?.por_categoria?.MOBILIARIO ?? 0))} />
      </div>
      <Card className="mt-4 space-y-2 p-3">
        <div className="flex flex-wrap gap-2">
          <Chip active={!cat} onClick={() => filtro(() => setCat(''))}>Tudo</Chip>
          {Object.entries(CATEGORIA_MATERIAL).map(([k, v]) => <Chip key={k} active={cat === k} onClick={() => filtro(() => setCat(k))}>{v}</Chip>)}
          <Chip active={baixo} onClick={() => filtro(() => setBaixo(!baixo))} icon={TriangleAlert}>Só abaixo do mínimo</Chip>
        </div>
        <input value={busca} onChange={(e) => filtro(() => setBusca(e.target.value))} placeholder="Nome (ou parte), código ou número de patrimônio…" className={inputCls} aria-label="Buscar material" />
      </Card>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
          <Card className={clsx('overflow-hidden', res.isFetching && res.isPlaceholderData && 'opacity-60')}>
            <Tabela colunas="minmax(220px,1.6fr) 130px minmax(140px,1fr) 130px 100px 110px minmax(120px,0.8fr)" largura={1000} rotulo="Materiais">
              <TCabecalho><TCelula>Material</TCelula><TCelula>Categoria</TCelula><TCelula>Unidade</TCelula><TCelula>Estoque</TCelula><TCelula>Mínimo</TCelula><TCelula>Estado</TCelula><TCelula>Local</TCelula></TCabecalho>
              {(d.itens as any[]).map((m) => (
                <TLinha key={m.id} onClick={() => setAberto(m.id)} alerta={m.abaixo_minimo} rotulo={m.nome}>
                  <TCelula fixa titulo={`${m.nome}${m.patrimonio ? ' · ' + m.patrimonio : ''}`}><span className="font-semibold">{m.nome}</span> <span className="text-[12px] text-muted">{m.patrimonio ?? m.codigo ?? ''}</span></TCelula>
                  <TCelula>{CATEGORIA_MATERIAL[m.categoria]}</TCelula>
                  <TCelula titulo={m.unidade}>{m.unidade}</TCelula>
                  <TCelula className={m.abaixo_minimo ? 'font-bold text-red-700' : 'font-semibold'}>{num(m.quantidade)} {m.unidade_medida}</TCelula>
                  <TCelula className="text-muted">{m.minimo > 0 ? num(m.minimo) : '—'}</TCelula>
                  <TCelula>{m.estado ? ESTADO[m.estado] : '—'}</TCelula>
                  <TCelula titulo={m.localizacao} className="text-muted">{m.localizacao ?? '—'}</TCelula>
                </TLinha>
              ))}
            </Tabela>
            {!d.itens.length && <EmptyState compact title="Nenhum material com estes filtros" />}
            <Paginacao pagina={pagina} total={Number(d.total ?? 0)} porPagina={POR_PAGINA} onPagina={setPagina} />
          </Card>
        )}
      </div>
      </>}
      <MaterialSheet id={aberto} onClose={() => setAberto(null)} podeEditar={!!d?.pode_editar} />
      <MaterialForm open={novo} onClose={() => setNovo(false)} unidade={rede ? (central ? null : unit) : me?.unit?.id ?? null} />
    </div>
  );
}

function useRecarregar() {
  const qc = useQueryClient();
  return () => ['materiais_lista', 'material_detalhe'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

function MaterialSheet({ id, onClose, podeEditar }: { id: string | null; onClose: () => void; podeEditar: boolean }) {
  const res = useRpc<any>('material_detalhe', { id }, { enabled: !!id });
  const toast = useToast();
  const recarregar = useRecarregar();
  const [tipo, setTipo] = useState('ENTRADA');
  const [qtd, setQtd] = useState('');
  const [motivo, setMotivo] = useState('');
  const [lote, setLote] = useState('');
  const [validade, setValidade] = useState('');
  const [editar, setEditar] = useState(false);
  const [excluir, setExcluir] = useState(false);
  const [busy, setBusy] = useState(false);
  const m = res.data;
  const movimentar = async () => {
    setBusy(true);
    try {
      await rpc('material_movimentar', { id, tipo, quantidade: qtd, motivo, lote, validade: validade || null });
      toast({ title: 'Movimento registrado', tone: 'success' });
      setQtd(''); setMotivo(''); setLote(''); setValidade('');
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const darBaixa = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('material_excluir', { id, motivo });
      toast({ title: r.excluido ? 'Material excluído' : 'Baixa registrada', description: r.mensagem, tone: 'success' });
      recarregar();
      setExcluir(false); setMotivo('');
      onClose();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!id} onClose={onClose} title={m?.nome ?? 'Material'} subtitle={m ? `${CATEGORIA_MATERIAL[m.categoria]} · ${m.unidade}` : ''} size="lg">
      {!m ? <SkeletonList rows={3} /> : (
        <div className="space-y-4 pt-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className={clsx('font-display text-3xl font-black', m.abaixo_minimo ? 'text-red-700' : 'text-ink')}>{num(m.quantidade)}</span>
            <span className="text-muted">{m.unidade_medida}{m.minimo > 0 ? ` · mínimo ${num(m.minimo)}` : ''}</span>
            {m.abaixo_minimo && <Badge tone="red">Abaixo do mínimo</Badge>}
            {m.patrimonio && <Badge tone="purple">Patrimônio {m.patrimonio}</Badge>}
            {m.estado && <Badge tone="gray">{ESTADO[m.estado]}</Badge>}
            {!m.ativo && <Badge tone="gray">Baixado</Badge>}
          </div>
          {podeEditar && m.ativo && (
            <Card className="space-y-2 p-3">
              <Segmented value={tipo} onChange={setTipo} items={[{ value: 'ENTRADA', label: 'Entrada' }, { value: 'SAIDA', label: 'Saída' }, { value: 'AJUSTE', label: 'Ajuste de inventário' }]} />
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-[140px_1fr_auto]">
                <input type="number" min={0} step="any" value={qtd} onChange={(e) => setQtd(e.target.value)} placeholder={tipo === 'AJUSTE' ? 'Contado' : 'Quantidade'} className={inputCls} aria-label="Quantidade" />
                <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder={tipo === 'SAIDA' ? 'Para onde / por quê' : tipo === 'AJUSTE' ? 'Motivo do ajuste (obrigatório)' : 'Origem (nota, doação, remessa…)'} className={inputCls} aria-label="Motivo" />
                <Button loading={busy} disabled={!qtd || (m.controla_validade && tipo === 'ENTRADA' && !validade)} icon={tipo === 'SAIDA' ? ArrowUpFromLine : ArrowDownToLine} onClick={movimentar}>Registrar</Button>
              </div>
              {m.controla_validade && tipo === 'ENTRADA' && (
                <div className="grid grid-cols-2 gap-2">
                  <input value={lote} onChange={(e) => setLote(e.target.value)} placeholder="Lote" className={inputCls} aria-label="Lote" />
                  <input type="date" value={validade} onChange={(e) => setValidade(e.target.value)} className={inputCls} aria-label="Validade" />
                </div>
              )}
              {m.controla_validade && tipo === 'SAIDA' && <p className="text-[12px] text-muted">A saída usa primeiro o lote que vence antes.</p>}
            </Card>
          )}
          {m.consumo_dia > 0 && (
            <p className="text-[13px] text-muted">Consumo estimado pelas refeições servidas: <b className="text-ink">{num(m.consumo_dia)} {m.unidade_medida}/dia</b> — dá para cerca de <b className="text-ink">{Math.floor(m.quantidade / m.consumo_dia)} dias</b>.</p>
          )}
          {(m.lotes as any[] | undefined)?.length ? (
            <div>
              <div className="mb-1 text-[12px] font-bold uppercase tracking-wide text-subtle">Lotes</div>
              <Card className="divide-y divide-line overflow-hidden">
                {(m.lotes as any[]).map((l) => (
                  <div key={l.id} className="flex items-center gap-3 px-3 py-2 text-[13px]">
                    <span className="font-mono text-[12.5px]">{l.lote}</span>
                    <span className="font-semibold tabular">{num(l.quantidade)} {m.unidade_medida}</span>
                    <span className="min-w-0 flex-1 truncate text-muted">{l.fornecedor ?? ''}</span>
                    {l.validade && <Badge tone={l.vencido ? 'red' : l.dias <= 15 ? 'amber' : 'gray'}>{l.vencido ? 'vencido' : 'val.'} {new Date(l.validade + 'T12:00:00').toLocaleDateString('pt-BR')}</Badge>}
                  </div>
                ))}
              </Card>
            </div>
          ) : null}
          <div>
            <div className="mb-1 text-[12px] font-bold uppercase tracking-wide text-subtle">Movimentação</div>
            <Card className="divide-y divide-line overflow-hidden">
              {(m.movimentos as any[]).map((v, i) => (
                <div key={i} className="flex items-center gap-3 px-3 py-2 text-[13px]">
                  <Badge tone={v.tipo === 'ENTRADA' ? 'green' : v.tipo === 'SAIDA' ? 'amber' : 'blue'}>{v.tipo === 'ENTRADA' ? 'Entrada' : v.tipo === 'SAIDA' ? 'Saída' : 'Ajuste'}</Badge>
                  <span className="font-semibold tabular">{v.tipo === 'SAIDA' ? '−' : v.quantidade >= 0 ? '+' : ''}{num(v.quantidade)}</span>
                  <span className="min-w-0 flex-1 truncate text-muted" title={v.motivo ?? ''}>{v.motivo ?? ''} · {v.autor}</span>
                  <span className="shrink-0 text-[12px] text-muted">saldo {num(v.saldo)} · {fmtDateTime(v.em)}</span>
                </div>
              ))}
              {!m.movimentos.length && <p className="p-3 text-sm text-muted">Sem movimentação.</p>}
            </Card>
          </div>
          {podeEditar && m.ativo && (
            <div className="flex flex-wrap gap-2">
              <Button variant="secondary" icon={Pencil} onClick={() => setEditar(true)}>Alterar dados</Button>
              <Button variant="secondary" icon={Trash2} className="text-red-700" onClick={() => setExcluir(!excluir)}>Excluir ou dar baixa</Button>
            </div>
          )}
          {excluir && (
            <Card className="space-y-2 p-3">
              <Field label="Motivo" hint="Sem movimentação o item é excluído; com movimentação ou patrimônio, recebe baixa e fica no histórico.">
                <input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={inputCls} />
              </Field>
              <Button variant="danger" loading={busy} disabled={motivo.trim().length < 5} onClick={darBaixa}>Confirmar</Button>
            </Card>
          )}
          <MaterialForm open={editar} onClose={() => setEditar(false)} material={m} unidade={m.unit_id} />
        </div>
      )}
    </Sheet>
  );
}

function MaterialForm({ open, onClose, material, unidade }: { open: boolean; onClose: () => void; material?: any; unidade: number | null }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [f, setF] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const v = (k: string, padrao = '') => f[k] ?? (material?.[k] != null ? String(material[k]) : padrao);
  const set = (k: string) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('material_salvar', {
        id: material?.id ?? null, unit_id: unidade, nome: v('nome'), codigo: v('codigo'), categoria: v('categoria', 'PEDAGOGICO'), unidade_medida: v('unidade_medida', 'unidade'),
        quantidade: material ? null : v('quantidade', '0'), minimo: v('minimo', '0'), patrimonio: v('patrimonio'), estado: v('estado'), localizacao: v('localizacao'), observacao: v('observacao'),
      });
      toast({ title: material ? 'Material alterado' : 'Material incluído', tone: 'success' });
      recarregar();
      setF({});
      onClose();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={material ? 'Alterar material' : 'Novo material'} subtitle={material ? undefined : unidade ? 'Na unidade escolhida.' : 'No almoxarifado central da SEDUC.'} size="lg"
      footer={<Button block size="lg" loading={busy} disabled={v('nome').trim().length < 3} onClick={salvar}>Salvar</Button>}>
      <div className="grid grid-cols-1 gap-3 pt-1 sm:grid-cols-2">
        <Field label="Nome"><input value={v('nome')} onChange={set('nome')} className={inputCls} /></Field>
        <Field label="Código (opcional)"><input value={v('codigo')} onChange={set('codigo')} className={inputCls} /></Field>
        <Field label="Categoria">
          <select value={v('categoria', 'PEDAGOGICO')} onChange={set('categoria')} className={inputCls}>
            {Object.entries(CATEGORIA_MATERIAL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
        <Field label="Unidade de medida"><input value={v('unidade_medida', 'unidade')} onChange={set('unidade_medida')} placeholder="unidade, caixa, kg, pacote…" className={inputCls} /></Field>
        {!material && <Field label="Quantidade inicial"><input type="number" min={0} step="any" value={v('quantidade', '0')} onChange={set('quantidade')} className={inputCls} /></Field>}
        <Field label="Estoque mínimo"><input type="number" min={0} step="any" value={v('minimo', '0')} onChange={set('minimo')} className={inputCls} /></Field>
        <Field label="Nº de patrimônio (equipamento ou móvel)"><input value={v('patrimonio')} onChange={set('patrimonio')} className={inputCls} /></Field>
        <Field label="Estado">
          <select value={v('estado')} onChange={set('estado')} className={inputCls}>
            <option value="">—</option>{Object.entries(ESTADO).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
        <Field label="Localização"><input value={v('localizacao')} onChange={set('localizacao')} className={inputCls} /></Field>
        <Field label="Observação"><input value={v('observacao')} onChange={set('observacao')} className={inputCls} /></Field>
      </div>
    </Sheet>
  );
}
