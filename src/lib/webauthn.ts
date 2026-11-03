// Biometria do aparelho (WebAuthn): converte as opções do gateway (JSON, base64url) para a API do navegador e a resposta de
// volta para JSON. A biometria é conferida pelo próprio aparelho; o que sai daqui é só a assinatura do desafio.
const deB64 = (s: string) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));
const paraB64 = (b: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

type Cred = { id: string; type: string; transports?: string[] };

/** o aparelho tem biometria ou bloqueio de tela que o navegador consegue usar */
export async function biometriaDisponivel(): Promise<boolean> {
  try {
    return !!window.PublicKeyCredential && (await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable());
  } catch {
    return false;
  }
}

function erroAmigavel(e: unknown): Error {
  const n = (e as DOMException)?.name;
  if (n === 'NotAllowedError') return new Error('A biometria foi cancelada ou o tempo acabou. Tente de novo.');
  if (n === 'InvalidStateError') return new Error('Este aparelho já está cadastrado para o seu ponto.');
  if (n === 'SecurityError') return new Error('Abra o IARA pelo endereço oficial para usar a biometria.');
  return new Error('Não consegui usar a biometria deste aparelho.');
}

export async function criarCredencial(o: any) {
  let c: PublicKeyCredential | null;
  try {
    c = (await navigator.credentials.create({
      publicKey: {
        ...o, challenge: deB64(o.challenge), user: { ...o.user, id: deB64(o.user.id) },
        excludeCredentials: (o.excludeCredentials ?? []).map((x: Cred) => ({ ...x, id: deB64(x.id) })),
      },
    })) as PublicKeyCredential | null;
  } catch (e) {
    throw erroAmigavel(e);
  }
  if (!c) throw new Error('O cadastro da biometria foi cancelado.');
  const r = c.response as AuthenticatorAttestationResponse;
  return {
    id: c.id, rawId: paraB64(c.rawId), type: c.type, authenticatorAttachment: c.authenticatorAttachment ?? undefined,
    clientExtensionResults: c.getClientExtensionResults(),
    response: { clientDataJSON: paraB64(r.clientDataJSON), attestationObject: paraB64(r.attestationObject), transports: r.getTransports?.() ?? [] },
  };
}

export async function usarCredencial(o: any) {
  let c: PublicKeyCredential | null;
  try {
    c = (await navigator.credentials.get({
      publicKey: { ...o, challenge: deB64(o.challenge), allowCredentials: (o.allowCredentials ?? []).map((x: Cred) => ({ ...x, id: deB64(x.id) })) },
    })) as PublicKeyCredential | null;
  } catch (e) {
    throw erroAmigavel(e);
  }
  if (!c) throw new Error('A biometria foi cancelada.');
  const r = c.response as AuthenticatorAssertionResponse;
  return {
    id: c.id, rawId: paraB64(c.rawId), type: c.type, authenticatorAttachment: c.authenticatorAttachment ?? undefined,
    clientExtensionResults: c.getClientExtensionResults(),
    response: {
      clientDataJSON: paraB64(r.clientDataJSON), authenticatorData: paraB64(r.authenticatorData), signature: paraB64(r.signature),
      userHandle: r.userHandle ? paraB64(r.userHandle) : undefined,
    },
  };
}
