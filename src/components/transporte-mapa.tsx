// Mapa de todas as rotas do transporte escolar: trajetos pelas ruas, escolas, veículos a caminho e, na rota escolhida, as paradas.
import { lazy, Suspense, useMemo, useState } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import { ExternalLink, Search, X } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Card, Chip, EmptyState, ErrorState, Skeleton, inputCls } from '@/components/ui';
import { EstadoViagem, hm } from '@/components/transporte';

const MapView = lazy(() => import('@/components/map/MapView'));
const CORES = ['#1D6FD8', '#7A24C5', '#0A8F5B', '#D94C4C', '#F28C38', '#0E7490', '#A21CAF', '#4D7C0F', '#B45309', '#BE185D'];
const norm = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();

export function MapaRotas({ unitId }: { unitId: number | null }) {
  const [turno, setTurno] = useState('');
  const [busca, setBusca] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const res = useRpc<any[]>('transporte_mapa', { unit_id: unitId, turno: turno || null }, { refetchInterval: 60_000 });
  const rotas = useMemo(() => (res.data ?? []).map((r, i) => ({ ...r, cor: CORES[i % CORES.length] })), [res.data]);
  const visiveis = useMemo(() => {
    const q = norm(busca.trim());
    return q ? rotas.filter((r) => norm(`${r.codigo} ${r.unidade} ${r.nome ?? ''}`).includes(q)) : rotas;
  }, [rotas, busca]);
  const atual = rotas.find((r) => String(r.id) === sel) ?? null;
  const linhas = useMemo(() => visiveis.map((r) => ({ id: String(r.id), coords: r.linha as [number, number][], cor: r.cor, rotulo: r.codigo })), [visiveis]);
  const pontos = useMemo(() => {
    const escolas = new Map<string, { lat: number; lng: number }>();
    for (const r of visiveis) if (r.escola?.lat) escolas.set(`${r.escola.lat},${r.escola.lng}`, r.escola);
    const pts: { lat: number; lng: number; rotulo?: string; tipo: 'PARADA' | 'VEICULO' | 'ESCOLA' }[] =
      [...escolas.values()].map((e) => ({ lat: e.lat, lng: e.lng, tipo: 'ESCOLA', rotulo: 'E' }));
    for (const r of visiveis) if (r.agora?.posicao) pts.push({ lat: r.agora.posicao.lat, lng: r.agora.posicao.lng, tipo: 'VEICULO', rotulo: '' });
    if (atual) (atual.paradas as [number, number][]).forEach(([lng, lat], i) => pts.push({ lat, lng, tipo: 'PARADA', rotulo: String(i + 1) }));
    return pts;
  }, [visiveis, atual]);
  const totais = useMemo(() => ({
    alunos: visiveis.reduce((a, r) => a + Number(r.alunos ?? 0), 0), km: visiveis.reduce((a, r) => a + Number(r.km ?? 0), 0),
    caminho: visiveis.filter((r) => r.agora?.situacao === 'EM_ANDAMENTO').length, ruas: visiveis.filter((r) => r.pelas_ruas).length,
  }), [visiveis]);

  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_360px]">
      <Card className="overflow-hidden">
        <Suspense fallback={<Skeleton className="h-[560px]" />}>
          {res.isLoading ? <Skeleton className="h-[560px]" /> : (
            <MapView units={[]} linhas={linhas} pontos={pontos} linhaDestaque={sel} onSelectLinha={(id) => setSel(id === sel ? null : id)}
              fitLinhas fitKey={`${unitId}-${turno}-${busca}-${sel ?? ''}-${rotas.length}`}
              focus={null} className="h-[460px] lg:h-[620px]" legend={false} cooperative />
          )}
        </Suspense>
        <p className="px-4 py-2 text-[12px] text-muted">
          {fmtInt(visiveis.length)} rota(s) · {fmtInt(totais.alunos)} alunos · {fmtInt(Math.round(totais.km))} km por sentido · {fmtInt(totais.ruas)} traçadas pelas ruas.
          {' '}E = escola; laranja = veículo a caminho agora (posição pelo horário, sem GPS). Toque numa linha para destacar e ver as paradas.
        </p>
      </Card>
      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {[['', 'Todos os turnos'], ['MANHA', 'Manhã'], ['TARDE', 'Tarde'], ['NOITE', 'Noite']].map(([v, l]) => (
            <Chip key={v} active={turno === v} onClick={() => { setTurno(v); setSel(null); }}>{l}</Chip>
          ))}
        </div>
        <label className="relative block">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" aria-hidden />
          <input value={busca} onChange={(e) => { setBusca(e.target.value); setSel(null); }} placeholder="Rota ou escola…" className={`${inputCls} h-10 pl-9`} aria-label="Buscar rota ou escola" />
        </label>
        {atual && (
          <Card className="space-y-1 p-3 ring-2" style={{ ['--tw-ring-color' as any]: atual.cor }}>
            <div className="flex items-start justify-between gap-2">
              <div>
                <div className="font-display text-lg font-extrabold">{atual.codigo} · {atual.unidade}</div>
                <div className="text-[12.5px] text-muted">{SHIFT[atual.turno] ?? atual.turno} · {fmtInt(atual.alunos)} alunos · {(atual.paradas ?? []).length} paradas · {atual.km != null ? `${String(atual.km).replace('.', ',')} km` : '—'}</div>
                <div className="text-[12.5px] text-muted">Ida: sai {hm(atual.ida?.inicio)} · chega {hm(atual.ida?.chegada)}</div>
              </div>
              <button type="button" onClick={() => setSel(null)} className="rounded-full p-1 hover:bg-slate-100" aria-label="Tirar o destaque"><X className="size-4" /></button>
            </div>
            <div className="flex items-center justify-between gap-2 text-[13px]">
              <EstadoViagem e={atual.agora} compacto />
              <Link to={`/transporte/rotas/${atual.id}`} className="inline-flex items-center gap-1 font-semibold text-blue-800 underline">Abrir a rota<ExternalLink className="size-3.5" /></Link>
            </div>
          </Card>
        )}
        <Card className="max-h-[540px] overflow-y-auto">
          {res.isLoading ? <Skeleton className="m-3 h-40" /> : !visiveis.length ? <EmptyState compact title="Nenhuma rota" /> : (
            <ul role="list" aria-label="Rotas no mapa">
              {visiveis.map((r) => (
                <li key={r.id}>
                  <button type="button" onClick={() => setSel(String(r.id) === sel ? null : String(r.id))}
                    className={clsx('flex w-full items-center gap-2 border-b border-line/60 px-3 py-2 text-left text-[13px] hover:bg-blue-50', String(r.id) === sel && 'bg-blue-50')}>
                    <span className="h-3 w-6 shrink-0 rounded-full" style={{ background: r.cor }} aria-hidden />
                    <span className="w-12 shrink-0 font-semibold">{r.codigo}</span>
                    <span className="min-w-0 flex-1 truncate" title={r.unidade}>{r.unidade}</span>
                    <span className="shrink-0 text-muted">{(SHIFT[r.turno] ?? r.turno).slice(0, 5)}</span>
                    <span className="w-14 shrink-0 text-right tabular-nums text-muted">{fmtInt(r.alunos)} al.</span>
                    {r.agora?.situacao === 'EM_ANDAMENTO' && <span className="size-2 shrink-0 rounded-full bg-orange-500" title="a caminho agora" />}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
