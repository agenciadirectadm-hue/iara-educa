import { lazy, Suspense, useMemo } from 'react';
import { useSearchParams } from 'react-router';
import { Bus, CalendarCheck, Contact, GraduationCap, NotebookPen, RefreshCw } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useGeoLayers, useUnitsMap } from '@/lib/data';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Card, Chip, ErrorState, PageHeader, Section, Segmented, Simulado, Skeleton, SkeletonList } from '@/components/ui';
import { HEAT_STOPS, cssGradient } from '@/components/map/mapStyle';
import type { Calor } from '@/components/map/MapView';

const MapView = lazy(() => import('@/components/map/MapView'));

type Tema = 'transporte' | 'frequencia' | 'alfabetizacao' | 'cadastros' | 'formacao';
const TEMAS: { value: Tema; label: string; icon: typeof Bus; camadas: { value: string; label: string; pergunta: string }[] }[] = [
  {
    value: 'transporte', label: 'Transporte', icon: Bus, camadas: [
      { value: 'transporte_necessidade', label: 'Onde mais precisa', pergunta: 'Onde moram as crianças longe da escola e sem transporte?' },
      { value: 'transporte_oferta', label: 'Onde mais tem', pergunta: 'Onde o transporte escolar já atende mais alunos?' },
      { value: 'transporte_efetividade', label: 'Onde é mais efetivo', pergunta: 'Onde as rotas levam quem está previsto, no horário?' },
      { value: 'transporte_veiculos', label: 'Veículos agora', pergunta: 'Onde estão os veículos neste momento?' },
    ],
  },
  {
    value: 'frequencia', label: 'Frequência e ocorrências', icon: CalendarCheck, camadas: [
      { value: 'frequencia', label: 'Presença por escola', pergunta: 'Quais escolas têm menor presença nos últimos 30 dias?' },
      { value: 'faltas', label: 'Faltas pela casa', pergunta: 'Em que partes da cidade as faltas se concentram?' },
      { value: 'ocorrencias', label: 'Ocorrências com alunos', pergunta: 'Onde há mais ocorrências com alunos nos últimos 90 dias?' },
    ],
  },
  {
    value: 'alfabetizacao', label: 'Alfabetização', icon: NotebookPen, camadas: [
      { value: 'alfa_esperado', label: 'Na idade esperada', pergunta: 'Quantas crianças estão no nível de escrita esperado para a idade?' },
      { value: 'alfa_precoce', label: 'Precoces', pergunta: 'Onde estão as crianças que se alfabetizaram antes do esperado?' },
      { value: 'alfa_abaixo', label: 'Com defasagem (handicap)', pergunta: 'Onde estão as crianças abaixo do esperado para a idade?' },
    ],
  },
  { value: 'cadastros', label: 'Cadastros atualizados', icon: Contact, camadas: [{ value: 'cadastros', label: 'Cadastros completos', pergunta: 'Quanto falta para 100% dos cadastros completos?' }] },
  { value: 'formacao', label: 'Formação dos professores', icon: GraduationCap, camadas: [{ value: 'formacao', label: 'Pós-graduação', pergunta: 'Onde os professores têm mais e menos pós-graduação?' }] },
];

const num = (v: unknown, sufixo = '') => (v == null ? '—' : `${typeof v === 'number' && !Number.isInteger(v) ? String(v).replace('.', ',') : fmtInt(Number(v))}${sufixo}`);

