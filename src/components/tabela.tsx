import { createContext, useContext, type CSSProperties, type ReactNode } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';

const Colunas = createContext('1fr');

/**
 * Lista em linha única: um registro por linha, com colunas alinhadas (grade CSS).
 * Se não couber na largura, a tabela rola na horizontal e a coluna marcada como `fixa` fica parada à esquerda.
 */
export function Tabela({ colunas, largura, rotulo, className, children }: {
  colunas: string; largura: number; rotulo: string; className?: string; children: ReactNode;
}) {
  return (
    <div role="region" aria-label={rotulo} tabIndex={0} className={clsx('overflow-x-auto overscroll-x-contain focus-visible:outline-none', className)}>
      <div role="table" aria-label={rotulo} style={{ minWidth: largura }}>
        <Colunas.Provider value={colunas}>{children}</Colunas.Provider>
      </div>
    </div>
  );
}

export function TCabecalho({ children }: { children: ReactNode }) {
  const colunas = useContext(Colunas);
  return (
    <div role="row" style={{ gridTemplateColumns: colunas }}
      className="sticky top-0 z-[2] grid items-center gap-x-3 border-b border-line bg-slate-50 px-3 py-2 text-[11px] font-bold uppercase tracking-wide text-subtle">
      {children}
    </div>
  );
}

export function TLinha({ to, onClick, ativo, alerta, rotulo, className, children }: {
  to?: string; onClick?: () => void; ativo?: boolean; alerta?: boolean; rotulo?: string; className?: string; children: ReactNode;
}) {
  const colunas = useContext(Colunas);
  const style: CSSProperties = { gridTemplateColumns: colunas };
  const cls = clsx('group grid min-h-11 w-full items-center gap-x-3 border-b border-line/60 px-3 py-1.5 text-left text-[13.5px] transition last:border-b-0',
    ativo ? 'bg-purple-50' : alerta ? 'bg-red-50 hover:bg-red-100/70' : 'bg-white hover:bg-slate-50', className);
  if (to) return <Link role="row" to={to} aria-label={rotulo} className={cls} style={style}>{children}</Link>;
  if (onClick) return <button type="button" role="row" onClick={onClick} aria-label={rotulo} aria-current={ativo || undefined} className={cls} style={style}>{children}</button>;
  return <div role="row" className={cls} style={style}>{children}</div>;
}

/**
 * Célula de uma linha: nunca quebra; o excesso vira reticências (o texto completo fica no `titulo`).
 * `livre`: não corta (avatar com borda, selos).
 */
export function TCelula({ titulo, fixa, livre, className, children }: { titulo?: string; fixa?: boolean; livre?: boolean; className?: string; children?: ReactNode }) {
  return (
    <div role="cell" title={titulo}
      className={clsx('min-w-0 whitespace-nowrap', livre ? 'overflow-visible' : 'truncate', fixa && 'sticky left-0 z-[1] -ml-3 bg-inherit pl-3', className)}>
      {children}
    </div>
  );
}
