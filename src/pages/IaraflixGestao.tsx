import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { ArrowLeft, Award, CheckCircle2, Clock, Film, ListChecks, Plus, Subtitles, Trash2, Upload, Users } from 'lucide-react';
import { useRpc, useRpcMutation } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { LIMITE_VIDEO, duracaoDoVideo, enviarDaAula, fmtDuracao } from '@/lib/iaraflix';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Kpi, PageHeader, Section, Segmented, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { IaraflixMarca } from '@/components/iaraflix';
import { VideosFamiliaGestao } from '@/components/videos-familia';

type AulaG = {
  id: string; ordem: number; titulo: string; resumo: string | null; pratica: string | null; duracao_s: number | null; tem_video: boolean;
  video_mime: string | null; video_bytes: number | null; tem_legenda: boolean; conferido_por: string | null; conferido_em: string | null;
  situacao: 'PUBLICADA' | 'RASCUNHO'; atualizado_em: string; atualizado_por: string | null;
};
type PerguntaG = { id: string; ordem: number; enunciado: string; opcoes: string[]; correta: number; explicacao: string | null };
type TrilhaG = { id: string; ordem: number; titulo: string; publico: string; situacao: string; perfis: string[]; obrigatoria: boolean; carga_horaria: number; aulas: AulaG[]; perguntas: PerguntaG[] };
type Gestao = { trilhas: TrilhaG[]; limite_bytes: number };

type Aba = 'aulas' | 'perguntas' | 'adesao' | 'familias';

export default function IaraflixGestao() {
  const { me } = useSession();
  const gestor = !!me?.permissions?.includes('iaraflix.manage');
  const videosFamilia = !!me?.permissions?.includes('videos_familia.manage');
  const [sp, setSp] = useSearchParams();
  const aba = (gestor || videosFamilia ? (sp.get('aba') as Aba) ?? (gestor ? 'aulas' : 'familias') : 'adesao') as Aba;
  const mudarAba = (a: Aba) => setSp((p) => { p.set('aba', a); return p; }, { replace: true });

  return (
    <div>
      <Link to="/iaraflix" className="mb-2 inline-flex items-center gap-1.5 text-sm font-semibold text-purple-700 hover:text-purple-900">
        <ArrowLeft className="size-4" aria-hidden /><IaraflixMarca claro className="text-[15px]" />
      </Link>
      <PageHeader
        eyebrow="IARAFLIX"
        title={gestor ? 'Gestão do treinamento' : 'Adesão da equipe'}
        subtitle={gestor
          ? 'Publique as aulas e os vídeos de cada trilha, ajuste as perguntas e acompanhe quem já concluiu.'
          : 'Quem da sua equipe já fez a trilha do próprio perfil no IARAFLIX.'}
      />
      {(gestor || videosFamilia) && (
        <Tabs value={aba} onChange={mudarAba} className="mb-4"
          items={[
            ...(gestor ? [{ value: 'aulas' as Aba, label: 'Aulas e vídeos' }, { value: 'perguntas' as Aba, label: 'Perguntas' }, { value: 'adesao' as Aba, label: 'Adesão' }] : []),
            ...(videosFamilia ? [{ value: 'familias' as Aba, label: 'Vídeos para as famílias' }] : []),
          ]} />
      )}
      {aba === 'familias' ? <VideosFamiliaGestao /> : aba === 'adesao' ? <Adesao /> : <Conteudo aba={aba} />}
    </div>
  );
}

