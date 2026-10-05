// Reserva da geocodificação: quando o servidor não alcança o mapa (o OpenStreetMap recusa servidores em nuvem
// compartilhada), o navegador consulta o serviço público diretamente — como qualquer site de mapas.
// Só o endereço é enviado; nunca nome, CPF ou outro dado da pessoa. No máximo uma consulta por segundo.
const NOMINATIM = 'https://nominatim.openstreetmap.org/search';
const VIEWBOX = '-52.20,-23.20,-51.75,-23.65'; // Maringá e distritos

export type Candidato = { lat: number; lng: number; precisao: string; fonte: string; rotulo: string };

let ultima = 0;
const pausa = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function consulta(params: Record<string, string>): Promise<Candidato[]> {
  const espera = 1100 - (Date.now() - ultima);
  if (espera > 0) await pausa(espera);
  ultima = Date.now();
  const qs = new URLSearchParams({
    format: 'jsonv2', limit: '3', countrycodes: 'br', addressdetails: '1', viewbox: VIEWBOX, bounded: '1', 'accept-language': 'pt-BR', ...params,
  });
  const r = await fetch(`${NOMINATIM}?${qs}`);
  if (!r.ok) return [];
  const itens = (await r.json()) as Array<{ lat: string; lon: string; display_name: string; address?: { house_number?: string } }>;
  return itens.map((i) => ({
    lat: Number(i.lat), lng: Number(i.lon), precisao: i.address?.house_number ? 'ENDERECO' : 'LOGRADOURO', fonte: 'OpenStreetMap', rotulo: i.display_name,
  }));
}

export async function geocodificarNoNavegador(q: { logradouro: string; numero?: string; bairro?: string; cidade?: string }): Promise<Candidato[]> {
  if (!q.logradouro.trim()) return [];
  const rua = [q.numero, q.logradouro].filter(Boolean).join(' ').trim();
  const cidade = q.cidade?.trim() || 'Maringá';
  try {
    const out = await consulta({ street: rua, city: cidade, state: 'Paraná' });
    if (out.length) return out;
    return await consulta({ q: [rua, q.bairro, `${cidade}, PR`].filter(Boolean).join(', ') });
  } catch {
    return [];
  }
}
