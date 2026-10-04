import { useMemo, type CSSProperties, type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import clsx from 'clsx';

/** Pivô do braço (ombro, dentro da manga) relativo à arte recortada — gerado por scripts/mascote. */
const ARM_PIVOT = '69.09% 61.47%';
const RATIO = 778 / 900;

export type IaraMood = 'wave' | 'idle' | 'success' | 'thinking' | 'attention' | 'still';

/**
 * Mascote oficial IARA (ipê-roxo feminina) em camadas: corpo + braço articulado.
 * Versões: wave (acena), success (pulinho + flores), thinking (pensando), attention (alerta), idle (respira), still (sem movimento).
 */
export function IaraMascot({ height = 320, mood = 'wave', className, entrance = false, delay = 0 }: {
  height?: number; mood?: IaraMood; className?: string; entrance?: boolean; delay?: number;
}) {
  const reduce = useReducedMotion();
  const width = Math.round(height * RATIO);
  const move = !reduce && mood !== 'still';

  const armAnim = move && (mood === 'wave' || mood === 'success')
    ? { rotate: [0, 16, -8, 16, -4, 10, 0] }
    : move && mood === 'attention' ? { rotate: [0, 10, 0] } : { rotate: 0 };
  const armTransition = mood === 'wave'
    ? { duration: 2.2, delay: delay + (entrance ? 1.3 : 0.2), repeat: Infinity, repeatDelay: 4.5, ease: 'easeInOut' as const }
    : { duration: 1.4, delay, repeat: mood === 'attention' ? Infinity : 0, repeatDelay: 2 };

  const bodyAnim = !move ? {} : mood === 'success'
    ? { y: [0, -18, 0, -8, 0] }
    : mood === 'attention' ? { rotate: [0, -2, 2, -1, 0] } : { rotate: [0, 0.9, 0, -0.9, 0] };
  const bodyTransition = mood === 'success'
    ? { duration: 1.1, delay: delay + 0.2, ease: 'easeOut' as const }
    : mood === 'attention' ? { duration: 0.8, repeat: Infinity, repeatDelay: 2.5 } : { duration: 7, repeat: Infinity, ease: 'easeInOut' as const };

  return (
    <motion.div
      className={clsx('relative select-none', className)}
      style={{ width, height }}
      initial={entrance && !reduce ? { opacity: 0, y: 40, scale: 0.92 } : false}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ type: 'spring', stiffness: 120, damping: 16, delay }}
      aria-hidden
    >
      <motion.div className="absolute inset-0" style={{ transformOrigin: '50% 98%' }} animate={bodyAnim} transition={bodyTransition}>
        <motion.img
          src="./iara/iara-arm.webp"
          alt=""
          draggable={false}
          className="absolute inset-0 h-full w-full"
          style={{ transformOrigin: ARM_PIVOT }}
          animate={armAnim}
          transition={armTransition}
        />
        <img src="./iara/iara-body.webp" alt="" draggable={false} className="absolute inset-0 h-full w-full" />
        {mood === 'thinking' && <ThinkingDots />}
        {mood === 'attention' && (
          <motion.span
            className="absolute right-[6%] top-[30%] inline-flex size-9 items-center justify-center rounded-full bg-amber-400 font-display text-xl font-black text-ink shadow-lift"
            animate={move ? { scale: [1, 1.15, 1] } : undefined}
            transition={{ duration: 1, repeat: Infinity }}
          >
            !
          </motion.span>
        )}
      </motion.div>
      {mood === 'success' && <FlowerBurst count={10} delay={delay + 0.3} />}
    </motion.div>
  );
}

function ThinkingDots() {
  return (
    <div className="absolute right-[2%] top-[38%] flex gap-1 rounded-full bg-white px-3 py-2 shadow-lift">
      {[0, 1, 2].map((i) => (
        <motion.span key={i} className="size-2 rounded-full bg-purple-500" animate={{ y: [0, -4, 0], opacity: [0.4, 1, 0.4] }} transition={{ duration: 0.9, delay: i * 0.15, repeat: Infinity }} />
      ))}
    </div>
  );
}

export function IaraAvatar({ size = 40, online, className, ring = true }: { size?: number; online?: boolean; className?: string; ring?: boolean }) {
  return (
    <span className={clsx('relative inline-block shrink-0', className)} style={{ width: size, height: size }}>
      <img src="./iara/iara-avatar.webp" alt="IARA" className={clsx('h-full w-full rounded-full object-cover', ring && 'ring-2 ring-white shadow-soft')} />
      {online && <span className="absolute bottom-0 right-0 size-3 rounded-full bg-green-500 ring-2 ring-white" aria-hidden />}
    </span>
  );
}

