import { useState } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import clsx from 'clsx';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { TIPO_CALENDARIO, diaCurto } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, PageHeader, SkeletonList } from '@/components/ui';
import { UnitSelect } from '@/components/escola';

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** Calendário escolar: feriados de lei, dias sem aula, reuniões, conselhos e prazos (rede + unidade). */
export default function Calendario() {
  const { me } = useSession();
  const hoje = new Date();
  const [ano, setAno] = useState(hoje.getFullYear());
  const [mes, setMes] = useState(hoje.getMonth());
  const rede = me && me.scope !== 'UNIT' && me.scope !== 'GUARDIAN';
  const [unit, setUnit] = useState<number | null>(null);
  const de = `${ano}-${String(mes + 1).padStart(2, '0')}-01`;
  const fim = new Date(ano, mes + 1, 0).getDate();
  const ate = `${ano}-${String(mes + 1).padStart(2, '0')}-${fim}`;
  const res = useRpc<any[]>('calendario', { de, ate, unit_id: unit });
  const mover = (n: number) => {
    const d = new Date(ano, mes + n, 1);
    setAno(d.getFullYear());
    setMes(d.getMonth());
  };
  const itens = res.data ?? [];
  const semAula = new Set<string>();
  for (const e of itens) if (e.sem_aula) for (let d = new Date(e.inicio + 'T12:00'); d <= new Date(e.fim + 'T12:00'); d.setDate(d.getDate() + 1)) semAula.add(d.toISOString().slice(0, 10));
  const primeiro = new Date(ano, mes, 1).getDay();
  const hojeISO = `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}-${String(hoje.getDate()).padStart(2, '0')}`;

  return (
    <div>
      <PageHeader eyebrow="Ano letivo de 2026" title="Calendário escolar"
        subtitle="Feriados e datas cívicas reais de 2026; reuniões, conselhos e eventos das unidades são de demonstração."
        actions={rede ? <UnitSelect value={unit} onChange={setUnit} todas="Só a rede" /> : undefined} />
      <div className="mb-3 flex items-center gap-2">
        <Button size="sm" variant="secondary" icon={ChevronLeft} onClick={() => mover(-1)} aria-label="Mês anterior" />
        <h2 className="min-w-[160px] text-center font-display text-lg font-extrabold capitalize">{MESES[mes]} de {ano}</h2>
        <Button size="sm" variant="secondary" icon={ChevronRight} onClick={() => mover(1)} aria-label="Próximo mês" />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[360px_1fr]">
        <Card className="p-3">
          <div className="grid grid-cols-7 gap-1 text-center text-[11px] font-bold uppercase text-subtle">
            {['D', 'S', 'T', 'Q', 'Q', 'S', 'S'].map((d, i) => <div key={i}>{d}</div>)}
          </div>
          <div className="mt-1 grid grid-cols-7 gap-1">
            {Array.from({ length: primeiro }).map((_, i) => <div key={'v' + i} />)}
            {Array.from({ length: fim }).map((_, i) => {
              const iso = `${ano}-${String(mes + 1).padStart(2, '0')}-${String(i + 1).padStart(2, '0')}`;
              const dow = new Date(ano, mes, i + 1).getDay();
              const tem = itens.some((e) => iso >= e.inicio && iso <= e.fim);
              return (
                <div key={iso} className={clsx('flex aspect-square flex-col items-center justify-center rounded-xl text-[13px] font-semibold',
                  iso === hojeISO ? 'bg-purple-700 text-white' : semAula.has(iso) ? 'bg-red-50 text-red-700' : dow === 0 || dow === 6 ? 'text-subtle' : 'bg-slate-50')}>
                  {i + 1}
                  {tem && <span className={clsx('mt-0.5 size-1.5 rounded-full', iso === hojeISO ? 'bg-white' : 'bg-purple-600')} />}
                </div>
              );
            })}
          </div>
          <p className="mt-2 text-[11.5px] text-muted"><span className="mr-1 inline-block size-2.5 rounded bg-red-100 align-middle" />sem aula · <span className="mx-1 inline-block size-1.5 rounded-full bg-purple-600 align-middle" />há evento</p>
        </Card>
        {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
          <Card className="divide-y divide-line overflow-hidden">
            {itens.length ? itens.map((e) => (
              <div key={e.id} className="flex items-center gap-3 px-4 py-2.5">
                <span className="w-[120px] shrink-0 text-[12.5px] font-semibold capitalize">{diaCurto(e.inicio)}{e.fim !== e.inicio ? ` a ${e.fim.slice(8, 10)}/${e.fim.slice(5, 7)}` : ''}</span>
                <span className="min-w-0 flex-1 truncate text-[13.5px] font-semibold" title={e.descricao ?? e.titulo}>{e.titulo}</span>
                <span className="hidden truncate text-[12px] text-muted md:block">{e.unidade ?? 'Rede'}</span>
                <Badge tone={TIPO_CALENDARIO[e.tipo]?.tone ?? 'gray'}>{e.sem_aula ? 'Sem aula' : TIPO_CALENDARIO[e.tipo]?.label ?? e.tipo}</Badge>
              </div>
            )) : <EmptyState compact title="Nada neste mês" />}
          </Card>
        )}
      </div>
    </div>
  );
}
