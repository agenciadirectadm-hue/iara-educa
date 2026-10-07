// Busca ativa: rótulos, a resposta da família à ausência e a ficha de acompanhamento do aluno (equipe).
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, Check, MessageCircleQuestion, Send, ShieldAlert } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Meter, Section, Segmented, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';

export const MOTIVO_AUSENCIA: Record<string, string> = {
  SAUDE: 'Saúde', CONSULTA: 'Consulta ou atendimento', TRANSPORTE: 'Transporte', DIFICULDADE_FAMILIAR: 'Dificuldade familiar',
  RECUSA: 'Recusa ou dificuldade para frequentar a escola', OUTRO: 'Outro motivo', ESTA_NA_ESCOLA: 'A criança está na escola — conferir',
};
export const SITUACAO_AUSENCIA: Record<string, { label: string; tone: Tone }> = {
  AGUARDANDO_ESCLARECIMENTO: { label: 'Aguardando esclarecimento', tone: 'amber' }, MOTIVO_INFORMADO: { label: 'Motivo informado pela família', tone: 'blue' },
  JUSTIFICATIVA_EM_ANALISE: { label: 'Justificativa em análise', tone: 'purple' }, JUSTIFICATIVA_ACEITA: { label: 'Justificativa aceita', tone: 'green' },
  INJUSTIFICADA: { label: 'Ausência injustificada', tone: 'red' }, AFASTAMENTO: { label: 'Afastamento acompanhado', tone: 'teal' },
  ERRO_CORRIGIDO: { label: 'Erro de chamada corrigido', tone: 'gray' },
};
export const TIPO_TAREFA: Record<string, string> = {
  LIGAR: 'Ligar para a família', CONFERIR_TELEFONE: 'Conferir telefone', CONFERIR_PRESENCA: 'Conferir a chamada', REUNIAO: 'Contato da equipe / reunião',
  APOIO_SETOR: 'Apoio do setor competente', NOTIFICAR_CT: 'Notificar o Conselho Tutelar', AVALIAR_RISCO: 'Avaliar risco (urgente)', ENVIO_ALTERNATIVO: 'Envio pelo canal alternativo',
};
export const DESTINO_TAREFA: Record<string, string> = { SECRETARIA_UNIDADE: 'Secretaria da unidade', EQUIPE_PEDAGOGICA: 'Equipe pedagógica', DIRECAO: 'Direção', SEDUC: 'SEDUC', TRANSPORTE: 'Transporte escolar' };
export const SITUACAO_ENC: Record<string, { label: string; tone: Tone }> = {
  AGUARDANDO_APROVACAO: { label: 'Aguardando aprovação', tone: 'amber' }, APROVADO: { label: 'Aprovado — enviar', tone: 'blue' }, ENVIADO: { label: 'Enviado', tone: 'purple' },
  FALHA_ENVIO: { label: 'Falha no envio', tone: 'red' }, RECEBIDO: { label: 'Recebido pelo órgão', tone: 'green' }, RETORNO_REGISTRADO: { label: 'Retorno registrado', tone: 'green' },
  CANCELADO: { label: 'Cancelado', tone: 'gray' },
};
export const NIVEL_CONTATO: Record<string, string> = { '1': 'Primeiro contato', '2': 'Lembrete', '3': 'Contato da equipe', '4': 'Busca ativa', REDE: 'Rede de apoio', CORRECAO: 'Correção' };
export const STATUS_CONTATO: Record<string, { label: string; tone: Tone }> = {
  AGENDADA: { label: 'Agendada', tone: 'gray' }, ENVIADA: { label: 'Enviada', tone: 'blue' }, SIMULADA: { label: 'Enviada', tone: 'blue' },
  FALHA: { label: 'Falha de entrega', tone: 'red' }, CANCELADA: { label: 'Cancelada', tone: 'gray' }, RESPONDIDA: { label: 'Respondida', tone: 'green' },
};

