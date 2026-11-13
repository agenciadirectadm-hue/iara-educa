import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { ArrowLeft, ArrowRight, CheckCircle2, ClipboardCheck, Expand, Shrink, ShieldCheck } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDuracao, linkDaAula } from '@/lib/iaraflix';
import { Button, ButtonLink, Card, ErrorState, SkeletonList } from '@/components/ui';
import { useToast } from '@/components/overlays';
import { IaraflixMarca, IpeAssistindo } from '@/components/iaraflix';

type Aula = {
  id: string; ordem: number; titulo: string; resumo: string | null; pratica: string | null; duracao_s: number | null;
  tem_video: boolean; tem_legenda: boolean; situacao: string;
  trilha: { id: string; titulo: string; total: number };
  posicao_s: number; assistido_s: number; concluida: boolean;
  anterior: string | null; proxima: { id: string; titulo: string } | null;
  marca: { nome: string; unidade: string | null };
};

export default function IaraflixAula() {
  const { id } = useParams();
  const qc = useQueryClient();
  const toast = useToast();
  const navigate = useNavigate();
  const q = useRpc<Aula>('iaraflix_aula', { id }, { staleTime: 0 });
  const [concluida, setConcluida] = useState(false);
  const [marcando, setMarcando] = useState(false);
  useEffect(() => setConcluida(!!q.data?.concluida), [q.data?.id, q.data?.concluida]);

  const aoConcluir = useCallback(() => {
    setConcluida(true);
    toast({ title: 'Aula concluída', description: 'O seu progresso foi salvo.', tone: 'success' });
    qc.invalidateQueries({ queryKey: ['iaraflix_trilha'] });
    qc.invalidateQueries({ queryKey: ['iaraflix_inicio'] });
  }, [qc, toast]);

  if (q.isLoading) return <SkeletonList rows={5} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const a = q.data!;

  const estudada = async () => {
    setMarcando(true);
    try {
      const r = await rpc<{ concluida: boolean }>('iaraflix_progresso', { aula_id: a.id, estudada: true });
      if (r.concluida) aoConcluir();
    } catch (e) {
      toast({ title: 'Não foi possível salvar', description: (e as Error).message, tone: 'error' });
    } finally {
      setMarcando(false);
    }
  };

  return (
    <div>
      <Link to={`/iaraflix/trilha/${a.trilha.id}`} className="mb-3 inline-flex items-center gap-1.5 text-sm font-semibold text-purple-700 hover:text-purple-900">
        <ArrowLeft className="size-4" aria-hidden />{a.trilha.titulo}
      </Link>

      {a.tem_video ? (
        <Player key={a.id} aula={a} onConcluida={aoConcluir} />
      ) : (
        <div className="relative grid aspect-video w-full place-items-center overflow-hidden rounded-[22px] bg-[#16072a] text-white">
          <div aria-hidden className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_80%_at_70%_30%,rgb(168_70_232/0.4),transparent_70%)]" />
          <div className="relative flex flex-col items-center gap-2 px-6 text-center sm:flex-row sm:gap-6 sm:text-left">
            <IpeAssistindo height={170} className="hidden sm:block" />
            <div className="max-w-sm">
              <IaraflixMarca className="text-2xl" />
              <p className="mt-2 font-display text-lg font-extrabold">O vídeo desta aula está em produção.</p>
              <p className="mt-1 text-[14px] text-white/80">Enquanto isso, leia o que a aula cobre, faça a prática e marque como estudada.</p>
            </div>
          </div>
        </div>
      )}

      <div className="mt-4 grid gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
        <div className="min-w-0">
          <div className="text-[12px] font-bold uppercase tracking-[0.12em] text-purple-700">Aula {a.ordem} de {a.trilha.total} · {a.trilha.titulo}</div>
          <h1 className="mt-1 font-display text-[26px] font-extrabold leading-tight text-ink text-balance">{a.titulo}</h1>
          {a.resumo && <p className="mt-2 text-[15px] text-ink-2 text-pretty">{a.resumo}</p>}
          {a.pratica && (
            <Card className="mt-4 flex items-start gap-3 p-4">
              <span className="inline-flex size-10 shrink-0 items-center justify-center rounded-xl bg-green-100 text-green-800"><ClipboardCheck className="size-5" aria-hidden /></span>
              <div>
                <div className="text-[13px] font-bold uppercase tracking-wide text-green-800">Prática no ambiente de treinamento</div>
                <p className="mt-0.5 text-[15px] text-ink">{a.pratica}</p>
                <p className="mt-1 text-xs text-muted">O ambiente de treinamento só tem dados fictícios (como a Maria, o Davi e a Ana Luísa): pode errar à vontade.</p>
              </div>
            </Card>
          )}
          {!a.tem_video && !concluida && (
            <Button className="mt-4" variant="purple" icon={CheckCircle2} loading={marcando} onClick={estudada}>Marcar como estudada</Button>
          )}
        </div>
        <div className="space-y-3">
          <Card className={clsx('p-4', concluida && 'ring-2 ring-green-200')}>
            {concluida ? (
              <div className="flex items-center gap-2 font-semibold text-green-800"><CheckCircle2 className="size-5" aria-hidden />Aula concluída</div>
            ) : (
              <p className="text-[13.5px] text-muted">{a.tem_video ? 'A aula conta como concluída quando você assiste a pelo menos 90% do vídeo. Pode pausar e voltar depois: o IARAFLIX guarda onde você parou.' : 'Sem vídeo ainda: a aula conta quando você marca como estudada.'}</p>
            )}
            <div className="mt-3 flex flex-wrap gap-2">
              {a.anterior && <ButtonLink to={`/iaraflix/aula/${a.anterior}`} variant="secondary" size="sm" icon={ArrowLeft}>Anterior</ButtonLink>}
              {a.proxima
                ? <Button size="sm" variant={concluida ? 'purple' : 'secondary'} onClick={() => navigate(`/iaraflix/aula/${a.proxima!.id}`)}>Próxima <ArrowRight className="size-4" aria-hidden /></Button>
                : <ButtonLink to={`/iaraflix/trilha/${a.trilha.id}#perguntas`} size="sm" variant={concluida ? 'purple' : 'secondary'}>Perguntas e certificado</ButtonLink>}
            </div>
            {a.proxima && <p className="mt-2 truncate text-xs text-muted">A seguir: {a.proxima.titulo}</p>}
          </Card>
          <p className="flex items-start gap-2 px-1 text-xs text-muted">
            <ShieldCheck className="mt-0.5 size-4 shrink-0 text-green-700" aria-hidden />
            Vídeo gravado só com dados fictícios. Abre só para quem tem acesso à trilha, com o seu nome na tela; não grave nem compartilhe.
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * Player: o link do vídeo vale 15 minutos e é renovado se vencer no meio da aula. Marca d'água com o nome de quem assiste
 * (muda de lugar), sem baixar, sem "picture in picture", tela cheia do quadro inteiro (para a marca não sumir).
 * O tempo assistido conta só o que tocou de fato (avançar não conta); a posição é salva a cada 15 s, ao pausar e ao sair.
 */
