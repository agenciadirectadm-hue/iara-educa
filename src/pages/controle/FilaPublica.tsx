// Fila pública anonimizada (controle externo): cada inscrição pelo código público, com pontos, critérios, espera,
// as três distâncias e a conferência da ordem — sem nome, endereço ou documento. Exporta CSV para análise própria.
import { useState } from 'react';
import { keepPreviousData } from '@tanstack/react-query';
import clsx from 'clsx';
import { Check, CheckCircle2, Download, Search, X } from 'lucide-react';
import { rpc, type MedidaDistancia } from '@/lib/api';
import { useBootstrap, useUnitsMap } from '@/lib/data';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtDate, fmtInt, fmtKm } from '@/lib/format';
import { FLAG, QUEUE_CATEGORY, QUEUE_STATUS } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, PageHeader, SkeletonList, SourceChip, inputCls } from '@/components/ui';
import { useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { LinkMetodologia, MEDIDA, MEDIDAS } from '@/components/distancias';
import { Paginacao, useFiltrosUrl } from '@/pages/Alunos';

const POR_PAGINA = 50;
const CHAVE: Record<MedidaDistancia, 'linha_reta_m' | 'a_pe_m' | 'carro_m'> = { LINHA_RETA: 'linha_reta_m', A_PE: 'a_pe_m', CARRO: 'carro_m' };
const CRITERIOS = ['IRMAO_NA_UNIDADE', 'CADUNICO', 'TERRITORIO', 'MAE_SOLO', 'PCD_TEA_AEE'];

function csv(itens: any[]): string {
  const cab = ['codigo', 'unidade', 'faixa', 'posicao', 'pontos', 'criterios', 'categoria', 'situacao', 'entrada', 'dias_espera',
    'linha_reta_m', 'a_pe_m', 'carro_m', 'regras', 'ordem_conferida'];
  const esc = (v: unknown) => {
    const s = v == null ? '' : String(v);
    return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const linhas = itens.map((x) => [x.codigo, x.unidade, x.faixa, x.posicao, x.pontos, (x.criterios ?? []).map((c: string) => FLAG[c]?.short ?? c).join(' + '),
    QUEUE_CATEGORY[x.categoria]?.label ?? x.categoria, QUEUE_STATUS[x.status]?.label ?? x.status, x.entrada, x.dias,
    x.dist?.linha_reta_m, x.dist?.a_pe_m, x.dist?.carro_m, x.regras, x.ordem_conferida ? 'sim' : 'não'].map(esc).join(';'));
  return '﻿' + [cab.join(';'), ...linhas].join('\r\n');
}

export default function FilaPublica() {
  const { sp, set } = useFiltrosUrl();
  const boot = useBootstrap();
  const units = useUnitsMap();
  const toast = useToast();
  const [q, setQ] = useState(sp.get('q') ?? '');
  const dq = useDebounced(q.trim(), 300);
  const unit = sp.get('unidade');
  const faixa = sp.get('faixa');
  const flag = sp.get('criterio');
  const pagina = Number(sp.get('pagina') ?? 1);
  const args = { unit_id: unit ? Number(unit) : null, grade_level_id: faixa ? Number(faixa) : null, flag, q: dq || null };
  const res = useRpc<any>('controle_fila', { ...args, page: pagina, page_size: POR_PAGINA }, { placeholderData: keepPreviousData });
  const [baixando, setBaixando] = useState(false);
  const crit = res.data?.criterio_distancia as { medida: MedidaDistancia; limite_m: number } | undefined;
  const grades = (boot.data?.grades ?? []) as any[];
  const unidades = [...(units.data?.units ?? [])].sort((a, b) => a.short_name.localeCompare(b.short_name, 'pt-BR'));

  const exportar = async () => {
    setBaixando(true);
    try {
      const r = await rpc<any>('controle_fila', { ...args, page: 1, page_size: 5000 });
      const blob = new Blob([csv(r.itens)], { type: 'text/csv;charset=utf-8' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `fila-anonimizada-${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      toast({ title: 'CSV gerado', description: `${fmtInt(r.itens.length)} inscrições, sem dados pessoais.`, tone: 'success' });
    } catch (e) {
      toast({ title: 'Não foi possível exportar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBaixando(false);
    }
  };

  return (
    <div>
      <PageHeader
        eyebrow="Controle externo · fila pública"
        title="Fila de espera, sem nomes"
        subtitle="Cada inscrição aparece pelo código público. Posição, pontos e critérios seguem a IN nº 025/2025; a ordem de cada fila é conferida automaticamente."
        actions={<Button variant="secondary" icon={Download} loading={baixando} onClick={exportar}>Exportar CSV</Button>}
      />

      {res.data && (
        <Card className={clsx('mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 p-3 text-[13.5px] ring-1',
          res.data.filas_conferidas === res.data.filas ? 'bg-green-50 ring-green-200' : 'bg-red-50 ring-red-200')}>
          <CheckCircle2 className={clsx('size-5', res.data.filas_conferidas === res.data.filas ? 'text-green-700' : 'text-red-700')} />
          <span><b>Ordem conferida em {fmtInt(res.data.filas_conferidas)} de {fmtInt(res.data.filas)} filas</b> (unidade × faixa): a posição registrada é a calculada pela regra — pontos e, no empate, a data de entrada.</span>
          <span className="text-muted">Regras {res.data.regras}.</span>
        </Card>
      )}

      <div className="flex flex-col gap-2 sm:flex-row">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
          <input value={q} onChange={(e) => { setQ(e.target.value); set({ q: e.target.value || null }); }} placeholder="Código público (ex.: F-3A9C1B)"
            className={clsx(inputCls, 'pl-11 uppercase placeholder:normal-case')} aria-label="Buscar pelo código público" />
          {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => { setQ(''); set({ q: null }); }} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
        </div>
        <select value={unit ?? ''} onChange={(e) => set({ unidade: e.target.value || null })} className={clsx(inputCls, 'sm:w-80')} aria-label="Unidade">
          <option value="">Todas as unidades</option>
          {unidades.map((u) => <option key={u.id} value={u.id}>{u.short_name} · {u.type === 'CMEI' ? 'CMEI' : 'Escola'}</option>)}
        </select>
      </div>
      <div className="no-scrollbar -mx-4 mt-2 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
        <Chip active={!faixa} onClick={() => set({ faixa: null })}>Todas as faixas</Chip>
        {grades.map((g) => <Chip key={g.id} active={faixa === String(g.id)} onClick={() => set({ faixa: faixa === String(g.id) ? null : g.id })}>{g.short_name}</Chip>)}
      </div>
      <div className="no-scrollbar -mx-4 mt-1 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
        <Chip active={!flag} onClick={() => set({ criterio: null })}>Todos os critérios</Chip>
        {CRITERIOS.map((c) => <Chip key={c} active={flag === c} onClick={() => set({ criterio: flag === c ? null : c })}>{FLAG[c]?.short ?? c}</Chip>)}
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] text-muted">
        {res.data && <span className="inline-flex items-center gap-1">{fmtInt(res.data.total)} inscrição(ões)<SourceChip kind="demo" /></span>}
        {crit && <span>Distâncias da casa à unidade: o critério “até {fmtKm(crit.limite_m)}” usa a medida <b className="text-purple-800">{MEDIDA[crit.medida].rotulo.toLowerCase()}</b> · <LinkMetodologia>como medimos</LinkMetodologia></span>}
      </div>

      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} />
          : res.data.itens.length === 0 ? <Card><EmptyState title="Nenhuma inscrição neste filtro" /></Card> : (
          <Card className="overflow-hidden">
            <Tabela rotulo="Fila pública anonimizada" largura={1220}
              colunas="112px minmax(170px,1.3fr) 96px 68px 60px minmax(170px,1fr) 92px 70px 92px 84px 88px 70px">
              <TCabecalho>
                <span>Código</span><span>Unidade</span><span>Faixa</span><span className="text-right">Posição</span><span className="text-right">Pontos</span>
                <span>Critérios</span><span>Entrada</span><span className="text-right">Espera</span>
                {MEDIDAS.map((m) => <span key={m} className={clsx('whitespace-nowrap text-right', crit?.medida === m && 'text-purple-800')}>{MEDIDA[m].rotulo}{crit?.medida === m && ' ★'}</span>)}
                <span className="text-center">Ordem</span>
              </TCabecalho>
              {(res.data.itens as any[]).map((x) => (
                <TLinha key={x.codigo} rotulo={`${x.codigo}, ${x.posicao ?? '—'}º, ${x.unidade}`}>
                  <TCelula fixa className="font-mono text-[12.5px] font-semibold">{x.codigo}</TCelula>
                  <TCelula titulo={x.unidade}>{x.unidade}</TCelula>
                  <TCelula className="text-muted">{x.faixa}</TCelula>
                  <TCelula className="text-right font-display font-black tabular text-purple-800">{x.posicao ? `${x.posicao}º` : '—'}</TCelula>
                  <TCelula className="text-right tabular">{fmtInt(x.pontos)}</TCelula>
                  <TCelula titulo={(x.criterios ?? []).map((c: string) => FLAG[c]?.label ?? c).join(' · ') || QUEUE_CATEGORY[x.categoria]?.label}>
                    <span className="inline-flex gap-1">
                      {x.status !== 'WAITING' && <Badge tone={QUEUE_STATUS[x.status]?.tone}>{QUEUE_STATUS[x.status]?.label}</Badge>}
                      {(x.criterios ?? []).map((c: string) => <Badge key={c} tone="purple">{FLAG[c]?.short ?? c}</Badge>)}
                      {!(x.criterios ?? []).length && <span className="text-muted">sem critério de pontos</span>}
                    </span>
                  </TCelula>
                  <TCelula className="tabular text-muted">{fmtDate(x.entrada)}</TCelula>
                  <TCelula className={clsx('text-right tabular', x.dias > 90 ? 'font-semibold text-amber-800' : 'text-muted')}>{fmtInt(x.dias)} d</TCelula>
                  {MEDIDAS.map((m) => {
                    const v = x.dist?.[CHAVE[m]] as number | null;
                    return (
                      <TCelula key={m} className={clsx('text-right tabular', crit?.medida === m ? 'font-semibold' : 'text-muted')}>
                        {v != null ? fmtKm(v) : '—'}
                        {crit?.medida === m && v != null && (v <= crit.limite_m ? <Check className="ml-0.5 inline size-3.5 text-green-700" /> : <X className="ml-0.5 inline size-3.5 text-subtle" />)}
                      </TCelula>
                    );
                  })}
                  <TCelula className="text-center">{x.ordem_conferida ? <Check className="inline size-4 text-green-700" aria-label="ordem conferida" /> : <X className="inline size-4 text-red-600" aria-label="ordem divergente" />}</TCelula>
                </TLinha>
              ))}
            </Tabela>
            <Paginacao pagina={pagina} total={res.data.total} porPagina={POR_PAGINA} onPagina={(n) => set({ pagina: n })} />
          </Card>
        )}
      </div>
      <p className="mt-3 text-[12px] text-muted">
        Sem nome, endereço, documento ou contato. O código público não identifica a criança; a família pode consultar o próprio caso com a Defensoria ou o MP informando o protocolo.
      </p>
    </div>
  );
}
