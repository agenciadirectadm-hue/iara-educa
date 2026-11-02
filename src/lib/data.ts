import { useRpc } from './hooks';
import type { Bootstrap, UnitMapItem } from './types';
import type { GeoLayers } from '@/components/map/MapView';

export const useBootstrap = () => useRpc<Bootstrap>('bootstrap', {}, { staleTime: 5 * 60_000 });
export const useUnitsMap = () => useRpc<{ units: UnitMapItem[]; generated_at: string }>('units_map', {}, { staleTime: 60_000 });
export const useGeoLayers = () => useRpc<GeoLayers & { notes: string[] }>('geo_layers', {}, { staleTime: 10 * 60_000 });
/** Setores censitários com crianças de 0 a 4 anos (Censo 2022) — só carrega quando a camada de demanda é aberta. */
export const useGeoSetores = (enabled: boolean, areaId?: number) =>
  useRpc<GeoJSON.FeatureCollection & { fonte: string }>('geo_setores', areaId ? { area_id: areaId } : {}, { enabled, staleTime: 60 * 60_000 });
