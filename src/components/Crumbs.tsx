import { Fragment } from 'react';
import { Link } from 'react-router';
import { ChevronRight, House } from 'lucide-react';

/** Trilha do macro ao micro (cidade → território → unidade → etapa → série → turma → aluno — spec §10.5). */
export function Crumbs({ items }: { items: { label: string; to?: string }[] }) {
  return (
    <nav aria-label="Trilha de navegação" className="no-scrollbar -mx-4 mb-3 overflow-x-auto px-4">
      <ol className="flex w-max items-center gap-1 text-[13px]">
        <li>
          <Link to="/inicio" className="inline-flex size-8 items-center justify-center rounded-xl bg-white text-ink-2 ring-1 ring-line hover:text-purple-700" aria-label="Início">
            <House className="size-4" />
          </Link>
        </li>
        {items.map((it, i) => (
          <Fragment key={i}>
            <ChevronRight className="size-4 shrink-0 text-subtle" aria-hidden />
            <li>
              {it.to && i < items.length - 1 ? (
                <Link to={it.to} className="inline-flex h-8 max-w-[180px] items-center truncate rounded-xl bg-white px-3 font-semibold text-ink-2 ring-1 ring-line hover:text-purple-700">
                  <span className="truncate">{it.label}</span>
                </Link>
              ) : (
                <span className="inline-flex h-8 max-w-[220px] items-center truncate rounded-xl bg-purple-100 px-3 font-bold text-purple-800" aria-current="page">
                  <span className="truncate">{it.label}</span>
                </span>
              )}
            </li>
          </Fragment>
        ))}
      </ol>
    </nav>
  );
}
