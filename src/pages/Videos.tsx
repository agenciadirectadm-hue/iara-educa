import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { useQuery } from '@tanstack/react-query';
import clsx from 'clsx';
import { ArrowLeft, Clapperboard, Clock, PlayCircle, ShieldCheck, TvMinimalPlay } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { CATEGORIAS_VIDEO, fmtDuracao, linkVideoFamilia, type VideoFamilia } from '@/lib/iaraflix';
import { Button, EmptyState, ErrorState, Section, SkeletonList } from '@/components/ui';
import { IpeAssistindo } from '@/components/iaraflix';

type Lista = { categorias: { codigo: string; nome: string }[]; videos: VideoFamilia[] };

const CAPA: Record<string, string> = {
  TUTORIAL: 'from-purple-700 via-purple-600 to-fuchsia-500', MATRICULA: 'from-blue-900 via-blue-700 to-purple-600',
  VIDA_ESCOLAR: 'from-green-800 via-teal-600 to-blue-700', AVISOS: 'from-fuchsia-800 via-purple-700 to-rose-500', OUTROS: 'from-slate-700 via-purple-800 to-purple-600',
};
const nomeCategoria = (c: string) => CATEGORIAS_VIDEO.find((x) => x.codigo === c)?.nome ?? 'Vídeo da SEDUC';
const durTxt = (s: number | null) => (s == null ? null : s < 60 ? `${s} s` : fmtDuracao(s));

/** Cartão de um vídeo: capa colorida (sem imagem do YouTube: nada é carregado de fora antes do play). */
function CartaoVideo({ v, grande }: { v: VideoFamilia; grande?: boolean }) {
  return (
    <Link to={`/videos/${v.id}`} aria-label={`Assistir: ${v.titulo}`}
      className={clsx('group relative flex flex-col overflow-hidden rounded-3xl bg-gradient-to-br p-4 text-white shadow-[0_18px_40px_-26px_rgb(74_16_120/0.9)] ring-1 ring-white/10 transition hover:-translate-y-0.5',
        CAPA[v.categoria] ?? CAPA.OUTROS, grande ? 'min-h-[200px] sm:p-6' : 'min-h-[150px]')}>
      <span aria-hidden className="pointer-events-none absolute -right-8 -top-10 size-36 rounded-full bg-white/10 blur-xl" />
      <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[0.12em] text-white/75">
        {v.fonte === 'YOUTUBE' ? <TvMinimalPlay className="size-3.5" aria-hidden /> : <Clapperboard className="size-3.5" aria-hidden />}
        {nomeCategoria(v.categoria)}
      </div>
      <div className={clsx('mt-2 font-display font-extrabold leading-tight text-balance', grande ? 'text-2xl sm:text-3xl' : 'text-lg')}>{v.titulo}</div>
      {v.descricao && <p className={clsx('mt-1 text-white/85', grande ? 'line-clamp-3 text-[15px]' : 'line-clamp-2 text-[13px]')}>{v.descricao}</p>}
      <div className="mt-auto flex items-center gap-2 pt-3 text-[12.5px] font-semibold text-white/90">
        <PlayCircle className={clsx('transition group-hover:scale-110', grande ? 'size-9' : 'size-7')} aria-hidden />
        {durTxt(v.duracao_s) && <span className="inline-flex items-center gap-1"><Clock className="size-3.5" aria-hidden />{durTxt(v.duracao_s)}</span>}
      </div>
    </Link>
  );
}

/** Página pública: os vídeos que a SEDUC publicou para as famílias, por assunto. */
export default function Videos() {
  const q = useRpc<Lista>('videos_familia_lista', {}, { staleTime: 60_000 });
  if (q.isLoading) return <SkeletonList rows={4} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const { videos, categorias } = q.data!;
  const destaque = videos.find((v) => v.destaque) ?? null;

  return (
    <div>
      <section className="relative overflow-hidden rounded-[28px] bg-gradient-to-br from-purple-50 via-white to-blue-50 ring-1 ring-line">
        <div className="grid grid-cols-[minmax(0,1fr)] items-end gap-2 px-5 pt-5 sm:grid-cols-[minmax(0,1fr)_auto] sm:px-8 sm:pt-7">
          <div className="min-w-0 pb-5 sm:pb-7">
            <div className="text-xs font-bold uppercase tracking-[0.12em] text-purple-700">Para as famílias</div>
            <h1 className="mt-1 font-display text-[30px] font-extrabold leading-tight text-ink sm:text-4xl">Vídeos da SEDUC</h1>
            <p className="mt-2 max-w-xl text-[15px] text-muted text-pretty">
              Aprenda a usar o portal e a IARA, entenda como funcionam a vaga, a matrícula e a vida escolar, e veja os avisos e as campanhas da rede.
              Também dá para pedir pela IARA: "tem vídeo de como fazer a matrícula?".
            </p>
          </div>
          <IpeAssistindo height={190} className="mx-auto hidden sm:block" />
        </div>
      </section>

      {videos.length === 0 ? (
        <div className="mt-6">
          <EmptyState title="A SEDUC ainda não publicou vídeos" body="Quando publicar, eles aparecem aqui e a IARA também indica pelo WhatsApp." />
        </div>
      ) : (
        <>
          {destaque && (
            <Section title="Em destaque">
              <CartaoVideo v={destaque} grande />
            </Section>
          )}
          {categorias.map((c) => {
            const lista = videos.filter((v) => v.categoria === c.codigo && v.id !== destaque?.id);
            if (!lista.length) return null;
            return (
              <Section key={c.codigo} title={c.nome}>
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{lista.map((v) => <CartaoVideo key={v.id} v={v} />)}</div>
              </Section>
            );
          })}
        </>
      )}

      <p className="mt-6 flex items-start gap-2 text-xs text-muted">
        <ShieldCheck className="mt-0.5 size-4 shrink-0 text-green-700" aria-hidden />
        Os vídeos do YouTube só carregam quando você toca para assistir, sem cookies de propaganda. Os vídeos não pedem login nem dados seus.
      </p>
    </div>
  );
}

