import { useRpc } from './hooks';
import type { Bootstrap, UnitMapItem } from './types';
import type { GeoLayers } from '@/components/map/MapView';

export const useBootstrap = () => useRpc<Bootstrap>('bootstrap', {}, { staleTime: 5 * 60_000 });
export const useUnitsMap = () => useRpc<{ units: UnitMapItem[]; generated_at: string }>('units_map', {}, { staleTime: 60_000 });
export const useGeoLayers = () => useRpc<GeoLayers & { notes: string[] }>('geo_layers', {}, { staleTime: 10 * 60_000 });