export function useRecarregarBA() {
  const qc = useQueryClient();
  return () => ['busca_ativa_painel', 'busca_ativa_lista', 'busca_ativa_aluno', 'familia_ausencias', 'frequencia_regras', 'familia_frequencia'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Família: ausências aguardando o motivo, com as opções da mensagem da IARA. */
export function AusenciasFamilia() {
  const res = useRpc<any[]>('familia_ausencias', {});
  const [alvo, setAlvo] = useState<any | null>(null);
  if (!res.data?.length) return null;
  return (
    <Card className="mb-3 p-4 ring-2 ring-amber-200">
      <div className="flex items-center gap-2 font-semibold"><MessageCircleQuestion className="size-5 text-amber-600" />A escola quer saber se está tudo bem</div>
      <p className="mt-1 text-[13px] text-muted">Informe o motivo da ausência para a escola acompanhar e ajudar. Documentos (como atestado) vão em Documentos, na área do responsável.</p>
      <div className="mt-2 divide-y divide-line rounded-2xl ring-1 ring-line">
        {res.data.map((a) => (
          <div key={a.id} className="flex flex-wrap items-center gap-2 px-3 py-2 text-[13.5px]">
            <span className="min-w-0 flex-1"><b>{a.primeiro_nome}</b> não foi à {a.unidade} em {fmtDate(a.data)}</span>
            <Button size="sm" variant="purple" onClick={() => setAlvo(a)}>Informar o motivo</Button>
          </div>
        ))}
      </div>
      <ResponderSheet alvo={alvo} onClose={() => setAlvo(null)} />
    </Card>
  );
}

function ResponderSheet({ alvo, onClose }: { alvo: any | null; onClose: () => void }) {
  const [motivo, setMotivo] = useState('');
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarBA();
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_ausencia_responder', { id: alvo.id, motivo, texto, canal: 'PORTAL' });
      toast({ title: 'Obrigada!', description: r.mensagem, tone: 'success' });
      recarregar();
      setMotivo(''); setTexto('');
      onClose();
    } catch (e) {
      toast({ title: 'Não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Ausência de ${alvo?.primeiro_nome ?? ''} em ${alvo ? fmtDate(alvo.data) : ''}`} subtitle="Não precisa contar diagnóstico. Se a família precisar de apoio, a escola entra em contato."
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={!motivo || (motivo === 'OUTRO' && texto.trim().length < 3)} onClick={enviar}>Enviar</Button>}>
      <div className="space-y-2">
        {Object.entries(MOTIVO_AUSENCIA).map(([k, v]) => (
          <button key={k} type="button" onClick={() => setMotivo(k)}
            className={`flex w-full items-center gap-2 rounded-2xl px-3 py-3 text-left text-[14px] ring-1 ${motivo === k ? 'bg-purple-50 ring-2 ring-purple-500' : 'bg-white ring-line'}`}>
            {motivo === k && <Check className="size-4 text-purple-700" />}{v}
          </button>
        ))}
        <Field label={motivo === 'OUTRO' ? 'Conte com suas palavras' : 'Quer acrescentar algo? (opcional)'}>
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={1000} className={`${inputCls} h-auto py-3`} />
        </Field>
      </div>
    </Sheet>
  );
}

/** Equipe: ficha de acompanhamento do aluno — limite legal, ausências, contatos, tarefas, caso e encaminhamentos. */
export function AlunoBuscaAtiva({ studentId, onClose }: { studentId: string | null; onClose: () => void }) {
  const res = useRpc<any>('busca_ativa_aluno', { student_id: studentId }, { enabled: !!studentId });
  const toast = useToast();
  const recarregar = useRecarregarBA();
  const [acao, setAcao] = useState<any | null>(null);
  const [texto, setTexto] = useState('');
  const [extra, setExtra] = useState('');
  const [busy, setBusy] = useState(false);
  const d = res.data;
  const executar = async (fn: string, args: object, ok: string) => {
    setBusy(true);
    try {
      await rpc(fn, args);
      toast({ title: ok, tone: 'success' });
      recarregar();
      setAcao(null); setTexto(''); setExtra('');
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const ll = d?.limite_legal;
  return (
    <Sheet open={!!studentId} onClose={onClose} size="xl" title={d?.aluno?.nome ?? 'Acompanhamento'} subtitle={d ? `${d.aluno.turma} · ${d.aluno.unidade} · ${d.aluno.etapa === 'EF' ? 'ensino fundamental' : d.aluno.etapa === 'PRE' ? 'pré-escola' : 'creche'}` : ''}>
      {!d ? (res.error ? <ErrorState error={res.error} /> : <SkeletonList rows={5} />) : (
        <div className="space-y-4">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Card className="p-3 text-[13.5px]">
              <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Responsável</div>
              <div className="font-semibold">{d.responsavel?.nome ?? '—'}</div>
              <div className="text-muted">{d.responsavel?.whatsapp ?? d.responsavel?.telefone ?? 'sem telefone'}{d.responsavel?.alternativo ? ` · alternativo ${d.responsavel.alternativo}` : ''}</div>
            </Card>
            {ll ? (
              <Card className="p-3 text-[13.5px]">
                <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Limite legal de faltas (LDB)</div>
                <div><b>{ll.horas} h</b> de ausência ({ll.dias} dias) · alerta em {Math.round(ll.alerta_horas)} h · limite {Math.round(ll.limite_horas)} h</div>
                <Meter value={Number(ll.horas)} max={Number(ll.limite_horas)} tone={Number(ll.horas) > Number(ll.alerta_horas) ? 'red' : 'green'} className="mt-1" />
              </Card>
            ) : <Card className="p-3 text-[13px] text-muted">Creche: sem frequência mínima legal — acompanhamento e apoio à família.</Card>}
          </div>

          {d.caso && (
            <Section title="Caso de busca ativa" action={<span className="flex gap-1">{d.caso.urgente && <Badge tone="red" icon={ShieldAlert}>Urgente</Badge>}<Badge tone={d.caso.situacao === 'ENCERRADO' ? 'gray' : 'purple'}>{d.caso.situacao.replace('_', ' ').toLowerCase()}</Badge></span>}>
              <Card className="space-y-2 p-3 text-[13.5px]">
                <p>{d.caso.motivo}</p>
                <div className="space-y-1 border-l-2 border-purple-200 pl-3">
                  {(d.caso.eventos as any[]).map((e, i) => <div key={i} className="text-[13px]"><span className="text-muted">{fmtDateTime(e.em)} · {e.autor}</span><br />{e.texto}</div>)}
                </div>
                {d.pode_gerir && d.caso.situacao !== 'ENCERRADO' && (
                  <div className="flex flex-wrap gap-2 pt-1">
                    <Button size="sm" variant="secondary" onClick={() => setAcao({ tipo: 'evento', caso: d.caso.id })}>Registrar contato ou visita</Button>
                    <Button size="sm" variant="secondary" onClick={() => setAcao({ tipo: 'retorno', caso: d.caso.id })}>Voltou à escola</Button>
                    <Button size="sm" variant="secondary" onClick={() => setAcao({ tipo: 'encerrar', caso: d.caso.id })}>Encerrar o caso</Button>
                  </div>
                )}
              </Card>
            </Section>
          )}

          <Section title="Tarefas">
            <Card className="divide-y divide-line">
              {(d.tarefas as any[]).map((t) => (
                <div key={t.id} className="flex flex-wrap items-center gap-2 px-3 py-2 text-[13px]">
                  <Badge tone={t.prioridade === 'URGENTE' ? 'red' : t.prioridade === 'ALTA' ? 'amber' : 'gray'}>{TIPO_TAREFA[t.tipo] ?? t.tipo}</Badge>
                  <span className="min-w-0 flex-1">{t.descricao}{t.resultado ? <span className="text-muted"> — {t.resultado}</span> : null}</span>
                  <span className="text-[12px] text-muted">{DESTINO_TAREFA[t.destino]} · prazo {fmtDate(t.prazo)}</span>
                  {t.situacao === 'ABERTA' && d.pode_gerir ? <Button size="sm" onClick={() => setAcao({ tipo: 'tarefa', id: t.id, t })}>Concluir</Button> : <Badge tone={t.situacao === 'CONCLUIDA' ? 'green' : 'gray'}>{t.situacao.toLowerCase()}</Badge>}
                </div>
              ))}
              {!d.tarefas.length && <p className="p-3 text-[13px] text-muted">Sem tarefas.</p>}
            </Card>
          </Section>

          <Section title="Encaminhamentos" action={d.pode_gerir ? <Button size="sm" variant="secondary" onClick={() => setAcao({ tipo: 'encaminhar' })}>Preparar encaminhamento</Button> : undefined}>
            <Card className="divide-y divide-line">
              {(d.encaminhamentos as any[]).map((e) => {
                const st = SITUACAO_ENC[e.situacao];
                return (
                  <div key={e.id} className="space-y-1 px-3 py-2 text-[13px]">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge tone={e.tipo === 'CONSELHO_TUTELAR' ? 'red' : 'blue'}>{e.tipo === 'CONSELHO_TUTELAR' ? 'Conselho Tutelar' : 'Rede de apoio'}</Badge>
                      <Badge tone={st?.tone ?? 'gray'}>{st?.label ?? e.situacao}</Badge>
                      {e.obrigatorio && <Badge tone="red">Obrigatório (lei)</Badge>}
                      <span className="text-muted">{e.orgao ?? 'destinatário a definir'}{e.orgao && !e.orgao_verificado ? ' (não verificado)' : ''}</span>
                    </div>
                    <div>{e.fundamento}{e.necessidade ? ` · ${e.necessidade}` : ''}{e.protocolo ? ` · protocolo ${e.protocolo}` : ''}{e.retorno ? ` · retorno: ${e.retorno}` : ''}</div>
                    <div className="flex flex-wrap gap-2">
                      {e.situacao === 'AGUARDANDO_APROVACAO' && d.pode_aprovar && <Button size="sm" variant="purple" onClick={() => setAcao({ tipo: 'aprovar', id: e.id, e })}>Conferir e aprovar</Button>}
                      {['APROVADO', 'FALHA_ENVIO'].includes(e.situacao) && d.pode_gerir && <Button size="sm" icon={Send} onClick={() => setAcao({ tipo: 'envio', id: e.id })}>Registrar envio</Button>}
                      {e.situacao === 'ENVIADO' && d.pode_gerir && <Button size="sm" variant="secondary" onClick={() => executar('ba_encaminhamento', { acao: 'RECEBIDO', id: e.id }, 'Recebimento registrado')}>Órgão recebeu</Button>}
                      {['ENVIADO', 'RECEBIDO'].includes(e.situacao) && d.pode_gerir && <Button size="sm" variant="secondary" onClick={() => setAcao({ tipo: 'retorno_enc', id: e.id })}>Registrar retorno</Button>}
                    </div>
                  </div>
                );
              })}
              {!d.encaminhamentos.length && <p className="p-3 text-[13px] text-muted">Nenhum encaminhamento.</p>}
            </Card>
          </Section>

          <Section title="Ausências">
            <Card className="divide-y divide-line">
              {(d.ausencias as any[]).map((a) => (
                <div key={a.id} className="flex flex-wrap items-center gap-2 px-3 py-2 text-[13px]">
                  <span className="w-20 font-semibold">{fmtDate(a.data)}</span>
                  <Badge tone={SITUACAO_AUSENCIA[a.situacao]?.tone ?? 'gray'}>{SITUACAO_AUSENCIA[a.situacao]?.label}</Badge>
                  {a.risco && <Badge tone="red" icon={AlertTriangle}>Risco</Badge>}
                  <span className="min-w-0 flex-1 text-muted">{a.motivo ? MOTIVO_AUSENCIA[a.motivo] : ''}{a.motivo_texto ? ` — “${a.motivo_texto}”` : ''}{a.nivel > 1 ? ` · nível ${a.nivel}` : ''}</span>
                  {d.pode_gerir && ['AGUARDANDO_ESCLARECIMENTO', 'MOTIVO_INFORMADO', 'JUSTIFICATIVA_EM_ANALISE'].includes(a.situacao) && (
                    <select defaultValue="" onChange={(ev) => ev.target.value && executar('ba_ausencia_classificar', { id: a.id, situacao: ev.target.value }, 'Ausência classificada')}
                      className="h-8 rounded-xl bg-white px-2 text-[12.5px] ring-1 ring-line" aria-label="Classificar ausência">
                      <option value="">Classificar…</option><option value="JUSTIFICATIVA_ACEITA">Justificativa aceita</option><option value="INJUSTIFICADA">Injustificada</option>
                      <option value="AFASTAMENTO">Afastamento acompanhado</option>
                    </select>
                  )}
                </div>
              ))}
              {!d.ausencias.length && <EmptyState compact title="Sem ausências registradas" />}
            </Card>
            <p className="mt-1 text-[12px] text-muted">Justificativa aceita não apaga a ausência nem é abono: ela suspende os lembretes do período e marca a data de acompanhamento.</p>
          </Section>

          <Section title="Mensagens à família">
            <Card className="divide-y divide-line">
              {(d.contatos as any[]).map((k, i) => (
                <div key={i} className="px-3 py-2 text-[13px]">
                  <div className="flex flex-wrap items-center gap-2"><Badge tone="gray">{NIVEL_CONTATO[k.nivel] ?? k.nivel}</Badge><Badge tone={STATUS_CONTATO[k.status]?.tone ?? 'gray'}>{STATUS_CONTATO[k.status]?.label}</Badge>{k.status === 'SIMULADA' && <Simulado detail="Mensagem de demonstração: não saiu para nenhum telefone." />}
                    <span className="text-muted">{fmtDateTime(k.enviada_em)}</span>{k.falha && <span className="text-red-700">{k.falha}</span>}</div>
                  <p className="mt-1 text-ink-2">{k.texto}</p>
                </div>
              ))}
              {!d.contatos.length && <p className="p-3 text-[13px] text-muted">Nenhuma mensagem.</p>}
            </Card>
          </Section>
          {d.pode_gerir && !d.caso?.id && <Button variant="secondary" onClick={() => setAcao({ tipo: 'abrir' })}>Abrir caso de busca ativa</Button>}
          {d.pode_gerir && d.caso?.situacao === 'ENCERRADO' && <Button variant="secondary" onClick={() => setAcao({ tipo: 'abrir' })}>Abrir novo caso</Button>}

          <AcaoSheet acao={acao} d={d} texto={texto} setTexto={setTexto} extra={extra} setExtra={setExtra} busy={busy} onClose={() => setAcao(null)}
            onConfirmar={() => {
              if (!acao) return;
              if (acao.tipo === 'tarefa') executar('ba_tarefa_concluir', { id: acao.id, resultado: texto, sucesso: extra !== 'nao' }, 'Tarefa concluída');
              else if (acao.tipo === 'evento') executar('ba_caso', { acao: 'EVENTO', caso_id: acao.caso, tipo: extra || 'CONTATO_TELEFONE', texto }, 'Registrado no caso');
              else if (acao.tipo === 'retorno') executar('ba_caso', { acao: 'EVENTO', caso_id: acao.caso, tipo: 'RETORNO', texto }, 'Retorno registrado (o caso segue em acompanhamento)');
              else if (acao.tipo === 'encerrar') executar('ba_caso', { acao: 'ENCERRAR', caso_id: acao.caso, texto, resultado: extra }, 'Caso encerrado');
              else if (acao.tipo === 'abrir') executar('ba_caso', { acao: 'ABRIR', student_id: studentId, texto, urgente: extra === 'urgente' }, 'Caso aberto');
              else if (acao.tipo === 'aprovar') executar('ba_encaminhamento', { acao: 'APROVAR', id: acao.id, orgao_id: extra || null, comunicar_familia: texto === 'sim' }, 'Encaminhamento aprovado');
              else if (acao.tipo === 'envio') executar('ba_encaminhamento', { acao: 'ENVIO', id: acao.id, protocolo: texto, falhou: extra === 'falhou' }, extra === 'falhou' ? 'Falha registrada: tarefa de envio alternativo criada' : 'Envio registrado');
              else if (acao.tipo === 'retorno_enc') executar('ba_encaminhamento', { acao: 'RETORNO', id: acao.id, texto }, 'Retorno registrado');
              else if (acao.tipo === 'encaminhar') executar('ba_encaminhamento', { acao: 'CRIAR', student_id: studentId, tipo: extra || 'REDE_APOIO', fundamento: texto, orgao_id: acao.orgao ?? null,
                servico: acao.servico ?? null, necessidade: acao.necessidade ?? null, comunicar_familia: !!acao.comunicar }, 'Encaminhamento preparado: aguarda aprovação');
            }} setAcao={setAcao} />
        </div>
      )}
    </Sheet>
  );
}

function AcaoSheet({ acao, d, texto, setTexto, extra, setExtra, busy, onClose, onConfirmar, setAcao }: any) {
  if (!acao) return null;
  const titulos: Record<string, string> = {
    tarefa: 'Concluir a tarefa', evento: 'Registrar no caso', retorno: 'O aluno voltou à escola', encerrar: 'Encerrar o caso', abrir: 'Abrir caso de busca ativa',
    aprovar: 'Conferir e aprovar o encaminhamento', envio: 'Registrar o envio', retorno_enc: 'Retorno do órgão', encaminhar: 'Preparar encaminhamento',
  };
  const enc = acao.e;
  return (
    <Sheet open onClose={onClose} title={titulos[acao.tipo]} size={acao.tipo === 'aprovar' ? 'lg' : 'md'}
      footer={<Button block size="lg" loading={busy} onClick={onConfirmar}>Confirmar</Button>}>
      <div className="space-y-3 text-[14px]">
        {acao.tipo === 'tarefa' && <>
          <p className="text-muted">{acao.t.descricao}</p>
          <Segmented value={extra || 'sim'} onChange={setExtra} items={[{ value: 'sim', label: 'Com sucesso' }, { value: 'nao', label: 'Sem sucesso' }]} />
          <Field label="O que foi feito"><textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
        </>}
        {acao.tipo === 'evento' && <>
          <select value={extra} onChange={(e) => setExtra(e.target.value)} className={`${inputCls} h-11`}>
            <option value="CONTATO_TELEFONE">Contato por telefone</option><option value="MENSAGEM">Mensagem</option><option value="VISITA">Visita</option>
            <option value="REUNIAO">Reunião</option><option value="APOIO">Apoio oferecido</option><option value="OBSERVACAO">Observação</option>
          </select>
          <Field label="Registro"><textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} className={`${inputCls} h-auto py-3`} /></Field>
        </>}
        {acao.tipo === 'retorno' && <>
          <p className="text-muted">O retorno atualiza o caso, mas não o encerra: o encerramento exige registro da equipe.</p>
          <Field label="Registro"><textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
        </>}
        {acao.tipo === 'encerrar' && <>
          <Field label="Motivo do encerramento"><input value={texto} onChange={(e) => setTexto(e.target.value)} className={inputCls} /></Field>
          <Field label="Resultado"><textarea value={extra} onChange={(e) => setExtra(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
        </>}
        {acao.tipo === 'abrir' && <>
          <Field label="Motivo"><textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
          <label className="flex items-center gap-2"><input type="checkbox" checked={extra === 'urgente'} onChange={(e) => setExtra(e.target.checked ? 'urgente' : '')} />Urgente (indício de risco)</label>
        </>}
        {acao.tipo === 'aprovar' && enc && <>
          <Card className="space-y-1 bg-slate-50 p-3 text-[13px]">
            <div><b>Fundamento:</b> {enc.fundamento}</div>
            {enc.necessidade && <div><b>Necessidade:</b> {enc.necessidade}</div>}
            <div className="text-muted">O expediente é montado na aprovação com: identificação necessária do aluno e responsável, unidade e etapa, datas e horas de ausência, motivos informados, contatos e providências, apoios oferecidos e resultados, fundamento e servidor responsável.</div>
          </Card>
          <Field label="Destinatário (só órgãos verificados)">
            <select value={extra} onChange={(e) => setExtra(e.target.value)} className={`${inputCls} h-11`}>
              <option value="">{enc.orgao ? `Manter: ${enc.orgao}` : 'Escolha…'}</option>
              {(d.orgaos as any[]).filter((o) => (enc.tipo === 'CONSELHO_TUTELAR' ? o.tipo === 'CONSELHO_TUTELAR' : o.tipo !== 'CONSELHO_TUTELAR')).map((o) => (
                <option key={o.id} value={o.id} disabled={!o.verificado}>{o.nome}{o.verificado ? '' : ' — não verificado'}</option>
              ))}
            </select>
          </Field>
          <label className="flex items-start gap-2 text-[13px]"><input type="checkbox" className="mt-1" checked={texto === 'sim'} onChange={(e) => setTexto(e.target.checked ? 'sim' : '')} />
            <span>Comunicar a família {enc.tipo === 'CONSELHO_TUTELAR' ? '(só se não aumentar o risco à criança nem prejudicar a proteção)' : '(mensagem acolhedora, com o serviço e a necessidade mínima)'}</span></label>
        </>}
        {acao.tipo === 'envio' && <>
          <Segmented value={extra || 'ok'} onChange={setExtra} items={[{ value: 'ok', label: 'Enviado' }, { value: 'falhou', label: 'O canal oficial falhou' }]} />
          {extra !== 'falhou' && <Field label="Protocolo ou número do envio" hint="“Mensagem entregue” não é o mesmo que “caso recebido”: registre o recebimento depois."><input value={texto} onChange={(e) => setTexto(e.target.value)} className={inputCls} /></Field>}
        </>}
        {acao.tipo === 'retorno_enc' && <Field label="Retorno do órgão"><textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>}
        {acao.tipo === 'encaminhar' && <>
          <Segmented value={extra || 'REDE_APOIO'} onChange={setExtra} items={[{ value: 'REDE_APOIO', label: 'Rede de apoio' }, { value: 'CONSELHO_TUTELAR', label: 'Conselho Tutelar' }]} />
          <Field label="Destinatário">
            <select value={acao.orgao ?? ''} onChange={(e) => setAcao({ ...acao, orgao: e.target.value || null })} className={`${inputCls} h-11`}>
              <option value="">Escolha…</option>
              {(d.orgaos as any[]).filter((o) => ((extra || 'REDE_APOIO') === 'CONSELHO_TUTELAR' ? o.tipo === 'CONSELHO_TUTELAR' : o.tipo !== 'CONSELHO_TUTELAR')).map((o) => (
                <option key={o.id} value={o.id}>{o.nome}{o.verificado ? '' : ' — não verificado'}</option>
              ))}
            </select>
          </Field>
          {(extra || 'REDE_APOIO') === 'REDE_APOIO' && <>
            <Field label="Serviço"><input value={acao.servico ?? ''} onChange={(e) => setAcao({ ...acao, servico: e.target.value })} placeholder="Ex.: CRAS — acompanhamento familiar" className={inputCls} /></Field>
            <Field label="Necessidade (mínima)"><input value={acao.necessidade ?? ''} onChange={(e) => setAcao({ ...acao, necessidade: e.target.value })} placeholder="Ex.: transporte até a escola" className={inputCls} /></Field>
          </>}
          <Field label="Fundamento"><input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder={(extra || 'REDE_APOIO') === 'CONSELHO_TUTELAR' ? 'Ex.: ECA, art. 56, II — faltas reiteradas, providências esgotadas' : 'Ex.: necessidade de apoio identificada no contato'} className={inputCls} /></Field>
          <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" checked={!!acao.comunicar} onChange={(e) => setAcao({ ...acao, comunicar: e.target.checked })} />Comunicar a família quando aprovado</label>
        </>}
      </div>
    </Sheet>
  );
}
