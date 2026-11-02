/** Regra única de cores dos mapas: toda medida vira verde, amarelo ou vermelho; cinza é sem dado (ou sigilo).
 * Vermelho = agir primeiro (o terço com a pior situação), amarelo = intermediário, verde = o terço com a melhor situação.
 * Os cortes são os terços dos próprios valores mostrados (regiões, microrregiões, escolas ou pontos), então a leitura é
 * sempre a mesma em qualquer mapa. Localização (unidade sem medida) usa uma cor neutra. */

export const SEMAFORO = { vermelho: '#DC2626', amarelo: '#EAB308', verde: '#16A34A', cinza: '#CBD3DE' } as const;
export type Classe = 'vermelho' | 'amarelo' | 'verde';
/** "maior": quanto maior o valor, pior (fila, faltas…); "menor": quanto menor, pior (vagas, presença…). */
export type Pior = 'maior' | 'menor';

export type Cortes = { t1: number; t2: number; pior: Pior };

/** Terços dos valores (sem os nulos). */
export function cortes(valores: (number | null | undefined)[], pior: Pior): Cortes | null {
  const v = valores.filter((x): x is number => x != null && Number.isFinite(x)).sort((a, b) => a - b);
  if (!v.length) return null;
  const q = (p: number) => v[Math.min(v.length - 1, Math.floor(p * (v.length - 1)))];
  return { t1: q(1 / 3), t2: q(2 / 3), pior };
}

/** Classe de um valor. Empates ficam na ponta de baixo: zero falta é verde; zero vaga é vermelho. */
export function classe(v: number | null | undefined, c: Cortes | null): Classe | null {
  if (v == null || !Number.isFinite(v) || !c) return null;
  if (c.pior === 'maior') return v <= c.t1 ? 'verde' : v > c.t2 ? 'vermelho' : 'amarelo';
  return v <= c.t1 ? 'vermelho' : v > c.t2 ? 'verde' : 'amarelo';
}

export const corDe = (k: Classe | null) => (k ? SEMAFORO[k] : SEMAFORO.cinza);

const fmt = (v: number, sufixo: string) => `${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}${sufixo}`;

/** Itens da legenda, do vermelho ao verde, com a faixa de valores de cada cor. */
export function legenda(c: Cortes | null, palavras: { pior: string; melhor: string }, sufixo = '', semDado?: string | null) {
  const itens: { cor: string; rotulo: string }[] = [];
  if (c) {
    const [baixo, alto] = [fmt(c.t1, sufixo), fmt(c.t2, sufixo)];
    const faixaPior = c.pior === 'maior' ? `acima de ${alto}` : `até ${baixo}`;
    const faixaMelhor = c.pior === 'maior' ? `até ${baixo}` : `acima de ${alto}`;
    itens.push({ cor: SEMAFORO.vermelho, rotulo: `${palavras.pior} (${faixaPior})` });
    itens.push({ cor: SEMAFORO.amarelo, rotulo: c.t1 === c.t2 ? 'Intermediário' : `Intermediário (${baixo} a ${alto})` });
    itens.push({ cor: SEMAFORO.verde, rotulo: `${palavras.melhor} (${faixaMelhor})` });
  }
  if (semDado) itens.push({ cor: SEMAFORO.cinza, rotulo: semDado });
  return itens;
}
