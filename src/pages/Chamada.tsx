import { useEffect, useMemo, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { CalendarCheck, CalendarX, Check, CheckCheck, Clock, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, fmtInt, plural } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { diaLongo, hojeISO, pctTone } from '@/lib/escola';
import { Avatar, Badge, Button, Card, EmptyState, ErrorState, PageHeader, SkeletonList, Simulado, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { useToast } from '@/components/overlays';

/** Chamada do dia: um aluno por linha; toque alterna presente/falta. Justificada (atestado) fica marcada. */
export default function Chamada() {
  const { id } = useParams();
  const [sp, setSp] = useSearchParams();
  const data = sp.get('data') ?? hojeISO();
  const res = useRpc<any>('frequencia_turma', { class_id: id, data });
  const qc = useQueryClient();
  const toast = useToast();
  const [faltas, setFaltas] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [mudou, setMudou] = useState(false);

  useEffect(() => {
    if (!res.data) return;
    const f: Record<string, string> = {};
    for (const a of res.data.alunos as any[]) if (a.falta) f[a.id] = a.falta;
    setFaltas(f);
    setMudou(false);
  }, [res.data]);

  const alunos = (res.data?.alunos ?? []) as any[];
  const nFaltas = useMemo(() => Object.keys(faltas).length, [faltas]);

  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;

  const alternar = (a: any) => {
    if (!d.pode_lancar || !d.dia_letivo) return;
    setFaltas((f) => {
      const n = { ...f };
      if (n[a.id]) delete n[a.id];
      else n[a.id] = 'FALTA';
      return n;
    });
    setMudou(true);
  };
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('frequencia_lancar', { class_id: id, data, faltas: Object.keys(faltas) });
      toast({ title: 'Chamada registrada', description: `${fmtInt(alunos.length - nFaltas)} presentes e ${fmtInt(nFaltas)} falta(s). A família vê no portal e pela IARA.`, tone: 'success' });
      ['frequencia_turma', 'frequencia_painel', 'familia_frequencia'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
    } catch (e) {
      toast({ title: 'Chamada não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="pb-24">
      <PageHeader
        eyebrow={<span className="inline-flex items-center gap-1">{d.turma.unidade}<Simulado detail="Alunos e faltas são fictícios; a turma e a unidade seguem o Censo 2025." /></span>}
        title={`Chamada · ${d.turma.nome}`}
        subtitle={`Turno ${SHIFT[d.turma.turno]?.toLowerCase() ?? ''} · ${diaLongo(data)}`}
        actions={<Link to={`/turmas/${id}`} className="text-[13px] font-semibold text-blue-700">Ver a turma</Link>}
      />

      <Card className="mb-3 flex flex-wrap items-center gap-3 p-3">
        <input type="date" value={data} max={hojeISO()} onChange={(e) => e.target.value && setSp({ data: e.target.value }, { replace: true })}
          className={clsx(inputCls, 'h-10 w-auto')} aria-label="Dia da chamada" />
        {d.registrado ? (
          <Badge tone="green" icon={CalendarCheck}>Registrada · {d.registrado_por} · {fmtDateTime(d.registrado_em)}</Badge>
        ) : d.dia_letivo ? <Badge tone="amber" icon={Clock}>Ainda sem chamada neste dia</Badge> : null}
        <div className="ml-auto flex gap-3 text-[13px] font-semibold">
          <span className="text-green-700">{plural(alunos.length - nFaltas, 'presente', 'presentes')}</span>
          <span className="text-red-700">{plural(nFaltas, 'falta', 'faltas')}</span>
        </div>
      </Card>

      {!d.dia_letivo ? (
        <Card className="p-2">
          <EmptyState compact title="Dia sem aula" body={d.evento ? `${d.evento.titulo}. Não há chamada neste dia.` : 'Fim de semana ou fora do ano letivo.'} />
        </Card>
      ) : (
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(200px,1fr) 90px 140px" largura={460} rotulo="Alunos da turma">
            <TCabecalho><TCelula>Aluno</TCelula><TCelula>Frequência</TCelula><TCelula className="text-right">Hoje</TCelula></TCabecalho>
            {alunos.map((a) => {
              const f = faltas[a.id];
              return (
                <TLinha key={a.id} onClick={d.pode_lancar ? () => alternar(a) : undefined} alerta={!!f} rotulo={`${a.nome}: ${f ? 'falta' : 'presente'}`}>
                  <TCelula fixa titulo={a.nome}>
                    <span className="flex min-w-0 items-center gap-2">
                      <Avatar name={a.social ?? a.nome} seed={a.id} size={30} />
                      <span className="truncate font-semibold">{a.social ?? a.nome}</span>
                      {a.aee && <Badge tone="purple">AEE</Badge>}
                    </span>
                  </TCelula>
                  <TCelula><Badge tone={pctTone(a.percentual)}>{a.percentual != null ? `${String(a.percentual).replace('.', ',')}%` : '—'}</Badge></TCelula>
                  <TCelula livre className="flex justify-end">
                    {f === 'FALTA_JUSTIFICADA' ? (
                      <span className="inline-flex h-8 items-center gap-1 rounded-full bg-amber-100 px-3 text-[12.5px] font-bold text-amber-900" title={a.justificativa ?? ''}>Justificada</span>
                    ) : f ? (
                      <span className="inline-flex h-8 items-center gap-1 rounded-full bg-red-600 px-3 text-[12.5px] font-bold text-white"><X className="size-4" />Falta</span>
                    ) : (
                      <span className="inline-flex h-8 items-center gap-1 rounded-full bg-green-100 px-3 text-[12.5px] font-bold text-green-800"><Check className="size-4" />Presente</span>
                    )}
                  </TCelula>
                </TLinha>
              );
            })}
          </Tabela>
          {!alunos.length && <EmptyState compact title="Turma sem alunos ativos" />}
        </Card>
      )}

      {d.pode_lancar && d.dia_letivo && alunos.length > 0 && (
        <div className="fixed inset-x-0 bottom-[72px] z-30 px-4 lg:bottom-6 lg:left-auto lg:right-8 lg:w-[420px] lg:px-0">
          <Card className="flex items-center gap-2 p-2 shadow-lift">
            <Button variant="secondary" icon={CheckCheck} onClick={() => { setFaltas({}); setMudou(true); }} disabled={!nFaltas}>Todos presentes</Button>
            <Button className="flex-1" variant="success" icon={d.registrado && !mudou ? CalendarCheck : CalendarX} loading={busy} onClick={salvar}
              disabled={d.registrado && !mudou}>
              {d.registrado ? (mudou ? 'Salvar alterações' : 'Chamada salva') : 'Registrar chamada'}
            </Button>
          </Card>
        </div>
      )}
      {!d.pode_lancar && (
        <p className="mt-3 text-center text-[12.5px] text-muted">Seu perfil consulta esta chamada; quem lança é o(a) professor(a) da turma ou a secretaria da unidade.</p>
      )}
    </div>
  );
}
