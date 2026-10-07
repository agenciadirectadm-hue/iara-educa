import { useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { Award, CalendarRange, CheckCheck, Clock, Plus, Trash2, UserPlus } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt } from '@/lib/format';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

export const TIPO_EVENTO: Record<string, string> = {
  FORMACAO: 'Formação', OFICINA: 'Oficina', PALESTRA: 'Palestra', FEIRA: 'Feira', MOSTRA: 'Mostra', OLIMPIADA: 'Olimpíada', CAMPANHA: 'Campanha', OUTRO: 'Outro',
};
const PUBLICO: Record<string, string> = { SERVIDORES: 'Servidores', ALUNOS: 'Alunos', TODOS: 'Servidores e alunos' };
const SIT_EVENTO: Record<string, { label: string; tone: 'green' | 'amber' | 'blue' | 'gray' | 'purple' }> = {
  INSCRICOES: { label: 'Inscrições', tone: 'blue' }, EM_ANDAMENTO: { label: 'Em andamento', tone: 'purple' }, CONCLUIDO: { label: 'Concluído', tone: 'green' }, CANCELADO: { label: 'Cancelado', tone: 'gray' },
};
const FUNCAO: Record<string, string> = { PARTICIPANTE: 'Participante', PALESTRANTE: 'Palestrante', ORGANIZACAO: 'Organização', PREMIADO: 'Premiado(a)' };

function useRecarregar() {
  const qc = useQueryClient();
  return () => ['eventos_lista', 'evento_detalhe', 'familia_eventos'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Eventos da rede e das escolas: formações (servidores), feiras, mostras e olimpíadas (alunos), com inscrição, presença e certificado verificável. */
export default function Eventos() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const [sit, setSit] = useState('');
  const res = useRpc<any>('eventos_lista', { unit_id: unit, situacao: sit });
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState<any | null>(null);
  const d = res.data;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Eventos e certificados<Simulado detail="Eventos, inscrições e certificados de demonstração." /></span>}
        subtitle="Formações para servidores e feiras, mostras e olimpíadas para alunos. Com a presença registrada, o certificado sai com código de verificação; a família vê no portal e pela IARA."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{d?.pode_criar && <Button icon={Plus} onClick={() => setNovo({})}>Novo evento</Button>}</>} />
      {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Kpi compact icon={CalendarRange} tone="blue" label="Eventos abertos" value={fmtInt(d.resumo.abertos)} onClick={() => setSit('')} />
            <Kpi compact icon={CheckCheck} tone="green" label="Concluídos" value={fmtInt(d.resumo.concluidos)} onClick={() => setSit('CONCLUIDO')} />
            <Kpi compact icon={Award} tone="purple" label="Certificados emitidos" value={fmtInt(d.resumo.certificados)} />
            <Kpi compact icon={Clock} tone="amber" label="Horas de formação certificadas" value={fmtInt(Number(d.resumo.horas))} sub="soma das horas dos servidores" />
          </div>
          <div className="flex flex-wrap gap-1.5">
            <Chip active={!sit} onClick={() => setSit('')}>Todos</Chip>
            {Object.entries(SIT_EVENTO).map(([k, v]) => <Chip key={k} active={sit === k} onClick={() => setSit(k)}>{v.label}</Chip>)}
          </div>
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(240px,2fr) 110px 150px minmax(150px,1fr) 150px 90px 100px 130px" largura={1140} rotulo="Eventos">
              <TCabecalho><TCelula fixa>Evento</TCelula><TCelula>Tipo</TCelula><TCelula>Público</TCelula><TCelula>Onde</TCelula><TCelula>Quando</TCelula><TCelula>Horas</TCelula><TCelula>Inscritos</TCelula><TCelula>Situação</TCelula></TCabecalho>
              {(d.itens as any[]).map((e) => (
                <TLinha key={e.id} onClick={() => setAberto(e.id)} rotulo={e.titulo}>
                  <TCelula fixa titulo={e.titulo} className="font-semibold">{e.is_demo && <MarcaSimulado className="mr-1" />}{e.titulo}</TCelula>
                  <TCelula>{TIPO_EVENTO[e.tipo] ?? e.tipo}</TCelula><TCelula>{PUBLICO[e.publico]}</TCelula><TCelula titulo={e.unidade}>{e.unidade}</TCelula>
                  <TCelula>{e.inicio === e.fim ? fmtDate(e.inicio) : `${fmtDate(e.inicio).slice(0, 5)} a ${fmtDate(e.fim)}`}</TCelula>
                  <TCelula>{String(e.carga_horaria).replace('.', ',')}</TCelula><TCelula>{fmtInt(e.inscritos)}{e.vagas ? `/${e.vagas}` : ''}</TCelula>
                  <TCelula><Badge tone={SIT_EVENTO[e.situacao]?.tone}>{SIT_EVENTO[e.situacao]?.label}</Badge></TCelula>
                </TLinha>
              ))}
            </Tabela>
            {!(d.itens as any[]).length && <EmptyState compact title="Nenhum evento" />}
          </Card>
        </div>
      )}
      <EventoSheet id={aberto} onClose={() => setAberto(null)} onEditar={(e) => { setAberto(null); setNovo(e); }} />
      <EventoForm ev={novo} rede={rede} onClose={() => setNovo(null)} onCriado={(id) => { setNovo(null); setAberto(id); }} />
    </div>
  );
}

