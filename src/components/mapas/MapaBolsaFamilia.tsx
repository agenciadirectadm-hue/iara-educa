import { useMemo, useState } from 'react';
import { Link } from 'react-router';
import { ChevronRight, School, X } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useGeoLayers, useUnitsMap } from '@/lib/data';
import { fmtInt } from '@/lib/format';
import { Segmented, SkeletonList } from '@/components/ui';
import MapView, { type Coropleta } from '@/components/map/MapView';
import { SEMAFORO, classe, corDe, cortes, legenda } from '@/components/map/semaforo';
import { caixaDe, type Caixa } from '@/components/map/geometria';

export type ItemMapa = { id: number; sigilo?: boolean; acompanhados?: number; abaixo?: number | null; abaixo_2?: number | null; assiduos?: number; taxa?: number };
type Medida = 'deixaram' | 'assiduos';
type Detalhe = {
  unidade: { id: number; nome: string; tipo: string; regiao?: string | null }; sigilo?: boolean; nota?: string;
  alunos?: number; acompanhados?: number; assiduos?: number; deixaram_de_receber?: number | null; abaixo_2?: number | null;
  periodos?: { periodo: number; acompanhados: number; abaixo: number | null }[]; motivos_periodo?: number | null;
  motivos?: { categoria: string; texto: string; alunos: number | null }[];
};

const CURTO = ['', 'Fev–mar', 'Abr–mai', 'Jun–jul', 'Ago–set', 'Out–nov'];
const MEDIDA: Record<Medida, { titulo: string; pior: 'maior' | 'menor'; palavras: { pior: string; melhor: string } }> = {
  deixaram: { titulo: 'deixaram de receber (% dos acompanhados)', pior: 'maior', palavras: { pior: 'Mais deixaram de receber', melhor: 'Menos deixaram de receber' } },
  assiduos: { titulo: 'têm recebido assiduamente (% dos acompanhados)', pior: 'menor', palavras: { pior: 'Menos assíduos', melhor: 'Mais assíduos' } },
};
const num = (v: number | null | undefined) => (v == null ? 'menos de 3' : fmtInt(v));
const valorDe = (i: ItemMapa | undefined, m: Medida) => (!i || i.sigilo || i.taxa == null ? null : m === 'deixaram' ? i.taxa : Math.round((100 - i.taxa) * 10) / 10);

/** Mapa do Bolsa Família na escola: regiões e unidades no semáforo (deixaram de receber ou assiduidade). Tocar numa região
 * abre os números dela e das unidades que ficam ali; tocar numa unidade abre cada período e os motivos sugeridos. */
