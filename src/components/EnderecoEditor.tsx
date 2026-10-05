import { useEffect, useRef, useState } from 'react';
import clsx from 'clsx';
import { Building2, CheckCircle2, LocateFixed, MapPin, Search, TriangleAlert } from 'lucide-react';
import { geoLocalizar, rpc } from '@/lib/api';
import { geocodificarNoNavegador, type Candidato } from '@/lib/geo';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useGeoLayers, useUnitsMap } from '@/lib/data';
import { PRECISAO, fmtDistancia, mascaraCep, precisaoRotulo, soDigitos, type Endereco } from '@/lib/cadastro';
import { Button } from './ui';
import { Campo, Escolha, Texto } from './cadastro';
import MapView from './map/MapView';

type Ponto = { dentro_maringa: boolean; territorio: string | null; territorio_tipo: string | null; bairro: string | null; bairro_distancia_m: number | null;
  unidades: { id: number; nome: string; tipo_rotulo: string | null; distancia_m: number; vagas: number | null }[] };

/**
 * Endereço com localização: CEP → rua e bairro (ViaCEP); endereço → ponto no mapa (OpenStreetMap); clique no mapa ajusta o ponto
 * (precisão "ponto conferido no mapa"). Mostra território, bairro, zona e as unidades mais próximas. Só o endereço sai do sistema.
 */