function EventoSheet({ id, onClose, onEditar }: { id: string | null; onClose: () => void; onEditar: (e: any) => void }) {
  const res = useRpc<any>('evento_detalhe', { id }, { enabled: !!id });
  const recarregar = useRecarregar();
  const toast = useToast();
  const [pres, setPres] = useState<Record<string, number>>({});
  const [busca, setBusca] = useState('');
  const q = useDebounced(busca, 300);
  const [busy, setBusy] = useState(false);
  const e = res.data;
  const aberto = e && !['CONCLUIDO', 'CANCELADO'].includes(e.situacao);
  const bus = useRpc<any>('evento_busca', { evento_id: id, q }, { enabled: !!id && !!e?.pode_gerir && !!aberto });
  const acao = async (args: object, ok: string) => {
    setBusy(true);
    try {
      const r = await rpc<any>('evento_participantes', { evento_id: id, ...args });
      toast({ title: ok, description: r.afetados != null ? `${fmtInt(r.afetados)} registro(s).` : undefined, tone: 'success' });
      setPres({});
      recarregar();
    } catch (err) {
      toast({ title: 'Não foi possível', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const fechar = () => { setPres({}); setBusca(''); onClose(); };
  const parts = (e?.participantes ?? []) as any[];
  const semPresenca = parts.filter((p) => p.funcao === 'PARTICIPANTE' && p.presenca == null).length;
  return (
    <Sheet open={!!id} onClose={fechar} title={e?.titulo ?? 'Evento'} subtitle={e ? `${TIPO_EVENTO[e.tipo]} · ${e.unidade} · ${String(e.carga_horaria).replace('.', ',')} h · frequência mínima ${e.frequencia_minima}%` : ''}
      footer={e?.pode_gerir && aberto ? (
        <div className="flex flex-wrap gap-2">
          {Object.keys(pres).length > 0 && <Button loading={busy} onClick={() => acao({ acao: 'PRESENCA', itens: Object.entries(pres).map(([pid, v]) => ({ id: pid, presenca: v })) }, 'Presença registrada')}>Salvar presença ({Object.keys(pres).length})</Button>}
          <Button variant="secondary" onClick={() => onEditar(e)}>Editar</Button>
          <Button variant="success" icon={Award} loading={busy} disabled={semPresenca > 0} onClick={() => acao({ acao: 'CONCLUIR' }, 'Evento concluído: certificados emitidos')}>Concluir e emitir certificados</Button>
        </div>
      ) : undefined}>
      {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} /> : e && (
        <div className="space-y-3 pt-1 text-[14px]">
          <div className="flex flex-wrap items-center gap-2"><Badge tone={SIT_EVENTO[e.situacao]?.tone}>{SIT_EVENTO[e.situacao]?.label}</Badge><span className="text-muted">{PUBLICO[e.publico]} · {e.inicio === e.fim ? fmtDate(e.inicio) : `${fmtDate(e.inicio)} a ${fmtDate(e.fim)}`}{e.local ? ` · ${e.local}` : ''}</span></div>
          {e.descricao && <p>{e.descricao}</p>}
          {e.pode_gerir && aberto && semPresenca > 0 && <p className="text-[12.5px] text-amber-800">Falta a presença de {semPresenca} participante(s) para concluir.</p>}
          {e.pode_gerir && aberto && (
            <Section title="Inscrever" className="mt-2">
              {e.publico !== 'ALUNOS' && <input value={busca} onChange={(ev) => setBusca(ev.target.value)} placeholder="Buscar servidor pelo nome (3 letras)" aria-label="Buscar servidor" className={inputCls} />}
              <div className="mt-2 flex flex-wrap gap-1.5">
                {((bus.data?.servidores ?? []) as any[]).map((s) => <Chip key={s.id} icon={UserPlus} onClick={() => acao({ acao: 'INSCREVER', staff_id: s.id }, `${s.nome} inscrito(a)`)}>{s.nome} · {s.unidade ?? s.cargo}</Chip>)}
                {((bus.data?.turmas ?? []) as any[]).map((t) => <Chip key={t.id} icon={UserPlus} onClick={() => acao({ acao: 'INSCREVER', class_id: t.id }, `Turma ${t.turma} inscrita`)}>Turma {t.turma} ({t.alunos})</Chip>)}
              </div>
            </Section>
          )}
          <Section title={`Participantes (${parts.length})`} className="mt-2">
            <div className="divide-y divide-line rounded-2xl ring-1 ring-line">
              {parts.map((p) => (
                <div key={p.id} className="flex items-center gap-2 px-3 py-1.5 text-[13.5px]">
                  <span className="min-w-0 flex-1 truncate"><b>{p.nome}</b> <span className="text-muted">· {p.vinculo ?? (p.tipo === 'SERVIDOR' ? 'servidor' : 'aluno')}{p.funcao !== 'PARTICIPANTE' ? ` · ${FUNCAO[p.funcao]}` : ''}</span></span>
                  {e.pode_gerir && aberto && p.funcao === 'PARTICIPANTE' ? (
                    <input type="number" min={0} max={100} aria-label={`Presença de ${p.nome}`} value={pres[p.id] ?? p.presenca ?? ''} placeholder="%"
                      onChange={(ev) => setPres({ ...pres, [p.id]: Number(ev.target.value) })} className="h-8 w-16 rounded-xl px-2 text-right ring-1 ring-line" />
                  ) : p.presenca != null ? <span className="text-muted">{String(p.presenca).replace('.', ',')}%</span> : null}
                  {p.certificado && <Link to={`/certificado/${p.certificado}`} className="text-[12.5px] font-semibold text-blue-800 underline">certificado</Link>}
                  {e.pode_gerir && aberto && <button type="button" aria-label={`Remover ${p.nome}`} onClick={() => acao({ acao: 'REMOVER', id: p.id }, 'Inscrição removida')} className="text-subtle hover:text-red-700"><Trash2 className="size-4" /></button>}
                </div>
              ))}
              {!parts.length && <div className="px-3 py-3 text-muted">Ninguém inscrito ainda.</div>}
            </div>
          </Section>
        </div>
      )}
    </Sheet>
  );
}

function EventoForm({ ev, rede, onClose, onCriado }: { ev: any | null; rede: boolean; onClose: () => void; onCriado: (id: string) => void }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  if (ev && chave !== (ev.id ?? 'novo')) {
    setChave(ev.id ?? 'novo');
    const hoje = new Date().toISOString().slice(0, 10);
    setF({ titulo: ev.titulo ?? '', tipo: ev.tipo ?? 'FORMACAO', publico: ev.publico ?? 'SERVIDORES', unit_id: ev.unit_id ?? null, inicio: ev.inicio ?? hoje, fim: ev.fim ?? hoje,
      local: ev.local ?? '', carga_horaria: ev.carga_horaria ?? 4, vagas: ev.vagas ?? '', frequencia_minima: ev.frequencia_minima ?? 75, descricao: ev.descricao ?? '' });
  }
  const fechar = () => { setChave(null); onClose(); };
  const salvar = async (cancelar = false) => {
    setBusy(true);
    try {
      const r = await rpc<any>('evento_salvar', { id: ev.id, ...f, cancelar });
      toast({ title: cancelar ? 'Evento cancelado' : 'Evento salvo', tone: 'success' });
      recarregar();
      setChave(null);
      if (cancelar) onClose(); else onCriado(r.id);
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!ev} onClose={fechar} title={ev?.id ? 'Editar evento' : 'Novo evento'}
      footer={<div className="flex gap-2">{ev?.id && <Button variant="secondary" loading={busy} onClick={() => salvar(true)}>Cancelar o evento</Button>}<Button block loading={busy} disabled={(f.titulo ?? '').trim().length < 5} onClick={() => salvar()}>Salvar</Button></div>}>
      {ev && (
        <div className="space-y-3 pt-1">
          <Field label="Título"><input value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} className={inputCls} /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Tipo"><select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })} className={inputCls}>{Object.entries(TIPO_EVENTO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field label="Público"><select value={f.publico} onChange={(e) => setF({ ...f, publico: e.target.value })} className={inputCls}>{Object.entries(PUBLICO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          </div>
          {rede && !ev.id && <Field label="Unidade" hint="Em branco: evento da rede (formação central)."><UnitSelect value={f.unit_id} onChange={(v) => setF({ ...f, unit_id: v })} todas="Rede municipal" className="w-full" /></Field>}
          <div className="grid grid-cols-2 gap-3">
            <Field label="Início"><input type="date" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} className={inputCls} /></Field>
            <Field label="Fim"><input type="date" value={f.fim} onChange={(e) => setF({ ...f, fim: e.target.value })} className={inputCls} /></Field>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <Field label="Carga (h)"><input type="number" step="0.5" min={0.5} value={f.carga_horaria} onChange={(e) => setF({ ...f, carga_horaria: e.target.value })} className={inputCls} /></Field>
            <Field label="Vagas"><input type="number" min={1} value={f.vagas} onChange={(e) => setF({ ...f, vagas: e.target.value })} className={inputCls} placeholder="livre" /></Field>
            <Field label="Freq. mín. (%)"><input type="number" min={0} max={100} value={f.frequencia_minima} onChange={(e) => setF({ ...f, frequencia_minima: e.target.value })} className={inputCls} /></Field>
          </div>
          <Field label="Local"><input value={f.local} onChange={(e) => setF({ ...f, local: e.target.value })} className={inputCls} /></Field>
          <Field label="Descrição"><textarea rows={3} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} className={`${inputCls} h-auto py-3`} /></Field>
        </div>
      )}
    </Sheet>
  );
}
