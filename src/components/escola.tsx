// Peças compartilhadas da vida escolar: grade de horário, próximos eventos do calendário e cartão do mural.
import { Fragment } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import { CalendarDays, Megaphone } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtInt, timeAgo } from '@/lib/format';
import { DIA_CURTO, TIPO_CALENDARIO, TIPO_MURAL, diaCurto } from '@/lib/escola';
import { Badge, Card, EmptyState, Meter, Skeleton } from '@/components/ui';

/** Escolha de unidade para os perfis da rede (o perfil de unidade não vê o seletor: o servidor fixa a unidade dele). */
export function UnitSelect({ value, onChange, todas = 'Toda a rede', className }: {
  value: number | null; onChange: (id: number | null) => void; todas?: string | null; className?: string;
}) {
  const res = useRpc<{ items: { id: number; name: string }[] }>('persona_units', { q: '' }, { staleTime: 10 * 60_000 });
  return (
    <select value={value ?? ''} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} aria-label="Unidade"
      className={clsx('h-10 rounded-2xl bg-white px-3 text-[14px] font-semibold ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-300', className)}>
      {todas != null && <option value="">{todas}</option>}
      {todas == null && value == null && <option value="">Escolha a unidade…</option>}
      {(res.data?.items ?? []).map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
    </select>
  );
}

