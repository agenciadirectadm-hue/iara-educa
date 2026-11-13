import { useId } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import { motion, useReducedMotion } from 'motion/react';
import { Award, CheckCircle2, Clock, Film, PlayCircle } from 'lucide-react';
import { fmtMinutos } from '@/lib/iaraflix';

/** Marca do IARAFLIX: "IARA" + "FLIX" em degradê do ipê-roxo. `claro`: para fundo claro. */
export function IaraflixMarca({ className, claro }: { className?: string; claro?: boolean }) {
  return (
    <span className={clsx('inline-flex items-baseline font-display font-black tracking-[-0.02em]', className)} aria-label="IARAFLIX">
      <span className={claro ? 'text-ink' : 'text-white'}>IARA</span>
      <span className="bg-gradient-to-r from-purple-300 via-fuchsia-300 to-purple-500 bg-clip-text text-transparent">FLIX</span>
    </span>
  );
}

/**
 * O Ipê assistindo a uma aula no notebook: a mascote atrás da tampa (com a flor do ipê e o play), a luz da tela no rosto
 * e um balde de pipoca. Usa a mesma arte da mascote oficial (corpo), sem o braço que acena.
 */
export function IpeAssistindo({ height = 300, className }: { height?: number; className?: string }) {
  const reduce = useReducedMotion();
  const id = useId().replace(/:/g, '');
  const width = Math.round((height * 778) / 900);
  const petalas = [0, 72, 144, 216, 288];
  const pipocas: [number, number, number][] = [[632, 708, 15], [650, 698, 16], [671, 694, 17], [692, 699, 15], [708, 709, 13], [643, 690, 12], [662, 683, 13], [684, 684, 12], [700, 692, 11], [656, 704, 12], [679, 703, 13]];
  return (
    <svg viewBox="0 0 778 900" width={width} height={height} className={clsx('select-none', className)} role="img"
      aria-label="O Ipê, mascote da IARA, assistindo a uma aula do IARAFLIX no notebook">
      <defs>
        <linearGradient id={`${id}-tampa`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#5b1696" />
          <stop offset="0.55" stopColor="#3d0d66" />
          <stop offset="1" stopColor="#24073f" />
        </linearGradient>
        <radialGradient id={`${id}-rosto`} cx="0.5" cy="0.5" r="0.5">
          <stop offset="0" stopColor="#d9c2ff" stopOpacity="0.75" />
          <stop offset="1" stopColor="#d9c2ff" stopOpacity="0" />
        </radialGradient>
        <linearGradient id={`${id}-feixe`} x1="0" y1="1" x2="0" y2="0">
          <stop offset="0" stopColor="#c9a7ff" stopOpacity="0.42" />
          <stop offset="1" stopColor="#c9a7ff" stopOpacity="0" />
        </linearGradient>
        <linearGradient id={`${id}-mesa`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#4a2273" />
          <stop offset="1" stopColor="#1d0b33" />
        </linearGradient>
        <clipPath id={`${id}-balde`}><path d="M618 712 H718 L704 806 H632 Z" /></clipPath>
      </defs>

      <image href="./iara/iara-body.webp" x="0" y="0" width="778" height="900" />

      {/* luz da tela: um feixe que sobe da tampa e ilumina o rosto (pisca de leve, como um vídeo passando) */}
      <motion.g style={{ mixBlendMode: 'screen' }} initial={{ opacity: 0.75 }}
        animate={reduce ? undefined : { opacity: [0.6, 0.95, 0.7, 1, 0.65] }}
        transition={{ duration: 6, repeat: Infinity, ease: 'easeInOut' }}>
        <path d="M222 548 H558 L612 300 H168 Z" fill={`url(#${id}-feixe)`} />
        <ellipse cx="412" cy="425" rx="165" ry="118" fill={`url(#${id}-rosto)`} />
      </motion.g>

      {/* mesa */}
      <rect x="24" y="800" width="730" height="110" rx="26" fill={`url(#${id}-mesa)`} />
      <rect x="24" y="800" width="730" height="3" rx="1.5" fill="#ffffff" opacity="0.14" />

      {/* notebook visto por trás */}
      <ellipse cx="390" cy="812" rx="232" ry="14" fill="#000" opacity="0.28" />
      <rect x="200" y="545" width="380" height="248" rx="22" fill={`url(#${id}-tampa)`} />
      <rect x="200.5" y="545.5" width="379" height="247" rx="21.5" fill="none" stroke="#ffffff" strokeOpacity="0.18" />
      <rect x="226" y="546" width="328" height="2.5" rx="1.25" fill="#e9dcff" opacity="0.75" />
      <g transform="translate(390 655)">
        {petalas.map((r) => (
          <ellipse key={r} cx="0" cy="-27" rx="17" ry="27" fill="#e6cdfa" opacity="0.94" transform={`rotate(${r})`} />
        ))}
        <circle r="17" fill="#ffffff" />
        <path d="M-5 -9 L10 0 L-5 9 Z" fill="#7a24c5" />
      </g>
      <text x="390" y="742" textAnchor="middle" fill="#ffffff" fillOpacity="0.82" fontSize="24" fontWeight="900" letterSpacing="5"
        style={{ fontFamily: 'Nunito Variable, Inter Variable, system-ui, sans-serif' }}>IARAFLIX</text>
      <path d="M172 790 H608 L592 812 H188 Z" fill="#1c0631" />
      <rect x="350" y="792" width="80" height="5" rx="2.5" fill="#ffffff" opacity="0.12" />

      {/* pipoca */}
      <g>
        {pipocas.map(([x, y, r], i) => <circle key={i} cx={x} cy={y} r={r} fill="#fff8e6" stroke="#f1d79b" strokeWidth="2" />)}
        <path d="M618 712 H718 L704 806 H632 Z" fill="#ffffff" />
        <g clipPath={`url(#${id}-balde)`}>
          {[0, 1, 2, 3, 4].map((k) => <rect key={k} x={622 + k * 20} y="700" width="10" height="120" fill="#a846e8" transform={`skewX(${(k - 2) * -3})`} />)}
        </g>
        <path d="M614 706 H722 V718 H614 Z" fill="#7a24c5" />
      </g>
    </svg>
  );
}

/** Cor de capa de cada trilha (sempre a mesma para a mesma trilha). */
const CAPAS = [
  'from-purple-800 via-purple-700 to-fuchsia-600', 'from-blue-950 via-blue-900 to-purple-700', 'from-purple-900 via-fuchsia-800 to-rose-600',
  'from-green-800 via-teal-700 to-blue-900', 'from-indigo-900 via-purple-800 to-purple-500', 'from-fuchsia-900 via-purple-800 to-blue-700',
];
export function capaDaTrilha(id: string) {
  let h = 0;
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return CAPAS[h % CAPAS.length];
}

export type TrilhaResumo = {
  id: string; titulo: string; publico: string; objetivo: string; carga_horaria: number; minha: boolean; obrigatoria: boolean; situacao: string;
  aulas: number; com_video: number; concluidas: number; duracao_s: number; proxima: { id: string; ordem: number; titulo: string; posicao_s: number } | null;
  concluida_em: string | null; certificado: string | null; saber?: string[];
};

/** Cartão-pôster da trilha, no estilo de uma vitrine de vídeos. */
export function PosterTrilha({ t, className }: { t: TrilhaResumo; className?: string }) {
  const pct = t.aulas ? Math.round((t.concluidas / t.aulas) * 100) : 0;
  return (
    <Link to={`/iaraflix/trilha/${t.id}`} aria-label={`Trilha ${t.titulo}: ${t.concluidas} de ${t.aulas} aulas`}
      className={clsx('group relative flex min-h-[168px] flex-col overflow-hidden rounded-3xl bg-gradient-to-br p-4 text-white shadow-[0_18px_40px_-24px_rgb(74_16_120/0.9)] ring-1 ring-white/10 transition hover:-translate-y-0.5 hover:shadow-[0_22px_44px_-20px_rgb(74_16_120/0.95)]', capaDaTrilha(t.id), className)}>
      <span aria-hidden className="pointer-events-none absolute -right-6 -top-8 size-32 rounded-full bg-white/10 blur-xl transition group-hover:bg-white/15" />
      <div className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.12em] text-white/75">
        <Film className="size-3.5" aria-hidden />
        {t.concluida_em ? 'Concluída' : t.obrigatoria ? 'Sua trilha' : t.minha ? 'Também para você' : 'Trilha da rede'}
        {t.situacao === 'RASCUNHO' && <span className="rounded-full bg-amber-300 px-1.5 text-[10px] text-ink">rascunho</span>}
      </div>
      <div className="mt-2 font-display text-xl font-extrabold leading-tight text-balance">{t.titulo}</div>
      <div className="mt-1 line-clamp-2 text-[13px] text-white/80">{t.publico}</div>
      <div className="mt-auto pt-4">
        <div className="flex items-center justify-between text-[12px] font-semibold text-white/85">
          <span>{t.aulas} aulas · {fmtMinutos(t.duracao_s)}</span>
          {t.concluida_em ? <span className="inline-flex items-center gap-1"><Award className="size-3.5" aria-hidden />Certificado</span>
            : <span>{t.concluidas}/{t.aulas}</span>}
        </div>
        <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/20">
          <div className="h-full rounded-full bg-white" style={{ width: `${pct}%` }} />
        </div>
      </div>
      <PlayCircle className="absolute bottom-4 right-4 hidden size-0 opacity-0 transition group-hover:size-9 group-hover:opacity-90 sm:block" aria-hidden />
    </Link>
  );
}

/** Situação de uma aula numa linha: concluída, em andamento, a fazer; e se o vídeo ainda está em produção. */
export function SituacaoAula({ concluida, posicao_s, duracao_s, tem_video }: { concluida: boolean; posicao_s: number; duracao_s: number | null; tem_video: boolean }) {
  if (concluida) return <span className="inline-flex items-center gap-1 text-[13px] font-semibold text-green-700"><CheckCircle2 className="size-4" aria-hidden />Concluída</span>;
  if (posicao_s > 0 && duracao_s) return <span className="inline-flex items-center gap-1 text-[13px] font-semibold text-purple-700"><Clock className="size-4" aria-hidden />{Math.min(99, Math.round((posicao_s / duracao_s) * 100))}% assistido</span>;
  return <span className="text-[13px] text-muted">{tem_video ? 'A assistir' : 'A estudar'}</span>;
}
