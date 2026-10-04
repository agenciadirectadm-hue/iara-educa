import { useMemo } from 'react';
import { Link, useNavigate, useParams } from 'react-router';
import clsx from 'clsx';
import { Building2, ListOrdered, MapPinned, School, Sparkles, Users } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useGeoLayers, useUnitsMap } from '@/lib/data';
import { fmt1, fmtInt, fmtPct } from '@/lib/format';
import { Badge, Card, ErrorState, Kpi, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { GroupedBars } from '@/components/charts';
import { Crumbs } from '@/components/Crumbs';
import MapView from '@/components/map/MapView';

export default function TerritoryPage() {
  const { id } = useParams();
  const tid = Number(id);
  const res = useRpc<any>('territory_detail', { id: tid });
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const navigate = useNavigate();

  const regionOnly = useMemo(() => {
    if (!geo.data?.regions) return null;
    return { ...geo.data, regions: { ...geo.data.regions, features: geo.data.regions.features.filter((f: any) => f.properties?.id === tid) } };
  }, [geo.data, tid]);

  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error || !res.data) return <ErrorState error={res.error ?? { message: 'Território não encontrado' }} onRetry={() => res.refetch()} />;
  const d = res.data;
  const t = d.territory;
  const k = d.kpis;
  const inRegion = (units.data?.units ?? []).filter((u) => u.macro_id === tid);
  const creche = (d.by_grade as any[]).find((g) => g.grade_level_id === 1);
  const deficit = creche ? creche.offerable - creche.queue : 0;

  return (
    <div>
      <Crumbs items={[{ label: 'Cidade', to: '/mapa?camada=deficit' }, { label: t.name }]} />
      <PageHeader eyebrow={t.kind === 'DISTRITO' ? 'Distrito' : 'Macrorregião'} title={t.name} subtitle={`${fmt1(t.area_km2)} km² · ${d.units.length} unidades · ${d.neighborhoods.length} bairros/regiões na base`} />
      <div className="mb-3 flex flex-wrap items-center gap-2 text-[12.5px] text-muted">
        <SourceChip kind="demo" detail={t.source} /> Território de demonstração (cálculo por distância/rumo ao centro). O território escolar oficial deve ser definido pela SEDUC.
      </div>

      <Card className="overflow-hidden">
        <MapView
          className="h-72 lg:h-96"
          units={inRegion}
          geo={regionOnly}
          regionMetric="balance_creche"
          heat="queue_creche"
          onSelectUnit={(u) => navigate(`/unidades/${u.id}`)}
          fitKey={tid}
          cooperative
        />
      </Card>

      <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Building2} tone="blue" label="Unidades" value={fmtInt(k.official.units)} sub={`${k.official.cmeis} CMEIs · ${k.official.schools} escolas`} source="oficial" />
        <Kpi compact icon={Users} tone="teal" label="Matrículas" value={fmtInt(k.official.enrollments)} source="oficial" />
        <Kpi compact icon={Sparkles} tone="green" label="Vagas ofertáveis" value={fmtInt(k.operational.offerable)} sub={`ocupação ${fmtPct(k.operational.occupancy)}`} source="demo" />
        <Kpi compact icon={ListOrdered} tone={deficit < 0 ? 'red' : 'blue'} label="Saldo de creche" value={`${deficit > 0 ? '+' : ''}${fmtInt(deficit)}`} sub={`${fmtInt(creche?.queue ?? 0)} na fila · ${fmtInt(creche?.offerable ?? 0)} vagas`} source="demo" />
      </div>

      <Section title="Demanda × oferta por série" action={<SourceChip kind="demo" />}>
        <Card className="p-4">
          <GroupedBars
            data={(d.by_grade as any[]).filter((g) => g.capacity > 0 || g.queue > 0).map((g) => ({ key: String(g.grade_level_id), label: g.grade, queue: g.queue, offerable: g.offerable }))}
            series={[{ key: 'queue', label: 'Fila', color: '#D94C4C' }, { key: 'offerable', label: 'Vagas ofertáveis', color: '#16A36A' }]}
          />
        </Card>
      </Section>

      <Section title="Unidades do território" subtitle="Ordenadas pela fila">
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
      </Section>

      <Section title="Bairros e regiões na base" subtitle="Nomes conforme os endereços públicos das unidades">
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
