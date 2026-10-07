// Sprint 5 — peças das telas: conteúdos ministrados (turma, pendências e família), rematrícula e transferência (família) e eventos (família).
import { useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Award, BookOpenCheck, CalendarCheck, ChevronLeft, ChevronRight, House, Save, School, Send } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { UnitSelect } from '@/components/escola';

const somaDias = (iso: string, n: number) => {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d + n);
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
};
const hoje = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const diaSemana = (iso: string) => new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: '2-digit' });

// ------------------------------------------------------------------ Conteúdos ministrados
export function AulasTurma({ classId }: { classId: string }) {
  const [data, setData] = useState(hoje());
  const res = useRpc<any>('aulas_dia', { class_id: classId, data });
  const [aberta, setAberta] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" variant="secondary" icon={ChevronLeft} onClick={() => setData(somaDias(data, extractDow(data) === 1 ? -3 : -1))}>Anterior</Button>
        <span className="font-semibold capitalize">{diaSemana(data)}</span>
        <Button size="sm" variant="secondary" icon={ChevronRight} disabled={data >= hoje()} onClick={() => setData(somaDias(data, extractDow(data) === 5 ? 3 : 1))}>Próximo</Button>
        {!d.letivo && <Badge tone="gray">sem aula</Badge>}
      </div>
      <div className="flex flex-wrap gap-1.5">
        {(d.semana as any[]).map((s) => (
          <Chip key={s.data} active={s.data === data} onClick={() => setData(s.data)}>{fmtDate(s.data).slice(0, 5)} · {s.registradas}/{s.previstas}</Chip>
        ))}
      </div>
      {d.letivo ? (
        <div className="space-y-2">
          {(d.aulas as any[]).map((a) => (
            <Card key={a.aula} className={clsx('flex flex-wrap items-start gap-3 p-3 text-[13.5px]', !a.registro && data < hoje() && 'ring-2 ring-amber-200')}>
              <div className="flex size-9 shrink-0 items-center justify-center rounded-2xl bg-purple-50 font-bold text-purple-800">{a.aula}ª</div>
              <div className="min-w-0 flex-1">
                <div className="font-semibold">{a.componente} <span className="font-normal text-muted">· {a.professor ?? 'professor a definir'}</span></div>
                {a.registro ? (
                  <>
                    <p>{a.registro.conteudo}</p>
                    {a.registro.atividade && <p className="text-muted">Atividade: {a.registro.atividade}</p>}
                    {a.registro.tarefa && <p className="text-purple-800"><House className="mr-1 inline size-3.5" />Tarefa: {a.registro.tarefa}</p>}
                    {(a.registro.habilidades ?? []).length > 0 && <div className="mt-1 flex flex-wrap gap-1">{(a.registro.habilidades as string[]).map((h) => <Badge key={h} tone="blue">{h}</Badge>)}</div>}
                  </>
                ) : <p className="text-muted">{data < hoje() ? 'Sem registro' : 'Ainda não registrada'}</p>}
              </div>
              {d.pode_registrar && <Button size="sm" variant={a.registro ? 'secondary' : 'primary'} onClick={() => setAberta(a)}>{a.registro ? 'Editar' : 'Registrar'}</Button>}
            </Card>
          ))}
          {!(d.aulas as any[]).length && <EmptyState compact title="Sem aulas no horário deste dia" />}
        </div>
      ) : <EmptyState compact title="Dia sem aula" body="Fim de semana, feriado ou recesso do calendário." />}
      <AulaSheet aula={aberta} classId={classId} data={data} onClose={() => setAberta(null)} />
    </div>
  );
}
function extractDow(iso: string) { return new Date(`${iso}T12:00:00`).getDay(); }

