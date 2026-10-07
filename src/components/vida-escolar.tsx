// Ocorrências e agenda escolar: peças usadas na ficha do aluno, no diário da turma, na lista da unidade e no portal da família.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Check, CheckCheck, MessageSquare, Send } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { GRAVIDADE, SITUACAO_OCORRENCIA, TIPO_AGENDA, TIPO_OCORRENCIA, diaCurto, hojeISO } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, Field, MarcaSimulado, Segmented, Skeleton, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';

const CHAVES_RECARREGAR = ['ocorrencias_lista', 'ocorrencia_detalhe', 'aluno_vida_escolar', 'familia_ocorrencias', 'agenda_turma', 'familia_agenda', 'alunos_lista'];
export function useRecarregarVidaEscolar() {
  const qc = useQueryClient();
  return () => CHAVES_RECARREGAR.forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Uma ocorrência por linha; registro da família em destaque e o que espera ciência marcado. */
export function OcorrenciasTabela({ itens, onAbrir, mostrarAluno = true }: { itens: any[]; onAbrir: (id: string) => void; mostrarAluno?: boolean }) {
  if (!itens.length) return <EmptyState compact title="Nenhuma ocorrência" />;
  return (
    <Tabela colunas={mostrarAluno ? 'minmax(180px,1.2fr) 96px minmax(170px,1fr) minmax(220px,2fr) 110px 150px' : '96px minmax(170px,1fr) minmax(240px,2fr) 110px 150px'}
      largura={mostrarAluno ? 980 : 760} rotulo="Ocorrências">
      <TCabecalho>
        {mostrarAluno && <TCelula>Aluno</TCelula>}<TCelula>Quando</TCelula><TCelula>Tipo</TCelula><TCelula>O que aconteceu</TCelula><TCelula>Registro</TCelula><TCelula>Situação</TCelula>
      </TCabecalho>
      {itens.map((o) => (
        <TLinha key={o.id} onClick={() => onAbrir(o.id)} alerta={o.situacao === 'ABERTA' && (o.origem === 'FAMILIA' || o.gravidade !== 'LEVE')} rotulo={`${o.aluno}: ${TIPO_OCORRENCIA[o.tipo]?.label}`}>
          {mostrarAluno && <TCelula fixa titulo={`${o.aluno} · ${o.turma ?? ''}`}><span className="font-semibold">{o.aluno}</span> <span className="text-[12px] text-muted">{o.turma}</span>{o.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>}
          <TCelula>{diaCurto(o.ocorrida_em?.slice(0, 10))}</TCelula>
          <TCelula livre><Badge tone={TIPO_OCORRENCIA[o.tipo]?.tone}>{TIPO_OCORRENCIA[o.tipo]?.label ?? o.tipo}</Badge>{o.gravidade !== 'LEVE' && <Badge tone={GRAVIDADE[o.gravidade]?.tone} className="ml-1">{GRAVIDADE[o.gravidade]?.label}</Badge>}</TCelula>
          <TCelula titulo={o.descricao}>{o.descricao}</TCelula>
          <TCelula>{o.origem === 'FAMILIA' ? <span className="font-semibold text-purple-800">Família</span> : 'Escola'}</TCelula>
          <TCelula livre>
            <Badge tone={SITUACAO_OCORRENCIA[o.situacao]?.tone}>{SITUACAO_OCORRENCIA[o.situacao]?.label}</Badge>
            {o.origem === 'ESCOLA' && !o.ciencia_familia_em && o.situacao !== 'ENCERRADA' && <span className="ml-1 text-[11.5px] text-muted">sem ciência</span>}
          </TCelula>
        </TLinha>
      ))}
    </Tabela>
  );
}

/** Detalhe com a linha do tempo: a escola registra providências e muda a situação; a família dá ciência e comenta. */
export function OcorrenciaSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const res = useRpc<any>('ocorrencia_detalhe', { id }, { enabled: !!id });
  const recarregar = useRecarregarVidaEscolar();
  const toast = useToast();
  const [texto, setTexto] = useState('');
  const [sit, setSit] = useState('');
  const [busy, setBusy] = useState(false);
  const o = res.data;
  const enviar = async (fn: string, args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc(fn, args);
      toast({ title: msg, tone: 'success' });
      setTexto(''); setSit('');
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!id} onClose={onClose} title={o ? `${TIPO_OCORRENCIA[o.tipo]?.label ?? 'Ocorrência'} · ${o.primeiro_nome}` : 'Ocorrência'}
      subtitle={o ? `${o.turma ?? ''} · ${o.unidade ?? ''} · ${fmtDateTime(o.ocorrida_em)}` : ''} size="lg">
      {!o ? <Skeleton className="h-40" /> : (
        <div className="space-y-4 pt-1">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={SITUACAO_OCORRENCIA[o.situacao]?.tone}>{SITUACAO_OCORRENCIA[o.situacao]?.label}</Badge>
            <Badge tone={GRAVIDADE[o.gravidade]?.tone}>{GRAVIDADE[o.gravidade]?.label}</Badge>
            <Badge tone={o.origem === 'FAMILIA' ? 'purple' : 'blue'}>{o.origem === 'FAMILIA' ? 'Relatada pela família' : 'Registrada pela escola'}</Badge>
            {o.origem === 'ESCOLA' && (o.ciencia_familia_em ? <Badge tone="green" icon={CheckCheck}>Família ciente</Badge> : <Badge tone="amber">Aguardando a ciência da família</Badge>)}
          </div>
          <Card className="p-3">
            <p className="text-[14.5px]">{o.descricao}</p>
            {o.local && <p className="mt-1 text-[12.5px] text-muted">Local: {o.local}</p>}
            {o.providencias && <p className="mt-2 whitespace-pre-line rounded-2xl bg-slate-50 p-2.5 text-[13px]"><b>Providências:</b> {o.providencias}</p>}
            <p className="mt-2 text-[12px] text-muted">Registro: {o.registrada_por ?? '—'}</p>
          </Card>
          {(o.eventos as any[]).length > 0 && (
            <ol className="space-y-2">
              {(o.eventos as any[]).map((e, i) => (
                <li key={i} className={clsx('rounded-2xl p-2.5 text-[13.5px] ring-1', e.origem === 'FAMILIA' ? 'ml-6 bg-purple-50 ring-purple-100' : 'mr-6 bg-white ring-line')}>
                  <div className="text-[11.5px] font-semibold text-muted">{e.origem === 'FAMILIA' ? 'Família' : 'Escola'} · {e.autor} · {fmtDateTime(e.em)}{e.situacao ? ` · ${SITUACAO_OCORRENCIA[e.situacao]?.label}` : ''}</div>
                  {e.texto}
                </li>
              ))}
            </ol>
          )}
          {o.pode_dar_ciencia && (
            <Button block variant="purple" icon={Check} loading={busy} onClick={() => enviar('familia_ocorrencia_ciente', { id: o.id }, 'Ciência registrada')}>Estou ciente</Button>
          )}
          {o.pode_comentar && (
            <div className="space-y-2">
              <Field label={o.pode_atualizar ? 'Providência ou comentário' : 'Comentário para a escola'}>
                <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
              </Field>
              {o.pode_atualizar && (
                <Segmented value={sit} onChange={setSit} items={[{ value: '', label: 'Manter situação' }, { value: 'EM_ACOMPANHAMENTO', label: 'Em acompanhamento' }, { value: 'ENCERRADA', label: 'Encerrar' }]} />
              )}
              <Button block icon={Send} loading={busy} disabled={texto.trim().length < 3 && !sit}
                onClick={() => enviar('ocorrencia_atualizar', { id: o.id, texto, situacao: sit || null }, o.pode_atualizar ? 'Acompanhamento registrado' : 'Comentário enviado à escola')}>
                {o.pode_atualizar ? 'Registrar' : 'Enviar comentário'}
              </Button>
            </div>
          )}
        </div>
      )}
    </Sheet>
  );
}

