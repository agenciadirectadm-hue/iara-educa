import { useEffect } from 'react';
import { useNavigate } from 'react-router';
import { motion, useReducedMotion } from 'motion/react';
import { ArrowRight } from 'lucide-react';
import { FallingFlowers, FlowerBurst, IaraMascot, IpeFlower } from '@/components/iara';
import { useSession } from '@/lib/session';

export const SPLASH_KEY = 'iara.abertura.vista';

/** Abertura (spec §7.1): flores surgem → copa → corpo → IARA acena → saudação → ENTRAR. Pode ser pulada. */
export default function Splash() {
  const navigate = useNavigate();
  const { session } = useSession();
  const reduce = useReducedMotion();

  const go = () => {
    try {
      localStorage.setItem(SPLASH_KEY, 'true');
    } catch {
      /* ok */
    }
    navigate(session ? '/inicio' : '/entrar', { replace: true });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => (e.key === 'Enter' || e.key === 'Escape') && go();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  const t = (s: number) => (reduce ? 0 : s);

  return (
    <div className="relative flex min-h-dvh flex-col items-center overflow-hidden bg-gradient-to-b from-white via-blue-50 to-green-100 pt-safe pb-safe">
      {/* halos de luz */}
      <motion.div
        className="absolute left-1/2 top-[16%] size-[620px] -translate-x-1/2 rounded-full bg-[radial-gradient(circle,rgba(168,70,232,0.28),transparent_65%)]"
        initial={{ scale: 0.4, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: t(1.6), ease: [0.22, 1, 0.36, 1] }}
        aria-hidden
      />
      <div className="absolute -bottom-32 left-1/2 h-64 w-[140%] -translate-x-1/2 rounded-[50%] bg-gradient-to-t from-green-200/70 to-transparent" aria-hidden />
      <FallingFlowers count={16} />

      <button onClick={go} className="absolute right-4 top-4 z-20 mt-safe rounded-full bg-white/80 px-4 py-2 text-sm font-semibold text-ink-2 shadow-soft ring-1 ring-line backdrop-blur hover:bg-white">
        Pular
      </button>

      <div className="relative z-10 flex w-full max-w-lg flex-1 flex-col items-center justify-center px-6 pt-10 text-center">
        {/* pequenas flores surgem antes da copa */}
        {!reduce && (
          <div className="pointer-events-none absolute left-1/2 top-[22%] -translate-x-1/2" aria-hidden>
            {[-90, -40, 10, 60, 100].map((x, i) => (
              <motion.div
                key={x}
                className="absolute"
                initial={{ opacity: 0, scale: 0, x, y: 30 }}
                animate={{ opacity: [0, 1, 0], scale: [0, 1.1, 0.6], y: [30, -10, -40] }}
                transition={{ duration: 1.4, delay: 0.1 + i * 0.12, ease: 'easeOut' }}
              >
                <IpeFlower size={26} />
              </motion.div>
            ))}
          </div>
        )}

        <motion.div
          initial={reduce ? false : { clipPath: 'circle(0% at 50% 32%)' }}
          animate={{ clipPath: 'circle(140% at 50% 32%)' }}
          transition={{ duration: t(1.5), delay: t(0.45), ease: [0.65, 0, 0.35, 1] }}
          className="relative"
        >
          <IaraMascot height={Math.min(420, typeof window !== 'undefined' ? window.innerHeight * 0.48 : 380)} mood="wave" entrance delay={t(0.5)} />
        </motion.div>
        <div className="relative">
          <FlowerBurst count={14} delay={t(1.2)} radius={170} />
        </div>

        <motion.h1
          className="mt-5 font-display text-[32px] font-black leading-[1.05] text-ink sm:text-[40px]"
          initial={reduce ? false : { opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: t(0.6), delay: t(2.1) }}
        >
          Bem-vindo à <span className="bg-gradient-to-r from-purple-700 to-blue-700 bg-clip-text text-transparent">IARA Educa</span>.
        </motion.h1>
        <motion.p
          className="mt-3 max-w-sm text-[17px] font-medium text-ink-2 text-balance"
          initial={reduce ? false : { opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: t(0.6), delay: t(2.8) }}
        >
          Mais oportunidades para cada criança de Maringá.
        </motion.p>

        <motion.button
          onClick={go}
          className="mt-8 inline-flex h-14 items-center gap-2 rounded-2xl bg-purple-700 px-10 font-display text-lg font-extrabold tracking-wide text-white shadow-glow"
          initial={reduce ? false : { opacity: 0, y: 14, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          whileTap={{ scale: 0.96 }}
          whileHover={{ y: -2 }}
          transition={{ duration: t(0.5), delay: t(3.3) }}
          autoFocus
        >
          ENTRAR <ArrowRight className="size-5" aria-hidden />
        </motion.button>
      </div>

      <motion.footer
        className="relative z-10 px-6 pb-5 text-center text-[12px] text-muted"
        initial={reduce ? false : { opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: t(3.4) }}
      >
        Secretaria Municipal de Educação · Maringá — PR
        <br />
        <span className="font-semibold text-amber-800">Protótipo em demonstração · dados pessoais fictícios</span>
      </motion.footer>
    </div>
  );
}
