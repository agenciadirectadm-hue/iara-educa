// Registro de reunião com o responsável: peças da ficha do aluno, do prontuário do responsável, da lista da rede,
// do controle externo e do portal da família.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router';
import clsx from 'clsx';
import { AlertTriangle, Check, CheckCheck, ClipboardPlus, FastForward, Lock, MessageSquareText, Send, ShieldAlert, Siren } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDateTime } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, MarcaSimulado, Simulado, Skeleton, SkeletonList, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';

export const TEMAS_REUNIAO: { value: string; label: string; protecao?: boolean }[] = [
  { value: 'VIOLENCIA_DOMESTICA', label: 'Violência doméstica', protecao: true },
  { value: 'VIOLENCIA_SEXUAL', label: 'Suspeita de violência sexual', protecao: true },
  { value: 'NEGLIGENCIA', label: 'Negligência ou abandono', protecao: true },
  { value: 'TRABALHO_INFANTIL', label: 'Trabalho infantil', protecao: true },
  { value: 'AUTOLESAO', label: 'Risco de autolesão', protecao: true },
  { value: 'INFREQUENCIA', label: 'Infrequência ou abandono escolar' },
  { value: 'DIREITO_EDUCACAO', label: 'Direito à educação' },
  { value: 'CONFLITO_FAMILIAR', label: 'Conflito familiar ou de guarda' },
  { value: 'OUTRO', label: 'Outro assunto' },
];
const TEMA_PROTECAO = new Set(TEMAS_REUNIAO.filter((t) => t.protecao).map((t) => t.value));

export const ORGAOS: { value: string; label: string; curto: string }[] = [
  { value: 'CONSELHO_TUTELAR', label: 'Conselho Tutelar', curto: 'Conselho' },
  { value: 'DEFENSORIA', label: 'Defensoria Pública', curto: 'Defensoria' },
  { value: 'MINISTERIO_PUBLICO', label: 'Ministério Público', curto: 'MP' },
];
const ORGAO = Object.fromEntries(ORGAOS.map((o) => [o.value, o]));

export const SITUACAO_REUNIAO: Record<string, { label: string; tone: Tone }> = {
  AGUARDANDO: { label: 'Aguardando o responsável', tone: 'amber' },
  ACEITA: { label: 'Confirmada', tone: 'green' },
  MANIFESTADA: { label: 'Com manifestação', tone: 'purple' },
  PRAZO_VENCIDO: { label: 'Sem validação', tone: 'red' },
  SEM_ENVIO: { label: 'Sem envio, por proteção', tone: 'gray' },
};

const MOTIVO_ENVIO: Record<string, string> = {
  PROTECAO: 'Proteção da criança',
  INDICADO: 'Indicado pela escola',
  SEM_VALIDACAO: 'Sem validação do responsável',
};
const PAPEL: Record<string, string> = {
  PROFESSOR: 'Professor(a)', DIRETOR_UNIDADE: 'Direção', SECRETARIA_ESCOLAR: 'Secretaria escolar', SECRETARIO: 'Secretário(a)', SUPERINTENDENCIA: 'Superintendência',
};
const EVENTO: Record<string, string> = {
  REGISTRO: 'Registro', ACEITE: 'Confirmação do responsável', MANIFESTACAO: 'Manifestação do responsável', ORGAOS_PREPARADOS: 'Órgãos externos',
  ENVIO_ORGAO: 'Envio a órgão externo', ORGAOS_CANCELADOS: 'Órgãos externos', CONSULTA_EXTERNA: 'Consulta externa',
};

export const etapaAviso = (dia: number | null | undefined) => (dia == null || dia < 0 ? null : dia === 0 ? 'D' : `D+${dia}`);

/** O registro precisa de atenção agora: prazo vencido, envio pendente ou aviso já em tom de alerta. */
export const reuniaoUrgente = (r: any) =>
  r.situacao === 'PRAZO_VENCIDO' || r.envios_pendentes > 0 || (r.situacao === 'AGUARDANDO' && r.ultimo_aviso >= 2);

