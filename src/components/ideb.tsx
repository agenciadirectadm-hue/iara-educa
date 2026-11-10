// Ideb (INEP) — dado oficial e público: a série da escola comparada com a rede municipal e o painel da rede.
import { useState } from 'react';
import { Link } from 'react-router';
import { ExternalLink, Map as MapIcon, TrendingDown, TrendingUp } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtInt } from '@/lib/format';
import { Badge, Card, EmptyState, ErrorState, Kpi, Section, SkeletonList, SourceChip } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

const n1 = (v: number | null | undefined) => (v == null ? '—' : Number(v).toFixed(1).replace('.', ','));
const COR_A = '#7c3aed'; // série principal (roxo da IARA)
const COR_B = '#64748b'; // referência (rede)

type Ponto = { ano: number; a: number | null; b?: number | null; meta?: number | null; obs?: string | null };

/** Linha por edição (2005–2025): até duas séries (escola e rede) e a meta do 1º ciclo como marcas vazadas. */
export function IdebLinha({ pontos, rotuloA, rotuloB }: { pontos: Ponto[]; rotuloA: string; rotuloB?: string }) {
  const [hover, setHover] = useState<number | null>(null);
  const W = 640, H = 220, PL = 34, PR = 26, PT = 18, PB = 28;
  const vals = pontos.flatMap((p) => [p.a, p.b, p.meta]).filter((v): v is number => v != null);
  const min = Math.max(0, Math.floor(Math.min(...vals) - 0.5)), max = Math.min(10, Math.ceil(Math.max(...vals) + 0.3));
  const x = (i: number) => PL + (i * (W - PL - PR)) / Math.max(pontos.length - 1, 1);
  const y = (v: number) => PT + ((max - v) * (H - PT - PB)) / Math.max(max - min, 1);
  const linha = (k: 'a' | 'b') => {
    let d = '';
    pontos.forEach((p, i) => { const v = p[k]; if (v == null) return; d += `${d && pontos[i - 1]?.[k] != null ? 'L' : 'M'}${x(i)},${y(v)}`; });
    return d;
  };
  const ticks = Array.from({ length: max - min + 1 }, (_, i) => min + i);
  const h = hover != null ? pontos[hover] : null;
  const ultimo = pontos.reduce((acc, p, i) => (p.a != null ? i : acc), -1);
  return (
    <div className="relative">
      <div className="mb-1 flex flex-wrap gap-3 text-[12.5px] text-muted">
        <span className="inline-flex items-center gap-1.5"><span className="inline-block h-0.5 w-4 rounded" style={{ background: COR_A }} />{rotuloA}</span>
        {rotuloB && <span className="inline-flex items-center gap-1.5"><span className="inline-block h-0.5 w-4 rounded" style={{ background: COR_B }} />{rotuloB}</span>}
        {pontos.some((p) => p.meta != null) && <span className="inline-flex items-center gap-1.5"><span className="inline-block size-2.5 rounded-full border-2" style={{ borderColor: COR_A }} />Meta (2007–2021)</span>}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={`Ideb por edição: ${rotuloA}${rotuloB ? ` e ${rotuloB}` : ''}`}
        onMouseLeave={() => setHover(null)}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={PL} x2={W - PR} y1={y(t)} y2={y(t)} stroke="currentColor" className="text-slate-200" strokeWidth={1} />
            <text x={PL - 6} y={y(t) + 4} textAnchor="end" className="fill-slate-400 text-[11px]">{t}</text>
          </g>
        ))}
        {pontos.map((p, i) => <text key={p.ano} x={x(i)} y={H - 8} textAnchor="middle" className="fill-slate-400 text-[11px]">{p.ano}</text>)}
        {hover != null && <line x1={x(hover)} x2={x(hover)} y1={PT} y2={H - PB} stroke="currentColor" className="text-slate-300" strokeWidth={1} />}
        {rotuloB && <path d={linha('b')} fill="none" stroke={COR_B} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />}
        <path d={linha('a')} fill="none" stroke={COR_A} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
        {pontos.map((p, i) => p.meta != null && <circle key={`m${p.ano}`} cx={x(i)} cy={y(p.meta)} r={4} fill="white" stroke={COR_A} strokeWidth={2} />)}
        {pontos.map((p, i) => p.a != null && <circle key={`a${p.ano}`} cx={x(i)} cy={y(p.a)} r={4} fill={COR_A} stroke="white" strokeWidth={2} />)}
        {pontos.map((p, i) => <rect key={`h${p.ano}`} x={x(i) - (W - PL - PR) / pontos.length / 2} y={PT} width={(W - PL - PR) / pontos.length} height={H - PT - PB} fill="transparent"
          onMouseEnter={() => setHover(i)} onClick={() => setHover(i)} />)}
        {/* rótulo direto só no último ponto */}
        {ultimo >= 0 && <text x={x(ultimo)} y={y(pontos[ultimo].a!) - 9} textAnchor="middle" className="fill-slate-700 text-[12px] font-semibold">{n1(pontos[ultimo].a)}</text>}
      </svg>
      {h && (
        <div className="pointer-events-none absolute right-2 top-6 rounded-xl bg-white px-3 py-2 text-[12.5px] shadow-soft ring-1 ring-line">
          <div className="font-semibold">{h.ano}</div>
          <div>{rotuloA}: <b>{h.a == null ? (h.obs ?? 'sem dado') : n1(h.a)}</b></div>
          {rotuloB && <div>{rotuloB}: <b>{n1(h.b)}</b></div>}
          {h.meta != null && <div>Meta: <b>{n1(h.meta)}</b></div>}
        </div>
      )}
    </div>
  );
}

