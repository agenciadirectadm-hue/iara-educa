// Senha de acesso ao portal. Com ela ligada, só entra quem digitou a senha neste aparelho: o servidor não cria sessão
// nem responde consulta sem sessão a quem não tem o passe. O segredo IARA_ACESSO guarda só o hash da senha
// (pbkdf2$<iterações>$<sal em base64>$<hash em base64>), gravado por scripts/definir-senha-acesso.ps1. Sem o segredo, o portal
// fica aberto como antes. Trocar a senha derruba todos os passes, porque eles são assinados com o próprio hash.

const SEGREDO = Deno.env.get("IARA_ACESSO") ?? "";
const enc = new TextEncoder();

export const acessoAtivo = () => SEGREDO.startsWith("pbkdf2$");

const deB64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const b64url = (u: Uint8Array) => btoa(String.fromCharCode(...u)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function iguais(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

export async function senhaConfere(senha: string): Promise<boolean> {
  if (!acessoAtivo()) return true;
  const [, iter, sal, hash] = SEGREDO.split("$");
  if (!iter || !sal || !hash) return false;
  const chave = await crypto.subtle.importKey("raw", enc.encode(senha.normalize("NFC")), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: deB64(sal), iterations: Number(iter) }, chave, 256);
  return iguais(new Uint8Array(bits), deB64(hash));
}

async function assinatura(dados: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", enc.encode(SEGREDO), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64url(new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(dados))));
}

/** Passe da aba aberta: o site o perde ao fechar a aba; aqui ele vale no máximo 12 horas e cai quando a senha muda. */
export async function emitirPasse(horas = 12): Promise<string> {
  const corpo = `v1.${Math.floor(Date.now() / 1000) + horas * 3600}.${b64url(crypto.getRandomValues(new Uint8Array(9)))}`;
  return `${corpo}.${await assinatura(corpo)}`;
}

export async function passeValido(passe: string | null): Promise<boolean> {
  if (!acessoAtivo()) return true;
  const p = (passe ?? "").split(".");
  if (p.length !== 4 || p[0] !== "v1" || !(Number(p[1]) > Date.now() / 1000)) return false;
  return iguais(enc.encode(await assinatura(p.slice(0, 3).join("."))), enc.encode(p[3]));
}