/** Registro de ocorrência: pela escola (com gravidade e providências) ou pela família (só o relato). */
export function NovaOcorrenciaSheet({ open, onClose, alunos, familia }: { open: boolean; onClose: () => void; alunos: { id: string; nome: string }[]; familia?: boolean }) {
  const recarregar = useRecarregarVidaEscolar();
  const toast = useToast();
  const [aluno, setAluno] = useState('');
  const [tipo, setTipo] = useState(familia ? 'OUTRO' : 'COMPORTAMENTO');
  const [grav, setGrav] = useState('LEVE');
  const [local, setLocal] = useState('');
  const [desc, setDesc] = useState('');
  const [prov, setProv] = useState('');
  const [encerrar, setEncerrar] = useState(false);
  const [busy, setBusy] = useState(false);
  const alvo = aluno || (alunos.length === 1 ? alunos[0].id : '');
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('ocorrencia_registrar', { student_id: alvo, tipo, gravidade: familia ? null : grav, local, descricao: desc, providencias: prov, encerrar });
      toast({ title: 'Ocorrência registrada', description: r.mensagem, tone: 'success' });
      recarregar();
      setDesc(''); setProv(''); setLocal(''); setEncerrar(false);
      onClose();
    } catch (e) {
      toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={familia ? 'Relatar algo à escola' : 'Nova ocorrência'}
      subtitle={familia ? 'A direção recebe na hora e responde por aqui e pela IARA.' : 'A família vê no portal e pela IARA e dá ciência.'}
      footer={<Button block size="lg" loading={busy} disabled={!alvo || desc.trim().length < 10} onClick={enviar}>{familia ? 'Enviar à escola' : 'Registrar'}</Button>}>
      <div className="space-y-4 pt-1">
        {alunos.length > 1 && (
          <Field label={familia ? 'Criança' : 'Aluno'}>
            <select value={aluno} onChange={(e) => setAluno(e.target.value)} className={inputCls}>
              <option value="">Escolha…</option>
              {alunos.map((a) => <option key={a.id} value={a.id}>{a.nome}</option>)}
            </select>
          </Field>
        )}
        <Field label="Assunto">
          <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={inputCls}>
            {Object.entries(TIPO_OCORRENCIA).filter(([k]) => !familia || !['ELOGIO', 'PEDAGOGICA', 'ATRASO_SAIDA'].includes(k)).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </Field>
        {!familia && (
          <div className="grid grid-cols-2 gap-3">
            <Field label="Gravidade">
              <select value={grav} onChange={(e) => setGrav(e.target.value)} className={inputCls}>
                {Object.entries(GRAVIDADE).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
              </select>
            </Field>
            <Field label="Local"><input value={local} onChange={(e) => setLocal(e.target.value)} placeholder="Sala, pátio, parque…" className={inputCls} /></Field>
          </div>
        )}
        <Field label="O que aconteceu" hint="Fatos, sem diagnóstico. Não cite nomes de outras crianças.">
          <textarea value={desc} onChange={(e) => setDesc(e.target.value)} rows={4} maxLength={2000} className={`${inputCls} h-auto py-3`} />
        </Field>
        {!familia && (
          <>
            <Field label="Providências tomadas (opcional)"><textarea value={prov} onChange={(e) => setProv(e.target.value)} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
            <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={encerrar} onChange={(e) => setEncerrar(e.target.checked)} className="size-5 accent-purple-700" />Resolvido na hora: registrar já encerrada</label>
          </>
        )}
      </div>
    </Sheet>
  );
}

/** Agenda: um registro por linha; a escola vê quantas famílias deram ciência, a família confirma a dela. */
export function AgendaLista({ itens, familia, onCiente }: { itens: any[]; familia?: boolean; onCiente?: (item: any) => void }) {
  if (!itens.length) return <EmptyState compact title="Nada na agenda neste período" />;
  const hoje = hojeISO();
  return (
    <div className="divide-y divide-line">
      {itens.map((a) => {
        const t = TIPO_AGENDA[a.tipo] ?? { label: a.tipo, tone: 'gray' as const };
        return (
          <div key={a.id + (a.filho_id ?? '')} className={clsx('flex items-start gap-3 px-4 py-3', a.origem === 'FAMILIA' && 'bg-purple-50/60')}>
            <div className={clsx('w-[74px] shrink-0 rounded-xl px-1.5 py-1 text-center text-[11.5px] font-bold capitalize', a.data === hoje ? 'bg-purple-700 text-white' : a.data > hoje ? 'bg-teal-50 text-teal-900' : 'bg-slate-100 text-ink-2')}>
              {diaCurto(a.data)}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-1.5">
                <Badge tone={a.origem === 'FAMILIA' ? 'purple' : t.tone}>{a.origem === 'FAMILIA' ? 'Bilhete da família' : t.label}</Badge>
                {a.student_id && a.origem === 'ESCOLA' && <span className="text-[12px] font-semibold text-purple-800">só para {familia ? 'vocês' : a.aluno?.split(' ')[0]}</span>}
                {a.origem === 'FAMILIA' && !familia && <span className="text-[12px] font-semibold text-purple-800">{a.aluno}</span>}
                {familia && a.filho && <span className="text-[12px] text-muted">· {a.filho}</span>}
                {a.is_demo && <MarcaSimulado />}
              </div>
              {a.titulo && <div className="mt-0.5 font-semibold">{a.titulo}</div>}
              <p className="text-[13.5px] text-ink-2">{a.texto}</p>
              <div className="mt-0.5 text-[11.5px] text-muted">{a.autor}</div>
            </div>
            <div className="shrink-0 text-right">
              {a.exige_ciencia && !familia && <span className="text-[12px] font-semibold text-green-800"><CheckCheck className="mr-1 inline size-3.5" />{fmtInt(a.ciencias)}/{fmtInt(a.destinatarios)}</span>}
              {a.exige_ciencia && familia && (a.ciente
                ? <Badge tone="green" icon={Check}>Ciente</Badge>
                : <Button size="sm" variant="purple" onClick={() => onCiente?.(a)}>Estou ciente</Button>)}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** Publicação na agenda da turma (ou bilhete para a família de um aluno). */
export function NovoRecadoSheet({ open, onClose, classId, alunos, alunoFixo }: {
  open: boolean; onClose: () => void; classId: string; alunos: { id: string; nome: string }[]; alunoFixo?: { id: string; nome: string };
}) {
  const recarregar = useRecarregarVidaEscolar();
  const toast = useToast();
  const [para, setPara] = useState(alunoFixo?.id ?? '');
  const [tipo, setTipo] = useState(alunoFixo ? 'BILHETE' : 'RECADO');
  const [titulo, setTitulo] = useState('');
  const [texto, setTexto] = useState('');
  const [data, setData] = useState(hojeISO());
  const [ciencia, setCiencia] = useState(false);
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('agenda_publicar', { class_id: classId, student_id: para || null, tipo, titulo, texto, data, exige_ciencia: ciencia });
      toast({ title: 'Publicado na agenda', description: para ? 'A família do aluno vê no portal e pela IARA.' : 'As famílias da turma veem no portal e pela IARA.', tone: 'success' });
      recarregar();
      setTitulo(''); setTexto(''); setCiencia(false);
      onClose();
    } catch (e) {
      toast({ title: 'Não publicado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Escrever na agenda" subtitle="Recado, tarefa, lembrete ou bilhete — chega ao portal da família e à IARA."
      footer={<Button block size="lg" icon={MessageSquare} loading={busy} disabled={texto.trim().length < 3} onClick={enviar}>Publicar</Button>}>
      <div className="space-y-4 pt-1">
        {!alunoFixo && (
          <Field label="Para quem">
            <select value={para} onChange={(e) => { setPara(e.target.value); if (e.target.value) setTipo('BILHETE'); }} className={inputCls}>
              <option value="">Toda a turma</option>
              {alunos.map((a) => <option key={a.id} value={a.id}>Só a família de {a.nome}</option>)}
            </select>
          </Field>
        )}
        <div className="grid grid-cols-2 gap-3">
          <Field label="Tipo">
            <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={inputCls}>
              {Object.entries(TIPO_AGENDA).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
            </select>
          </Field>
          <Field label="Dia"><input type="date" value={data} onChange={(e) => setData(e.target.value)} className={inputCls} /></Field>
        </div>
        <Field label="Título (opcional)"><input value={titulo} onChange={(e) => setTitulo(e.target.value)} maxLength={120} className={inputCls} /></Field>
        <Field label="Texto"><textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} maxLength={2000} className={`${inputCls} h-auto py-3`} /></Field>
        <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={ciencia} onChange={(e) => setCiencia(e.target.checked)} className="size-5 accent-purple-700" />Pedir que a família confirme a ciência</label>
      </div>
    </Sheet>
  );
}