/** Ficha da unidade (público): a escola e a rede, com posição na rede e as notas do Saeb. */
export function IdebUnidade({ unitId }: { unitId: number }) {
  const res = useRpc<any>('ideb_unidade', { unit_id: unitId }, { staleTime: 60 * 60_000 });
  if (res.isLoading) return <SkeletonList rows={2} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  if (!d.tem) return <Card><EmptyState compact title="Sem Ideb" body={d.motivo} /></Card>;
  const serie = d.serie as any[];
  const ult = serie.filter((s) => s.ideb != null).at(-1);
  const ant = serie.filter((s) => s.ideb != null && s.ano < (ult?.ano ?? 0)).at(-1);
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={ult && ant && ult.ideb >= ant.ideb ? TrendingUp : TrendingDown} tone="purple" label={`Ideb ${ult?.ano ?? ''}`} value={n1(ult?.ideb)}
          sub={ant ? `${n1(ant.ideb)} em ${ant.ano}` : undefined} source="oficial" sourceDetail="INEP" />
        <Kpi compact icon={TrendingUp} tone="gray" label={`Rede municipal ${ult?.ano ?? ''}`} value={n1(ult?.rede)} source="oficial" sourceDetail="INEP" />
        {d.posicao && <Kpi compact icon={TrendingUp} tone="teal" label="Posição na rede" value={`${d.posicao.posicao}ª`} sub={`de ${d.posicao.de} escolas`} />}
        <Kpi compact icon={TrendingUp} tone="blue" label="Aprovação (1º ao 5º)" value={ult?.aprovacao != null ? `${(ult.aprovacao * 100).toFixed(1).replace('.', ',')}%` : '—'}
          sub={ult ? `Saeb: mat. ${n1(ult.nota_mat)} · port. ${n1(ult.nota_lp)}` : undefined} />
      </div>
      <Card className="p-4">
        <IdebLinha pontos={serie.map((s) => ({ ano: s.ano, a: s.ideb, b: s.rede, meta: s.meta, obs: s.obs }))} rotuloA="Esta escola" rotuloB="Rede municipal" />
      </Card>
      <p className="flex flex-wrap items-center gap-2 text-[12.5px] text-muted">
        <SourceChip kind="oficial" detail="INEP" /> {d.nota} <a href={d.fonte.url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 font-semibold text-purple-700">{d.fonte.rotulo}<ExternalLink className="size-3.5" /></a>
      </p>
    </div>
  );
}