function Player({ aula, onConcluida }: { aula: Aula; onConcluida: () => void }) {
  const quadro = useRef<HTMLDivElement>(null);
  const video = useRef<HTMLVideoElement>(null);
  const assistido = useRef(aula.assistido_s);
  const ultimo = useRef(0);
  const ultimoSalvo = useRef(0);
  const jaConcluiu = useRef(aula.concluida);
  const retomar = useRef<number | null>(aula.posicao_s > 5 ? aula.posicao_s : null);
  const [cheia, setCheia] = useState(false);
  const [canto, setCanto] = useState(0);
  const [agora, setAgora] = useState(() => new Date());
  const link = useQuery({ queryKey: ['iaraflix-link', aula.id], queryFn: () => linkDaAula(aula.id), staleTime: 12 * 60_000, gcTime: 14 * 60_000, retry: 1 });

  // último estado conhecido do vídeo (ao sair da página o elemento já foi desmontado quando o progresso é salvo)
  const estado = useRef<{ pos: number; dur: number; fim: boolean } | null>(null);
  const salvar = useCallback(async () => {
    const v = video.current;
    if (v && Number.isFinite(v.duration)) estado.current = { pos: v.currentTime, dur: v.duration, fim: v.ended };
    const s = estado.current;
    if (!s) return;
    ultimoSalvo.current = Date.now();
    try {
      const r = await rpc<{ concluida: boolean }>('iaraflix_progresso', {
        aula_id: aula.id, posicao_s: s.fim ? 0 : s.pos, assistido_s: assistido.current, duracao_s: s.dur,
      });
      if (r.concluida && !jaConcluiu.current) { jaConcluiu.current = true; onConcluida(); }
    } catch { /* tenta de novo no próximo intervalo */ }
  }, [aula.id, onConcluida]);

  useEffect(() => {
    const t = setInterval(() => { setCanto((c) => (c + 1) % 4); setAgora(new Date()); }, 25_000);
    const fora = () => { if (document.visibilityState === 'hidden') salvar(); };
    const tela = () => setCheia(document.fullscreenElement === quadro.current);
    document.addEventListener('visibilitychange', fora);
    document.addEventListener('fullscreenchange', tela);
    return () => { clearInterval(t); document.removeEventListener('visibilitychange', fora); document.removeEventListener('fullscreenchange', tela); salvar(); };
  }, [salvar]);

  const posicoes = ['left-3 top-3', 'right-3 top-3', 'right-3 bottom-14', 'left-3 bottom-14'];
  const telaCheia = () => (document.fullscreenElement ? document.exitFullscreen() : quadro.current?.requestFullscreen?.())?.catch?.(() => {});

  return (
    <div ref={quadro} className={clsx('relative w-full overflow-hidden bg-black', cheia ? 'h-full' : 'aspect-video rounded-[22px]')}
      onContextMenu={(e) => e.preventDefault()}>
      {link.error ? (
        <div className="grid h-full place-items-center p-6 text-center text-white">
          <div><p className="font-semibold">{(link.error as Error).message}</p><Button className="mt-3" size="sm" variant="secondary" onClick={() => link.refetch()}>Tentar de novo</Button></div>
        </div>
      ) : link.data ? (
        <video
          ref={video}
          className="h-full w-full bg-black"
          src={link.data.video}
          controls
          playsInline
          preload="metadata"
          crossOrigin="anonymous"
          controlsList="nodownload nofullscreen noremoteplayback"
          disablePictureInPicture
          disableRemotePlayback
          onLoadedMetadata={(e) => {
            const v = e.currentTarget;
            if (retomar.current != null && retomar.current < v.duration - 5) v.currentTime = retomar.current;
            retomar.current = null;
            ultimo.current = v.currentTime;
          }}
          onTimeUpdate={(e) => {
            const v = e.currentTarget;
            const d = v.currentTime - ultimo.current;
            if (!v.seeking && d > 0 && d < 1.5 * (v.playbackRate || 1) + 0.6) assistido.current = Math.min(v.duration || Infinity, assistido.current + d);
            ultimo.current = v.currentTime;
            if (Number.isFinite(v.duration)) estado.current = { pos: v.currentTime, dur: v.duration, fim: v.ended };
            if (!v.paused && Date.now() - ultimoSalvo.current > 15_000) salvar();
          }}
          onSeeked={(e) => { ultimo.current = e.currentTarget.currentTime; }}
          onPause={salvar}
          onEnded={salvar}
          onError={() => {
            // link vencido no meio da aula: renova e volta ao mesmo ponto
            const v = video.current;
            if (v && link.data && Date.now() > new Date(link.data.expira_em).getTime() - 30_000) {
              retomar.current = v.currentTime;
              link.refetch();
            }
          }}
        >
          {link.data.legenda && <track kind="subtitles" srcLang="pt-BR" label="Português" src={link.data.legenda} default />}
        </video>
      ) : (
        <div className="grid h-full place-items-center text-white/70">Carregando a aula…</div>
      )}

      <div aria-hidden className={clsx('pointer-events-none absolute select-none rounded-md bg-black/25 px-2 py-1 text-[11px] font-semibold leading-tight text-white/60 transition-all duration-1000 sm:text-xs', posicoes[canto])}>
        {aula.marca.nome}{aula.marca.unidade && !aula.marca.nome?.includes(aula.marca.unidade) ? ` · ${aula.marca.unidade}` : ''}<br />
        IARAFLIX · {agora.toLocaleDateString('pt-BR')} {agora.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
      </div>
      {document.fullscreenEnabled && (
        <button type="button" onClick={telaCheia} aria-label={cheia ? 'Sair da tela cheia' : 'Tela cheia'}
          className="absolute right-3 top-1/2 inline-flex size-9 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white/90 opacity-70 transition hover:opacity-100">
          {cheia ? <Shrink className="size-4" aria-hidden /> : <Expand className="size-4" aria-hidden />}
        </button>
      )}
      {aula.duracao_s != null && !cheia && <span className="sr-only">Duração {fmtDuracao(aula.duracao_s)}</span>}
    </div>
  );
}