function Conteudo({ aba }: { aba: 'aulas' | 'perguntas' }) {
  const q = useRpc<Gestao>('iaraflix_gestao', {}, { staleTime: 0 });
  const [sp, setSp] = useSearchParams();
  const [aula, setAula] = useState<AulaG | 'nova' | null>(null);
  const [pergunta, setPergunta] = useState<PerguntaG | 'nova' | null>(null);
  if (q.isLoading) return <SkeletonList rows={6} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const trilhas = q.data!.trilhas;
  const tid = sp.get('trilha') ?? trilhas[0]?.id;
  const t = trilhas.find((x) => x.id === tid) ?? trilhas[0];
  if (!t) return <EmptyState title="Nenhuma trilha cadastrada" />;
  const comVideo = t.aulas.filter((a) => a.tem_video).length;
  const aulaAberta = aula && aula !== 'nova' ? t.aulas.find((a) => a.id === aula.id) ?? aula : aula;

  return (
    <>
      <div className="mb-3 flex flex-wrap items-end gap-3">
        <Field label="Trilha">
          <select className={clsx(inputCls, 'h-11 min-w-[260px]')} value={t.id}
            onChange={(e) => setSp((p) => { p.set('trilha', e.target.value); return p; }, { replace: true })}>
            {trilhas.map((x) => (
              <option key={x.id} value={x.id}>
                {x.titulo} — {x.aulas.filter((a) => a.tem_video).length}/{x.aulas.length} vídeos
              </option>
            ))}
          </select>
        </Field>
        <div className="pb-2 text-[13px] text-muted">
          {t.publico} · {t.obrigatoria ? 'obrigatória' : 'opcional'} para {t.perfis.includes('*') ? 'todos os servidores' : `${t.perfis.length} perfil(is)`} ·
          certificado de {String(t.carga_horaria).replace('.', ',')} h
        </div>
        <div className="ml-auto pb-1">
          {aba === 'aulas'
            ? <Button icon={Plus} variant="purple" size="sm" onClick={() => setAula('nova')}>Nova aula</Button>
            : <Button icon={Plus} variant="purple" size="sm" onClick={() => setPergunta('nova')} disabled={t.perguntas.length >= 10}>Nova pergunta</Button>}
        </div>
      </div>

      {aba === 'aulas' ? (
        <>
          <p className="mb-2 text-[13px] text-muted">{comVideo} de {t.aulas.length} aulas com vídeo. Sem vídeo, a aula mostra o que cobre e a prática, e a pessoa marca como estudada.</p>
          <Card className="overflow-hidden">
            <Tabela colunas="2.25rem minmax(0,1fr) 9rem 6.5rem 7rem 9rem" largura={820} rotulo="Aulas da trilha">
              <TCabecalho><span>Nº</span><span>Aula</span><span>Vídeo</span><span>Legenda</span><span>Situação</span><span>Atualizada</span></TCabecalho>
              {t.aulas.map((a) => (
                <TLinha key={a.id} onClick={() => setAula(a)} rotulo={`Editar a aula ${a.ordem}: ${a.titulo}`}>
                  <TCelula className="font-display font-extrabold text-purple-700">{a.ordem}</TCelula>
                  <TCelula titulo={a.titulo} className="font-semibold text-ink">{a.titulo}</TCelula>
                  <TCelula livre>{a.tem_video
                    ? <span className="inline-flex items-center gap-1 text-[13px] font-semibold text-green-700"><Film className="size-4" aria-hidden />{fmtDuracao(a.duracao_s)}</span>
                    : <span className="text-[13px] text-amber-700">em produção</span>}</TCelula>
                  <TCelula className="text-[13px] text-muted">{a.tem_legenda ? 'sim' : '—'}</TCelula>
                  <TCelula livre>{a.situacao === 'PUBLICADA' ? <Badge tone="green">Publicada</Badge> : <Badge tone="amber">Rascunho</Badge>}</TCelula>
                  <TCelula className="text-[13px] text-muted" titulo={a.atualizado_por ?? undefined}>{fmtDate(a.atualizado_em)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
          <Orientacoes />
        </>
      ) : (
        <Card className="overflow-hidden">
          <Tabela colunas="2.25rem minmax(0,1fr) minmax(0,16rem)" largura={680} rotulo="Perguntas da trilha">
            <TCabecalho><span>Nº</span><span>Pergunta</span><span>Resposta certa</span></TCabecalho>
            {t.perguntas.map((p) => (
              <TLinha key={p.id} onClick={() => setPergunta(p)} rotulo={`Editar a pergunta ${p.ordem}`}>
                <TCelula className="font-display font-extrabold text-purple-700">{p.ordem}</TCelula>
                <TCelula titulo={p.enunciado} className="text-ink">{p.enunciado}</TCelula>
                <TCelula titulo={p.opcoes[p.correta]} className="text-green-800">{p.opcoes[p.correta]}</TCelula>
              </TLinha>
            ))}
            {t.perguntas.length === 0 && <div className="p-4 text-sm text-muted">Sem perguntas: a trilha conclui quando todas as aulas forem concluídas.</div>}
          </Tabela>
        </Card>
      )}

      <AulaEditor aberta={aulaAberta} trilha={t} onClose={() => setAula(null)} />
      <PerguntaEditor aberta={pergunta} trilha={t} onClose={() => setPergunta(null)} />
    </>
  );
}

function Orientacoes() {
  return (
    <Card className="mt-4 p-4 text-[13.5px] text-ink-2">
      <div className="mb-1 font-bold text-ink">Como gravar e publicar</div>
      <ul className="list-disc space-y-1 pl-5">
        <li>Grave a tela <b>só no ambiente de treinamento</b>, com as famílias fictícias. Nada de dado real: a cada envio, você confirma isso, e fica registrado.</li>
        <li>De 3 a 5 minutos por aula, uma tarefa por vídeo. Exporte em MP4 (H.264), 720p, perto de 1 Mbps: 5 minutos ficam em cerca de 40 MB (o limite é 50 MB).</li>
        <li>Legenda em WebVTT (.vtt) ajuda quem assiste sem som e quem tem deficiência auditiva.</li>
        <li>O vídeo vai direto para um armazenamento privado no Brasil; quem assiste recebe um link que vale 15 minutos, com o próprio nome marcado na tela.</li>
      </ul>
    </Card>
  );
}

function AulaEditor({ aberta, trilha, onClose }: { aberta: AulaG | 'nova' | null; trilha: TrilhaG; onClose: () => void }) {
  const toast = useToast();
  const confirm = useConfirm();
  const qc = useQueryClient();
  const salvar = useRpcMutation('iaraflix_aula_salvar', ['iaraflix_gestao', 'iaraflix_inicio', 'iaraflix_trilha']);
  const remover = useRpcMutation('iaraflix_video_remover', ['iaraflix_gestao', 'iaraflix_inicio', 'iaraflix_trilha']);
  const nova = aberta === 'nova';
  const a = aberta && aberta !== 'nova' ? aberta : null;
  const [f, setF] = useState({ titulo: '', resumo: '', pratica: '', ordem: '', situacao: 'RASCUNHO' as 'PUBLICADA' | 'RASCUNHO' });
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [legenda, setLegenda] = useState<File | null>(null);
  const [conferido, setConferido] = useState(false);
  const [pct, setPct] = useState<number | null>(null);

  useEffect(() => {
    if (!aberta) return;
    setF(a ? { titulo: a.titulo, resumo: a.resumo ?? '', pratica: a.pratica ?? '', ordem: String(a.ordem), situacao: a.situacao }
      : { titulo: '', resumo: '', pratica: '', ordem: '', situacao: 'RASCUNHO' });
    setArquivo(null); setLegenda(null); setConferido(false); setPct(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aberta === 'nova' ? 'nova' : a?.id]);

  const gravar = async () => {
    try {
      await salvar.mutateAsync({ id: a?.id ?? null, trilha_id: trilha.id, ...f, ordem: f.ordem || null });
      toast({ title: nova ? 'Aula criada' : 'Aula salva', tone: 'success' });
      if (nova) onClose();
    } catch (e) {
      toast({ title: 'Não foi possível salvar', description: (e as Error).message, tone: 'error' });
    }
  };

  const enviar = async (tipo: 'VIDEO' | 'LEGENDA') => {
    const file = tipo === 'VIDEO' ? arquivo : legenda;
    if (!a || !file) return;
    setPct(0);
    try {
      const duracao = tipo === 'VIDEO' ? await duracaoDoVideo(file) : null;
      await enviarDaAula({ aulaId: a.id, tipo, arquivo: file, conferido, duracao_s: duracao }, setPct);
      toast({ title: tipo === 'VIDEO' ? 'Vídeo publicado' : 'Legenda publicada', tone: 'success' });
      if (tipo === 'VIDEO') { setArquivo(null); setConferido(false); } else setLegenda(null);
      for (const k of ['iaraflix_gestao', 'iaraflix_inicio', 'iaraflix_trilha', 'iaraflix_aula']) qc.invalidateQueries({ queryKey: [k] });
    } catch (e) {
      toast({ title: 'O envio não foi concluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setPct(null);
    }
  };
  const retirar = async (tipo: 'VIDEO' | 'LEGENDA') => {
    if (!a) return;
    const ok = await confirm({ title: tipo === 'VIDEO' ? 'Retirar o vídeo desta aula?' : 'Retirar a legenda?', body: 'O arquivo é apagado do armazenamento. A aula continua, sem o vídeo.', confirm: 'Retirar', tone: 'danger' });
    if (!ok) return;
    try {
      await remover.mutateAsync({ aula_id: a.id, tipo });
      toast({ title: tipo === 'VIDEO' ? 'Vídeo retirado' : 'Legenda retirada', tone: 'success' });
    } catch (e) {
      toast({ title: 'Não foi possível retirar', description: (e as Error).message, tone: 'error' });
    }
  };

  const grande = !!arquivo && arquivo.size > LIMITE_VIDEO;

  return (
    <Sheet open={!!aberta} onClose={onClose} size="lg" title={nova ? 'Nova aula' : `Aula ${a?.ordem}: ${a?.titulo}`} subtitle={trilha.titulo}
      footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={onClose}>Fechar</Button><Button variant="purple" loading={salvar.isPending} onClick={gravar}>Salvar</Button></div>}>
      <div className="space-y-4">
        <Field label="Título"><input className={inputCls} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} data-autofocus /></Field>
        <Field label="O que a aula cobre" hint="Aparece embaixo do vídeo e substitui o vídeo enquanto ele está em produção.">
          <textarea className={clsx(inputCls, 'h-24 py-3')} value={f.resumo} onChange={(e) => setF({ ...f, resumo: e.target.value })} />
        </Field>
        <Field label="Prática no ambiente de treinamento">
          <textarea className={clsx(inputCls, 'h-20 py-3')} value={f.pratica} onChange={(e) => setF({ ...f, pratica: e.target.value })} />
        </Field>
        <div className="flex flex-wrap items-end gap-4">
          <Field label="Ordem"><input className={clsx(inputCls, 'w-24')} inputMode="numeric" value={f.ordem} onChange={(e) => setF({ ...f, ordem: e.target.value.replace(/\D/g, '') })} /></Field>
          <div>
            <span className="mb-1 block text-[13px] font-semibold text-ink-2">Situação</span>
            <Segmented value={f.situacao} onChange={(v) => setF({ ...f, situacao: v })} items={[{ value: 'PUBLICADA', label: 'Publicada' }, { value: 'RASCUNHO', label: 'Rascunho' }]} />
          </div>
        </div>

        {a && (
          <div className="rounded-2xl bg-slate-50 p-4 ring-1 ring-line">
            <div className="flex items-center gap-2 font-bold text-ink"><Film className="size-4 text-purple-700" aria-hidden />Vídeo</div>
            {a.tem_video ? (
              <p className="mt-1 text-[13.5px] text-ink-2">
                Publicado: {fmtDuracao(a.duracao_s)}{a.video_bytes ? ` · ${(a.video_bytes / 1048576).toFixed(1).replace('.', ',')} MB` : ''}.
                {a.conferido_por && <> Sem dados reais, conferido por {a.conferido_por} em {fmtDateTime(a.conferido_em)}.</>}
                <button type="button" className="ml-2 inline-flex items-center gap-1 font-semibold text-red-700 hover:underline" onClick={() => retirar('VIDEO')}>
                  <Trash2 className="size-3.5" aria-hidden />Retirar
                </button>
              </p>
            ) : <p className="mt-1 text-[13.5px] text-amber-800">Ainda sem vídeo.</p>}
            <div className="mt-3 space-y-2">
              <input type="file" accept="video/mp4,video/webm" className="block w-full text-sm file:mr-3 file:rounded-xl file:border-0 file:bg-purple-100 file:px-3 file:py-2 file:font-semibold file:text-purple-800"
                onChange={(e) => setArquivo(e.target.files?.[0] ?? null)} />
              {arquivo && (
                <>
                  <p className={clsx('text-[13px]', grande ? 'font-semibold text-red-700' : 'text-muted')}>
                    {arquivo.name} · {(arquivo.size / 1048576).toFixed(1).replace('.', ',')} MB{grande ? ' — passa de 50 MB: exporte em 720p, perto de 1 Mbps.' : ''}
                  </p>
                  <label className="flex items-start gap-2 rounded-xl bg-white p-3 text-[13.5px] text-ink ring-1 ring-line">
                    <input type="checkbox" className="mt-0.5 size-4 accent-purple-700" checked={conferido} onChange={(e) => setConferido(e.target.checked)} />
                    Conferi o vídeo inteiro: foi gravado no ambiente de treinamento e só mostra dados fictícios (nenhum aluno, família ou servidor real).
                  </label>
                  <Button icon={Upload} variant="purple" size="sm" disabled={!conferido || grande || pct != null} loading={pct != null} onClick={() => enviar('VIDEO')}>
                    {pct != null ? `Enviando… ${pct}%` : a.tem_video ? 'Trocar o vídeo' : 'Publicar o vídeo'}
                  </Button>
                  {pct != null && <div className="h-1.5 overflow-hidden rounded-full bg-slate-200"><div className="h-full bg-purple-500 transition-all" style={{ width: `${pct}%` }} /></div>}
                </>
              )}
            </div>
            <div className="mt-4 flex items-center gap-2 font-bold text-ink"><Subtitles className="size-4 text-purple-700" aria-hidden />Legenda (WebVTT)</div>
            <p className="mt-1 text-[13.5px] text-ink-2">
              {a.tem_legenda ? <>Publicada. <button type="button" className="font-semibold text-red-700 hover:underline" onClick={() => retirar('LEGENDA')}>Retirar</button></> : 'Sem legenda.'}
            </p>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <input type="file" accept=".vtt,text/vtt" className="block text-sm file:mr-3 file:rounded-xl file:border-0 file:bg-purple-100 file:px-3 file:py-2 file:font-semibold file:text-purple-800"
                onChange={(e) => setLegenda(e.target.files?.[0] ?? null)} />
              {legenda && <Button icon={Upload} size="sm" variant="secondary" disabled={!a.tem_video || pct != null} onClick={() => enviar('LEGENDA')}>Publicar a legenda</Button>}
            </div>
          </div>
        )}
        {nova && <p className="text-[13px] text-muted">Depois de criar a aula, abra-a de novo para enviar o vídeo.</p>}
      </div>
    </Sheet>
  );
}

function PerguntaEditor({ aberta, trilha, onClose }: { aberta: PerguntaG | 'nova' | null; trilha: TrilhaG; onClose: () => void }) {
  const toast = useToast();
  const confirm = useConfirm();
  const salvar = useRpcMutation('iaraflix_pergunta_salvar', ['iaraflix_gestao', 'iaraflix_trilha']);
  const p = aberta && aberta !== 'nova' ? aberta : null;
  const [f, setF] = useState({ enunciado: '', opcoes: ['', '', ''], correta: 0, explicacao: '' });
  useEffect(() => {
    if (!aberta) return;
    setF(p ? { enunciado: p.enunciado, opcoes: [...p.opcoes], correta: p.correta, explicacao: p.explicacao ?? '' } : { enunciado: '', opcoes: ['', '', ''], correta: 0, explicacao: '' });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aberta === 'nova' ? 'nova' : p?.id]);

  const gravar = async (excluir = false) => {
    if (excluir && !(await confirm({ title: 'Excluir esta pergunta?', confirm: 'Excluir', tone: 'danger' }))) return;
    try {
      await salvar.mutateAsync({ id: p?.id ?? null, trilha_id: trilha.id, ...f, excluir });
      toast({ title: excluir ? 'Pergunta excluída' : 'Pergunta salva', tone: 'success' });
      onClose();
    } catch (e) {
      toast({ title: 'Não foi possível salvar', description: (e as Error).message, tone: 'error' });
    }
  };

  return (
    <Sheet open={!!aberta} onClose={onClose} title={p ? `Pergunta ${p.ordem}` : 'Nova pergunta'} subtitle={trilha.titulo}
      footer={<div className="flex justify-between gap-2">
        {p ? <Button variant="ghost" className="text-red-700" icon={Trash2} onClick={() => gravar(true)}>Excluir</Button> : <span />}
        <div className="flex gap-2"><Button variant="secondary" onClick={onClose}>Fechar</Button><Button variant="purple" loading={salvar.isPending} onClick={() => gravar()}>Salvar</Button></div>
      </div>}>
      <div className="space-y-4">
        <Field label="Pergunta"><textarea className={clsx(inputCls, 'h-20 py-3')} value={f.enunciado} onChange={(e) => setF({ ...f, enunciado: e.target.value })} data-autofocus /></Field>
        <div>
          <span className="mb-1 block text-[13px] font-semibold text-ink-2">Opções (marque a certa)</span>
          <div className="space-y-2">
            {f.opcoes.map((o, i) => (
              <div key={i} className="flex items-center gap-2">
                <input type="radio" name="correta" className="size-4 accent-green-700" checked={f.correta === i} onChange={() => setF({ ...f, correta: i })} aria-label={`Opção ${i + 1} é a certa`} />
                <input className={clsx(inputCls, 'h-11')} value={o} placeholder={`Opção ${i + 1}`} onChange={(e) => setF({ ...f, opcoes: f.opcoes.map((x, j) => (j === i ? e.target.value : x)) })} />
              </div>
            ))}
          </div>
          {f.opcoes.length < 5 && <Button className="mt-2" size="sm" variant="ghost" icon={Plus} onClick={() => setF({ ...f, opcoes: [...f.opcoes, ''] })}>Mais uma opção</Button>}
        </div>
        <Field label="Explicação" hint="Aparece quando a pessoa erra: ensine o certo em uma frase.">
          <textarea className={clsx(inputCls, 'h-20 py-3')} value={f.explicacao} onChange={(e) => setF({ ...f, explicacao: e.target.value })} />
        </Field>
      </div>
    </Sheet>
  );
}

type Painel = {
  escopo: string; unidade: number | null; rede: boolean; simulado: boolean;
  resumo: { concluidas: number; andamento: number; ultimos7: number; previstos: number; concluiram: number };
  trilhas: { id: string; titulo: string; previstos: number | null; concluiram: number; andamento: number }[];
  unidades: { id: number; unidade: string; previstos: number; concluiram: number; pct: number | null }[] | null;
  pessoas: { nome: string; funcao: string; trilha: string; total: number; aulas_concluidas: number; concluida_em: string | null; situacao: 'CONCLUIDA' | 'ANDAMENTO' | 'NAO_INICIADA' }[] | null;
  recentes: { nome: string; trilha: string; unidade: string | null; concluida_em: string }[];
};

const FUNCAO: Record<string, string> = { PROFESSOR: 'Professor(a)', EDUCADOR: 'Educador(a)', AEE: 'Professor(a) do AEE', APOIO: 'Apoio interdisciplinar' };

function Adesao() {
  const [unidade, setUnidade] = useState<number | null>(null);
  const q = useRpc<Painel>('iaraflix_painel', unidade ? { unidade } : {}, { staleTime: 60_000 });
  const [filtro, setFiltro] = useState<'todas' | 'pendentes'>('todas');
  const pessoas = useMemo(() => (q.data?.pessoas ?? []).filter((p) => filtro === 'todas' || p.situacao !== 'CONCLUIDA'), [q.data, filtro]);
  if (q.isLoading) return <SkeletonList rows={6} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const d = q.data!;
  const pct = d.resumo.previstos ? Math.round((d.resumo.concluiram / d.resumo.previstos) * 100) : null;

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <h2 className="font-display text-lg font-extrabold text-ink">{d.escopo}</h2>
        {d.simulado && <Simulado detail="Adesão gerada para a demonstração a partir do cadastro fictício de servidores." />}
        {d.rede && unidade && <Button size="sm" variant="ghost" icon={ArrowLeft} onClick={() => setUnidade(null)}>Rede inteira</Button>}
      </div>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Users} tone="blue" label="Servidores com trilha do perfil" value={fmtInt(d.resumo.previstos)} sub="professores, educadores, AEE e apoio do cadastro" />
        <Kpi compact icon={Award} tone="green" label="Concluíram a trilha do perfil" value={pct == null ? '—' : `${pct}%`} sub={`${fmtInt(d.resumo.concluiram)} pessoas · meta de 90%`} />
        <Kpi compact icon={Clock} tone="amber" label="Em andamento" value={fmtInt(d.resumo.andamento)} sub="todas as trilhas" />
        <Kpi compact icon={CheckCircle2} tone="purple" label="Concluídas nos últimos 7 dias" value={fmtInt(d.resumo.ultimos7)} sub={`${fmtInt(d.resumo.concluidas)} certificados no total`} />
      </div>

      <Section title="Por trilha">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(0,1fr) 6.5rem 6.5rem 6.5rem 8rem" largura={640} rotulo="Adesão por trilha">
            <TCabecalho><span>Trilha</span><span>Previstos</span><span>Concluíram</span><span>Andamento</span><span>%</span></TCabecalho>
            {d.trilhas.filter((t) => d.unidade == null || t.previstos || t.concluiram || t.andamento).map((t) => {
              const p = t.previstos ? Math.round((t.concluiram / t.previstos) * 100) : null;
              return (
                <TLinha key={t.id}>
                  <TCelula titulo={t.titulo} className="font-semibold text-ink">{t.titulo}</TCelula>
                  <TCelula className="tabular text-muted">{t.previstos ? fmtInt(t.previstos) : '—'}</TCelula>
                  <TCelula className="tabular">{fmtInt(t.concluiram)}</TCelula>
                  <TCelula className="tabular text-muted">{fmtInt(t.andamento)}</TCelula>
                  <TCelula livre>{p == null ? <span className="text-muted">—</span> : <Barra pct={p} />}</TCelula>
                </TLinha>
              );
            })}
          </Tabela>
        </Card>
        <p className="mt-2 text-xs text-muted">"Previstos" conta quem está ativo no cadastro de servidores com a função da trilha. As trilhas da SEDUC contam as contas de cada perfil quando os acessos forem criados.</p>
      </Section>

      {d.unidades && (
        <Section title="Por unidade" subtitle="As que mais precisam de atenção primeiro. Toque para ver a equipe.">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(0,1fr) 6.5rem 6.5rem 8rem" largura={520} rotulo="Adesão por unidade">
              <TCabecalho><span>Unidade</span><span>Previstos</span><span>Concluíram</span><span>%</span></TCabecalho>
              {d.unidades.map((u) => (
                <TLinha key={u.id} onClick={() => setUnidade(u.id)} alerta={(u.pct ?? 0) < 30} rotulo={`Ver a equipe de ${u.unidade}`}>
                  <TCelula titulo={u.unidade} className="font-semibold text-ink">{u.unidade}</TCelula>
                  <TCelula className="tabular text-muted">{fmtInt(u.previstos)}</TCelula>
                  <TCelula className="tabular">{fmtInt(u.concluiram)}</TCelula>
                  <TCelula livre><Barra pct={u.pct ?? 0} /></TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}

      {d.pessoas && (
        <Section title="Equipe" action={<Segmented value={filtro} onChange={setFiltro} items={[{ value: 'todas', label: 'Todos' }, { value: 'pendentes', label: 'Faltam concluir' }]} />}>
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(0,1fr) 10rem minmax(0,12rem) 6rem 10rem" largura={760} rotulo="Equipe da unidade">
              <TCabecalho><span>Nome</span><span>Função</span><span>Trilha</span><span>Aulas</span><span>Situação</span></TCabecalho>
              {pessoas.map((p, i) => (
                <TLinha key={`${p.nome}-${p.trilha}-${i}`} alerta={p.situacao === 'NAO_INICIADA'}>
                  <TCelula fixa titulo={p.nome} className="font-semibold text-ink">{p.nome}</TCelula>
                  <TCelula className="text-muted">{FUNCAO[p.funcao] ?? p.funcao}</TCelula>
                  <TCelula titulo={p.trilha}>{p.trilha}</TCelula>
                  <TCelula className="tabular text-muted">{p.aulas_concluidas}/{p.total}</TCelula>
                  <TCelula livre>
                    {p.situacao === 'CONCLUIDA' ? <Badge tone="green">Concluiu em {fmtDate(p.concluida_em)}</Badge>
                      : p.situacao === 'ANDAMENTO' ? <Badge tone="amber">Em andamento</Badge> : <Badge tone="red">Não começou</Badge>}
                  </TCelula>
                </TLinha>
              ))}
              {pessoas.length === 0 && <div className="p-4 text-sm text-muted">Ninguém nesta lista.</div>}
            </Tabela>
          </Card>
        </Section>
      )}

      {d.recentes.length > 0 && (
        <Section title="Concluídas por último">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(0,1fr) minmax(0,1fr) minmax(0,12rem) 7rem" largura={640} rotulo="Conclusões recentes">
              <TCabecalho><span>Nome</span><span>Trilha</span><span>Unidade</span><span>Data</span></TCabecalho>
              {d.recentes.map((r, i) => (
                <TLinha key={i}>
                  <TCelula className="font-semibold text-ink" titulo={r.nome}>{r.nome}</TCelula>
                  <TCelula titulo={r.trilha}>{r.trilha}</TCelula>
                  <TCelula className="text-muted" titulo={r.unidade ?? undefined}>{r.unidade ?? '—'}</TCelula>
                  <TCelula className="tabular text-muted">{fmtDate(r.concluida_em)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
      <p className="mt-4 flex items-center gap-2 text-xs text-muted"><ListChecks className="size-4" aria-hidden />A meta do plano de implantação é ter 90% de cada perfil com a trilha concluída antes da virada.</p>
    </div>
  );
}

function Barra({ pct }: { pct: number }) {
  const cor = pct >= 90 ? 'bg-green-500' : pct >= 50 ? 'bg-amber-400' : 'bg-red-500';
  return (
    <span className="flex w-full items-center gap-2">
      <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-100"><span className={clsx('block h-full rounded-full', cor)} style={{ width: `${Math.min(100, pct)}%` }} /></span>
      <span className="w-9 text-right text-[12.5px] font-semibold tabular text-ink-2">{pct}%</span>
    </span>
  );
}
