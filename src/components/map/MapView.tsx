import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { LngLatBounds, Map as MLMap, Marker, setWorkerUrl, type GeoJSONSource, type MapLayerMouseEvent } from 'maplibre-gl';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
import 'maplibre-gl/dist/maplibre-gl.css';
import clsx from 'clsx';
import { Crosshair, Minus, Plus } from 'lucide-react';
import type { UnitMapItem } from '@/lib/types';
import { MapLegend } from './MapLegend';
import {
  BALANCE_STOPS, HEAT_OFFERABLE_STOPS, HEAT_STOPS, OFFERABLE_REGION_STOPS, PURPLE, QUEUE_REGION_STOPS, REGION_OPACITY, ROTA_COLOR, ROUTE_LINE,
  SELECTED_STROKE, UNIT_COLOR, VACANCY_COLOR, interpolate,
} from './mapStyle';

setWorkerUrl(workerUrl);

const STYLE = 'https://tiles.openfreemap.org/styles/positron';
const CENTER: [number, number] = [-51.9386, -23.4253];

export type HeatMode = 'queue' | 'queue_creche' | 'enrollments' | 'offerable' | null;
export type ColorMode = 'type' | 'vacancy';
export type RegionMetric = 'balance_creche' | 'balance' | 'queue' | 'offerable' | null;

export type GeoLayers = {
  municipality?: GeoJSON.Feature;
  regions?: GeoJSON.FeatureCollection;
  areas?: GeoJSON.FeatureCollection;
};

export type MapViewProps = {
  units: UnitMapItem[];
  geo?: GeoLayers | null;
  selectedId?: number | null;
  onSelectUnit?: (u: UnitMapItem) => void;
  onSelectRegion?: (id: number) => void;
  onMapClick?: (lat: number, lng: number) => void;
  showUnits?: boolean;
  colorMode?: ColorMode;
  heat?: HeatMode;
  regionMetric?: RegionMetric;
  showAreas?: boolean;
  home?: { lat: number; lng: number; radius_m?: number } | null;
  highlight?: { id: number; label: string }[];
  lines?: boolean;
  fitKey?: string | number;
  focus?: { lat: number; lng: number; zoom?: number } | null;
  cooperative?: boolean;
  className?: string;
  controls?: boolean;
  padding?: { top: number; bottom: number; left: number; right: number };
  /** Legenda das camadas e marcações: faixa abaixo do mapa (padrão), cartão sobre o mapa ou nenhuma. */
  legend?: 'strip' | 'overlay' | false;
  /** Posição do cartão da legenda (modo overlay). */
  legendClassName?: string;
  /** Texto extra no fim da legenda (ex.: "toque numa região"). */
  legendNote?: ReactNode;
  /** Rótulos das marcações na legenda, conforme o contexto da tela. */
  homeLabel?: string;
  highlightLabel?: string;
  selectedLabel?: string;
  /** Rotas calculadas pelas ruas ([lng, lat]), da residência até cada unidade: a pé (tracejada) e de carro (contínua). */
  trajetos?: { id: number; modo: 'A_PE' | 'CARRO'; coords: [number, number][] }[] | null;
};

function circle(lat: number, lng: number, r: number, n = 72): GeoJSON.Feature<GeoJSON.Polygon> {
  const coords: [number, number][] = [];
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * Math.PI * 2;
    coords.push([lng + (r * Math.sin(a)) / (111320 * Math.cos((lat * Math.PI) / 180)), lat + (r * Math.cos(a)) / 110540]);
  }
  return { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [coords] } };
}

function maskOutside(f?: GeoJSON.Feature): GeoJSON.Feature | null {
  if (!f?.geometry) return null;
  const g = f.geometry as GeoJSON.Polygon | GeoJSON.MultiPolygon;
  const rings = g.type === 'Polygon' ? [g.coordinates[0]] : g.coordinates.map((poly) => poly[0]);
  return { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [[[-180, -85], [180, -85], [180, 85], [-180, 85], [-180, -85]], ...rings] } };
}

const empty: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features: [] };

