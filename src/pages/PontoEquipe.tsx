import { useEffect, useState } from 'react';
import clsx from 'clsx';
import { Check, Fingerprint, Lock, MapPin, X } from 'lucide-react';
import { useRpc, useRpcMutation } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { FUNCAO_SERVIDOR } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Field, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet } from '@/components/overlays';
import { EspelhoMes, Marcas, SITUACAO_PONTO, horas, type DiaPonto, type Espelho } from './MeuPonto';

type Membro = DiaPonto & { staff_id: string; nome: string; funcao: string; cargo: string | null; biometria: boolean };
type Painel = {
  unidade: { id: number; nome: string }; data: string; util: boolean; equipe: Membro[]; demonstracao: boolean;
  contagens: { equipe: number; presentes: number; trabalhando: number; ausentes: number; atrasos: number; fora: number; incompletos: number };
  pendencias: { id: string; staff_id: string; nome: string; data: string; tipo: string; descricao: string; enviada_em: string }[];
  fechamentos: { mes: string; fechado_em: string; por: string }[];
};
const MOTIVOS: Record<string, string> = {
  ESQUECIMENTO: 'Esquecimento', ATESTADO: 'Atestado', SERVICO_EXTERNO: 'Serviço externo', FORMACAO: 'Formação', OUTRO: 'Outro',
};
const hojeIso = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
const mesPassado = () => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 1); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`; };

/** Ponto da equipe (direção e secretaria da unidade): presença do dia, justificativas, ajustes com motivo e fechamento do mês. */
export default function PontoEquipe() {
  const [data, setData] = useState(hojeIso());
  const [filtro, setFiltro] = useState<'todos' | 'ausentes' | 'atrasos' | 'fora'>('todos');
  const [aberto, setAberto] = useState<Membro | null>(null);
  const pn = useRpc<Painel>('ponto_painel', { data });
  const tratar = useRpcMutation('ponto_tratar', ['ponto_painel']);
  const fechar = useRpcMutation('ponto_fechar_mes', ['ponto_painel']);

  if (pn.isLoading) return <SkeletonList rows={6} />;
  if (pn.error) return <ErrorState error={pn.error} onRetry={() => pn.refetch()} />;
  const p = pn.data!;
  const c = p.contagens;
  const lista = p.equipe.filter((m) => filtro === 'todos' ? true : filtro === 'ausentes' ? ['FALTA', 'AGUARDANDO'].includes(m.situacao)
    : filtro === 'atrasos' ? m.atraso_min != null : m.fora);
  const mp = mesPassado();
  const mpFechado = p.fechamentos.some((f) => f.mes === mp);

  return (
    <div>
      <PageHeader eyebrow={p.unidade.nome} title="Ponto da equipe"
        subtitle="Quem já marcou o ponto, atrasos, marcações longe da unidade e justificativas para abonar. Ajustes pedem motivo e ficam na auditoria."
        actions={<input type="date" value={data} max={hojeIso()} onChange={(e) => setData(e.target.value || hojeIso())} aria-label="Dia" className={clsx(inputCls, 'h-10 w-auto')} />} />
      {p.demonstracao && <Simulado detail="Marcações fictícias da equipe, para a demonstração." className="mb-3" />}
      {!p.util && <p className="mb-3 rounded-xl bg-slate-50 p-3 text-[13px] text-ink-2">Este dia não é dia de trabalho (fim de semana ou feriado).</p>}

      <div className="mb-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
        {([['todos', 'Marcaram', `${c.presentes} de ${c.equipe}`, 'text-ink'], ['ausentes', 'Sem marcação', c.ausentes, 'text-red-700'],
          ['atrasos', 'Atrasos', c.atrasos, 'text-amber-700'], ['fora', 'Longe da unidade', c.fora, 'text-amber-700']] as const).map(([k, rot, n, cor]) => (
          <button key={k} type="button" onClick={() => setFiltro(k)} aria-pressed={filtro === k}
            className={clsx('rounded-2xl bg-white p-3 text-left ring-1', filtro === k ? 'ring-2 ring-purple-600' : 'ring-line hover:bg-slate-50')}>
            <div className={clsx('text-[22px] font-extrabold tabular', cor)}>{n}</div>
            <div className="text-[12px] text-muted">{rot}</div>
          </button>
        ))}
        <div className="col-span-2 rounded-2xl bg-white p-3 ring-1 ring-line sm:col-span-1">
          <div className="text-[22px] font-extrabold tabular text-blue-800">{c.trabalhando}</div>
          <div className="text-[12px] text-muted">em jornada agora</div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.5fr_1fr]">
        <Card className="divide-y divide-line">
          {lista.length === 0 && <EmptyState compact title="Ninguém nesta situação." />}
          {lista.map((m) => (
            <button key={m.staff_id} type="button" onClick={() => setAberto(m)} className="block w-full px-3 py-2.5 text-left hover:bg-slate-50">
              <div className="flex items-center gap-2">
                <span className="min-w-0 flex-1 truncate text-[14px] font-semibold">{m.nome}</span>
                {m.biometria && <Fingerprint className="size-4 text-purple-700" aria-label="biometria cadastrada" />}
                {m.fora && <MapPin className="size-4 text-amber-700" aria-label="marcação longe da unidade" />}
                <Badge tone={SITUACAO_PONTO[m.situacao].tom}>{SITUACAO_PONTO[m.situacao].rotulo}{m.atraso_min ? ` ${m.atraso_min} min` : ''}</Badge>
              </div>
              <div className="mt-0.5 text-[12px] text-muted">
                {FUNCAO_SERVIDOR[m.funcao] ?? m.funcao}
                {m.marcacoes.length > 0 && ` · ${m.marcacoes.map((x) => x.hora).join(' · ')}`}
                {m.minutos > 0 && ` · ${horas(m.minutos)}`}
              </div>
            </button>
          ))}
        </Card>

        <div className="space-y-4">
          <Section title="Justificativas para decidir" subtitle={p.pendencias.length ? `${p.pendencias.length} aguardando` : undefined}>
            {p.pendencias.length === 0 ? <p className="text-[13px] text-muted">Nenhuma pendente.</p> : (
              <Card className="divide-y divide-line">
                {p.pendencias.slice(0, 12).map((j) => (
                  <div key={j.id} className="px-3 py-2.5">
                    <div className="text-[13px] font-semibold">{j.nome}</div>
                    <div className="text-[12px] text-muted">{fmtDate(j.data)} · {MOTIVOS[j.tipo] ?? j.tipo}</div>
                    <p className="mt-1 text-[13px] text-ink-2">{j.descricao}</p>
                    <div className="mt-2 flex gap-2">
                      <Button size="sm" variant="success" icon={Check} loading={tratar.isPending} onClick={() => tratar.mutate({ id: j.id, decisao: 'ABONAR' })}>Abonar</Button>
                      <Button size="sm" variant="secondary" icon={X} loading={tratar.isPending} onClick={() => tratar.mutate({ id: j.id, decisao: 'RECUSAR' })}>Recusar</Button>
                    </div>
                  </div>
                ))}
              </Card>
            )}
            {tratar.error && <p role="alert" className="mt-2 text-[13px] font-semibold text-red-700">{tratar.error.message}</p>}
          </Section>

          <Section title="Fechamento do mês">
            <Card className="space-y-2 p-3 text-[13px]">
              {mpFechado ? (
                <p className="flex items-center gap-1.5 text-ink-2"><Lock className="size-4" />O mês passado já está fechado.</p>
              ) : (
                <>
                  <p className="text-ink-2">Fechar o mês passado trava ajustes e abonos daquele mês. Antes, decida as justificativas pendentes dele.</p>
                  <Button size="sm" icon={Lock} loading={fechar.isPending} onClick={() => { if (confirm('Fechar o ponto do mês passado?')) fechar.mutate({ mes: mp }); }}>Fechar o mês passado</Button>
                </>
              )}
              {fechar.error && <p role="alert" className="font-semibold text-red-700">{fechar.error.message}</p>}
              {p.fechamentos.slice(0, 3).map((f) => <p key={f.mes} className="text-[12px] text-muted">{f.mes.split('-').reverse().join('/')}: fechado por {f.por}</p>)}
            </Card>
          </Section>
        </div>
      </div>

      <Pessoa membro={aberto} dia={data} onClose={() => setAberto(null)} />
    </div>
  );
}

function Pessoa({ membro, dia, onClose }: { membro: Membro | null; dia: string; onClose: () => void }) {
  const [mes, setMes] = useState(dia.slice(0, 7));
  const esp = useRpc<Espelho>('ponto_espelho', { staff_id: membro?.staff_id, mes }, { enabled: !!membro });
  const ajustar = useRpcMutation('ponto_ajustar', ['ponto_painel', 'ponto_espelho']);
  const [aj, setAj] = useState({ data: dia, hora: '07:30', tipo: 'ENTRADA', motivo: '' });
  useEffect(() => { setAj({ data: dia, hora: '07:30', tipo: 'ENTRADA', motivo: '' }); setMes(dia.slice(0, 7)); ajustar.reset(); }, [membro?.staff_id]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Sheet open={!!membro} onClose={onClose} title={membro?.nome} subtitle={membro ? FUNCAO_SERVIDOR[membro.funcao] ?? membro.funcao : undefined} size="lg">
      {membro && (
        <div className="space-y-4">
          <Card className="p-3">
            <div className="flex items-center justify-between text-[13px]">
              <b>{fmtDate(dia)}</b>
              <Badge tone={SITUACAO_PONTO[membro.situacao].tom}>{SITUACAO_PONTO[membro.situacao].rotulo}</Badge>
            </div>
            <Marcas dia={membro} />
          </Card>

          <Section title="Lançar marcação (ajuste)" subtitle="Para esquecimento comprovado ou aparelho sem biometria. Fica registrado com o seu nome e o motivo.">
            <Card className="grid grid-cols-2 gap-2 p-3 sm:grid-cols-4">
              <Field label="Dia"><input type="date" value={aj.data} max={hojeIso()} onChange={(e) => setAj({ ...aj, data: e.target.value })} className={inputCls} /></Field>
              <Field label="Hora"><input type="time" value={aj.hora} onChange={(e) => setAj({ ...aj, hora: e.target.value })} className={inputCls} /></Field>
              <Field label="Tipo">
                <select value={aj.tipo} onChange={(e) => setAj({ ...aj, tipo: e.target.value })} className={inputCls}>
                  <option value="ENTRADA">Entrada</option><option value="SAIDA">Saída</option>
                </select>
              </Field>
              <div className="col-span-2 sm:col-span-4">
                <Field label="Motivo"><input value={aj.motivo} onChange={(e) => setAj({ ...aj, motivo: e.target.value })} maxLength={300} className={inputCls}
                  placeholder="Ex.: entrada conferida pela direção; aparelho sem biometria" /></Field>
              </div>
              <div className="col-span-2 sm:col-span-4">
                <Button size="sm" loading={ajustar.isPending} disabled={aj.motivo.trim().length < 10}
                  onClick={() => ajustar.mutate({ staff_id: membro.staff_id, ...aj }, { onSuccess: () => setAj({ ...aj, motivo: '' }) })}>Lançar ajuste</Button>
                {ajustar.error && <p role="alert" className="mt-2 text-[13px] font-semibold text-red-700">{ajustar.error.message}</p>}
                {ajustar.isSuccess && <p role="status" className="mt-2 text-[13px] font-semibold text-green-700">Ajuste lançado.</p>}
              </div>
            </Card>
          </Section>

          <EspelhoMes esp={esp} mes={mes} setMes={setMes} />
        </div>
      )}
    </Sheet>
  );
}