const CHAVES = ['reunioes_lista', 'reuniao_detalhe', 'familia_reunioes', 'controle_reunioes', 'ocorrencias_lista', 'familia_ocorrencias', 'aluno_vida_escolar', 'citizen_home'];
function useRecarregar() {
  const qc = useQueryClient();
  return () => CHAVES.forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Um registro por linha. */
export function ReunioesTabela({ itens, onAbrir, mostrarAluno = true }: { itens: any[]; onAbrir: (id: string) => void; mostrarAluno?: boolean }) {
  if (!itens.length) return <EmptyState compact title="Nenhum registro de reunião" />;
  return (
    <Tabela colunas={mostrarAluno ? 'minmax(190px,1.2fr) 88px minmax(130px,.7fr) minmax(200px,1.1fr) minmax(230px,1.2fr) minmax(150px,.7fr)' : '88px minmax(150px,.8fr) minmax(200px,1.1fr) minmax(230px,1.2fr) minmax(150px,.7fr)'}
      largura={mostrarAluno ? 1060 : 860} rotulo="Reuniões com responsáveis">
      <TCabecalho>
        {mostrarAluno && <TCelula>Aluno</TCelula>}<TCelula>Data</TCelula><TCelula>{mostrarAluno ? 'Unidade' : 'Responsável'}</TCelula><TCelula>Assunto</TCelula><TCelula>Situação</TCelula><TCelula>Órgãos</TCelula>
      </TCabecalho>
      {itens.map((r) => (
        <TLinha key={r.id} onClick={() => onAbrir(r.id)} alerta={reuniaoUrgente(r)} rotulo={`${r.aluno}: ${r.tema_rotulo}`}>
          {mostrarAluno && (
            <TCelula fixa titulo={`${r.aluno} · ${r.codigo}`}>
              <span className={clsx(r.nao_lida ? 'font-extrabold' : 'font-semibold')}>{r.aluno}</span>
              {r.is_demo && <MarcaSimulado className="ml-1" />}
            </TCelula>
          )}
          <TCelula>{new Date(r.realizada_em).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}</TCelula>
          <TCelula titulo={mostrarAluno ? r.unidade : r.responsavel}>{mostrarAluno ? r.unidade : r.responsavel}</TCelula>
          <TCelula titulo={r.tema_rotulo}>
            {TEMA_PROTECAO.has(r.tema) && <ShieldAlert className="mr-1 inline size-3.5 text-red-700" aria-label="Proteção da criança" />}
            {r.tema_rotulo}
          </TCelula>
          <TCelula livre><SituacaoSelo r={r} /></TCelula>
          <TCelula titulo={(r.orgaos as string[]).map((o) => ORGAO[o]?.label ?? o).join(', ')}>
            {r.envios_pendentes > 0
              ? <span className="font-semibold text-red-800">{r.envios_pendentes} envio(s) pendente(s)</span>
              : (r.orgaos as string[]).length ? (r.orgaos as string[]).map((o) => ORGAO[o]?.curto ?? o).join(', ') : <span className="text-subtle">—</span>}
          </TCelula>
        </TLinha>
      ))}
    </Tabela>
  );
}

function SituacaoSelo({ r }: { r: any }) {
  const s = SITUACAO_REUNIAO[r.situacao];
  const etapa = r.situacao === 'AGUARDANDO' ? etapaAviso(r.ultimo_aviso) : null;
  return (
    <span className="inline-flex items-center gap-1">
      <Badge tone={r.situacao === 'AGUARDANDO' && r.ultimo_aviso >= 2 ? 'red' : s?.tone}>{s?.label ?? r.situacao}</Badge>
      {etapa && <Badge tone={r.ultimo_aviso >= 2 ? 'red' : 'gray'}>{etapa}</Badge>}
    </span>
  );
}

function Bloco({ titulo, children, tom }: { titulo: string; children: React.ReactNode; tom?: 'roxo' }) {
  return (
    <div className={clsx('rounded-2xl p-3 ring-1', tom === 'roxo' ? 'bg-purple-50 ring-purple-100' : 'bg-white ring-line')}>
      <div className="text-[11.5px] font-bold uppercase tracking-wide text-muted">{titulo}</div>
      <p className="mt-1 whitespace-pre-line text-[14px]">{children}</p>
    </div>
  );
}

/** O conteúdo do registro, igual para a equipe e para o controle externo. */
export function ReuniaoConteudo({ r, envios }: { r: any; envios?: React.ReactNode }) {
  const { can } = useSession();
  return (
    <div className="space-y-3 pt-1">
      <div className="flex flex-wrap items-center gap-1.5">
        <SituacaoSelo r={r} />
        {TEMA_PROTECAO.has(r.tema) && <Badge tone="red" icon={ShieldAlert}>Proteção da criança</Badge>}
        {!r.envia_responsavel && <Badge tone="gray" icon={Lock}>A família não vê</Badge>}
        <Badge tone="gray">{r.codigo}</Badge>
        {r.is_demo && <Simulado detail="Registro fictício, para a apresentação." />}
      </div>
      {r.situacao === 'PRAZO_VENCIDO' && (
        <div className="flex items-start gap-2 rounded-2xl bg-red-50 p-3 text-[13px] text-red-950 ring-1 ring-red-200">
          <Siren className="mt-0.5 size-4 shrink-0 text-red-700" aria-hidden />
          <span><b>O responsável não validou depois do último aviso.</b> O envio ao Conselho Tutelar, à Defensoria Pública e ao Ministério Público aguarda a confirmação do(a) Secretário(a) Municipal.</span>
        </div>
      )}
      {!r.envia_responsavel && (
        <div className="flex items-start gap-2 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-950 ring-1 ring-amber-200">
          <Lock className="mt-0.5 size-4 shrink-0 text-amber-700" aria-hidden />
          <span><b>Registro sem envio ao responsável, para proteger a criança.</b> Nenhum aviso é mandado à família.{r.motivo_sem_envio ? ` Motivo: ${r.motivo_sem_envio}` : ''}</span>
        </div>
      )}
      {r.ocorrencia_seduc_id && (
        <div className="flex flex-wrap items-center gap-2 rounded-2xl bg-red-50 p-3 text-[13px] text-red-950 ring-1 ring-red-200">
          <AlertTriangle className="size-4 shrink-0 text-red-700" aria-hidden />
          <span className="min-w-0 flex-1"><b>Ocorrência urgente com o(a) Secretário(a) Municipal</b>, para envio às autoridades competentes.</span>
          {can('ocorrencias.seduc') && <Link to="/ocorrencias?instancia=SECRETARIA&s=TODAS" className="font-semibold underline">Ver ocorrências</Link>}
        </div>
      )}
      <div className="grid grid-cols-2 gap-x-3 gap-y-1 text-[13px] text-muted">
        <span>Aluno: <b className="text-ink-2">{r.aluno}</b></span>
        <span>Unidade: <b className="text-ink-2">{r.unidade}</b></span>
        <span>Responsável: <b className="text-ink-2">{r.responsavel}</b></span>
        <span>Reunião: <b className="text-ink-2">{fmtDateTime(r.realizada_em)}</b></span>
        {r.participantes && <span className="col-span-2">Participantes: <b className="text-ink-2">{r.participantes}</b></span>}
        <span className="col-span-2">Registrado por: <b className="text-ink-2">{r.registrada_por}</b></span>
      </div>
      <Bloco titulo="Assunto tratado">{r.resumo}</Bloco>
      <Bloco titulo="Soluções propostas">{r.solucoes}</Bloco>
      <Bloco titulo="Posição da escola">{r.posicao_escola}</Bloco>
      <Bloco titulo="Posição do responsável">{r.posicao_responsavel}</Bloco>
      {r.manifestacao && <Bloco titulo={`Manifestação do responsável · ${fmtDateTime(r.resposta_em)}`} tom="roxo">{r.manifestacao}</Bloco>}
      {r.situacao === 'ACEITA' && (
        <div className="flex items-center gap-2 rounded-2xl bg-green-50 p-3 text-[13px] text-green-900 ring-1 ring-green-200">
          <CheckCheck className="size-4 shrink-0" aria-hidden /> Confirmado pelo responsável em {fmtDateTime(r.resposta_em)}.
        </div>
      )}
      {(r.envios as any[]).length > 0 && (
        <div>
          <div className="mb-1 text-[12.5px] font-semibold text-ink-2">Envio aos órgãos externos</div>
          {envios ?? (
            <Card className="divide-y divide-line">
              {(r.envios as any[]).map((e) => <EnvioLinha key={e.id} e={e} />)}
            </Card>
          )}
        </div>
      )}
      {(r.destinos as any[]).length > 0 && (
        <div>
          <div className="mb-1 text-[12.5px] font-semibold text-ink-2">Encaminhado a</div>
          <Card className="divide-y divide-line">
            {(r.destinos as any[]).map((d) => (
              <div key={d.papel} className="flex items-center gap-2 px-3 py-1.5 text-[13px]">
                <span className="min-w-0 flex-1 truncate">{PAPEL[d.papel] ?? d.papel}</span>
                {d.lido_em ? <span className="text-green-800">lido em {fmtDateTime(d.lido_em)}</span> : <span className="text-muted">ainda não leu</span>}
              </div>
            ))}
          </Card>
        </div>
      )}
      <div>
        <div className="mb-1 text-[12.5px] font-semibold text-ink-2">Linha do tempo</div>
        <ol className="space-y-2">
          {(r.eventos as any[]).map((e, i) => (
            <li key={i} className={clsx('rounded-2xl p-2.5 text-[13.5px] ring-1',
              e.tipo === 'AVISO' && e.dia >= 2 ? 'bg-red-50 ring-red-200' : e.tipo === 'AVISO' ? 'bg-amber-50 ring-amber-200' : e.tipo === 'MANIFESTACAO' ? 'bg-purple-50 ring-purple-100' : 'bg-white ring-line')}>
              <div className="flex flex-wrap items-center gap-1 text-[11.5px] font-semibold text-muted">
                {e.tipo === 'AVISO' && <Badge tone={e.dia >= 2 ? 'red' : 'amber'}>{etapaAviso(e.dia)}</Badge>}
                <span>{e.tipo === 'AVISO' ? e.titulo : EVENTO[e.tipo] ?? e.tipo}</span>
                <span>· {fmtDateTime(e.em)}{e.autor ? ` · ${e.autor}` : ''}</span>
              </div>
              <p className="mt-0.5 whitespace-pre-line">{e.texto}</p>
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

/** Um órgão por linha. Quem pode confirma o envio com o protocolo; sem isso, a linha só informa. */
function EnvioLinha({ e, podeConfirmar }: { e: any; podeConfirmar?: boolean }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [abrir, setAbrir] = useState(false);
  const [prot, setProt] = useState('');
  const [busy, setBusy] = useState(false);
  const confirmar = async () => {
    setBusy(true);
    try {
      await rpc('reuniao_envio_orgao', { id: e.id, protocolo: prot });
      toast({ title: 'Envio confirmado', description: `${ORGAO[e.orgao]?.label}: protocolo ${prot}.`, tone: 'success' });
      setAbrir(false); setProt('');
      recarregar();
    } catch (err) {
      toast({ title: 'Não confirmado', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="px-3 py-2 text-[13px]">
      <div className="flex flex-wrap items-center gap-2">
        <b className="min-w-0 flex-1 truncate">{ORGAO[e.orgao]?.label ?? e.orgao}</b>
        <span className="text-muted">{MOTIVO_ENVIO[e.motivo]}</span>
        {e.situacao === 'ENVIADO' && <Badge tone="green" icon={Check}>Enviado · {e.protocolo}</Badge>}
        {e.situacao === 'CANCELADO' && <Badge tone="gray">Cancelado: o responsável respondeu</Badge>}
        {e.situacao === 'AGUARDANDO_ENVIO' && <Badge tone="red">Aguarda confirmação</Badge>}
        {e.situacao === 'AGUARDANDO_ENVIO' && podeConfirmar && !abrir && <Button size="sm" variant="danger" icon={Send} onClick={() => setAbrir(true)}>Confirmar envio</Button>}
      </div>
      {abrir && (
        <div className="mt-2 flex gap-2">
          <input autoFocus value={prot} onChange={(ev) => setProt(ev.target.value)} maxLength={60} placeholder="Protocolo ou número do envio" aria-label="Protocolo ou número do envio" className={`${inputCls} h-10 flex-1`} />
          <Button size="sm" loading={busy} disabled={prot.trim().length < 3} onClick={confirmar}>Confirmar</Button>
        </div>
      )}
    </div>
  );
}

export function ReuniaoSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const res = useRpc<any>('reuniao_detalhe', { id }, { enabled: !!id });
  const recarregar = useRecarregar();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const r = res.data;
  const avancar = async () => {
    setBusy(true);
    try {
      await rpc('reuniao_demo_avancar', { id });
      recarregar();
    } catch (err) {
      toast({ title: 'Não foi possível avançar', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!id} onClose={onClose} title={r ? `Reunião: ${r.tema_rotulo}` : 'Registro de reunião'} subtitle={r ? `${r.aluno} · ${r.unidade}` : ''} size="lg"
      footer={r?.pode_avancar_dia ? (
        <div className="flex items-center gap-2">
          <Button block variant="secondary" icon={FastForward} loading={busy} onClick={avancar}>Avançar um dia</Button>
          <Simulado detail="Só na apresentação: mostra os avisos de D+1, D+2 e D+3 sem esperar o calendário." />
        </div>
      ) : undefined}>
      {res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : !r ? <Skeleton className="h-40" /> : (
        <ReuniaoConteudo r={r} envios={(
          <Card className="divide-y divide-line">
            {(r.envios as any[]).map((e) => <EnvioLinha key={e.id} e={e} podeConfirmar={r.pode_enviar_orgao} />)}
          </Card>
        )} />
      )}
    </Sheet>
  );
}

const agoraLocal = () => {
  const d = new Date();
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
};

export function NovaReuniaoSheet({ open, onClose, aluno, responsaveis, ocorrencias }: {
  open: boolean; onClose: () => void; aluno: { id: string; nome: string };
  responsaveis: { id: string; nome: string; parentesco?: string | null }[]; ocorrencias?: any[];
}) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [resp, setResp] = useState('');
  const [quando, setQuando] = useState(agoraLocal);
  const [participantes, setParticipantes] = useState('');
  const [tema, setTema] = useState('INFREQUENCIA');
  const [ocorrencia, setOcorrencia] = useState('');
  const [orgaos, setOrgaos] = useState<string[]>([]);
  const [resumo, setResumo] = useState('');
  const [solucoes, setSolucoes] = useState('');
  const [escola, setEscola] = useState('');
  const [posResp, setPosResp] = useState('');
  const [envia, setEnvia] = useState<boolean | null>(true);
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const alvo = resp || (responsaveis.length === 1 ? responsaveis[0].id : '');
  const protecao = TEMA_PROTECAO.has(tema);
  const sexual = tema === 'VIOLENCIA_SEXUAL';
  const ctTravado = protecao || envia === false || sexual;
  const marcados = ctTravado && !orgaos.includes('CONSELHO_TUTELAR') ? [...orgaos, 'CONSELHO_TUTELAR'] : orgaos;
  const trocarTema = (t: string) => {
    setTema(t);
    setEnvia(t === 'VIOLENCIA_DOMESTICA' ? null : t === 'VIOLENCIA_SEXUAL' ? false : true);
    setMotivo('');
  };
  const pronto = !!alvo && resumo.trim().length >= 20 && solucoes.trim().length >= 10 && escola.trim().length >= 10 && posResp.trim().length >= 5
    && (sexual || (envia !== null && (envia || motivo.trim().length >= 10)));
  const limpar = () => {
    setResp(''); setQuando(agoraLocal()); setParticipantes(''); setTema('INFREQUENCIA'); setOcorrencia(''); setOrgaos([]); setResumo(''); setSolucoes('');
    setEscola(''); setPosResp(''); setEnvia(true); setMotivo('');
  };
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('reuniao_registrar', {
        student_id: aluno.id, guardian_id: alvo, realizada_em: new Date(quando).toISOString(), participantes, tema, ocorrencia_id: ocorrencia || null, orgaos: marcados,
        resumo, solucoes, posicao_escola: escola, posicao_responsavel: posResp, envia_responsavel: sexual ? false : envia, motivo_sem_envio: motivo,
      });
      toast({ title: 'Reunião registrada', description: r.mensagem, tone: 'success' });
      recarregar();
      limpar();
      onClose();
    } catch (e) {
      toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const area = (label: string, v: string, set: (s: string) => void, hint?: string) => (
    <Field label={label} hint={hint}>
      <textarea value={v} onChange={(e) => set(e.target.value)} rows={3} maxLength={4000} className={`${inputCls} h-auto py-3`} />
    </Field>
  );
  return (
    <Sheet open={open} onClose={onClose} title="Registrar reunião com o responsável" subtitle={aluno.nome} size="lg"
      footer={<Button block size="lg" loading={busy} disabled={!pronto} onClick={enviar}>Registrar</Button>}>
      <div className="space-y-4 pt-1">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Field label="Responsável na reunião">
            <select value={alvo} onChange={(e) => setResp(e.target.value)} className={inputCls}>
              {responsaveis.length !== 1 && <option value="">Escolha…</option>}
              {responsaveis.map((g) => <option key={g.id} value={g.id}>{g.nome}{g.parentesco ? ` (${g.parentesco})` : ''}</option>)}
            </select>
          </Field>
          <Field label="Data e hora">
            <input type="datetime-local" value={quando} max={agoraLocal()} onChange={(e) => setQuando(e.target.value)} className={inputCls} />
          </Field>
        </div>
        <Field label="Assunto">
          <select value={tema} onChange={(e) => trocarTema(e.target.value)} className={inputCls}>
            {TEMAS_REUNIAO.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select>
        </Field>
        {protecao && (
          <div className="flex items-start gap-2 rounded-2xl bg-red-50 p-3 text-[13px] text-red-950 ring-1 ring-red-200">
            <Siren className="mt-0.5 size-4 shrink-0 text-red-700" aria-hidden />
            <span>Suspeita de maus-tratos deve ser comunicada ao Conselho Tutelar (ECA, art. 13). Este registro não substitui a comunicação: ele abre na hora uma ocorrência urgente ao(à) Secretário(a) Municipal, para envio às autoridades.</span>
          </div>
        )}
        <Field label="Participantes" hint="Opcional">
          <input value={participantes} onChange={(e) => setParticipantes(e.target.value)} maxLength={300} placeholder="Quem estava na reunião" className={inputCls} />
        </Field>
        {(ocorrencias ?? []).length > 0 && (
          <Field label="Ocorrência relacionada" hint="Opcional">
            <select value={ocorrencia} onChange={(e) => setOcorrencia(e.target.value)} className={inputCls}>
              <option value="">Nenhuma</option>
              {(ocorrencias as any[]).map((o) => <option key={o.id} value={o.id}>{new Date(o.ocorrida_em).toLocaleDateString('pt-BR')} · {String(o.descricao).slice(0, 60)}</option>)}
            </select>
          </Field>
        )}
        {area('Resumo do assunto tratado', resumo, setResumo)}
        {area('Soluções propostas', solucoes, setSolucoes)}
        {area('Posição da escola', escola, setEscola)}
        {area('Posição do responsável', posResp, setPosResp)}
        <Field label="Órgãos que devem acompanhar" hint={ctTravado ? 'O Conselho Tutelar entra sempre neste caso.' : 'Opcional. Cada órgão marcado abre ocorrência urgente ao(à) Secretário(a).'}>
          <div className="flex flex-wrap gap-2">
            {ORGAOS.map((o) => {
              const travado = ctTravado && o.value === 'CONSELHO_TUTELAR';
              return (
                <Chip key={o.value} active={marcados.includes(o.value)} icon={travado ? Lock : undefined}
                  onClick={() => { if (!travado) setOrgaos((x) => (x.includes(o.value) ? x.filter((y) => y !== o.value) : [...x, o.value])); }}>{o.label}</Chip>
              );
            })}
          </div>
        </Field>
        {sexual ? (
          <div className="flex items-start gap-2 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-950 ring-1 ring-amber-200">
            <Lock className="mt-0.5 size-4 shrink-0 text-amber-700" aria-hidden />
            <span>Este assunto é sigiloso: o registro não vai à família e nenhum aviso é enviado.</span>
          </div>
        ) : (
          <div className="rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
            <div className="text-[13.5px] font-semibold">Este registro pode ser enviado ao responsável?</div>
            <p className="mt-0.5 text-[12.5px] text-muted">Em violência doméstica, o aviso pode chegar a quem agride. Na dúvida, não envie.</p>
            <div className="mt-2 flex flex-wrap gap-2">
              <Chip active={envia === true} onClick={() => setEnvia(true)}>Sim, pode enviar</Chip>
              <Chip active={envia === false} icon={Lock} onClick={() => setEnvia(false)}>Não, há risco</Chip>
            </div>
            {envia === true && <p className="mt-2 text-[12.5px] text-muted">O responsável recebe agora e valida ou se manifesta. Sem resposta, os avisos seguem em D+1, D+2 e D+3; depois, o envio aos órgãos é preparado.</p>}
            {envia === false && (
              <div className="mt-2">
                <Field label="Por que não enviar?" hint="Fica no registro. A família não vê.">
                  <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2} maxLength={1000} className={`${inputCls} h-auto py-3`} />
                </Field>
              </div>
            )}
          </div>
        )}
      </div>
    </Sheet>
  );
}

/** Aba da ficha do aluno. */
export function ReunioesAluno({ aluno, responsaveis, ocorrencias }: {
  aluno: { id: string; nome: string }; responsaveis: { id: string; nome: string; parentesco?: string | null }[]; ocorrencias?: any[];
}) {
  const { can } = useSession();
  const res = useRpc<any>('reunioes_lista', { student_id: aluno.id });
  const [aberta, setAberta] = useState<string | null>(null);
  const [nova, setNova] = useState(false);
  return (
    <>
      {can('reunioes.write') && <div className="mb-3 flex justify-end"><Button icon={ClipboardPlus} onClick={() => setNova(true)}>Registrar reunião</Button></div>}
      {res.isLoading ? <SkeletonList rows={3} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden"><ReunioesTabela itens={res.data.itens} onAbrir={setAberta} mostrarAluno={false} /></Card>
      )}
      <p className="mt-2 text-[12px] text-muted">O registro vai a professor(a), direção, secretaria escolar, secretário(a) e superintendência e fica à disposição do controle externo.</p>
      <ReuniaoSheet id={aberta} onClose={() => setAberta(null)} />
      <NovaReuniaoSheet open={nova} onClose={() => setNova(false)} aluno={aluno} responsaveis={responsaveis} ocorrencias={ocorrencias} />
    </>
  );
}

/** Seção do prontuário do responsável. */
export function ReunioesResponsavel({ guardianId }: { guardianId: string }) {
  const { can } = useSession();
  const res = useRpc<any>('reunioes_lista', { guardian_id: guardianId }, { enabled: can('reunioes.read'), retry: false });
  const [aberta, setAberta] = useState<string | null>(null);
  if (!can('reunioes.read') || res.error) return null;
  return (
    <>
      {res.isLoading ? <SkeletonList rows={2} /> : <Card className="overflow-hidden"><ReunioesTabela itens={res.data.itens} onAbrir={setAberta} /></Card>}
      <ReuniaoSheet id={aberta} onClose={() => setAberta(null)} />
    </>
  );
}

/** Selo no topo da ficha do aluno quando há registro que precisa de atenção. */
export function useReunioesAluno(studentId: string | undefined, habilitado: boolean) {
  return useRpc<any>('reunioes_lista', { student_id: studentId }, { enabled: !!studentId && habilitado, retry: false });
}

// ---------------------------------------------------------------- Portal da família

export function ReunioesFamilia() {
  const res = useRpc<any>('familia_reunioes', {});
  const [abertaId, setAbertaId] = useState<string | null>(null);
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const itens = (res.data?.reunioes ?? []) as any[];
  const aberta = itens.find((r) => r.id === abertaId) ?? null;
  if (!itens.length) return <Card><EmptyState compact title="Nenhum registro de reunião" body="Quando a escola registrar uma reunião com você, ela aparece aqui e pela IARA, para você validar." /></Card>;
  return (
    <>
      <Card className="divide-y divide-line overflow-hidden">
        {itens.map((r) => {
          const ultimo = (r.avisos as any[]).at(-1)?.dia ?? 0;
          return (
            <button key={r.id} type="button" onClick={() => setAbertaId(r.id)} className={clsx('flex w-full items-center gap-2 px-4 py-3 text-left text-[13.5px] transition',
              r.pode_responder && ultimo >= 2 ? 'bg-red-50 hover:bg-red-100/70' : r.pode_responder ? 'bg-amber-50 hover:bg-amber-100/70' : 'bg-white hover:bg-slate-50')}>
              <span className="w-12 shrink-0 tabular text-muted">{new Date(r.realizada_em).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}</span>
              <span className="min-w-0 flex-1 truncate"><b>{r.aluno}</b> · {r.tema_rotulo}</span>
              {r.pode_responder
                ? <Badge tone={ultimo >= 2 ? 'red' : 'amber'}>{ultimo >= 2 ? 'Urgente: responda' : 'Responda'}</Badge>
                : <Badge tone={r.situacao === 'ACEITA' ? 'green' : 'purple'}>{r.situacao === 'ACEITA' ? 'Confirmado' : 'Manifestado'}</Badge>}
            </button>
          );
        })}
      </Card>
      <ReuniaoFamiliaSheet r={aberta} onClose={() => setAbertaId(null)} />
    </>
  );
}

function ReuniaoFamiliaSheet({ r, onClose }: { r: any | null; onClose: () => void }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [manifestar, setManifestar] = useState(false);
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);
  const fechar = () => { setManifestar(false); setTexto(''); onClose(); };
  const responder = async (acao: 'ACEITAR' | 'MANIFESTAR') => {
    setBusy(true);
    try {
      const x = await rpc<any>('familia_reuniao_responder', { id: r.id, acao, texto, canal: 'PORTAL' });
      toast({ title: acao === 'ACEITAR' ? 'Registro confirmado' : 'Manifestação registrada', description: x.mensagem, tone: 'success' });
      recarregar();
      fechar();
    } catch (e) {
      toast({ title: 'Não foi registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const avisos = (r?.avisos ?? []) as any[];
  const ultimo = avisos.at(-1);
  return (
    <Sheet open={!!r} onClose={fechar} title={r ? `Reunião sobre ${r.aluno}` : ''} subtitle={r ? `${r.unidade} · ${fmtDateTime(r.realizada_em)}` : ''} size="lg"
      footer={r?.pode_responder ? (manifestar ? (
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" disabled={busy} onClick={() => setManifestar(false)}>Voltar</Button>
          <Button className="flex-[2]" icon={Send} loading={busy} disabled={texto.trim().length < 10} onClick={() => responder('MANIFESTAR')}>Enviar manifestação</Button>
        </div>
      ) : (
        <div className="flex gap-2">
          <Button className="flex-[1.4]" variant="purple" icon={Check} loading={busy} onClick={() => responder('ACEITAR')}>Confirmo o registro</Button>
          <Button className="flex-1" variant="secondary" icon={MessageSquareText} disabled={busy} onClick={() => setManifestar(true)}>Quero me manifestar</Button>
        </div>
      )) : undefined}>
      {r && (
        <div className="space-y-3 pt-1">
          {r.pode_responder && ultimo && (
            <div className={clsx('rounded-2xl p-3 text-[13.5px] ring-1', ultimo.dia >= 2 ? 'bg-red-50 text-red-950 ring-red-200' : 'bg-amber-50 text-amber-950 ring-amber-200')}>
              <div className="flex flex-wrap items-center gap-1.5 font-bold">
                {ultimo.dia >= 2 && <Siren className="size-4 text-red-700" aria-hidden />}
                {ultimo.titulo}
              </div>
              <p className="mt-1 whitespace-pre-line">{ultimo.texto}</p>
              <p className="mt-1 text-[12px] opacity-80">Enviado em {fmtDateTime(ultimo.em)}.</p>
            </div>
          )}
          <Bloco titulo="Assunto tratado">{r.resumo}</Bloco>
          <Bloco titulo="Soluções propostas">{r.solucoes}</Bloco>
          <Bloco titulo="Posição da escola">{r.posicao_escola}</Bloco>
          <Bloco titulo="Sua posição">{r.posicao_responsavel}</Bloco>
          {r.manifestacao && <Bloco titulo={`Sua manifestação · ${fmtDateTime(r.resposta_em)}`} tom="roxo">{r.manifestacao}</Bloco>}
          {r.situacao === 'ACEITA' && <div className="flex items-center gap-2 rounded-2xl bg-green-50 p-3 text-[13px] text-green-900 ring-1 ring-green-200"><CheckCheck className="size-4 shrink-0" aria-hidden /> Você confirmou em {fmtDateTime(r.resposta_em)}.</div>}
          {r.pode_responder && (manifestar ? (
            <Field label="Sua manifestação" hint="Ela fica junto do registro. A escola e os órgãos de acompanhamento podem ler.">
              <textarea autoFocus value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} maxLength={4000} className={`${inputCls} h-auto py-3`} />
            </Field>
          ) : (
            <p className="text-[13px] text-muted">Responder não significa concordar: se algo não está certo, use “Quero me manifestar”.</p>
          ))}
        </div>
      )}
    </Sheet>
  );
}

/** Faixa do portal da família quando há registro para validar. */
export function FaixaReuniaoFamilia() {
  const res = useRpc<any>('familia_reunioes', {}, { retry: false });
  const pendentes = ((res.data?.reunioes ?? []) as any[]).filter((r) => r.pode_responder);
  if (!pendentes.length) return null;
  const ultimo = Math.max(...pendentes.map((r) => (r.avisos as any[]).at(-1)?.dia ?? 0));
  const urgente = ultimo >= 2;
  return (
    <Link to="/escola?aba=reunioes" className={clsx('mt-3 flex items-center gap-3 rounded-3xl p-4 ring-1 transition', urgente ? 'bg-red-50 text-red-950 ring-red-200 hover:bg-red-100/70' : 'bg-amber-50 text-amber-950 ring-amber-200 hover:bg-amber-100/70')}>
      {urgente ? <Siren className="size-6 shrink-0 text-red-700" aria-hidden /> : <AlertTriangle className="size-6 shrink-0 text-amber-700" aria-hidden />}
      <span className="min-w-0 flex-1">
        <b className="block">{urgente ? 'Urgente: registro de reunião sem validação' : 'Registro de reunião para validar'}</b>
        <span className="text-[13.5px]">{urgente ? 'Responda agora: confirme ou se manifeste.' : 'A escola registrou uma reunião. Leia e responda: confirme ou se manifeste.'}</span>
      </span>
    </Link>
  );
}

/** Faixa do início do(a) Secretário(a): envios às autoridades que dependem de confirmação. */
export function FaixaEnviosPendentes() {
  const { can } = useSession();
  const res = useRpc<any>('reunioes_lista', {}, { enabled: can('reunioes.enviar'), retry: false });
  const n = res.data?.contagem?.envios_pendentes ?? 0;
  if (!can('reunioes.enviar') || !n) return null;
  return (
    <Link to="/reunioes?situacao=ENVIO_PENDENTE" className="mb-3 flex items-center gap-3 rounded-3xl bg-red-50 p-4 text-red-950 ring-1 ring-red-200 transition hover:bg-red-100/70">
      <Siren className="size-6 shrink-0 text-red-700" aria-hidden />
      <span className="min-w-0 flex-1">
        <b className="block">{n} envio(s) às autoridades aguardam a sua confirmação</b>
        <span className="text-[13.5px]">Conselho Tutelar, Defensoria Pública e Ministério Público. Abra o registro e confirme com o protocolo.</span>
      </span>
    </Link>
  );
}