type Pad = { top: number; bottom: number; left: number; right: number };
/** Padding compatível com o tamanho atual do mapa (evita câmera NaN em telas baixas ou mapa oculto). */
function safePadding(map: MLMap, pad: Pad | number): Pad | null {
  const c = map.getContainer();
  const w = c.clientWidth;
  const h = c.clientHeight;
  if (w < 60 || h < 60) return null;
  const p = typeof pad === 'number' ? { top: pad, bottom: pad, left: pad, right: pad } : { ...pad };
  const maxV = h * 0.62;
  const maxH = w * 0.62;
  if (p.top + p.bottom > maxV) { const k = maxV / (p.top + p.bottom); p.top *= k; p.bottom *= k; }
  if (p.left + p.right > maxH) { const k = maxH / (p.left + p.right); p.left *= k; p.right *= k; }
  return p;
}

export function MapView(p: MapViewProps) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MLMap | null>(null);
  const homeMarker = useRef<Marker | null>(null);
  const selMarker = useRef<Marker | null>(null);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const pendingCamera = useRef<(() => void) | null>(null);
  const cb = useRef(p);
  cb.current = p;

  const unitFC = useMemo<GeoJSON.FeatureCollection>(() => ({
    type: 'FeatureCollection',
    features: p.units.map((u) => ({
      type: 'Feature',
      id: u.id,
      properties: {
        id: u.id, name: u.short_name, type: u.type, status: u.status, offerable: u.offerable, queue: u.queue, queue_creche: u.queue_creche,
        enrollments: u.public_enrollments ?? 0, vacancy_state: u.offerable > 0 ? 'vaga' : u.queue > 0 ? 'fila' : 'neutro',
      },
      geometry: { type: 'Point', coordinates: [u.lng, u.lat] },
    })),
  }), [p.units]);

  // criação do mapa
  useEffect(() => {
    if (!ref.current) return;
    let map: MLMap;
    try {
      map = new MLMap({
        container: ref.current,
        style: STYLE,
        center: CENTER,
        zoom: 11.2,
        minZoom: 9,
        maxZoom: 18,
        attributionControl: { compact: true },
        cooperativeGestures: p.cooperative ?? false,
        dragRotate: false,
        pitchWithRotate: false,
        locale: {
          'CooperativeGesturesHandler.WindowsHelpText': 'Use Ctrl + rolagem para aproximar o mapa',
          'CooperativeGesturesHandler.MacHelpText': 'Use ⌘ + rolagem para aproximar o mapa',
          'CooperativeGesturesHandler.MobileHelpText': 'Use dois dedos para mover o mapa',
        },
      });
    } catch {
      setFailed(true);
      return;
    }
    map.touchZoomRotate.disableRotation();
    mapRef.current = map;
    map.on('error', (e) => console.warn('mapa', e?.error?.message));
    map.on('resize', () => {
      const run = pendingCamera.current;
      if (run) run();
    });
    map.on('load', () => {
      // tons da marca no mapa base
      const tweak = (id: string, prop: string, value: unknown) => { if (map.getLayer(id)) map.setPaintProperty(id, prop as never, value as never); };
      tweak('background', 'background-color', '#f4f6fa');
      tweak('water', 'fill-color', '#cfe7f6');
      tweak('park', 'fill-color', '#dcf1e6');
      tweak('landcover_wood', 'fill-color', '#e2f2e9');

      map.addSource('mask', { type: 'geojson', data: empty });
      map.addSource('muni', { type: 'geojson', data: empty });
      map.addSource('regions', { type: 'geojson', data: empty, promoteId: 'id' });
      map.addSource('areas', { type: 'geojson', data: empty });
      map.addSource('units', { type: 'geojson', data: empty, promoteId: 'id' });
      map.addSource('radius', { type: 'geojson', data: empty });
      map.addSource('lines', { type: 'geojson', data: empty });
      map.addSource('rotas', { type: 'geojson', data: empty });
      map.addSource('ranks', { type: 'geojson', data: empty });

      map.addLayer({ id: 'mask', type: 'fill', source: 'mask', paint: { 'fill-color': '#ffffff', 'fill-opacity': 0.55 } });
      map.addLayer({ id: 'regions-fill', type: 'fill', source: 'regions', paint: { 'fill-color': '#A846E8', 'fill-opacity': 0 } });
      map.addLayer({ id: 'regions-line', type: 'line', source: 'regions', paint: { 'line-color': '#ffffff', 'line-width': 2, 'line-opacity': 0 } });
      map.addLayer({ id: 'areas-line', type: 'line', source: 'areas', layout: { visibility: 'none' }, paint: { 'line-color': PURPLE, 'line-width': 1, 'line-opacity': 0.45, 'line-dasharray': [2, 2] } });
      map.addLayer({ id: 'muni-line', type: 'line', source: 'muni', paint: { 'line-color': PURPLE, 'line-width': 2.2, 'line-opacity': 0.7, 'line-dasharray': [3, 2] } });
      map.addLayer({
        id: 'heat', type: 'heatmap', source: 'units', layout: { visibility: 'none' },
        paint: {
          'heatmap-weight': 0.5,
          'heatmap-intensity': ['interpolate', ['linear'], ['zoom'], 10, 1, 15, 2.2],
          'heatmap-radius': ['interpolate', ['linear'], ['zoom'], 10, 26, 13, 46, 16, 80],
          'heatmap-opacity': 0.78,
          'heatmap-color': interpolate(['heatmap-density'], HEAT_STOPS) as never,
        },
      });
      map.addLayer({ id: 'radius-fill', type: 'fill', source: 'radius', paint: { 'fill-color': PURPLE, 'fill-opacity': 0.08 } });
      map.addLayer({ id: 'radius-line', type: 'line', source: 'radius', paint: { 'line-color': PURPLE, 'line-width': 2, 'line-dasharray': [2, 1.5] } });
      map.addLayer({ id: 'lines', type: 'line', source: 'lines', paint: { 'line-color': ROUTE_LINE, 'line-width': 2, 'line-opacity': 0.55, 'line-dasharray': [1, 1.6] } });
      map.addLayer({
        id: 'rotas-contorno', type: 'line', source: 'rotas', layout: { 'line-join': 'round', 'line-cap': 'round' },
        paint: { 'line-color': '#ffffff', 'line-width': ['match', ['get', 'modo'], 'CARRO', 8, 6.5], 'line-opacity': 0.9 },
      });
      map.addLayer({
        id: 'rota-carro', type: 'line', source: 'rotas', filter: ['==', ['get', 'modo'], 'CARRO'], layout: { 'line-join': 'round', 'line-cap': 'round' },
        paint: { 'line-color': ROTA_COLOR.CARRO, 'line-width': 4.5, 'line-opacity': 0.85 },
      });
      map.addLayer({
        id: 'rota-pe', type: 'line', source: 'rotas', filter: ['==', ['get', 'modo'], 'A_PE'], layout: { 'line-join': 'round' },
        paint: { 'line-color': ROTA_COLOR.A_PE, 'line-width': 3.5, 'line-dasharray': [1.6, 1.1] },
      });
      map.addLayer({
        id: 'units-halo', type: 'circle', source: 'units',
        paint: { 'circle-radius': ['interpolate', ['linear'], ['zoom'], 10, 6, 14, 11, 17, 16], 'circle-color': '#ffffff', 'circle-opacity': 0.95 },
      });
      map.addLayer({
        id: 'units', type: 'circle', source: 'units',
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 10, 4, 14, 8, 17, 12],
          'circle-color': UNIT_COLOR.CMEI,
          'circle-stroke-width': ['case', ['boolean', ['feature-state', 'selected'], false], 4, 0],
          'circle-stroke-color': SELECTED_STROKE,
        },
      });
      map.addLayer({
        id: 'units-label', type: 'symbol', source: 'units', minzoom: 13.3,
        layout: { 'text-field': ['get', 'name'], 'text-size': 11.5, 'text-offset': [0, 1.25], 'text-anchor': 'top', 'text-font': ['Noto Sans Regular'], 'text-max-width': 9 },
        paint: { 'text-color': '#23334A', 'text-halo-color': '#ffffff', 'text-halo-width': 1.6 },
      });
      map.addLayer({ id: 'ranks-circle', type: 'circle', source: 'ranks', paint: { 'circle-radius': 13, 'circle-color': PURPLE, 'circle-stroke-color': '#ffffff', 'circle-stroke-width': 3 } });
      map.addLayer({
        id: 'ranks-label', type: 'symbol', source: 'ranks',
        layout: { 'text-field': ['get', 'label'], 'text-size': 13, 'text-font': ['Noto Sans Bold'], 'text-allow-overlap': true, 'icon-allow-overlap': true },
        paint: { 'text-color': '#ffffff' },
      });

      const pick = (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (!f) return;
        const u = cb.current.units.find((x) => x.id === Number(f.properties?.id));
        if (u) cb.current.onSelectUnit?.(u);
      };
      map.on('click', 'units', pick);
      map.on('click', 'ranks-circle', pick);
      map.on('click', (e) => {
        const hits = map.queryRenderedFeatures(e.point, { layers: ['units', 'ranks-circle'] });
        if (hits.length) return;
        const reg = map.queryRenderedFeatures(e.point, { layers: ['regions-fill'] });
        if (reg.length && cb.current.regionMetric && cb.current.onSelectRegion) {
          cb.current.onSelectRegion(Number(reg[0].properties?.id));
          return;
        }
        cb.current.onMapClick?.(e.lngLat.lat, e.lngLat.lng);
      });
      for (const l of ['units', 'ranks-circle', 'regions-fill']) {
        map.on('mouseenter', l, () => (map.getCanvas().style.cursor = 'pointer'));
        map.on('mouseleave', l, () => (map.getCanvas().style.cursor = ''));
      }
      setReady(true);
    });
    return () => {
      map.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // unidades + cores
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    (map.getSource('units') as GeoJSONSource).setData(unitFC);
    map.setLayoutProperty('units', 'visibility', p.showUnits === false ? 'none' : 'visible');
    map.setLayoutProperty('units-halo', 'visibility', p.showUnits === false ? 'none' : 'visible');
    map.setLayoutProperty('units-label', 'visibility', p.showUnits === false ? 'none' : 'visible');
    map.setPaintProperty(
      'units', 'circle-color',
      p.colorMode === 'vacancy'
        ? ['match', ['get', 'vacancy_state'], 'vaga', VACANCY_COLOR.vaga, 'fila', VACANCY_COLOR.fila, VACANCY_COLOR.neutro]
        : ['case', ['!=', ['get', 'status'], 'ATIVA'], UNIT_COLOR.VALIDAR, ['==', ['get', 'type'], 'CMEI'], UNIT_COLOR.CMEI, UNIT_COLOR.ESCOLA],
    );
  }, [ready, unitFC, p.colorMode, p.showUnits]);

  // mapa de calor
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    if (!p.heat) {
      map.setLayoutProperty('heat', 'visibility', 'none');
      return;
    }
    const prop = { queue: 'queue', queue_creche: 'queue_creche', enrollments: 'enrollments', offerable: 'offerable' }[p.heat];
    const max = Math.max(1, ...p.units.map((u) => Number((u as any)[prop === 'enrollments' ? 'public_enrollments' : prop]) || 0));
    map.setPaintProperty('heat', 'heatmap-weight', ['interpolate', ['linear'], ['get', prop], 0, 0, max, 1]);
    map.setPaintProperty('heat', 'heatmap-color', interpolate(['heatmap-density'], p.heat === 'offerable' ? HEAT_OFFERABLE_STOPS : HEAT_STOPS) as never);
    map.setLayoutProperty('heat', 'visibility', 'visible');
  }, [ready, p.heat, p.units]);

  // regiões, áreas e limite municipal
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    (map.getSource('regions') as GeoJSONSource).setData(p.geo?.regions ?? empty);
    (map.getSource('areas') as GeoJSONSource).setData(p.geo?.areas ?? empty);
    const muni = p.geo?.municipality;
    (map.getSource('muni') as GeoJSONSource).setData(muni ?? empty);
    const mask = maskOutside(muni);
    (map.getSource('mask') as GeoJSONSource).setData(mask ? { type: 'FeatureCollection', features: [mask] } : empty);
    map.setLayoutProperty('areas-line', 'visibility', p.showAreas ? 'visible' : 'none');
    if (p.regionMetric) {
      const m = p.regionMetric;
      const color = m === 'balance_creche' || m === 'balance'
        ? interpolate(['get', m], BALANCE_STOPS)
        : m === 'queue'
          ? interpolate(['get', 'queue'], QUEUE_REGION_STOPS)
          : interpolate(['get', 'offerable'], OFFERABLE_REGION_STOPS);
      map.setPaintProperty('regions-fill', 'fill-color', color as never);
      map.setPaintProperty('regions-fill', 'fill-opacity', REGION_OPACITY);
      map.setPaintProperty('regions-line', 'line-opacity', 0.9);
    } else {
      map.setPaintProperty('regions-fill', 'fill-opacity', 0);
      map.setPaintProperty('regions-line', 'line-opacity', 0);
    }
  }, [ready, p.geo, p.regionMetric, p.showAreas]);

  // residência, raio, rotas e ranking
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    homeMarker.current?.remove();
    homeMarker.current = null;
    if (p.home) {
      const el = document.createElement('div');
      el.className = 'flex size-10 items-center justify-center rounded-full bg-ink text-white shadow-lift ring-4 ring-white';
      el.setAttribute('aria-label', 'Residência informada');
      el.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/></svg>';
      homeMarker.current = new Marker({ element: el }).setLngLat([p.home.lng, p.home.lat]).addTo(map);
    }
    (map.getSource('radius') as GeoJSONSource).setData(p.home?.radius_m ? circle(p.home.lat, p.home.lng, p.home.radius_m) : empty);
    const hl = p.highlight ?? [];
    const pts = hl.map((h) => ({ h, u: p.units.find((u) => u.id === h.id) })).filter((x) => x.u);
    (map.getSource('ranks') as GeoJSONSource).setData({
      type: 'FeatureCollection',
      features: pts.map(({ h, u }) => ({ type: 'Feature', properties: { id: u!.id, label: h.label }, geometry: { type: 'Point', coordinates: [u!.lng, u!.lat] } })),
    });
    (map.getSource('lines') as GeoJSONSource).setData(p.home && p.lines ? {
      type: 'FeatureCollection',
      features: pts.map(({ u }) => ({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: [[p.home!.lng, p.home!.lat], [u!.lng, u!.lat]] } })),
    } : empty);
  }, [ready, p.home, p.highlight, p.lines, p.units]);

  // rotas calculadas pelas ruas (a pé e de carro), da residência até cada unidade
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    const feats: GeoJSON.Feature[] = (p.trajetos ?? []).filter((t) => t.coords.length > 1).map((t) => ({
      type: 'Feature', properties: { modo: t.modo, id: t.id }, geometry: { type: 'LineString', coordinates: t.coords },
    }));
    (map.getSource('rotas') as GeoJSONSource).setData({ type: 'FeatureCollection', features: feats });
  }, [ready, p.trajetos]);

  // seleção
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    map.removeFeatureState({ source: 'units' });
    selMarker.current?.remove();
    selMarker.current = null;
    const u = p.units.find((x) => x.id === p.selectedId);
    if (u) {
      map.setFeatureState({ source: 'units', id: u.id }, { selected: true });
      const el = document.createElement('div');
      el.className = 'pointer-events-none relative size-6';
      el.innerHTML = `<span class="pulse-ring absolute inset-0 rounded-full" style="background:${u.type === 'CMEI' ? UNIT_COLOR.CMEI : UNIT_COLOR.ESCOLA}"></span>`;
      selMarker.current = new Marker({ element: el }).setLngLat([u.lng, u.lat]).addTo(map);
    }
  }, [ready, p.selectedId, p.units]);

  // enquadramento
  useEffect(() => {
    const map = mapRef.current;
    if (!ready || !map) return;
    const frame = () => {
      const pad = safePadding(map, p.padding ?? { top: 70, bottom: 70, left: 40, right: 40 });
      if (!pad) {
        pendingCamera.current = frame; // mapa sem tamanho (oculto/animando): enquadra quando houver espaço
        return;
      }
      pendingCamera.current = null;
      try {
        if (p.focus) {
          map.flyTo({ center: [p.focus.lng, p.focus.lat], zoom: p.focus.zoom ?? 14.5, padding: pad, duration: 900, essential: true });
          return;
        }
        const pts: [number, number][] = [];
        if (p.home) pts.push([p.home.lng, p.home.lat]);
        const hl = p.highlight?.map((h) => p.units.find((u) => u.id === h.id)).filter(Boolean) as UnitMapItem[] | undefined;
        (hl?.length ? hl : p.home ? [] : p.units).forEach((u) => pts.push([u.lng, u.lat]));
        for (const t of p.trajetos ?? []) t.coords.forEach((x) => pts.push(x));
        if (!pts.length) return;
        const b = pts.reduce((acc, c) => acc.extend(c), new LngLatBounds(pts[0], pts[0]));
        if (pts.length === 1) map.flyTo({ center: pts[0], zoom: 14.5, padding: pad, duration: 800 });
        else map.fitBounds(b, { padding: pad, duration: 900, maxZoom: 15.2 });
      } catch (e) {
        console.warn('[mapa] enquadramento ignorado', e);
      }
    };
    frame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, p.fitKey, p.focus?.lat, p.focus?.lng]);

  if (failed) {
    return (
      <div className={clsx('flex items-center justify-center bg-slate-100 p-6 text-center text-sm text-muted', p.className)}>
        Não foi possível carregar o mapa neste aparelho (WebGL indisponível). Use a visualização em lista.
      </div>
    );
  }

  const legendMode = p.legend ?? 'strip';
  const legendInput = {
    units: p.units, showUnits: p.showUnits, colorMode: p.colorMode, regionMetric: p.regionMetric, heat: p.heat,
    hasBoundary: !!p.geo?.municipality, showAreas: p.showAreas && !!p.geo?.areas, home: p.home, homeLabel: p.homeLabel,
    highlight: p.highlight, highlightLabel: p.highlightLabel, lines: p.lines,
    rotas: { A_PE: (p.trajetos ?? []).some((t) => t.modo === 'A_PE'), CARRO: (p.trajetos ?? []).some((t) => t.modo === 'CARRO') },
    selectedUnit: p.selectedId != null ? p.units.find((u) => u.id === p.selectedId) ?? null : null, selectedLabel: p.selectedLabel,
  };

  const mapArea = (
    <div className={clsx('overflow-hidden', !/\b(absolute|fixed|sticky)\b/.test(p.className ?? '') && 'relative', p.className)}>
      <div ref={ref} className="h-full w-full" role="application" aria-label="Mapa interativo das unidades de Maringá" />
      {!ready && <div className="skeleton absolute inset-0" aria-hidden />}
      {legendMode === 'overlay' && <MapLegend variant="overlay" className={p.legendClassName ?? 'bottom-3 left-3'} note={p.legendNote} {...legendInput} />}
      {p.controls !== false && (
        <div className="absolute right-3 top-1/2 z-10 flex -translate-y-1/2 flex-col gap-2">
          <button className="glass inline-flex size-11 items-center justify-center rounded-2xl shadow-soft ring-1 ring-white/70" onClick={() => mapRef.current?.zoomIn()} aria-label="Aproximar">
            <Plus className="size-5" />
          </button>
          <button className="glass inline-flex size-11 items-center justify-center rounded-2xl shadow-soft ring-1 ring-white/70" onClick={() => mapRef.current?.zoomOut()} aria-label="Afastar">
            <Minus className="size-5" />
          </button>
          <button
            className="glass inline-flex size-11 items-center justify-center rounded-2xl shadow-soft ring-1 ring-white/70"
            onClick={() => {
              const map = mapRef.current;
              if (!map || !p.units.length) return;
              const b = p.units.reduce((acc, u) => acc.extend([u.lng, u.lat]), new LngLatBounds([p.units[0].lng, p.units[0].lat], [p.units[0].lng, p.units[0].lat]));
              const pad = safePadding(map, p.padding ?? 60);
              if (pad) map.fitBounds(b, { padding: pad, duration: 800 });
            }}
            aria-label="Ver a cidade inteira"
          >
            <Crosshair className="size-5" />
          </button>
        </div>
      )}
    </div>
  );

  if (legendMode !== 'strip') return mapArea;
  return (
    <div>
      {mapArea}
      <MapLegend variant="strip" note={p.legendNote} {...legendInput} />
    </div>
  );
}

export default MapView;