/** Grade semanal: linhas = aulas (com horário), colunas = segunda a sexta. */
export function GradeHorario({ aulas, rotulo, celula }: {
  aulas: { dia: number; aula: number; hora?: string | null; turno?: string }[];
  rotulo: string;
  celula: (a: any) => { titulo: string; sub?: string; alerta?: boolean };
}) {
  if (!aulas.length) return <EmptyState compact title="Sem horário cadastrado" />;
  const turnos = [...new Set(aulas.map((a) => a.turno ?? ''))];
  return (
    <div className="space-y-4">
      {turnos.map((t) => {
        const doTurno = aulas.filter((a) => (a.turno ?? '') === t);
        const linhas = [...new Set(doTurno.map((a) => a.aula))].sort((x, y) => x - y);
        return (
          <div key={t} role="region" aria-label={`${rotulo}${t ? ' · ' + t : ''}`} tabIndex={0} className="overflow-x-auto">
            {t && <div className="mb-1.5 text-[12px] font-bold uppercase tracking-wide text-subtle">{t === 'MANHA' ? 'Manhã' : t === 'TARDE' ? 'Tarde' : t === 'NOITE' ? 'Noite' : t}</div>}
            <div className="grid min-w-[620px] gap-1" style={{ gridTemplateColumns: '78px repeat(5, minmax(0, 1fr))' }}>
              <div />
              {[1, 2, 3, 4, 5].map((d) => <div key={d} className="px-1 text-center text-[11.5px] font-bold uppercase text-subtle">{DIA_CURTO[d]}</div>)}
              {linhas.map((l) => (
                <Fragment key={l}>
                  <div className="flex flex-col justify-center rounded-xl bg-slate-50 px-2 py-1 text-[11.5px] ring-1 ring-line">
                    <span className="font-bold">{l}ª aula</span>
                    <span className="text-muted">{doTurno.find((a) => a.aula === l)?.hora ?? ''}</span>
                  </div>
                  {[1, 2, 3, 4, 5].map((d) => {
                    const a = doTurno.find((x) => x.aula === l && x.dia === d);
                    if (!a) return <div key={d} className="rounded-xl bg-slate-50/60" />;
                    const c = celula(a);
                    return (
                      <div key={d} title={`${c.titulo}${c.sub ? ' · ' + c.sub : ''}`}
                        className={clsx('min-w-0 rounded-xl px-2 py-1 text-[11.5px] ring-1', c.alerta ? 'bg-red-50 text-red-900 ring-red-200' : 'bg-white ring-line')}>
                        <div className="truncate font-semibold">{c.titulo}</div>
                        {c.sub && <div className="truncate text-muted">{c.sub}</div>}
                      </div>
                    );
                  })}
                </Fragment>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** Próximos eventos do calendário (rede + unidade do perfil ou dos filhos). */
export function ProximosEventos({ dias = 45, limite = 6, unitId }: { dias?: number; limite?: number; unitId?: number }) {
  const hoje = new Date();
  const ate = new Date(hoje.getTime() + dias * 86400000);
  const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const res = useRpc<any[]>('calendario', { de: iso(hoje), ate: iso(ate), unit_id: unitId ?? null });
  if (res.isLoading) return <Skeleton className="h-40" />;
  const itens = (res.data ?? []).slice(0, limite);
  return (
    <Card className="divide-y divide-line overflow-hidden">
      {itens.length ? itens.map((e) => (
        <div key={e.id} className="flex items-center gap-3 px-4 py-2.5">
          <CalendarDays className="size-4 shrink-0 text-purple-700" />
          <span className="w-[86px] shrink-0 text-[12.5px] font-semibold capitalize text-ink-2">{diaCurto(e.inicio)}</span>
          <span className="min-w-0 flex-1 truncate text-[13.5px] font-semibold" title={e.descricao ?? e.titulo}>{e.titulo}</span>
          {e.unidade && <span className="hidden truncate text-[12px] text-muted sm:block">{e.unidade}</span>}
          <Badge tone={TIPO_CALENDARIO[e.tipo]?.tone ?? 'gray'}>{e.sem_aula ? 'Sem aula' : TIPO_CALENDARIO[e.tipo]?.label ?? e.tipo}</Badge>
        </div>
      )) : <p className="p-4 text-sm text-muted">Nada no calendário nas próximas semanas.</p>}
      <Link to="/calendario" className="block px-4 py-2.5 text-center text-[13px] font-semibold text-blue-700 hover:bg-slate-50">Ver o calendário</Link>
    </Card>
  );
}

/** Uma publicação do mural com o alcance (leituras e ciência) para quem publicou. */
export function PublicacaoCard({ p, acoes }: { p: any; acoes?: React.ReactNode }) {
  const t = TIPO_MURAL[p.tipo] ?? { label: p.tipo, tone: 'gray' as const };
  const alcance = p.destinatarios ? Math.min(100, Math.round((100 * (p.leituras ?? 0)) / p.destinatarios)) : null;
  return (
    <Card className="p-4">
      <div className="flex flex-wrap items-center gap-1.5">
        <Badge tone={t.tone}>{t.label}</Badge>
        <span className="text-[12px] font-semibold text-muted">{p.unidade ?? 'Toda a rede'} · {timeAgo(p.publicado_em)}</span>
        {p.situacao === 'ARQUIVADO' && <Badge tone="gray">Arquivado</Badge>}
        {p.fixado && <Badge tone="purple">Fixado</Badge>}
      </div>
      <h3 className="mt-1.5 font-display text-[17px] font-extrabold leading-snug">{p.titulo}</h3>
      <p className="mt-1 whitespace-pre-line text-[14px] text-ink-2">{p.texto}</p>
      {p.data_evento && <p className="mt-1.5 text-[13px] font-semibold text-teal-800">Data: {diaCurto(p.data_evento)}</p>}
      {p.votos && (
        <div className="mt-3 space-y-1.5">
          {(p.votos as any[]).map((v) => {
            const total = (p.votos as any[]).reduce((s, x) => s + x.votos, 0) || 1;
            return (
              <div key={v.opcao}>
                <div className="flex justify-between text-[12.5px]"><span className="font-semibold">{v.opcao}</span><span className="tabular text-muted">{fmtInt(v.votos)} · {Math.round((100 * v.votos) / total)}%</span></div>
                <Meter value={v.votos} max={total} tone="amber" />
              </div>
            );
          })}
        </div>
      )}
      {p.publico !== 'PROFISSIONAIS' && p.destinatarios > 0 && (
        <div className="mt-3 rounded-2xl bg-slate-50 p-2.5 ring-1 ring-line">
          <div className="flex flex-wrap justify-between gap-2 text-[12.5px]">
            <span><Megaphone className="mr-1 inline size-3.5 text-purple-700" /><b>{fmtInt(p.leituras)}</b> de {fmtInt(p.destinatarios)} famílias leram</span>
            {p.exige_confirmacao && <span className="font-semibold text-green-800">{fmtInt(p.confirmacoes)} confirmaram a ciência</span>}
          </div>
          {alcance != null && <Meter value={alcance} className="mt-1.5" tone="purple" />}
        </div>
      )}
      {acoes && <div className="mt-3 flex flex-wrap gap-2">{acoes}</div>}
    </Card>
  );
}
