/** Pequenas contas de geometria no navegador (coordenadas [lng, lat] do GeoJSON). */

export type Caixa = [[number, number], [number, number]];

/** Caixa ([oeste, sul], [leste, norte]) de um polígono ou multipolígono. */
export function caixaDe(g?: GeoJSON.Geometry | null): Caixa | null {
  if (!g || (g.type !== 'Polygon' && g.type !== 'MultiPolygon')) return null;
  const aneis = g.type === 'Polygon' ? g.coordinates : g.coordinates.flat();
  let [o, s, l, n] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const anel of aneis) for (const [x, y] of anel) { o = Math.min(o, x); s = Math.min(s, y); l = Math.max(l, x); n = Math.max(n, y); }
  return Number.isFinite(o) ? [[o, s], [l, n]] : null;
}

function noAnel(x: number, y: number, anel: number[][]): boolean {
  let dentro = false;
  for (let i = 0, j = anel.length - 1; i < anel.length; j = i++) {
    const [xi, yi] = anel[i];
    const [xj, yj] = anel[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) dentro = !dentro;
  }
  return dentro;
}

/** O ponto (lng, lat) está dentro do polígono (descontando os buracos)? */
export function pontoDentro(lng: number, lat: number, g?: GeoJSON.Geometry | null): boolean {
  if (!g || (g.type !== 'Polygon' && g.type !== 'MultiPolygon')) return false;
  const poligonos = g.type === 'Polygon' ? [g.coordinates] : g.coordinates;
  return poligonos.some(([fora, ...buracos]) => noAnel(lng, lat, fora) && !buracos.some((b) => noAnel(lng, lat, b)));
}
