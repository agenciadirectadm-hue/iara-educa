// Depois de uma publicação, uma aba aberta pode pedir um pedaço do site que já não existe no servidor. Recarregar resolve, mas o service
// worker pode entregar a página antiga na primeira vez: por isso até duas tentativas seguidas, e depois disso quem decide é a pessoa.
const CHAVE = 'iara-recarga-versao';
const JANELA_MS = 60_000;
const TENTATIVAS = 2;

export function erroDeVersao(e: unknown): boolean {
  const msg = String((e as Error | undefined)?.message ?? e ?? '');
  return /dynamically imported module|Importing a module script failed|error loading dynamically imported|Unable to preload CSS|ChunkLoadError/i.test(msg);
}

/** Recarrega se ainda há tentativa. Devolve false quando já tentou (ou quando não dá para contar, para nunca entrar em laço). */
export async function recarregarNovaVersao(): Promise<boolean> {
  const agora = Date.now();
  let feitas = 0;
  try {
    const salvo = JSON.parse(sessionStorage.getItem(CHAVE) ?? 'null') as { n: number; em: number } | null;
    if (salvo && agora - salvo.em < JANELA_MS) feitas = salvo.n;
    if (feitas >= TENTATIVAS) return false;
    sessionStorage.setItem(CHAVE, JSON.stringify({ n: feitas + 1, em: agora }));
  } catch {
    return false;
  }
  try {
    const regs = await navigator.serviceWorker?.getRegistrations();
    await Promise.race([
      Promise.all((regs ?? []).map((r) => r.update())),
      new Promise((pronto) => setTimeout(pronto, 3000)),
    ]);
  } catch {
    // sem service worker, ou sem rede para procurar: recarrega do mesmo jeito
  }
  window.location.reload();
  return true;
}
