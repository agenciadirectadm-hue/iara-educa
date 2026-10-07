// Envio e leitura de arquivos pelo gateway (o bucket é privado: o navegador nunca recebe link direto do Storage).
import { useQuery } from '@tanstack/react-query';
import { API_URL, ApiError, apiToken } from './api';

export type Finalidade = 'DOCUMENTO' | 'FOTO_ALUNO' | 'FOTO_SERVIDOR' | 'CONVERSA';
export const DOC_MAX_BYTES = 10 * 1024 * 1024;

/** Foto: reduz para até 900 px e regrava em JPEG — some o EXIF (inclusive a localização) antes de sair do aparelho. */
export async function prepararFoto(file: File): Promise<Blob> {
  if (!['image/jpeg', 'image/png'].includes(file.type) && !file.type.startsWith('image/')) throw new Error('Escolha uma foto (JPEG ou PNG).');
  const bmp = await createImageBitmap(file);
  const escala = Math.min(1, 900 / Math.max(bmp.width, bmp.height));
  const c = document.createElement('canvas');
  c.width = Math.round(bmp.width * escala);
  c.height = Math.round(bmp.height * escala);
  c.getContext('2d')!.drawImage(bmp, 0, 0, c.width, c.height);
  return await new Promise<Blob>((ok, erro) => c.toBlob((b) => (b ? ok(b) : erro(new Error('Não foi possível preparar a foto.'))), 'image/jpeg', 0.86));
}

export async function enviarArquivo(params: { finalidade: Finalidade; student_id?: string; staff_id?: string; doc_type?: string; origem?: string; nome?: string }, corpo: Blob): Promise<any> {
  if (corpo.size > DOC_MAX_BYTES) throw new ApiError('Arquivo maior que 10 MB.', 413);
  const q = new URLSearchParams(Object.entries(params).filter(([, v]) => v) as [string, string][]);
  let res: Response;
  try {
    res = await fetch(`${API_URL}/arquivo?${q}`, {
      method: 'POST', body: corpo,
      headers: { 'content-type': corpo.type || 'application/octet-stream', ...(apiToken() ? { 'x-iara-session': apiToken()! } : {}) },
    });
  } catch {
    throw new ApiError('Sem conexão com o servidor. Verifique a internet e tente novamente.', 0, 'OFFLINE');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError((data as { error?: string }).error ?? 'O arquivo não foi enviado.', res.status, (data as { code?: string }).code);
  return data;
}

export async function baixarArquivo(id: string): Promise<Blob> {
  const res = await fetch(`${API_URL}/arquivo/${id}`, { headers: apiToken() ? { 'x-iara-session': apiToken()! } : {} });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new ApiError((data as { error?: string }).error ?? 'Arquivo indisponível.', res.status);
  }
  return await res.blob();
}

/** Endereço local (blob:) do arquivo, guardado em cache por 10 minutos. */
export function useArquivoUrl(id: string | null | undefined) {
  return useQuery({
    queryKey: ['arquivo', id],
    queryFn: async () => URL.createObjectURL(await baixarArquivo(id!)),
    enabled: !!id,
    staleTime: 10 * 60_000,
    gcTime: 30 * 60_000,
    retry: false,
  });
}

export async function abrirArquivo(id: string) {
  const janela = window.open('', '_blank');
  try {
    const url = URL.createObjectURL(await baixarArquivo(id));
    if (janela) janela.location.href = url;
    else window.location.href = url;
  } catch (e) {
    janela?.close();
    throw e;
  }
}