type Ver = VideoFamilia & { mais: VideoFamilia[] };

/** Um vídeo: YouTube (carrega só depois do toque) ou arquivo da SEDUC (link curto do armazenamento). */
export function VideoFamiliaPagina() {
  const { id } = useParams();
  const q = useRpc<Ver>('videos_familia_ver', { id }, { staleTime: 60_000 });
  if (q.isLoading) return <SkeletonList rows={4} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const v = q.data!;
  return (
    <div>
      <Link to="/videos" className="mb-3 inline-flex items-center gap-1.5 text-sm font-semibold text-purple-700 hover:text-purple-900">
        <ArrowLeft className="size-4" aria-hidden />Vídeos da SEDUC
      </Link>
      <Player key={v.id} v={v} />
      <div className="mt-4">
        <div className="text-[12px] font-bold uppercase tracking-[0.12em] text-purple-700">{nomeCategoria(v.categoria)}{durTxt(v.duracao_s) ? ` · ${durTxt(v.duracao_s)}` : ''}</div>
        <h1 className="mt-1 font-display text-[26px] font-extrabold leading-tight text-ink text-balance">{v.titulo}</h1>
        {v.descricao && <p className="mt-2 max-w-3xl whitespace-pre-line text-[15px] text-ink-2 text-pretty">{v.descricao}</p>}
        {v.situacao === 'RASCUNHO' && <p className="mt-2 text-sm font-semibold text-amber-700">Rascunho: só a gestão vê este vídeo.</p>}
      </div>
      {v.mais.length > 0 && (
        <Section title="Mais vídeos">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{v.mais.map((m) => <CartaoVideo key={m.id} v={m} />)}</div>
        </Section>
      )}
    </div>
  );
}

function Player({ v }: { v: Ver }) {
  const [tocar, setTocar] = useState(false);
  const [contou, setContou] = useState(false);
  const [vertical, setVertical] = useState(false);
  const contar = () => { if (!contou) { setContou(true); rpc('videos_familia_assistiu', { id: v.id }).catch(() => {}); } };
  const link = useQuery({ queryKey: ['video-familia-link', v.id], queryFn: () => linkVideoFamilia(v.id), enabled: v.fonte === 'ARQUIVO' && v.tem_arquivo,
    staleTime: 12 * 60_000, gcTime: 14 * 60_000, retry: 1 });

  if (v.fonte === 'YOUTUBE' && v.youtube_id) {
    return (
      <div className="relative aspect-video w-full overflow-hidden rounded-[22px] bg-black">
        {tocar ? (
          <iframe className="absolute inset-0 h-full w-full" title={v.titulo}
            src={`https://www.youtube-nocookie.com/embed/${v.youtube_id}?autoplay=1&rel=0&modestbranding=1&playsinline=1`}
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowFullScreen referrerPolicy="strict-origin-when-cross-origin" />
        ) : (
          <button type="button" onClick={() => { setTocar(true); contar(); }}
            className={clsx('group absolute inset-0 flex flex-col items-center justify-center gap-3 bg-gradient-to-br text-white', CAPA[v.categoria] ?? CAPA.OUTROS)}>
            <PlayCircle className="size-20 transition group-hover:scale-110" aria-hidden />
            <span className="font-display text-lg font-extrabold">Assistir</span>
            <span className="inline-flex items-center gap-1.5 text-[13px] text-white/85"><TvMinimalPlay className="size-4" aria-hidden />O vídeo abre pelo YouTube</span>
          </button>
        )}
      </div>
    );
  }
  // vídeo em pé (celular, 9:16): o quadro acompanha, em vez de espremer o vídeo numa tela larga
  return (
    <div className={clsx('relative overflow-hidden rounded-[22px] bg-black', vertical ? 'mx-auto aspect-[9/16] h-[min(78vh,640px)] max-w-full' : 'aspect-video w-full')}>
      {link.data ? (
        <video className="h-full w-full" src={link.data.video} controls playsInline preload="metadata" onPlay={contar}
          onLoadedMetadata={(e) => setVertical(e.currentTarget.videoHeight > e.currentTarget.videoWidth)}
          onError={() => { if (Date.now() > new Date(link.data!.expira_em).getTime() - 30_000) link.refetch(); }} />
      ) : link.error ? (
        <div className="grid h-full place-items-center p-6 text-center text-white">
          <div><p className="font-semibold">{(link.error as Error).message}</p><Button className="mt-3" size="sm" variant="secondary" onClick={() => link.refetch()}>Tentar de novo</Button></div>
        </div>
      ) : (
        <div className="grid h-full place-items-center text-white/70">{v.tem_arquivo ? 'Carregando o vídeo…' : 'O arquivo deste vídeo ainda não foi enviado.'}</div>
      )}
    </div>
  );
}

/** Faixa curta para o início da família: os vídeos mais recentes (some se a SEDUC ainda não publicou nenhum). */
export function FaixaVideos() {
  const q = useRpc<Lista>('videos_familia_lista', {}, { staleTime: 5 * 60_000 });
  const vids = q.data?.videos ?? [];
  if (!vids.length) return null;
  return (
    <Section title="Vídeos da SEDUC" subtitle="Aprenda a usar o portal e a IARA e veja os avisos da rede"
      action={<Link to="/videos" className="text-sm font-semibold text-purple-700">Ver todos</Link>}>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{vids.slice(0, 3).map((v) => <CartaoVideo key={v.id} v={v} />)}</div>
    </Section>
  );
}

