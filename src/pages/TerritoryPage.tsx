import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';
import clsx from 'clsx';
import { Baby, Building2, Flame, ListOrdered, MapPinned, School, Sparkles, Users } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useGeoLayers, useGeoSetores, useUnitsMap } from '@/lib/data';
import { fmt1, fmtInt, fmtPct } from '@/lib/format';
import { Badge, Card, Chip, ErrorState, Kpi, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { GroupedBars } from '@/components/charts';
import { Crumbs } from '@/components/Crumbs';
import MapView, { type GeoLayers } from '@/components/map/MapView';

const EYEBROW: Record<string, string> = { AREA_PONDERACAO: 'Área de ponderação · IBGE', DISTRITO: 'Distrito' };

export default function TerritoryPage() {
  const { id } = useParams();
  const tid = Number(id);
  const res = useRpc<any>('territory_detail', { id: tid });
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const navigate = useNavigate();
  const [camada, setCamada] = useState<'saldo' | 'criancas'>('saldo');
  const kind: string | undefined = res.data?.territory?.kind;
  const setores = useGeoSetores(camada === 'criancas' && kind === 'AREA_PONDERACAO', tid);

  // só a área (ou o distrito) no mapa; o distrito ganha os números do Censo para colorir pelo total de crianças
  const regionOnly = useMemo<GeoLayers | null>(() => {
    if (!geo.data) return null;
    const d = res.data;
    const regiao = geo.data.regions?.features.find((f) => f.properties?.id === tid);
    const distrito = geo.data.districts?.features.find((f) => f.properties?.id === tid);
    const feature = regiao ?? (distrito && d
      ? { ...distrito, properties: { ...distrito.properties, label: d.territory.name, lat: d.territory.lat, lng: d.territory.lng, criancas_0a4: d.censo?.criancas_0a4 ?? 0 } }
      : null);
    return {
      ...geo.data,
      regions: { type: 'FeatureCollection', features: feature ? [feature] : [] },
      districts: { type: 'FeatureCollection', features: (geo.data.districts?.features ?? []).filter((f) => f.properties?.parent_id === tid) },
    };
  }, [geo.data, tid, res.data]);

  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error || !res.data) return <ErrorState error={res.error ?? { message: 'Território não encontrado' }} onRetry={() => res.refetch()} />;
  const d = res.data;
  const t = d.territory;
  const k = d.kpis;
  const c = d.censo;
  const ids = new Set((d.units as any[]).map((u) => u.id));
  const inRegion = (units.data?.units ?? []).filter((u) => ids.has(u.id));
  const creche = (d.by_grade as any[]).find((g) => g.grade_level_id === 1);
  const deficit = creche ? creche.offerable - creche.queue : 0;
  const distrito = t.kind === 'DISTRITO';
  const verSetores = camada === 'criancas' && !distrito;

  return (
    <div>
      <Crumbs items={[{ label: 'Cidade', to: '/mapa?camada=deficit' }, ...(t.parent ? [{ label: t.parent.name, to: `/territorios/${t.parent.id}` }] : []), { label: t.name }]} />
      <PageHeader eyebrow={EYEBROW[t.kind] ?? 'Território'} title={t.name}
        subtitle={`${fmt1(t.area_km2)} km² · ${d.units.length} unidades · ${fmtInt(c.pessoas)} moradores · ${d.neighborhoods.length} bairros na base`} />
      <div className="mb-3 flex flex-wrap items-center gap-2 text-[12.5px] text-muted">
        <SourceChip kind="oficial" detail={t.source} />
        {distrito
          ? 'Limite oficial do distrito (IBGE, Censo 2022). Unidades, fila e vagas contam as unidades dentro do distrito.'
          : 'Recorte oficial do IBGE (Censo Demográfico 2022). Unidades, fila e vagas são somadas por área de ponderação.'}
      </div>

      <Card className="relative overflow-hidden">
        <MapView
          className="h-72 lg:h-96"
          units={inRegion}
          geo={regionOnly}
          regionMetric={distrito ? 'criancas_0a4' : camada === 'saldo' ? 'balance_creche' : null}
          setores={verSetores ? setores.data ?? null : null}
          heat={camada === 'saldo' && !distrito ? 'queue_creche' : null}
          onSelectUnit={(u) => navigate(`/unidades/${u.id}`)}
          fitKey={`${tid}-${inRegion.length}`}
          cooperative
        />
        {!distrito && (
          <div className="pointer-events-none absolute inset-x-0 top-0 flex gap-2 p-3">
            <div className="pointer-events-auto no-scrollbar flex gap-2 overflow-x-auto">
              <Chip icon={Flame} active={camada === 'saldo'} onClick={() => setCamada('saldo')}>Saldo de creche</Chip>
              <Chip icon={Baby} active={camada === 'criancas'} onClick={() => setCamada('criancas')}>Crianças 0–4 por setor</Chip>
            </div>
          </div>
        )}
      </Card>

      <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Building2} tone="blue" label="Unidades" value={fmtInt(k.official.units)} sub={`${k.official.cmeis} CMEIs · ${k.official.schools} escolas`} source="oficial" />
        <Kpi compact icon={Users} tone="teal" label="Matrículas" value={fmtInt(k.official.enrollments)} source="oficial" />
        <Kpi compact icon={Sparkles} tone="green" label="Vagas ofertáveis" value={fmtInt(k.operational.offerable)} sub={`ocupação ${fmtPct(k.operational.occupancy)}`} source="demo" />
        <Kpi compact icon={ListOrdered} tone={deficit < 0 ? 'red' : 'blue'} label="Saldo de creche" value={`${deficit > 0 ? '+' : ''}${fmtInt(deficit)}`} sub={`${fmtInt(creche?.queue ?? 0)} na fila · ${fmtInt(creche?.offerable ?? 0)} vagas`} source="demo" />
      </div>

      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Kpi compact icon={Users} tone="purple" label="Moradores (Censo 2022)" value={fmtInt(c.pessoas)} sub={`${fmtInt(c.domicilios)} domicílios`} source="oficial" />
        <Kpi compact icon={Baby} tone="amber" label="Crianças de 0 a 4 anos" value={fmtInt(c.criancas_0a4)}
          sub={c.setores_sigilo ? `${c.setores_sigilo} setor(es) em sigilo do IBGE` : 'Censo 2022'} source="oficial" />
        <Kpi compact icon={MapPinned} tone="blue" label="Setores censitários" value={fmtInt(c.setores)} sub={c.setores_rurais ? `${c.setores_rurais} rurais` : 'todos urbanos'} source="oficial" />
      </div>
      {c.pessoas === 0 && (
        <p className="mt-2 text-[12.5px] text-muted">Área sem moradores no Censo 2022 — entra no mapa para completar o território, sem demanda residente.</p>
      )}

      <Section title="Demanda × oferta por série" subtitle={c.criancas_0a4 ? `No Censo 2022, ${fmtInt(c.criancas_0a4)} crianças de 0 a 4 anos moravam ${distrito ? 'no distrito' : 'nesta área'}.` : undefined} action={<SourceChip kind="demo" />}>
        <Card className="p-4">
          <GroupedBars
            data={(d.by_grade as any[]).filter((g) => g.capacity > 0 || g.queue > 0).map((g) => ({ key: String(g.grade_level_id), label: g.grade, queue: g.queue, offerable: g.offerable }))}
            series={[{ key: 'queue', label: 'Fila', color: '#D94C4C' }, { key: 'offerable', label: 'Vagas ofertáveis', color: '#16A36A' }]}
          />
        </Card>
      </Section>

      {(d.districts as any[]).length > 0 && (
        <Section title="Distritos nesta área" subtitle="Limite oficial do IBGE (união dos setores censitários do distrito)">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {(d.districts as any[]).map((x) => (
              <Link key={x.id} to={`/territorios/${x.id}`} className="rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
                <div className="flex items-center gap-2 font-semibold"><MapPinned className="size-5 text-amber-700" />{x.name}</div>
                <div className="mt-1 text-[12.5px] text-muted">
                  {x.units} unidades · {fmtInt(x.censo.pessoas)} moradores · {fmtInt(x.censo.criancas_0a4)} crianças de 0 a 4 anos
                </div>
              </Link>
            ))}
          </div>
        </Section>
      )}

      <Section title={distrito ? 'Unidades do distrito' : 'Unidades da área'} subtitle="Ordenadas pela fila">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {[...(d.units as any[])].sort((a, b) => b.ops.queue - a.ops.queue).map((u) => (
            <Link key={u.id} to={`/unidades/${u.id}`} className="rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
              <div className="flex items-center gap-2">
                <School className={clsx('size-5', u.type === 'CMEI' ? 'text-purple-600' : 'text-blue-600')} />
                <div className="min-w-0 flex-1 truncate font-semibold">{u.name}</div>
              </div>
              <div className="mt-0.5 truncate text-[12.5px] text-muted">{u.neighborhood}</div>
              <div className="mt-2 flex flex-wrap gap-1.5">
                <Badge tone={u.ops.offerable > 0 ? 'green' : 'gray'}>{u.ops.offerable} vagas</Badge>
                <Badge tone={u.ops.queue > 10 ? 'red' : 'gray'}>{u.ops.queue} fila</Badge>
                <Badge tone="blue">{fmtPct(u.ops.occupancy)}</Badge>
              </div>
            </Link>
          ))}
        </div>
        {d.units.length === 0 && <p className="text-sm text-muted">Nenhuma unidade da rede municipal nesta área.</p>}
      </Section>

      <Section title="Bairros na base" subtitle="Nomes conforme os endereços públicos das unidades">
        <div className="flex flex-wrap gap-2">
          {(d.neighborhoods as any[]).map((b) => (
            <Link key={b.id} to={`/mapa?q=${encodeURIComponent(b.name)}`} className="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-[13px] font-semibold ring-1 ring-line hover:bg-purple-50">
              <MapPinned className="size-3.5 text-purple-700" />{b.name} <span className="text-muted">({b.units})</span>
            </Link>
          ))}
        </div>
      </Section>
    </div>
  );
}