/** Mapas de calor da visão do prefeito: transporte, frequência e ocorrências, alfabetização na idade esperada, cadastros e formação dos professores. Só dados agregados. */
export default function MapasCalor() {
  const [sp, setSp] = useSearchParams();
  const camada = sp.get('camada') ?? 'transporte_necessidade';
  const tema = TEMAS.find((t) => t.camadas.some((c) => c.value === camada)) ?? TEMAS[0];
  const info = tema.camadas.find((c) => c.value === camada) ?? tema.camadas[0];
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const res = useRpc<any>('mapa_calor', { camada: info.value }, { refetchInterval: info.value === 'transporte_veiculos' ? 60_000 : false, staleTime: 60_000 });
  const d = res.data;
  const calor = useMemo<Calor | null>(() => (d ? { modo: d.modo, pontos: d.pontos ?? [], escala: d.escala ?? null, max: d.max ?? null } : null), [d]);
  const ir = (c: string) => setSp({ camada: c }, { replace: true });
  return (
    <div>
      <PageHeader eyebrow="Visão do Prefeito · cidade inteira"
        title={<span className="inline-flex items-center gap-2">Mapas de calor<Simulado detail="Camadas calculadas sobre os dados fictícios da demonstração." /></span>}
        subtitle="Onde está a necessidade, onde está o serviço e onde ele funciona. Só dados agregados: o que depende da casa da criança aparece em áreas de ~400 m, nunca por pessoa." />
      <div className="no-scrollbar -mx-4 flex gap-1.5 overflow-x-auto px-4 pb-1">
        {TEMAS.map((t) => <Chip key={t.value} icon={t.icon} active={t.value === tema.value} onClick={() => ir(t.camadas[0].value)}>{t.label}</Chip>)}
      </div>
      {tema.camadas.length > 1 && (
        <Segmented className="mt-2 max-w-full overflow-x-auto" value={info.value} onChange={ir} items={tema.camadas.map((c) => ({ value: c.value, label: c.label }))} />
      )}
      <div className="mt-3 grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_340px]">
        <Card className="relative overflow-hidden">
          <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-2.5">
            <h2 className="flex-1 font-display text-[16px] font-bold">{info.pergunta}</h2>
            {res.isFetching && <RefreshCw className="size-4 animate-spin text-subtle" aria-label="Atualizando" />}
          </div>
          <Suspense fallback={<Skeleton className="h-[62vh] min-h-[380px]" />}>
            <MapView className="h-[62vh] min-h-[380px]" units={units.data?.units ?? []} showUnits={false} geo={geo.data} calor={calor}
              fitKey="cidade" cooperative legend={false} padding={{ top: 40, bottom: 30, left: 24, right: 64 }} />
          </Suspense>
          {d && <Legenda d={d} />}
        </Card>
        <div className="space-y-3">
          {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
            <>
              <div className="grid grid-cols-2 gap-2">
                {(d.resumo as any[]).map((k) => (
                  <Card key={k.rotulo} className="p-3">
                    <div className="font-display text-[22px] font-extrabold leading-none">{num(k.valor, k.sufixo ?? '')}</div>
                    <div className="mt-1 text-[12px] leading-tight text-muted">{k.rotulo}</div>
                  </Card>
                ))}
              </div>
              {(d.ranking?.itens ?? []).length > 0 && (
                <Section title={d.ranking.titulo} className="mt-1">
                  <Card className="divide-y divide-line">
                    {(d.ranking.itens as any[]).map((x, i) => (
                      <div key={i} className="flex items-center gap-2 px-3 py-2 text-[13px]">
                        <span className="w-5 shrink-0 text-right font-bold text-subtle">{i + 1}</span>
                        <span className="min-w-0 flex-1 truncate" title={`${x.nome} · ${x.detalhe ?? ''}`}><b>{x.nome}</b> <span className="text-muted">· {x.detalhe}</span></span>
                        <span className="shrink-0 font-semibold">{num(x.valor, x.sufixo ?? '')}</span>
                      </div>
                    ))}
                  </Card>
                </Section>
              )}
              {d.faixas && (
                <Section title="Esperado para a idade" className="mt-1">
                  <Card className="p-3 text-[12.5px]"><ul className="list-disc space-y-0.5 pl-4">{(d.faixas as string[]).map((f) => <li key={f}>{f}</li>)}</ul></Card>
                </Section>
              )}
              {d.niveis && (
                <Section title="Escolaridade dos professores" className="mt-1">
                  <Card className="divide-y divide-line text-[13px]">{(d.niveis as any[]).map((n) => <div key={n.rotulo} className="flex justify-between px-3 py-1.5"><span>{n.rotulo}</span><b>{fmtInt(n.n)}</b></div>)}</Card>
                </Section>
              )}
              {d.pendencias && (
                <Section title="O que mais falta nos cadastros" className="mt-1">
                  <Card className="divide-y divide-line text-[13px]">{(d.pendencias as any[]).map((n) => <div key={n.item} className="flex justify-between px-3 py-1.5"><span>{n.item}</span><b>{fmtInt(n.n)}</b></div>)}</Card>
                </Section>
              )}
              <p className="text-[12px] leading-relaxed text-muted">{d.nota} Atualizado em {fmtDateTime(d.atualizado_em)}.</p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function Legenda({ d }: { d: any }) {
  const sufixo = d.sufixo ?? '';
  if (d.legenda) {
    return (
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-line px-4 py-2 text-[12px]">
        <span className="font-semibold text-subtle">Mancha = concentração de veículos</span>
        {(d.legenda as [string, string][]).map(([cor, rot]) => <span key={rot} className="inline-flex items-center gap-1.5"><span className="size-2.5 rounded-full" style={{ background: cor }} />{rot}</span>)}
      </div>
    );
  }
  if (d.modo === 'taxa' && d.escala) {
    const esc = d.escala as [number, string][];
    return (
      <div className="border-t border-line px-4 py-2 text-[12px]">
        <div className="h-2.5 rounded-full" style={{ background: cssGradient(esc) }} aria-hidden />
        <div className="mt-1 flex justify-between text-muted">
          {esc.map(([v], i) => <span key={v}>{i === 0 ? 'até ' : ''}{String(v).replace('.', ',')}{sufixo.trim()}</span>)}
        </div>
      </div>
    );
  }
  return (
    <div className="border-t border-line px-4 py-2 text-[12px]">
      <div className="h-2.5 rounded-full" style={{ background: cssGradient(HEAT_STOPS) }} aria-hidden />
      <div className="mt-1 flex justify-between text-muted"><span>menos{sufixo}</span><span>mais{d.max ? ` (${num(Math.round(Number(d.max)))}${sufixo} ou mais)` : ''}</span></div>
    </div>
  );
}
