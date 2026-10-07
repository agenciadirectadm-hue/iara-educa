// Ocorrências e agenda escolar: peças usadas na ficha do aluno, no diário da turma, na lista da unidade e no portal da família.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Link } from 'react-router';
import { ArrowUpRight, Check, CheckCheck, FileWarning, Lock, MessageSquare, Send, ShieldAlert, Undo2 } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { GRAVIDADE, INSTANCIA_OCORRENCIA, SITUACAO_OCORRENCIA, TIPO_AGENDA, TIPO_OCORRENCIA, VIOLENCIA, diaCurto, hojeISO } from '@/lib/escola';
import { Badge, Button, Card, Chip, EmptyState, Field, MarcaSimulado, Segmented, Skeleton, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';

const CHAVES_RECARREGAR = ['ocorrencias_lista', 'ocorrencia_detalhe', 'aluno_vida_escolar', 'familia_ocorrencias', 'agenda_turma', 'familia_agenda', 'alunos_lista'];
export function useRecarregarVidaEscolar() {
  const qc = useQueryClient();
  return () => CHAVES_RECARREGAR.forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Uma ocorrência por linha; registro da família em destaque, 2ª instância e prazo vencido marcados. */
export function OcorrenciasTabela({ itens, onAbrir, mostrarAluno = true }: { itens: any[]; onAbrir: (id: string) => void; mostrarAluno?: boolean }) {
  if (!itens.length) return <EmptyState compact title="Nenhuma ocorrência" />;
  return (
    <Tabela colunas={mostrarAluno ? 'minmax(180px,1.2fr) 96px minmax(190px,1fr) minmax(220px,2fr) 110px 190px' : '96px minmax(190px,1fr) minmax(240px,2fr) 110px 190px'}
      largura={mostrarAluno ? 1020 : 800} rotulo="Ocorrências">
      <TCabecalho>
        {mostrarAluno && <TCelula>Aluno</TCelula>}<TCelula>Quando</TCelula><TCelula>Tipo</TCelula><TCelula>O que aconteceu</TCelula><TCelula>Registro</TCelula><TCelula>Situação</TCelula>
      </TCabecalho>
      {itens.map((o) => (
        <TLinha key={o.id} onClick={() => onAbrir(o.id)} alerta={o.situacao !== 'ENCERRADA' && (o.vencida || (o.situacao === 'ABERTA' && (o.origem === 'FAMILIA' || o.gravidade !== 'LEVE')))}
          rotulo={`${o.aluno}: ${TIPO_OCORRENCIA[o.tipo]?.label}`}>
          {mostrarAluno && <TCelula fixa titulo={`${o.aluno} · ${o.turma ?? ''}`}><span className="font-semibold">{o.aluno}</span> <span className="text-[12px] text-muted">{o.turma}</span>{o.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>}
          <TCelula>{diaCurto(o.ocorrida_em?.slice(0, 10))}</TCelula>
          <TCelula livre>
            <Badge tone={TIPO_OCORRENCIA[o.tipo]?.tone}>{TIPO_OCORRENCIA[o.tipo]?.label ?? o.tipo}</Badge>
            {o.gravidade !== 'LEVE' && <Badge tone={GRAVIDADE[o.gravidade]?.tone} className="ml-1">{GRAVIDADE[o.gravidade]?.label}</Badge>}
            {(o.violencia ?? []).length > 0 && <Badge tone="red" icon={ShieldAlert} className="ml-1">violência</Badge>}
            {o.sigilosa && <Badge tone="gray" icon={Lock} className="ml-1">sigilosa</Badge>}
          </TCelula>
          <TCelula titulo={o.descricao}>{o.descricao}</TCelula>
          <TCelula>{o.origem === 'FAMILIA' ? <span className="font-semibold text-purple-800">Família</span> : 'Escola'}</TCelula>
          <TCelula livre>
            <Badge tone={SITUACAO_OCORRENCIA[o.situacao]?.tone}>{SITUACAO_OCORRENCIA[o.situacao]?.label}</Badge>
            {o.instancia === 'SECRETARIA' && <Badge tone="purple" className="ml-1">{o.pedido_familia ? 'SEDUC · pedido da família' : 'SEDUC'}</Badge>}
            {o.vencida && <span className="ml-1 text-[11.5px] font-semibold text-red-700">prazo vencido</span>}
            {!o.vencida && o.origem === 'ESCOLA' && !o.ciencia_familia_em && o.situacao !== 'ENCERRADA' && <span className="ml-1 text-[11.5px] text-muted">sem ciência</span>}
          </TCelula>
        </TLinha>
      ))}
    </Tabela>
  );
}

const ROTULO_EVENTO: Record<string, string> = {
  NOTA_INTERNA: 'Nota interna', SITUACAO: 'Situação', COMUNICACAO: 'Mensagem à família', ENCAMINHADA_SEDUC: 'Encaminhada à Secretaria',
  PEDIDO_REVISAO: 'Pedido de análise da Secretaria', DEVOLVIDA_UNIDADE: 'Devolvida à unidade', SOLUCAO: 'Solução', CLASSIFICACAO: 'Classificação',
};
type AcaoOc = 'NOTA_INTERNA' | 'COMENTAR' | 'SOLUCIONAR' | 'ENCAMINHAR_SEDUC' | 'DEVOLVER_UNIDADE' | 'CLASSIFICAR';
const preencher = (t: string, pv: any, sol: string) => t.replaceAll('{aluno}', pv?.aluno ?? '').replaceAll('{unidade}', pv?.unidade ?? 'escola')
  .replaceAll('{data}', pv?.data ?? '').replaceAll('{prazo}', pv?.prazo ?? '').replaceAll('{solucao}', sol.trim() || '(descreva a solução)');

/** Detalhe com a linha do tempo. A família vê o registro, as mensagens e a solução; a equipe vê também as notas internas,
 *  trata em 1ª instância (unidade) ou 2ª instância (Secretaria), responde com modelo e prepara a comunicação ao Conselho Tutelar. */
export function OcorrenciaSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const res = useRpc<any>('ocorrencia_detalhe', { id }, { enabled: !!id });
  const recarregar = useRecarregarVidaEscolar();
  const toast = useToast();
  const [texto, setTexto] = useState('');
  const [sit, setSit] = useState('');
  const [acao, setAcao] = useState<AcaoOc>('NOTA_INTERNA');
  const [solucao, setSolucao] = useState('');
  const [modelo, setModelo] = useState('');
  const [msgEditada, setMsgEditada] = useState<string | null>(null);
  const [viol, setViol] = useState<string[] | null>(null);
  const [sigilosa, setSigilosa] = useState<boolean | null>(null);
  const [revisao, setRevisao] = useState(false);
  const [busy, setBusy] = useState(false);
  const o = res.data;
  const familia = o && !o.pode_atualizar;
  const limpar = () => { setTexto(''); setSit(''); setSolucao(''); setMsgEditada(null); setViol(null); setSigilosa(null); setRevisao(false); };
  const enviar = async (fn: string, args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc(fn, args);
      toast({ title: msg, tone: 'success' });
      limpar();
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const modelos = ((o?.modelos ?? []) as any[]).filter((m) => (o?.instancia === 'SECRETARIA' ? m.momento === 'DEVOLUTIVA_SEDUC' : m.momento === 'SOLUCAO'));
  const mod = modelos.find((m) => m.id === modelo) ?? modelos[0];
  const msgFamilia = msgEditada ?? (mod ? preencher(mod.texto, o?.previa, solucao) : solucao);
  const acoes: { value: AcaoOc; label: string }[] = o ? [
    { value: 'NOTA_INTERNA', label: 'Nota interna' },
    ...(o.sigilosa ? [] : [{ value: 'COMENTAR' as AcaoOc, label: 'Mensagem à família' }]),
    ...(o.pode_solucionar ? [{ value: 'SOLUCIONAR' as AcaoOc, label: 'Solucionar' }] : []),
    ...(o.pode_encaminhar_seduc ? [{ value: 'ENCAMINHAR_SEDUC' as AcaoOc, label: 'Encaminhar à SEDUC' }] : []),
    ...(o.pode_devolver && !o.pedido_familia ? [{ value: 'DEVOLVER_UNIDADE' as AcaoOc, label: 'Devolver à unidade' }] : []),
    ...(o.pode_classificar ? [{ value: 'CLASSIFICAR' as AcaoOc, label: 'Classificar' }] : []),
  ] : [];
  const violAtual = viol ?? ((o?.violencia ?? []) as string[]);
  return (
    <Sheet open={!!id} onClose={() => { limpar(); onClose(); }} title={o ? `${TIPO_OCORRENCIA[o.tipo]?.label ?? 'Ocorrência'} · ${o.primeiro_nome}` : 'Ocorrência'}
      subtitle={o ? `${o.turma ?? ''} · ${o.unidade ?? ''} · ${fmtDateTime(o.ocorrida_em)}` : ''} size="lg">
      {!o ? <Skeleton className="h-40" /> : (
        <div className="space-y-4 pt-1">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={SITUACAO_OCORRENCIA[o.situacao]?.tone}>{SITUACAO_OCORRENCIA[o.situacao]?.label}</Badge>
            <Badge tone={GRAVIDADE[o.gravidade]?.tone}>{GRAVIDADE[o.gravidade]?.label}</Badge>
            <Badge tone={o.origem === 'FAMILIA' ? 'purple' : 'blue'}>{o.origem === 'FAMILIA' ? 'Relatada pela família' : 'Registrada pela escola'}</Badge>
            <Badge tone={INSTANCIA_OCORRENCIA[o.instancia]?.tone}>{o.pedido_familia ? '2ª instância · a pedido da família' : INSTANCIA_OCORRENCIA[o.instancia]?.label}</Badge>
            {o.situacao !== 'ENCERRADA' && o.prazo && <Badge tone={o.vencida ? 'red' : 'gray'}>{o.vencida ? 'prazo vencido' : 'resposta até'} {diaCurto(o.prazo)}</Badge>}
            {o.origem === 'ESCOLA' && !o.sigilosa && (o.ciencia_familia_em ? <Badge tone="green" icon={CheckCheck}>Família ciente</Badge> : <Badge tone="amber">Aguardando a ciência da família</Badge>)}
            {o.sigilosa && <Badge tone="gray" icon={Lock}>Sigilosa: a família não vê</Badge>}
          </div>
          {!familia && (o.violencia ?? []).length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5 text-[12.5px]"><ShieldAlert className="size-4 text-red-700" aria-hidden />
              {(o.violencia as string[]).map((v) => <Badge key={v} tone="red">{VIOLENCIA[v]?.label ?? v}</Badge>)}
              {o.idade != null && <span className="text-muted">· {o.idade} anos na data</span>}
            </div>
          )}
          {!familia && o.exige_ct && (
            <div className="rounded-2xl bg-red-50 p-3 text-[13px] text-red-900 ring-1 ring-red-200">
              <b>Comunicação obrigatória ao Conselho Tutelar</b> (ECA, arts. 13 e 245; Lei 13.431/2017; Lei 13.819/2019). O expediente segue para a aprovação da direção em
              {' '}<Link to="/busca-ativa?painel=LEGAIS" className="font-semibold underline">Busca ativa › Comunicações legais</Link>. A família não é avisada antes da avaliação.
            </div>
          )}
          <Card className="p-3">
            <p className="text-[14.5px]">{o.descricao}</p>
            {o.local && <p className="mt-1 text-[12.5px] text-muted">Local: {o.local}</p>}
            {o.providencias && <p className="mt-2 whitespace-pre-line rounded-2xl bg-slate-50 p-2.5 text-[13px]"><b>Providências imediatas:</b> {o.providencias}</p>}
            {o.solucao && <p className="mt-2 whitespace-pre-line rounded-2xl bg-green-50 p-2.5 text-[13px] text-green-900"><b>Solução:</b> {o.solucao}</p>}
            <p className="mt-2 text-[12px] text-muted">Registro: {o.registrada_por ?? '—'}{o.motivo_seduc ? ` · Motivo da 2ª instância: ${o.motivo_seduc}` : ''}</p>
          </Card>
          {!familia && (o.encaminhamentos ?? []).length > 0 && (
            <div className="space-y-1">
              {(o.encaminhamentos as any[]).map((e) => (
                <div key={e.id} className="flex flex-wrap items-center gap-2 rounded-2xl bg-white p-2 text-[12.5px] ring-1 ring-line">
                  <Badge tone="red">Conselho Tutelar</Badge><span>{e.orgao ?? 'destinatário a definir'}</span>
                  <Badge tone={e.situacao === 'ENVIADO' || e.situacao === 'RECEBIDO' ? 'green' : 'amber'}>{e.situacao.replaceAll('_', ' ').toLowerCase()}</Badge>
                  {e.protocolo && <span className="text-muted">protocolo {e.protocolo}</span>}
                </div>
              ))}
            </div>
          )}
          {(o.eventos as any[]).length > 0 && (
            <ol className="space-y-2">
              {(o.eventos as any[]).map((e, i) => (
                <li key={i} className={clsx('rounded-2xl p-2.5 text-[13.5px] ring-1', e.interno ? 'mr-6 bg-slate-50 ring-slate-200'
                  : e.origem === 'FAMILIA' ? 'ml-6 bg-purple-50 ring-purple-100' : e.tipo === 'SOLUCAO' ? 'mr-6 bg-green-50 ring-green-100' : 'mr-6 bg-white ring-line')}>
                  <div className="flex flex-wrap items-center gap-1 text-[11.5px] font-semibold text-muted">
                    {e.interno && <Lock className="size-3" aria-label="interno" />}
                    {e.origem === 'FAMILIA' ? 'Família' : ROTULO_EVENTO[e.tipo] ?? 'Escola'} · {e.autor} · {fmtDateTime(e.em)}{e.situacao ? ` · ${SITUACAO_OCORRENCIA[e.situacao]?.label}` : ''}
                  </div>
                  <p className="whitespace-pre-line">{e.texto}</p>
                </li>
              ))}
            </ol>
          )}
          {o.pode_dar_ciencia && (
            <Button block variant="purple" icon={Check} loading={busy} onClick={() => enviar('familia_ocorrencia_ciente', { id: o.id }, 'Ciência registrada')}>Estou ciente</Button>
          )}

          {familia && (
            <div className="space-y-2">
              <Field label={revisao ? 'Por que você pede a análise da Secretaria?' : 'Mensagem para a escola'}>
                <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
              </Field>
              <Button block icon={Send} loading={busy} disabled={texto.trim().length < (revisao ? 10 : 3)}
                onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao: revisao ? 'PEDIR_REVISAO' : 'COMENTAR', texto },
                  revisao ? 'Pedido enviado à Secretaria de Educação' : 'Mensagem enviada à escola')}>
                {revisao ? 'Pedir a análise da Secretaria' : 'Enviar mensagem'}
              </Button>
              {o.pode_pedir_revisao && !revisao && (
                <button type="button" onClick={() => setRevisao(true)} className="w-full text-center text-[13px] font-semibold text-purple-800 underline">
                  Não concordo com a resposta: pedir a análise da Secretaria de Educação
                </button>
              )}
            </div>
          )}

          {!familia && o.pode_atualizar && (
            <div className="space-y-3 rounded-3xl bg-slate-50 p-3 ring-1 ring-line">
              <div className="no-scrollbar -mx-1 overflow-x-auto px-1"><Segmented value={acao} onChange={(v) => { setAcao(v); setMsgEditada(null); }} items={acoes} /></div>
              {acao === 'NOTA_INTERNA' && (
                <>
                  <Field label="Nota interna" hint="Fica só para a equipe (escola e Secretaria). A família não vê.">
                    <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
                  </Field>
                  <Segmented value={sit} onChange={setSit} items={[{ value: '', label: 'Manter situação' }, { value: 'EM_ACOMPANHAMENTO', label: 'Em acompanhamento' }, { value: 'ABERTA', label: 'Aberta' }]} />
                  <Button block icon={Lock} loading={busy} disabled={texto.trim().length < 3 && !sit}
                    onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao: 'NOTA_INTERNA', texto, situacao: sit || null }, 'Nota interna registrada')}>Registrar nota interna</Button>
                </>
              )}
              {acao === 'COMENTAR' && (
                <>
                  <Field label="Mensagem à família" hint="A família recebe no portal e pela IARA (WhatsApp, se vinculado). Não cite outras crianças.">
                    <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
                  </Field>
                  <Button block icon={Send} loading={busy} disabled={texto.trim().length < 3}
                    onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao: 'COMENTAR', texto }, 'Mensagem enviada à família')}>Enviar à família</Button>
                </>
              )}
              {acao === 'SOLUCIONAR' && (
                <>
                  <Field label="Solução" hint="O que foi feito e o resultado. A família vê este texto.">
                    <textarea value={solucao} onChange={(e) => { setSolucao(e.target.value); setMsgEditada(null); }} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
                  </Field>
                  {modelos.length > 0 && (
                    <Field label="Modelo de resposta">
                      <select value={mod?.id ?? ''} onChange={(e) => { setModelo(e.target.value); setMsgEditada(null); }} className={inputCls}>
                        {modelos.map((m) => <option key={m.id} value={m.id}>{m.titulo}</option>)}
                      </select>
                    </Field>
                  )}
                  {!o.sigilosa && (
                    <Field label="Mensagem que a família recebe" hint="Pode ajustar o texto antes de enviar.">
                      <textarea value={msgFamilia} onChange={(e) => setMsgEditada(e.target.value)} rows={5} maxLength={2000} className={`${inputCls} h-auto py-3`} />
                    </Field>
                  )}
                  <Button block variant="purple" icon={CheckCheck} loading={busy} disabled={solucao.trim().length < 10 || msgFamilia.includes('(descreva a solução)')}
                    onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao: 'SOLUCIONAR', solucao, texto: o.sigilosa ? '' : msgFamilia },
                      o.sigilosa ? 'Ocorrência encerrada' : 'Solução registrada e comunicada à família')}>
                    {o.sigilosa ? 'Encerrar (sigilosa, sem aviso à família)' : 'Encerrar e comunicar à família'}
                  </Button>
                </>
              )}
              {(acao === 'ENCAMINHAR_SEDUC' || acao === 'DEVOLVER_UNIDADE') && (
                <>
                  <Field label={acao === 'ENCAMINHAR_SEDUC' ? 'Motivo do encaminhamento à Secretaria (2ª instância)' : 'Orientação da Secretaria para a unidade'}
                    hint={acao === 'ENCAMINHAR_SEDUC' ? 'A família é avisada de que a análise passou à Secretaria; o motivo fica interno.' : 'Fica interno; a unidade volta a responder.'}>
                    <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
                  </Field>
                  <Button block icon={acao === 'ENCAMINHAR_SEDUC' ? ArrowUpRight : Undo2} loading={busy} disabled={texto.trim().length < 10}
                    onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao, texto }, acao === 'ENCAMINHAR_SEDUC' ? 'Encaminhada à Secretaria' : 'Devolvida à unidade')}>
                    {acao === 'ENCAMINHAR_SEDUC' ? 'Encaminhar à Secretaria' : 'Devolver à unidade'}
                  </Button>
                </>
              )}
              {acao === 'CLASSIFICAR' && (
                <>
                  <Field label="Tipos de violência" hint="Para tratamento, comunicação obrigatória e indicadores. A família não vê esta classificação.">
                    <div className="grid gap-1.5 sm:grid-cols-2">
                      {Object.entries(VIOLENCIA).map(([k, v]) => (
                        <label key={k} className="flex items-start gap-2 rounded-2xl bg-white p-2 text-[13px] ring-1 ring-line">
                          <input type="checkbox" className="mt-0.5 size-4 accent-purple-700" checked={violAtual.includes(k)}
                            onChange={(e) => setViol(e.target.checked ? [...violAtual, k] : violAtual.filter((x) => x !== k))} />
                          <span><b>{v.label}</b><span className="block text-[11.5px] text-muted">{v.hint}</span></span>
                        </label>
                      ))}
                    </div>
                  </Field>
                  <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={sigilosa ?? !!o.sigilosa} onChange={(e) => setSigilosa(e.target.checked)} className="size-5 accent-purple-700" />
                    Sigilosa: a família não vê (suspeita envolvendo a própria família)</label>
                  <Button block icon={ShieldAlert} loading={busy}
                    onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao: 'CLASSIFICAR', violencia: violAtual, sigilosa: sigilosa ?? o.sigilosa, texto }, 'Classificação registrada')}>
                    Salvar classificação
                  </Button>
                  {o.pode_comunicar_ct && !(o.encaminhamentos ?? []).length && (
                    <Button block variant="secondary" icon={FileWarning} loading={busy}
                      onClick={() => enviar('ocorrencia_atualizar', { id: o.id, acao: 'COMUNICAR_CT' }, 'Comunicação ao Conselho Tutelar preparada para aprovação')}>
                      Preparar comunicação ao Conselho Tutelar
                    </Button>
                  )}
                </>
              )}
            </div>
          )}
        </div>
      )}
    </Sheet>
  );
}