function AulaSheet({ aula, classId, data, onClose }: { aula: any | null; classId: string; data: string; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  if (aula && chave !== `${data}:${aula.aula}`) {
    setChave(`${data}:${aula.aula}`);
    const r = aula.registro ?? {};
    setF({ conteudo: r.conteudo ?? '', objetivos: r.objetivos ?? '', habilidades: (r.habilidades ?? []).join(', '), atividade: r.atividade ?? '', tarefa: r.tarefa ?? '', materiais: r.materiais ?? '' });
  }
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('aula_registrar', { class_id: classId, data, aula: aula.aula, ...f, habilidades: String(f.habilidades).split(/[,\s]+/).filter(Boolean) });
      toast({ title: 'Aula registrada', description: 'A família vê o conteúdo e a tarefa no portal e pela IARA.', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['aulas_dia'] });
      setChave(null);
      onClose();
    } catch (e) {
      toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!aula} onClose={() => { setChave(null); onClose(); }} title={aula ? `${aula.aula}ª aula · ${aula.componente}` : ''} subtitle={diaSemana(data)}
      footer={<Button block icon={Save} loading={busy} disabled={(f.conteudo ?? '').trim().length < 5} onClick={salvar}>Salvar</Button>}>
      {aula && (
        <div className="space-y-3 pt-1">
          <Field label="Conteúdo"><textarea value={f.conteudo} onChange={(e) => setF({ ...f, conteudo: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
          <Field label="Objetivos (opcional)"><input value={f.objetivos} onChange={(e) => setF({ ...f, objetivos: e.target.value })} className={inputCls} /></Field>
          <Field label="Habilidades da BNCC (opcional)" hint="Ex.: EF03MA05, EF03LP01"><input value={f.habilidades} onChange={(e) => setF({ ...f, habilidades: e.target.value.toUpperCase() })} className={inputCls} /></Field>
          <Field label="Atividade"><input value={f.atividade} onChange={(e) => setF({ ...f, atividade: e.target.value })} className={inputCls} /></Field>
          <Field label="Tarefa de casa (opcional)" hint="A família vê no portal e pela IARA."><input value={f.tarefa} onChange={(e) => setF({ ...f, tarefa: e.target.value })} className={inputCls} /></Field>
          <Field label="Materiais (opcional)"><input value={f.materiais} onChange={(e) => setF({ ...f, materiais: e.target.value })} className={inputCls} /></Field>
        </div>
      )}
    </Sheet>
  );
}

export function AulasPendencias({ unitId, onUnidade }: { unitId: number | null; onUnidade?: (id: number) => void }) {
  const res = useRpc<any>('aulas_pendencias', { unit_id: unitId });
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const pct = d.previstas ? Math.round((100 * d.registradas) / d.previstas) : 0;
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <Kpi compact icon={BookOpenCheck} tone={pct >= 90 ? 'green' : 'amber'} label={`Aulas registradas (${fmtDate(d.de)} a ${fmtDate(d.ate)})`} value={`${pct}%`} sub={`${fmtInt(d.registradas)} de ${fmtInt(d.previstas)}`} />
        <Kpi compact icon={CalendarCheck} tone="red" label="Aulas sem registro" value={fmtInt(d.previstas - d.registradas)} />
      </div>
      <Card className="overflow-hidden">
        {d.unit_id ? (
          <Tabela colunas="minmax(140px,1fr) 100px 110px 90px 140px" largura={600} rotulo="Aulas por turma">
            <TCabecalho><TCelula fixa>Turma</TCelula><TCelula>Previstas</TCelula><TCelula>Registradas</TCelula><TCelula>%</TCelula><TCelula>Última sem registro</TCelula></TCabecalho>
            {(d.turmas as any[]).map((t) => (
              <TLinha key={t.class_id} to={`/turmas/${t.class_id}/diario?aba=aulas`} alerta={(t.pct ?? 0) < 80} rotulo={t.turma}>
                <TCelula fixa className="font-semibold">{t.turma}</TCelula><TCelula>{fmtInt(t.previstas)}</TCelula><TCelula>{fmtInt(t.registradas)}</TCelula><TCelula>{t.pct ?? 0}%</TCelula>
                <TCelula>{t.ultima_sem_registro ? fmtDate(t.ultima_sem_registro) : '—'}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : (
          <Tabela colunas="minmax(200px,1.5fr) 100px 110px 90px" largura={560} rotulo="Aulas por unidade">
            <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Previstas</TCelula><TCelula>Registradas</TCelula><TCelula>%</TCelula></TCabecalho>
            {((d.unidades ?? []) as any[]).map((u) => (
              <TLinha key={u.unit_id} onClick={onUnidade ? () => onUnidade(u.unit_id) : undefined} alerta={(u.pct ?? 0) < 80} rotulo={u.unidade}><TCelula fixa>{u.unidade}</TCelula><TCelula>{fmtInt(u.previstas)}</TCelula><TCelula>{fmtInt(u.registradas)}</TCelula><TCelula>{u.pct ?? 0}%</TCelula></TLinha>
            ))}
          </Tabela>
        )}
      </Card>
      {d.unit_id && (d.professores as any[]).length > 0 && (
        <Section title="Por professor">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,1.5fr) 100px 110px 90px" largura={560} rotulo="Aulas por professor">
              <TCabecalho><TCelula fixa>Professor</TCelula><TCelula>Previstas</TCelula><TCelula>Registradas</TCelula><TCelula>%</TCelula></TCabecalho>
              {(d.professores as any[]).map((p) => (
                <TLinha key={p.staff_id} alerta={(p.pct ?? 0) < 80} rotulo={p.nome}><TCelula fixa>{p.nome}</TCelula><TCelula>{fmtInt(p.previstas)}</TCelula><TCelula>{fmtInt(p.registradas)}</TCelula><TCelula>{p.pct ?? 0}%</TCelula></TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
    </div>
  );
}

export function AulasFamilia() {
  const res = useRpc<any[]>('familia_aulas', {});
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <EmptyState title="Nenhuma criança matriculada" />;
  return (
    <div className="space-y-5">
      {res.data.map((k) => (
        <Section key={k.student_id} title={`O que ${k.primeiro_nome} estudou`} subtitle={k.turma}>
          {!(k.dias as any[]).length && <Card className="p-3 text-[13.5px] text-muted">Ainda sem aulas registradas nos últimos dias.</Card>}
          <div className="space-y-2">
            {(k.dias as any[]).map((d) => (
              <Card key={d.data} className="p-3 text-[13.5px]">
                <div className="mb-1 font-semibold capitalize">{diaSemana(d.data)}</div>
                <ul className="space-y-1">
                  {(d.aulas as any[]).map((a) => (
                    <li key={a.aula}><b>{a.componente}:</b> {a.conteudo}{a.tarefa && <span className="block text-purple-800"><House className="mr-1 inline size-3.5" />Tarefa: {a.tarefa}</span>}</li>
                  ))}
                </ul>
              </Card>
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}

// ------------------------------------------------------------------ Rematrícula e transferência (família)
const SIT_REM: Record<string, { label: string; tone: 'green' | 'amber' | 'red' | 'gray' | 'purple' | 'blue' }> = {
  PENDENTE: { label: 'Aguardando a sua confirmação', tone: 'amber' }, AGUARDANDO_RESULTADO: { label: 'Aguarda o resultado do ano', tone: 'purple' },
  CONFIRMADA: { label: 'Confirmada', tone: 'green' }, NAO_RENOVADA: { label: 'Não renovada', tone: 'gray' }, OUTRA_ESCOLA: { label: 'Pediu outra escola', tone: 'blue' },
  CONCLUINTE: { label: 'Concluinte do 5º ano', tone: 'blue' },
};
export { SIT_REM };

export function RematriculaFamilia() {
  const res = useRpc<any[]>('familia_rematricula', {});
  const tr = useRpc<any>('transferencias_lista', {});
  const qc = useQueryClient();
  const toast = useToast();
  const [sheet, setSheet] = useState<{ r: any; acao: string } | null>(null);
  const [transf, setTransf] = useState<any | null>(null);
  const responder = async (args: object) => {
    try {
      const r = await rpc<any>('rematricula_responder', { canal: 'PORTAL', ...args });
      toast({ title: 'Registrado', description: r.mensagem, tone: 'success' });
      setSheet(null);
      qc.invalidateQueries({ queryKey: ['familia_rematricula'] });
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="space-y-4">
      {!res.data?.length && <EmptyState title="Sem rematrícula para confirmar" />}
      {(res.data ?? []).map((r) => (
        <Card key={r.id} className="space-y-2 p-4 text-[14px]">
          <div className="flex flex-wrap items-center gap-2"><b className="font-display text-lg">{r.primeiro_nome} em {r.ano}</b><Badge tone={SIT_REM[r.situacao]?.tone}>{SIT_REM[r.situacao]?.label}</Badge></div>
          <p>{r.situacao === 'CONCLUINTE' ? `${r.primeiro_nome} conclui o 5º ano: o 6º ano é na rede estadual. A escola orienta a matrícula.`
            : <>{r.serie_destino} na <b>{r.unidade_destino}</b>, turno {SHIFT[r.turno_destino]?.toLowerCase() ?? r.turno_destino}{r.tipo === 'TRANSICAO' && ` — transição: a escola mais perto com ${r.serie_destino}${r.distancia_m ? ` (cerca de ${(r.distancia_m / 1000).toFixed(1).replace('.', ',')} km)` : ''}`}.</>}</p>
          {r.situacao === 'PENDENTE' && <p className="text-[12.5px] text-muted">Confirme até {fmtDate(r.prazo)}. Sem resposta, a escola entra em contato.</p>}
          {['PENDENTE', 'AGUARDANDO_RESULTADO', 'CONFIRMADA'].includes(r.situacao) && (
            <div className="flex flex-wrap gap-2">
              {r.situacao !== 'CONFIRMADA' && <Button size="sm" icon={Send} onClick={() => responder({ id: r.id, acao: 'CONFIRMAR' })}>Confirmar</Button>}
              {(r.turnos_destino ?? []).length > 1 && <Button size="sm" variant="secondary" onClick={() => setSheet({ r, acao: 'TURNO' })}>Trocar o turno</Button>}
              <Button size="sm" variant="secondary" icon={School} onClick={() => setTransf(r)}>Quero outra escola</Button>
              <Button size="sm" variant="ghost" onClick={() => setSheet({ r, acao: 'NAO_RENOVAR' })}>Não vou renovar</Button>
            </div>
          )}
        </Card>
      ))}
      {(tr.data?.itens ?? []).length > 0 && (
        <Section title="Pedidos de transferência">
          <div className="space-y-2">{(tr.data.itens as any[]).map((t) => (
            <Card key={t.id} className="p-3 text-[13.5px]"><b>{t.primeiro_nome}</b> → {t.unidade_destino} · <Badge tone={t.situacao === 'EFETIVADA' ? 'green' : t.situacao === 'FILA' ? 'amber' : t.situacao === 'RECUSADA' ? 'red' : 'purple'}>{t.situacao === 'AGUARDANDO_DESTINO' ? 'aguardando a escola' : t.situacao.toLowerCase()}</Badge>
              {t.resposta && <p className="text-muted">{t.resposta}</p>}</Card>))}</div>
        </Section>
      )}
      <RespostaSheet alvo={sheet} onClose={() => setSheet(null)} onEnviar={responder} />
      <TransferenciaSheet alvo={transf} onClose={() => setTransf(null)} />
    </div>
  );
}

function RespostaSheet({ alvo, onClose, onEnviar }: { alvo: { r: any; acao: string } | null; onClose: () => void; onEnviar: (a: object) => void }) {
  const [turno, setTurno] = useState('');
  const [motivo, setMotivo] = useState('');
  return (
    <Sheet open={!!alvo} onClose={onClose} title={alvo?.acao === 'TURNO' ? 'Trocar o turno' : 'Não vou renovar'}
      footer={alvo && <Button block disabled={alvo.acao === 'TURNO' ? !turno : motivo.trim().length < 5}
        onClick={() => onEnviar(alvo.acao === 'TURNO' ? { id: alvo.r.id, acao: 'CONFIRMAR', turno } : { id: alvo.r.id, acao: 'NAO_RENOVAR', motivo })}>Enviar</Button>}>
      {alvo?.acao === 'TURNO' ? (
        <div className="flex flex-wrap gap-2 pt-1">{(alvo.r.turnos_destino as string[]).map((t) => <Chip key={t} active={turno === t} onClick={() => setTurno(t)}>{SHIFT[t] ?? t}</Chip>)}</div>
      ) : (
        <Field label="Motivo" hint="Ex.: mudança de cidade, escola particular. A vaga fica livre para outra criança."><input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={inputCls} /></Field>
      )}
    </Sheet>
  );
}

export function TransferenciaSheet({ alvo, onClose }: { alvo: any | null; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [dest, setDest] = useState<number | null>(null);
  const [tipo, setTipo] = useState('MUDANCA_ENDERECO');
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('transferencia_solicitar', { student_id: alvo.student_id, unit_destino: dest, motivo_tipo: tipo, motivo });
      toast({ title: r.situacao === 'AGUARDANDO_DESTINO' ? 'Pedido enviado à escola' : 'Sem vaga livre agora', description: r.mensagem, tone: r.situacao === 'AGUARDANDO_DESTINO' ? 'success' : 'warning' });
      qc.invalidateQueries({ queryKey: ['transferencias_lista'] });
      onClose();
    } catch (e) {
      toast({ title: 'Não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Transferência de ${alvo?.primeiro_nome ?? ''}`} subtitle="Com vaga e sem fila na série, a nova escola confirma e a matrícula muda; senão, a transferência entra na fila (IN nº 025/2025)."
      footer={<Button block loading={busy} disabled={!dest} onClick={enviar}>Pedir transferência</Button>}>
      <div className="space-y-3 pt-1">
        <Field label="Para qual escola"><UnitSelect value={dest} onChange={setDest} todas={null} className="w-full" /></Field>
        <Field label="Motivo">
          <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={inputCls}>
            <option value="MUDANCA_ENDERECO">Mudança de endereço</option><option value="PERTO_DO_TRABALHO">Perto do trabalho</option><option value="IRMAOS">Irmãos na escola</option>
            <option value="SAUDE">Saúde</option><option value="OUTRO">Outro</option>
          </select>
        </Field>
        <Field label="Detalhe (opcional)"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={inputCls} /></Field>
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ Eventos (família)
export function EventosFamilia() {
  const res = useRpc<any[]>('familia_eventos', {});
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="space-y-5">
      {(res.data ?? []).map((k) => (
        <Section key={k.student_id} title={`Eventos e certificados · ${k.primeiro_nome}`}>
          {!(k.eventos as any[]).length && <Card className="p-3 text-[13.5px] text-muted">Nenhum evento registrado neste ano.</Card>}
          <div className="space-y-2">
            {(k.eventos as any[]).map((e, i) => (
              <Card key={i} className="flex flex-wrap items-center gap-3 p-3 text-[13.5px]">
                <Award className="size-5 text-purple-700" aria-hidden />
                <div className="min-w-0 flex-1"><b>{e.titulo}</b>{e.funcao === 'PREMIADO' && <Badge tone="amber" className="ml-1">premiado(a)</Badge>}
                  <div className="text-muted">{e.unidade} · {fmtDate(e.inicio)} · {String(e.carga_horaria).replace('.', ',')} h</div></div>
                {e.certificado && <Link to={`/certificado/${e.certificado}`} className="font-semibold text-blue-800 underline">Certificado</Link>}
              </Card>
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}