/** Flor de ipê-roxo estilizada (5 pétalas). */
export function IpeFlower({ size = 24, color = '#A846E8', className, style }: { size?: number; color?: string; className?: string; style?: CSSProperties }) {
  return (
    <svg viewBox="-20 -20 40 40" width={size} height={size} className={className} style={style} aria-hidden>
      {[0, 72, 144, 216, 288].map((r) => (
        <ellipse key={r} cx="0" cy="-9" rx="6.2" ry="9.5" fill={color} opacity="0.92" transform={`rotate(${r})`} />
      ))}
      <circle r="4.2" fill="#F7D774" />
      <circle r="2" fill="#E8A93C" />
    </svg>
  );
}

const FLOWER_COLORS = ['#A846E8', '#C77DF0', '#8E35D6', '#D7A6F7', '#B65CEB'];

/** Explosão de flores ao redor da copa. */
export function FlowerBurst({ count = 14, delay = 0, radius = 140 }: { count?: number; delay?: number; radius?: number }) {
  const reduce = useReducedMotion();
  const flowers = useMemo(
    () => Array.from({ length: count }, (_, i) => {
      const a = (i / count) * Math.PI * 2 + Math.random() * 0.4;
      const r = radius * (0.6 + Math.random() * 0.6);
      return { x: Math.cos(a) * r, y: Math.sin(a) * r * 0.75 - radius * 0.25, s: 14 + Math.random() * 18, c: FLOWER_COLORS[i % FLOWER_COLORS.length], rot: Math.random() * 360 };
    }),
    [count, radius],
  );
  if (reduce) return null;
  return (
    <div className="pointer-events-none absolute left-1/2 top-[28%]" aria-hidden>
      {flowers.map((f, i) => (
        <motion.div
          key={i}
          className="absolute"
          initial={{ x: 0, y: 0, scale: 0, opacity: 0, rotate: 0 }}
          animate={{ x: f.x, y: [0, f.y, f.y + 60], scale: [0, 1, 0.8], opacity: [0, 1, 0], rotate: f.rot }}
          transition={{ duration: 2.4, delay: delay + i * 0.04, ease: 'easeOut' }}
        >
          <IpeFlower size={f.s} color={f.c} />
        </motion.div>
      ))}
    </div>
  );
}

/** Flores caindo suavemente no fundo (abertura e telas vazias). */
export function FallingFlowers({ count = 14 }: { count?: number }) {
  const reduce = useReducedMotion();
  const items = useMemo(
    () => Array.from({ length: count }, (_, i) => ({
      left: Math.random() * 100, size: 12 + Math.random() * 22, dur: 9 + Math.random() * 8, delay: Math.random() * 6, drift: (Math.random() - 0.5) * 120,
      c: FLOWER_COLORS[i % FLOWER_COLORS.length], rot: Math.random() * 360,
    })),
    [count],
  );
  if (reduce) return null;
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
      {items.map((f, i) => (
        <motion.div
          key={i}
          className="absolute -top-10"
          style={{ left: `${f.left}%` }}
          animate={{ y: ['0vh', '110vh'], x: [0, f.drift], rotate: [f.rot, f.rot + 220], opacity: [0, 0.85, 0.85, 0] }}
          transition={{ duration: f.dur, delay: f.delay, repeat: Infinity, ease: 'linear' }}
        >
          <IpeFlower size={f.size} color={f.c} />
        </motion.div>
      ))}
    </div>
  );
}

/** Balão de fala da IARA (ajuda contextual — discreta nas telas de gestão). */
export function IaraBubble({ children, className, actions, compact }: { children: ReactNode; className?: string; actions?: ReactNode; compact?: boolean }) {
  return (
    <div className={clsx('flex items-start gap-3', className)}>
      <IaraAvatar size={compact ? 40 : 52} online />
      <div className="relative min-w-0 flex-1 rounded-3xl rounded-tl-md bg-white p-3.5 shadow-soft ring-1 ring-purple-100">
        <div className="mb-0.5 text-xs font-bold text-purple-700">IARA · assistente virtual</div>
        <div className="text-[14.5px] leading-relaxed text-ink-2">{children}</div>
        {actions && <div className="mt-3 flex flex-wrap gap-2">{actions}</div>}
      </div>
    </div>
  );
}
