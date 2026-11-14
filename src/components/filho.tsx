import { createContext, useContext } from 'react';

/** O filho escolhido na Vida escolar da família: cada aba mostra só o que é dele. */
export type FilhoEscolhido = { id: string; nome: string };

const Ctx = createContext<FilhoEscolhido | null>(null);
export const FilhoEscolhidoProvider = Ctx.Provider;

/** Filho escolhido na Vida escolar; fora dela é null e as listas mostram todos os filhos. */
export function useFilhoEscolhido() {
  return useContext(Ctx);
}

const porAluno = (x: unknown) => (x as { student_id?: string } | null)?.student_id;

/** Deixa na lista só o que é do filho (sem filho escolhido, devolve a lista inteira). */
export function soDoFilho<T>(filho: FilhoEscolhido | null, lista: T[] | null | undefined, chave: (x: T) => unknown = porAluno): T[] {
  return !filho ? (lista ?? []) : (lista ?? []).filter((x) => chave(x) === filho.id);
}

/** Versão em hook de soDoFilho, para os componentes das abas. Chamar antes de qualquer retorno antecipado. */
export function useSoDoFilho() {
  const filho = useContext(Ctx);
  return <T,>(lista: T[] | null | undefined, chave?: (x: T) => unknown) => soDoFilho(filho, lista, chave);
}