export function MapaBolsaFamilia({ regioes, unidades }: { regioes: ItemMapa[]; unidades: ItemMapa[] }) {
  const geo = useGeoLayers();
  const units = useUnitsMap();
  const [medida, setMedida] = useState<Medida>('deixaram');
  const [aberta, setAberta] = useState<{ tipo: 'regiao' | 'unidade'; id: number } | null>(null);
  const porRegiao = useMemo(() => new Map(regioes.map((r) => [r.id, r])), [regioes]);
  const porUnidade = useMemo(() => new Map(unidades.map((u) => [u.id, u])), [unidades]);
  const m = MEDIDA[medida];

  const coropleta = useMemo<Coropleta | null>(() => {
    const base = geo.data?.regions;
    if (!base) return null;
    const c = cortes(base.features.map((f) => valorDe(porRegiao.get(Number(f.properties?.id)), medida)), m.pior);
    const feicoes = base.features.map((f) => {
      const id = Number(f.properties?.id);
      const it = porRegiao.get(id);
      const v = valorDe(it, medida);
      const txt = v == null ? (it?.sigilo ? 'sigilo (menos de 3 alunos)' : 'sem alunos do Bolsa Família') : `${v.toLocaleString('pt-BR')}% (${fmtInt(it!.acompanhados)} acompanhados)`;
      return { type: 'Feature' as const, geometry: f.geometry, properties: { chave: String(id), valor: v, cor: corDe(classe(v, c)), sel: aberta?.tipo === 'regiao' && aberta.id === id, titulo: `${f.properties?.name}: ${txt}` } };
    });
    return { tipo: 'area', feicoes: { type: 'FeatureCollection', features: feicoes },
      faixas: { titulo: `Regiões · ${m.titulo}`, itens: legenda(c, m.palavras, '%', 'Sigilo ou sem alunos do Bolsa Família') } };
  }, [geo.data, porRegiao, medida, m, aberta]);

  const { corUnidade, faixas } = useMemo(() => {
    const lista = units.data?.units ?? [];
    const c = cortes(lista.map((u) => valorDe(porUnidade.get(u.id), medida)), m.pior);
    const cores: Record<number, string> = {};
    for (const u of lista) cores[u.id] = porUnidade.get(u.id)?.taxa != null ? corDe(classe(valorDe(porUnidade.get(u.id), medida), c)) : SEMAFORO.cinza;
    return { corUnidade: cores, faixas: [{ titulo: `Unidades · ${m.titulo}`, itens: legenda(c, m.palavras, '%', 'Sigilo ou sem alunos do Bolsa Família') }] };
  }, [units.data, porUnidade, medida, m]);

  const regiaoAberta = aberta?.tipo === 'regiao' ? geo.data?.regions?.features.find((f) => Number(f.properties?.id) === aberta.id) : null;
  const unidadeAberta = aberta?.tipo === 'unidade' ? units.data?.units.find((u) => u.id === aberta.id) : null;
  const caixaCidade = useMemo<Caixa | null>(() => {
    const l = units.data?.units ?? [];
    return l.length ? [[Math.min(...l.map((u) => u.lng)), Math.min(...l.map((u) => u.lat))], [Math.max(...l.map((u) => u.lng)), Math.max(...l.map((u) => u.lat))]] : null;
  }, [units.data]);
  const caixaRegiao = regiaoAberta ? caixaDe(regiaoAberta.geometry) : null;
  const enquadrar = caixaRegiao ? { chave: `r-${aberta!.id}`, caixa: caixaRegiao }
    : unidadeAberta ? { chave: `u-${unidadeAberta.id}`, caixa: [[unidadeAberta.lng - 0.012, unidadeAberta.lat - 0.008], [unidadeAberta.lng + 0.012, unidadeAberta.lat + 0.008]] as Caixa }
      : caixaCidade ? { chave: 'cidade', caixa: caixaCidade } : null;
  const largo = typeof window !== 'undefined' && window.innerWidth >= 640;

  if (geo.isLoading || units.isLoading) return <SkeletonList rows={4} />;
  return (
    <div className="relative overflow-hidden rounded-3xl ring-1 ring-line">
      <MapView
        className="h-[58vh] min-h-[380px] lg:h-[520px]"
        units={units.data?.units ?? []}
        geo={geo.data}
        coropleta={coropleta}
        onSelectCoropleta={(chave) => setAberta({ tipo: 'regiao', id: Number(chave) })}
        colorMode="classe"
        corUnidade={corUnidade}
        faixas={faixas}
        onSelectUnit={(u) => setAberta({ tipo: 'unidade', id: u.id })}
        enquadrar={enquadrar}
        fitKey="bolsa-familia"
        cooperative
        padding={aberta ? (largo ? { top: 64, bottom: 30, left: 380, right: 48 } : { top: 64, bottom: 360, left: 24, right: 48 }) : { top: 64, bottom: 30, left: 24, right: 48 }}
        legendNote="Toque numa região ou numa unidade para ver o detalhe"
      />
      <div className="pointer-events-none absolute inset-x-0 top-0 p-3">
        <Segmented className="pointer-events-auto whitespace-nowrap shadow-soft" value={medida} onChange={(v) => setMedida(v as Medida)}
          items={[{ value: 'deixaram', label: 'Deixaram de receber' }, { value: 'assiduos', label: 'Assiduidade' }]} />
      </div>
      {regiaoAberta && (
        <Cartao titulo={String(regiaoAberta.properties?.name)} rotulo="Região do IBGE" onFechar={() => setAberta(null)}>
          <Numeros item={porRegiao.get(aberta!.id)} />
          <div className="mt-3 max-h-44 divide-y divide-line overflow-y-auto rounded-2xl ring-1 ring-line">
            {(units.data?.units ?? []).filter((u) => u.macro_id === aberta!.id)
              .map((u) => ({ u, it: porUnidade.get(u.id) }))
              .sort((a, b) => (b.it?.taxa ?? -1) - (a.it?.taxa ?? -1))
              .map(({ u, it }) => (
                <button key={u.id} type="button" onClick={() => setAberta({ tipo: 'unidade', id: u.id })} className="flex w-full items-center gap-2 px-3 py-2 text-left text-[13px] hover:bg-purple-50">
                  <span className="size-2.5 shrink-0 rounded-full" style={{ background: corUnidade[u.id] }} aria-hidden />
                  <span className="min-w-0 flex-1 truncate font-semibold">{u.name}</span>
                  <span className="shrink-0 text-[12px] tabular text-muted">{it?.taxa == null ? 'sigilo' : `${num(it.abaixo)} de ${fmtInt(it.acompanhados)}`}</span>
                </button>
              ))}
          </div>
          <p className="mt-2 text-[11.5px] text-muted">Por unidade: quantos deixaram de receber, dos acompanhados. Toque para abrir.</p>
        </Cartao>
      )}
      {unidadeAberta && <CartaoUnidade id={unidadeAberta.id} nome={unidadeAberta.name} item={porUnidade.get(unidadeAberta.id)} onFechar={() => setAberta(null)}
        onVoltar={unidadeAberta.macro_id ? () => setAberta({ tipo: 'regiao', id: unidadeAberta.macro_id }) : undefined} />}
    </div>
  );
}