/** Painel da rede (público): série da rede, escolas no último ano e quem subiu ou caiu. */
export function IdebRedePainel() {
  const res = useRpc<any>('ideb_rede', {}, { staleTime: 60 * 60_000 });
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const r = d.resumo;
  const ult = (d.rede as any[]).find((x) => x.ano === d.ultimo_ano);
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi compact icon={TrendingUp} tone="purple" label={`Ideb da rede ${d.ultimo_ano}`} value={n1(ult?.ideb)} sub="anos iniciais" source="oficial" sourceDetail="INEP" />
        <Kpi compact icon={TrendingUp} tone="green" label="Escolas com 7,0 ou mais" value={fmtInt(r.acima_7)} sub={`de ${fmtInt(r.com_ideb)} com Ideb`} />
        <Kpi compact icon={TrendingDown} tone="red" label="Abaixo de 6,0" value={fmtInt(r.abaixo_6)} />
        <Kpi compact icon={TrendingUp} tone="teal" label={`Subiram desde ${d.ultimo_ano - 2}`} value={fmtInt(r.subiram)} />
        <Kpi compact icon={TrendingDown} tone="amber" label={`Caíram desde ${d.ultimo_ano - 2}`} value={fmtInt(r.cairam)} />
      </div>
      <Card className="p-4">
        <IdebLinha pontos={(d.rede as any[]).map((x) => ({ ano: x.ano, a: x.ideb, meta: x.meta }))} rotuloA="Rede municipal de Maringá" />
      </Card>
      <Section title={`Escolas em ${d.ultimo_ano}`} subtitle="Uma linha por escola, do maior para o menor Ideb."
        action={<Link to="/mapa?q=ideb" className="inline-flex items-center gap-1.5 text-[13px] font-semibold text-purple-700"><MapIcon className="size-4" />Ver no mapa</Link>}>
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(220px,1.6fr) minmax(140px,1fr) 80px 90px 100px 110px 90px 90px" largura={1000} rotulo="Ideb por escola">
            <TCabecalho><TCelula fixa>Escola</TCelula><TCelula>Região</TCelula><TCelula>Ideb</TCelula><TCelula>{d.ultimo_ano - 2}</TCelula><TCelula>Variação</TCelula><TCelula>Aprovação</TCelula><TCelula>Mat.</TCelula><TCelula>Port.</TCelula></TCabecalho>
            {(d.escolas as any[]).map((e) => (
              <TLinha key={e.inep} to={e.unit_id ? `/unidades/${e.unit_id}?aba=ideb` : undefined} alerta={e.ideb != null && e.ideb < 6}>
                <TCelula fixa titulo={e.nome}>{e.nome}</TCelula><TCelula>{e.regiao ?? '—'}</TCelula>
                <TCelula livre>{e.ideb == null ? <Badge tone="gray">{e.obs ?? 'sem Ideb'}</Badge> : <b>{n1(e.ideb)}</b>}</TCelula>
                <TCelula>{n1(e.anterior)}</TCelula>
                <TCelula>{e.variacao == null ? '—' : `${e.variacao > 0 ? '+' : ''}${n1(e.variacao)}`}</TCelula>
                <TCelula>{e.aprovacao != null ? `${(e.aprovacao * 100).toFixed(1).replace('.', ',')}%` : '—'}</TCelula>
                <TCelula>{n1(e.nota_mat)}</TCelula><TCelula>{n1(e.nota_lp)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
      <p className="flex flex-wrap items-center gap-2 text-[12.5px] text-muted">
        <SourceChip kind="oficial" detail="INEP" /> {d.nota} <a href={d.fonte.url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 font-semibold text-purple-700">{d.fonte.rotulo}<ExternalLink className="size-3.5" /></a>
      </p>
    </div>
  );
}