export default function EnderecoEditor({ value, onChange, faixaId }: { value: Endereco; onChange: (e: Endereco) => void; faixaId?: number | null }) {
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const [busy, setBusy] = useState<'cep' | 'mapa' | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [foco, setFoco] = useState<{ lat: number; lng: number; zoom?: number } | null>(null);
  const [verBairros, setVerBairros] = useState(false);
  const set = (patch: Partial<Endereco>) => onChange({ ...value, ...patch });
  const temPonto = value.lat != null && value.lng != null;
  const local = useRpc<Ponto>('localizar_ponto', { lat: value.lat, lng: value.lng, faixa_id: faixaId ?? null }, { enabled: temPonto, staleTime: 60_000 });
  const dBairro = useDebounced(value.bairro, 300);
  const bairros = useRpc<any>('geo_search', { q: dBairro }, { enabled: verBairros && dBairro.length >= 2 });

  /** Melhor ponto disponível: geocodificador (servidor ou navegador) → centro do bairro → pedir o clique no mapa. */
  const posicionar = async (e: Endereco, candidatos: Candidato[], servidorSemMapa: boolean): Promise<Endereco> => {
    let c = candidatos[0];
    if (!c && servidorSemMapa && e.logradouro) {
      c = (await geocodificarNoNavegador({ logradouro: e.logradouro, numero: e.numero, bairro: e.bairro, cidade: e.cidade }))[0];
    }
    if (c) {
      setFoco({ lat: c.lat, lng: c.lng, zoom: c.precisao === 'ENDERECO' ? 17 : 16 });
      setAviso(c.precisao === 'ENDERECO' ? null : 'Achamos a rua, mas não o número: toque no mapa sobre a casa para marcar o ponto exato.');
      return { ...e, lat: c.lat, lng: c.lng, precisao: c.precisao, fonte: c.fonte };
    }
    if (e.bairro) {
      const g = await rpc<any>('geo_search', { q: e.bairro }).catch(() => null);
      const b = (g?.items ?? []).find((i: any) => i.kind === 'BAIRRO');
      if (b) {
        setFoco({ lat: b.lat, lng: b.lng, zoom: 15 });
        setAviso('Marcamos o centro do bairro. Toque no mapa sobre a casa para deixar a localização exata.');
        return { ...e, lat: b.lat, lng: b.lng, precisao: 'BAIRRO', fonte: 'Centro do bairro' };
      }
    }
    setAviso('Não encontramos o endereço no mapa. Toque no mapa para marcar a casa.');
    return e;
  };

  const buscarCep = async () => {
    const d = soDigitos(value.cep);
    if (d.length !== 8) {
      setAviso('O CEP tem 8 dígitos.');
      return;
    }
    setBusy('cep');
    setAviso(null);
    try {
      const r = await geoLocalizar({ cep: d, numero: value.numero || undefined, logradouro: value.logradouro || undefined, bairro: value.bairro || undefined });
      if (r.cep_erro) {
        setAviso(r.cep_erro);
        return;
      }
      const novo: Endereco = {
        ...value, logradouro: r.cep?.logradouro || value.logradouro, bairro: r.cep?.bairro || value.bairro,
        cidade: r.cep?.cidade || value.cidade, uf: r.cep?.uf || value.uf,
      };
      const pos = await posicionar(novo, r.candidatos, r.geocodificador === 'indisponivel');
      onChange(pos);
      if (r.fora_de_maringa) setAviso(`CEP de ${r.cep?.cidade}/${r.cep?.uf}, fora de Maringá. A fila da rede municipal considera residência no município.`);
    } catch (e) {
      setAviso((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  const localizar = async () => {
    if (!value.logradouro.trim() && !value.bairro.trim()) {
      setAviso('Informe a rua (ou ao menos o bairro) para localizar.');
      return;
    }
    setBusy('mapa');
    setAviso(null);
    try {
      const r = await geoLocalizar({ logradouro: value.logradouro, numero: value.numero, bairro: value.bairro, cidade: value.cidade, cep: soDigitos(value.cep) || undefined });
      onChange(await posicionar(value, r.candidatos, r.geocodificador === 'indisponivel'));
    } catch (e) {
      setAviso((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  // CEP completo digitado → busca sozinho (uma vez por CEP)
  const cepBuscado = useRef(soDigitos(value.cep));
  useEffect(() => {
    const d = soDigitos(value.cep);
    if (d.length === 8 && d !== cepBuscado.current) {
      cepBuscado.current = d;
      buscarCep();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value.cep]);

  const p = local.data;
  const exata = PRECISAO[value.precisao]?.exata;
  const proximas = (p?.unidades ?? []).slice(0, 3);
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-6">
        <Campo label="CEP" className="sm:col-span-2" dica="Preenche a rua e o bairro">
          <div className="flex gap-2">
            <Texto value={value.cep} onChange={(v) => set({ cep: mascaraCep(v) })} inputMode="numeric" placeholder="00000-000" aria-label="CEP" />
            <Button type="button" variant="secondary" icon={Search} loading={busy === 'cep'} onClick={buscarCep} aria-label="Buscar CEP" className="shrink-0 px-3" />
          </div>
        </Campo>
        <Campo label="Logradouro" obrigatorio className="sm:col-span-4">
          <Texto value={value.logradouro} onChange={(v) => set({ logradouro: v })} placeholder="Rua, avenida…" autoComplete="off" />
        </Campo>
        <Campo label="Número" className="sm:col-span-2">
          <Texto value={value.numero} onChange={(v) => set({ numero: v })} placeholder="s/n" inputMode="numeric" />
        </Campo>
        <Campo label="Complemento" className="sm:col-span-4">
          <Texto value={value.complemento} onChange={(v) => set({ complemento: v })} placeholder="Casa, apartamento, bloco…" />
        </Campo>
        <Campo label="Bairro" className="relative sm:col-span-3">
          <Texto value={value.bairro} onChange={(v) => { set({ bairro: v }); setVerBairros(true); }} onBlur={() => setTimeout(() => setVerBairros(false), 200)} placeholder="Ex.: Zona 7, Jardim Alvorada" autoComplete="off" />
          {verBairros && (bairros.data?.items ?? []).length > 0 && (
            <div className="absolute inset-x-0 top-full z-20 mt-1 max-h-60 overflow-y-auto rounded-2xl bg-white shadow-lift ring-1 ring-line">
              {(bairros.data.items as any[]).filter((i) => i.kind === 'BAIRRO').slice(0, 6).map((i) => (
                <button key={i.label} type="button" onMouseDown={(e) => e.preventDefault()}
                  onClick={() => { setVerBairros(false); if (!temPonto) setFoco({ lat: i.lat, lng: i.lng, zoom: 15 }); onChange({ ...value, bairro: i.label, ...(temPonto ? {} : { lat: i.lat, lng: i.lng, precisao: 'BAIRRO', fonte: 'Centro do bairro' }) }); }}
                  className="flex w-full items-center gap-2 px-3 py-2.5 text-left text-[14px] hover:bg-purple-50">
                  <MapPin className="size-4 text-purple-700" />{i.label}
                </button>
              ))}
            </div>
          )}
        </Campo>
        <Campo label="Cidade" className="sm:col-span-2">
          <Texto value={value.cidade} onChange={(v) => set({ cidade: v })} />
        </Campo>
        <Campo label="UF" className="sm:col-span-1">
          <Texto value={value.uf} onChange={(v) => set({ uf: v.toUpperCase().slice(0, 2) })} maxLength={2} />
        </Campo>
        <Campo label="Ponto de referência" className="sm:col-span-4" dica="Ajuda o transporte escolar e a visita da equipe">
          <Texto value={value.referencia} onChange={(v) => set({ referencia: v })} placeholder="Ex.: em frente ao mercado, portão verde" />
        </Campo>
        <Campo label="Zona" className="sm:col-span-2">
          <Escolha nome="Zona" value={value.zona} onChange={(v) => set({ zona: v })} opcoes={[['URBANA', 'Urbana'], ['RURAL', 'Rural']]} />
        </Campo>
      </div>

      <div className="overflow-hidden rounded-3xl ring-1 ring-line">
        <div className="flex flex-wrap items-center gap-2 border-b border-line bg-slate-50 px-3 py-2">
          <LocateFixed className="size-4 text-purple-700" />
          <span className="text-[13px] font-semibold text-ink-2">Localização no mapa</span>
          <span className="text-[12px] text-muted">toque no mapa para marcar ou ajustar a casa</span>
          <Button type="button" size="sm" variant="secondary" icon={MapPin} loading={busy === 'mapa'} onClick={localizar} className="ml-auto">
            Localizar endereço
          </Button>
        </div>
        <MapView
          className="h-64 sm:h-80"
          units={units.data?.units ?? []}
          geo={geo.data}
          home={temPonto ? { lat: value.lat!, lng: value.lng! } : null}
          highlight={proximas.map((u, i) => ({ id: u.id, label: String(i + 1) }))}
          lines
          onMapClick={(lat, lng) => { setAviso(null); set({ lat, lng, precisao: 'PONTO_NO_MAPA', fonte: 'Marcado no mapa' }); }}
          focus={foco}
          fitKey="endereco"
          cooperative
          homeLabel="Endereço marcado"
          highlightLabel="Unidades mais próximas"
        />
        <div className="space-y-2 p-3 text-[13px]">
          {aviso && <p className="flex items-start gap-2 rounded-2xl bg-amber-50 p-2.5 text-amber-950 ring-1 ring-amber-200"><TriangleAlert className="mt-0.5 size-4 shrink-0" />{aviso}</p>}
          {!temPonto ? (
            <p className="text-muted">Sem ponto marcado ainda. Busque pelo CEP, use "Localizar endereço" ou toque no mapa.</p>
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <span className={clsx('inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[12.5px] font-semibold ring-1',
                  exata ? 'bg-green-50 text-green-900 ring-green-200' : 'bg-amber-50 text-amber-900 ring-amber-200')}>
                  {exata ? <CheckCircle2 className="size-3.5" /> : <TriangleAlert className="size-3.5" />}{precisaoRotulo(value.precisao)}
                </span>
                {p && <span><b>Território:</b> {p.dentro_maringa ? p.territorio ?? '—' : 'fora de Maringá'}</span>}
                {p?.bairro && <span><b>Bairro de referência:</b> {p.bairro}</span>}
                <span className="text-subtle">{value.lat!.toFixed(5)}, {value.lng!.toFixed(5)}</span>
              </div>
              {p && !p.dentro_maringa && (
                <p className="rounded-2xl bg-amber-50 p-2.5 text-amber-950 ring-1 ring-amber-200">O ponto está fora de Maringá. O cadastro aceita, mas a fila da rede municipal considera residência no município.</p>
              )}
              {proximas.length > 0 && (
                <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-3">
                  {proximas.map((u, i) => (
                    <div key={u.id} className="flex items-center gap-2 rounded-2xl bg-white px-2.5 py-2 ring-1 ring-line">
                      <span className="inline-flex size-6 shrink-0 items-center justify-center rounded-full bg-purple-700 text-[12px] font-bold text-white">{i + 1}</span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-semibold">{u.nome}</span>
                        <span className="block text-[12px] text-muted"><Building2 className="mr-0.5 inline size-3" />{fmtDistancia(u.distancia_m)}{u.vagas != null ? ` · ${u.vagas} vaga(s) na faixa` : ''}</span>
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
          <p className="text-[11.5px] text-subtle">CEP: ViaCEP · mapa: © OpenStreetMap. Só o endereço é consultado — nenhum dado da pessoa sai do sistema.</p>
        </div>
      </div>
    </div>
  );
}
