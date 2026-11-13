// IARAFLIX: chamadas que não são uma função do banco (link curto do vídeo e envio direto ao Storage).
// O bucket é privado: o vídeo só abre com o link que o gateway assina depois de conferir a sessão e a trilha do perfil (vale 15 minutos).
import { API_URL, ApiError, apiToken, passeDeAcesso } from './api';

async function post<T>(path: string, corpo: object): Promise<T> {
  let res: Response;
  const passe = passeDeAcesso();
  try {
    res = await fetch(`${API_URL}${path}`, {
      method: 'POST', body: JSON.stringify(corpo),
      headers: { 'content-type': 'application/json', ...(apiToken() ? { 'x-iara-session': apiToken()! } : {}), ...(passe ? { 'x-iara-acesso': passe } : {}) },
    });
  } catch {
    throw new ApiError('Sem conexão com o servidor. Verifique a internet e tente novamente.', 0, 'OFFLINE');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError((data as { error?: string }).error ?? 'Falha de comunicação.', res.status, (data as { code?: string }).code);
  return data as T;
}

export type LinkAula = { video: string; legenda: string | null; mime: string; expira_em: string };
export const linkDaAula = (aulaId: string) => post<LinkAula>('/iaraflix/assistir', { aula_id: aulaId });

export const LIMITE_VIDEO = 50 * 1024 * 1024;

/** Duração do vídeo lida no próprio aparelho, antes do envio (segundos). */
export function duracaoDoVideo(file: File): Promise<number | null> {
  return new Promise((ok) => {
    const v = document.createElement('video');
    const url = URL.createObjectURL(file);
    const fim = (d: number | null) => { URL.revokeObjectURL(url); ok(d); };
    v.preload = 'metadata';
    v.onloadedmetadata = () => fim(Number.isFinite(v.duration) ? Math.round(v.duration) : null);
    v.onerror = () => fim(null);
    v.src = url;
  });
}

/**
 * Envia o vídeo (ou a legenda) de uma aula: o banco autoriza, o arquivo vai direto ao Storage (com progresso) e o gateway confere
 * o conteúdo antes de publicar. `conferido`: quem envia confirma que o vídeo foi gravado no ambiente de treinamento, só com dados fictícios.
 */
export async function enviarDaAula(p: { aulaId: string; tipo: 'VIDEO' | 'LEGENDA'; arquivo: File; conferido?: boolean; duracao_s?: number | null },
  progresso?: (pct: number) => void): Promise<void> {
  const mime = p.tipo === 'LEGENDA' ? 'text/vtt' : (p.arquivo.type || (p.arquivo.name.toLowerCase().endsWith('.webm') ? 'video/webm' : 'video/mp4'));
  const aut = await post<{ caminho: string; mime: string; url: string }>('/iaraflix/envio',
    { aula_id: p.aulaId, tipo: p.tipo, mime, bytes: p.arquivo.size });
  await new Promise<void>((ok, erro) => {
    const x = new XMLHttpRequest();
    x.open('PUT', aut.url);
    x.setRequestHeader('content-type', aut.mime);
    x.upload.onprogress = (e) => { if (e.lengthComputable) progresso?.(Math.round((e.loaded / e.total) * 100)); };
    x.onload = () => (x.status >= 200 && x.status < 300 ? ok() : erro(new ApiError(`O envio não terminou (${x.status}). Tente de novo.`, x.status)));
    x.onerror = () => erro(new ApiError('A conexão caiu durante o envio. Tente de novo.', 0, 'OFFLINE'));
    x.send(p.arquivo);
  });
  await post('/iaraflix/envio/confirmar', { aula_id: p.aulaId, tipo: p.tipo, caminho: aut.caminho, conferido: !!p.conferido, duracao_s: p.duracao_s ?? null });
}

// ---------------------------------------------------------------- vídeos da SEDUC para as famílias

export type VideoFamilia = {
  id: string; titulo: string; descricao: string | null; categoria: string; fonte: 'YOUTUBE' | 'ARQUIVO'; youtube_id: string | null; tem_arquivo: boolean;
  duracao_s: number | null; destaque: boolean; publicado_em: string | null; is_demo: boolean;
  situacao?: 'RASCUNHO' | 'PUBLICADO'; ordem?: number; visualizacoes?: number; arquivo_bytes?: number | null; atualizado_em?: string; atualizado_por?: string | null;
};
export const CATEGORIAS_VIDEO: { codigo: string; nome: string }[] = [
  { codigo: 'TUTORIAL', nome: 'Aprenda a usar o portal e a IARA' }, { codigo: 'MATRICULA', nome: 'Vagas e matrícula' },
  { codigo: 'VIDA_ESCOLAR', nome: 'Vida escolar' }, { codigo: 'AVISOS', nome: 'Avisos e campanhas da SEDUC' }, { codigo: 'OUTROS', nome: 'Outros' },
];

/** Código do vídeo do YouTube em qualquer formato de link (watch, youtu.be, shorts, embed, live) ou o próprio código. */
export function youtubeId(texto: string): string | null {
  const t = texto.trim();
  const m = t.match(/(?:youtube(?:-nocookie)?\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/|v\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
  if (m) return m[1];
  return /^[A-Za-z0-9_-]{11}$/.test(t) ? t : null;
}

/** Link curto do arquivo de um vídeo publicado para as famílias (vale sem login). */
export const linkVideoFamilia = (id: string) => post<{ video: string; mime: string; expira_em: string }>('/videos/assistir', { id });

/** Envia o arquivo de um vídeo das famílias direto ao Storage, com progresso; o gateway confere o conteúdo antes de gravar. */
export async function enviarVideoFamilia(p: { id: string; arquivo: File; duracao_s?: number | null }, progresso?: (pct: number) => void): Promise<void> {
  const mime = p.arquivo.type || (p.arquivo.name.toLowerCase().endsWith('.webm') ? 'video/webm' : 'video/mp4');
  const aut = await post<{ caminho: string; mime: string; url: string }>('/videos/envio', { id: p.id, mime, bytes: p.arquivo.size });
  await new Promise<void>((ok, erro) => {
    const x = new XMLHttpRequest();
    x.open('PUT', aut.url);
    x.setRequestHeader('content-type', aut.mime);
    x.upload.onprogress = (e) => { if (e.lengthComputable) progresso?.(Math.round((e.loaded / e.total) * 100)); };
    x.onload = () => (x.status >= 200 && x.status < 300 ? ok() : erro(new ApiError(`O envio não terminou (${x.status}). Tente de novo.`, x.status)));
    x.onerror = () => erro(new ApiError('A conexão caiu durante o envio. Tente de novo.', 0, 'OFFLINE'));
    x.send(p.arquivo);
  });
  await post('/videos/envio/confirmar', { id: p.id, caminho: aut.caminho, duracao_s: p.duracao_s ?? null });
}

export function fmtDuracao(s: number | null | undefined) {
  if (s == null) return '—';
  const m = Math.floor(s / 60);
  const ss = Math.round(s % 60);
  return `${m}:${String(ss).padStart(2, '0')}`;
}

export function fmtMinutos(s: number | null | undefined) {
  if (!s) return '—';
  const min = Math.round(s / 60);
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60 ? `${min % 60} min` : ''}`.trim();
}