function Cartao({ rotulo, titulo, onFechar, children }: { rotulo: string; titulo: string; onFechar: () => void; children: React.ReactNode }) {
  return (
    <div className="absolute inset-x-3 bottom-3 z-20 sm:inset-x-auto sm:bottom-auto sm:left-3 sm:top-[68px] sm:w-[350px]">
      <div className="max-h-[70vh] overflow-y-auto rounded-3xl bg-white/95 p-4 shadow-lift ring-1 ring-line backdrop-blur">
        <div className="flex items-start gap-2">
          <div className="min-w-0 flex-1">
            <div className="text-[11.5px] font-bold uppercase tracking-wide text-purple-700">{rotulo}</div>
            <div className="font-display text-[17px] font-extrabold leading-snug">{titulo}</div>
          </div>
          <button type="button" onClick={onFechar} className="inline-flex size-9 shrink-0 items-center justify-center rounded-xl bg-slate-100" aria-label="Fechar"><X className="size-4" /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

function Numeros({ item }: { item?: ItemMapa }) {
  if (!item || item.sigilo || item.acompanhados == null) return <p className="mt-3 text-[13px] text-muted">Menos de 3 alunos do Bolsa Família acompanhados aqui: os números ficam em sigilo.</p>;
  return (
    <div className="mt-3 grid grid-cols-3 gap-2 text-center">
      <div className="rounded-2xl bg-slate-50 p-2 ring-1 ring-line"><div className="font-display text-xl font-extrabold tabular">{fmtInt(item.acompanhados)}</div><div className="text-[11px] leading-tight text-muted">acompanhados</div></div>
      <div className="rounded-2xl bg-red-50 p-2 ring-1 ring-red-100"><div className="font-display text-xl font-extrabold tabular text-red-700">{num(item.abaixo)}</div><div className="text-[11px] leading-tight text-muted">deixaram de receber{item.taxa != null ? ` (${item.taxa.toLocaleString('pt-BR')}%)` : ''}</div></div>
      <div className="rounded-2xl bg-green-50 p-2 ring-1 ring-green-100"><div className="font-display text-xl font-extrabold tabular text-green-700">{fmtInt(item.assiduos)}</div><div className="text-[11px] leading-tight text-muted">assíduos</div></div>
    </div>
  );
}

function CartaoUnidade({ id, nome, item, onFechar, onVoltar }: { id: number; nome: string; item?: ItemMapa; onFechar: () => void; onVoltar?: () => void }) {
  const d = useRpc<Detalhe>('bolsa_familia_unidade', { unit_id: id });
  const det = d.data;
  return (
    <Cartao rotulo="Unidade" titulo={nome} onFechar={onFechar}>
      {det?.unidade.regiao && <div className="text-[12.5px] text-muted">{det.unidade.tipo === 'CMEI' ? 'CMEI' : 'Escola'} · {det.unidade.regiao}</div>}
      <Numeros item={item} />
      {d.isLoading ? <SkeletonList rows={2} /> : det && !det.sigilo && (
        <>
          <div className="mt-3 text-[12px] font-bold uppercase tracking-wide text-subtle">Abaixo do mínimo por período</div>
          <div className="mt-1 grid grid-cols-5 gap-1 text-center">
            {(det.periodos ?? []).map((p) => (
              <div key={p.periodo} className="rounded-xl bg-slate-50 px-1 py-1.5 ring-1 ring-line">
                <div className="text-[10.5px] text-muted">{CURTO[p.periodo]}</div>
                <div className="text-[14px] font-extrabold tabular text-red-700">{p.abaixo == null ? '<3' : fmtInt(p.abaixo)}</div>
                <div className="text-[10px] text-muted">de {fmtInt(p.acompanhados)}</div>
              </div>
            ))}
          </div>
          {det.motivos_periodo && (
            <>
              <div className="mt-3 text-[12px] font-bold uppercase tracking-wide text-subtle">Motivos sugeridos · {CURTO[det.motivos_periodo]}</div>
              {(det.motivos ?? []).length === 0 ? <p className="mt-1 text-[13px] text-muted">Ninguém abaixo do mínimo neste período.</p> : (
                <ul className="mt-1 space-y-1">
                  {det.motivos!.map((mo) => (
                    <li key={mo.categoria} className="flex items-center justify-between gap-2 text-[13px]">
                      <span className="min-w-0 truncate">{mo.texto}</span><span className="shrink-0 font-semibold tabular">{num(mo.alunos)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}
        </>
      )}
      <div className="mt-3 flex gap-2">
        {onVoltar && <button type="button" onClick={onVoltar} className="inline-flex h-10 flex-1 items-center justify-center rounded-xl bg-white text-[13px] font-semibold ring-1 ring-line hover:bg-slate-50">Ver a região</button>}
        <Link to={`/unidades/${id}`} className="inline-flex h-10 flex-1 items-center justify-center gap-1 rounded-xl bg-purple-700 text-[13px] font-semibold text-white hover:bg-purple-800">
          <School className="size-4" />Abrir unidade<ChevronRight className="size-4" />
        </Link>
      </div>
    </Cartao>
  );
}
