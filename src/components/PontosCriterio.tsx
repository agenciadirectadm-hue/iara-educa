import clsx from 'clsx';

/**
 * Pontos de um critério da fila. Só aparece "+N" quando o critério foi aplicado à criança;
 * os demais mostram "não aplicado" — nunca "+5" em cinza, que parecia somar sem somar.
 */
export function PontosCriterio({ weight, applied, className }: { weight: number; applied: boolean; className?: string }) {
  if (!(weight > 0)) return null;
  return applied ? (
    <span className={clsx('shrink-0 font-bold text-green-700', className)}>+{weight}</span>
  ) : (
    <span className={clsx('shrink-0 text-[12px] font-normal text-muted', className)} title={`Vale ${weight} pontos quando se aplica`}>
      não aplicado
    </span>
  );
}