/** Registro de ocorrência: pela escola (gravidade, providências e violência) ou pela família (só o relato). */
export function NovaOcorrenciaSheet({ open, onClose, alunos, familia }: { open: boolean; onClose: () => void; alunos: { id: string; nome: string }[]; familia?: boolean }) {
  const recarregar = useRecarregarVidaEscolar();
  const toast = useToast();
  const [aluno, setAluno] = useState('');
  const [tipo, setTipo] = useState(familia ? 'OUTRO' : 'COMPORTAMENTO');
  const [grav, setGrav] = useState('LEVE');
  const [local, setLocal] = useState('');
  const [desc, setDesc] = useState('');
  const [prov, setProv] = useState('');
  const [viol, setViol] = useState<string[]>([]);
  const [sigilosa, setSigilosa] = useState(false);
  const [encerrar, setEncerrar] = useState(false);
  const [busy, setBusy] = useState(false);
  const alvo = aluno || (alunos.length === 1 ? alunos[0].id : '');
  const exigeCt = viol.includes('SEXUAL') || viol.includes('AUTOLESAO') || (grav === 'GRAVE' && viol.some((v) => ['FISICA', 'PSICOLOGICA', 'INSTITUCIONAL'].includes(v)));
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('ocorrencia_registrar', { student_id: alvo, tipo, gravidade: familia ? null : grav, local, descricao: desc, providencias: prov,
        violencia: familia ? [] : viol, sigilosa: !familia && sigilosa, encerrar: encerrar && !viol.length && grav !== 'GRAVE' });
      toast({ title: 'Ocorrência registrada', description: r.mensagem, tone: 'success' });
      recarregar();
      setDesc(''); setProv(''); setLocal(''); setEncerrar(false); setViol([]); setSigilosa(false);
      onClose();
    } catch (e) {
      toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={familia ? 'Relatar algo à escola' : 'Nova ocorrência'}
      subtitle={familia ? 'A direção recebe na hora e responde por aqui e pela IARA.' : 'A família vê o registro no portal e pela IARA (menos o que for sigiloso).'}
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
            <Field label="Providências imediatas (opcional)" hint="A família vê este campo junto com o registro."><textarea value={prov} onChange={(e) => setProv(e.target.value)} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
            <Field label="Houve violência? (opcional)" hint="Classificação interna para tratamento e indicadores.">
              <div className="flex flex-wrap gap-1.5">
                {Object.entries(VIOLENCIA).map(([k, v]) => (
                  <Chip key={k} active={viol.includes(k)} onClick={() => setViol(viol.includes(k) ? viol.filter((x) => x !== k) : [...viol, k])}>{v.label}</Chip>
                ))}
              </div>
            </Field>
            {exigeCt && (
              <p className="rounded-2xl bg-red-50 p-3 text-[13px] text-red-900 ring-1 ring-red-200">
                Ao registrar, a comunicação obrigatória ao Conselho Tutelar é preparada para a aprovação da direção (ECA, art. 13). {viol.includes('SEXUAL') && 'O registro fica sigiloso.'}
              </p>
            )}
            <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={sigilosa || viol.includes('SEXUAL')} disabled={viol.includes('SEXUAL')} onChange={(e) => setSigilosa(e.target.checked)} className="size-5 accent-purple-700" />Sigiloso: a família não vê</label>
            {!viol.length && grav !== 'GRAVE' && (
              <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={encerrar} onChange={(e) => setEncerrar(e.target.checked)} className="size-5 accent-purple-700" />Resolvido na hora: registrar já encerrada</label>
            )}
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
