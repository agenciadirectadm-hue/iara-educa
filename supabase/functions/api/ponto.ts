// Ponto dos profissionais com a biometria do próprio aparelho (WebAuthn / FIDO2).
// A biometria (digital, rosto ou bloqueio de tela) é conferida pelo próprio aparelho, que assina o desafio do IARA com uma
// chave que nunca sai dele; aqui conferimos a assinatura com a chave pública guardada no cadastro. Só depois disso o banco
// registra a marcação (iara.ponto_gateway_*, executadas como sistema; o navegador não as alcança).
//   POST /ponto/biometria/opcoes    { tipo: CADASTRO | MARCACAO }   → opções para o navegador (desafio de uso único, 5 min)
//   POST /ponto/biometria/cadastrar { resposta, aparelho? }        → guarda a credencial (só a chave pública)
//   POST /ponto/marcar              { resposta, lat?, lng?, precisao? } → entrada ou saída, com a distância até a unidade
import { asSystem, sql, type RequestMeta } from "./db.ts";

const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const deB64url = (s: string) =>
  Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));

class ErroPonto extends Error {
  code = "22023";
}

// o detalhe da recusa fica no log (pode citar o desafio esperado); a pessoa vê uma mensagem simples
const recusar = (e: Error): never => {
  console.error("ponto: biometria recusada:", e.message.slice(0, 200));
  throw new ErroPonto("A biometria não foi confirmada. Tente de novo.");
};

async function gw(userId: string, meta: RequestMeta, fn: string, p: unknown): Promise<Record<string, unknown>> {
  const r = await asSystem(userId, meta, (tx) => tx.unsafe(`select iara.${fn}($1::jsonb) as r`, [sql.json(p as never) as never]));
  return ((r as unknown as { r: Record<string, unknown> }[])[0]?.r) ?? {};
}

// descrição curta do aparelho para a lista "biometrias cadastradas" (sem identificar o aparelho)
function aparelhoDe(ua: string): string {
  const so = /iPhone|iPad/.test(ua) ? "iPhone/iPad" : /Android/.test(ua) ? "Android" : /Windows/.test(ua) ? "Windows"
    : /Mac OS X/.test(ua) ? "Mac" : /Linux/.test(ua) ? "Linux" : "Aparelho";
  const nav = /Edg\//.test(ua) ? "Edge" : /SamsungBrowser/.test(ua) ? "Samsung Internet" : /Firefox\//.test(ua) ? "Firefox"
    : /Chrome\//.test(ua) ? "Chrome" : /Safari\//.test(ua) ? "Safari" : "navegador";
  return `${so} · ${nav}`;
}

/** origem: a do portal que chamou (já conferida na lista de CORS); a credencial fica presa ao domínio dela */
export async function pontoBiometria(acao: string, userId: string, meta: RequestMeta, origem: string, corpo: Record<string, unknown>) {
  const rpID = new URL(origem).hostname;
  // carregado só aqui: o restante do gateway não depende do pacote
  const w = await import("npm:@simplewebauthn/server@13.2.2");

  if (acao === "opcoes") {
    const tipo = corpo.tipo === "CADASTRO" ? "CADASTRO" : "MARCACAO";
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    const info = (await gw(userId, meta, "ponto_gateway_desafio", { tipo, desafio: b64url(bytes), rp_id: rpID })) as {
      staff_id: string; nome: string; credenciais: { id: string; transports: string[] }[];
    };
    const creds = info.credenciais.map((c) => ({ id: c.id, transports: (c.transports ?? []) as never[] }));
    if (tipo === "CADASTRO") {
      return await w.generateRegistrationOptions({
        rpName: "IARA Educa", rpID, userName: info.nome, userDisplayName: info.nome, userID: new TextEncoder().encode(info.staff_id),
        challenge: bytes, attestationType: "none", excludeCredentials: creds, timeout: 120_000,
        authenticatorSelection: { authenticatorAttachment: "platform", residentKey: "preferred", userVerification: "required" },
      });
    }
    return await w.generateAuthenticationOptions({ rpID, challenge: bytes, allowCredentials: creds, userVerification: "required", timeout: 120_000 });
  }

  const resposta = corpo.resposta as { id?: string } | undefined;
  if (!resposta?.id) throw new ErroPonto("Resposta da biometria ausente.");

  if (acao === "cadastrar") {
    const { desafio } = (await gw(userId, meta, "ponto_gateway_conferir", { tipo: "CADASTRO", rp_id: rpID })) as { desafio: string };
    const v = await w.verifyRegistrationResponse({
      response: resposta as never, expectedChallenge: desafio, expectedOrigin: origem, expectedRPID: rpID, requireUserVerification: true,
    }).catch(recusar);
    if (!v.verified) throw new ErroPonto("A biometria não foi confirmada. Tente de novo.");
    const c = v.registrationInfo.credential;
    return await gw(userId, meta, "ponto_gateway_cadastrar", {
      credencial: c.id, chave_publica: b64url(c.publicKey), contador: c.counter, transportes: c.transports ?? [], rp_id: rpID,
      aparelho: String(corpo.aparelho ?? "").slice(0, 60) || aparelhoDe(meta.ua),
    });
  }

  if (acao === "marcar") {
    const conf = (await gw(userId, meta, "ponto_gateway_conferir", { tipo: "MARCACAO", rp_id: rpID, credencial: resposta.id })) as {
      desafio: string; credencial: { id: string; chave_publica: string; contador: number; transportes: string[] };
    };
    const v = await w.verifyAuthenticationResponse({
      response: resposta as never, expectedChallenge: conf.desafio, expectedOrigin: origem, expectedRPID: rpID, requireUserVerification: true,
      credential: { id: conf.credencial.id, publicKey: deB64url(conf.credencial.chave_publica), counter: Number(conf.credencial.contador),
        transports: (conf.credencial.transportes ?? []) as never[] },
    }).catch(recusar);
    if (!v.verified) throw new ErroPonto("A biometria não foi confirmada. Tente de novo.");
    const num = (x: unknown) => (x == null || x === "" || !Number.isFinite(Number(x)) ? null : Number(x));
    return await gw(userId, meta, "ponto_gateway_marcar", {
      credencial: conf.credencial.id, contador: v.authenticationInfo.newCounter,
      lat: num(corpo.lat), lng: num(corpo.lng), precisao: num(corpo.precisao),
    });
  }
  throw new ErroPonto("Ação desconhecida.");
}
