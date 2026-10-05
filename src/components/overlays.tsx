import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { AnimatePresence, motion, useDragControls } from 'motion/react';
import clsx from 'clsx';
import { AlertTriangle, CheckCircle2, Info, X, XCircle } from 'lucide-react';
import { useIsDesktop } from '@/lib/hooks';

// ---------------------------------------------------------------- Sheet (inferior no celular, lateral no desktop)
export function Sheet({ open, onClose, title, subtitle, children, footer, size = 'md', labelledBy }: {
  open: boolean; onClose: () => void; title?: ReactNode; subtitle?: ReactNode; children: ReactNode; footer?: ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl'; labelledBy?: string;
}) {
  const desktop = useIsDesktop();
  const panelRef = useRef<HTMLDivElement>(null);
  const drag = useDragControls();

  useEffect(() => {
    if (!open) return;
    const prev = document.activeElement as HTMLElement | null;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    document.addEventListener('keydown', onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const t = setTimeout(() => panelRef.current?.querySelector<HTMLElement>('[data-autofocus], button, a, input, select, textarea')?.focus(), 60);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = overflow;
      clearTimeout(t);
      prev?.focus?.();
    };
  }, [open, onClose]);

  const width = { sm: 'lg:w-[400px]', md: 'lg:w-[480px]', lg: 'lg:w-[640px]', xl: 'lg:w-[min(920px,calc(100vw-280px))]' }[size];
  return createPortal(
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-[80]" role="presentation">
          <motion.div className="absolute inset-0 bg-ink/40" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose} />
          <motion.div
            ref={panelRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby={labelledBy ?? 'sheet-title'}
            className={clsx(
              'absolute flex flex-col bg-white shadow-lift',
              desktop ? clsx('right-0 top-0 h-full rounded-l-4xl', width) : 'inset-x-0 bottom-0 max-h-[92dvh] rounded-t-4xl pb-safe',
            )}
            initial={desktop ? { x: '100%' } : { y: '100%' }}
            animate={desktop ? { x: 0 } : { y: 0 }}
            exit={desktop ? { x: '100%' } : { y: '100%' }}
            transition={{ type: 'spring', stiffness: 380, damping: 38 }}
            drag={desktop ? false : 'y'}
            dragControls={drag}
            dragListener={false}
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.6 }}
            onDragEnd={(_, info) => {
              if (info.offset.y > 120 || info.velocity.y > 600) onClose();
            }}
          >
            {!desktop && (
              <div className="flex justify-center pt-2.5 pb-1" onPointerDown={(e) => drag.start(e)} style={{ touchAction: 'none' }}>
                <span className="h-1.5 w-12 rounded-full bg-slate-300" aria-hidden />
              </div>
            )}
            <div className="flex items-start gap-3 px-5 pb-2 pt-2 lg:pt-6" onPointerDown={(e) => !desktop && drag.start(e)} style={{ touchAction: desktop ? undefined : 'none' }}>
              <div className="min-w-0 flex-1">
                {title && <h2 id="sheet-title" className="font-display text-xl font-extrabold leading-tight">{title}</h2>}
                {subtitle && <p className="mt-0.5 text-sm text-muted">{subtitle}</p>}
              </div>
              <button onClick={onClose} className="inline-flex size-10 shrink-0 items-center justify-center rounded-2xl bg-slate-100 text-ink hover:bg-slate-200" aria-label="Fechar">
                <X className="size-5" aria-hidden />
              </button>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-5">{children}</div>
            {footer && <div className="border-t border-line bg-white px-5 py-3">{footer}</div>}
          </motion.div>
        </div>
      )}
    </AnimatePresence>,
    document.body,
  );
}

// ---------------------------------------------------------------- Toasts
type ToastItem = { id: number; title: string; description?: string; tone?: 'success' | 'error' | 'info' | 'warning' };
const ToastCtx = createContext<(t: Omit<ToastItem, 'id'>) => void>(() => {});
export const useToast = () => useContext(ToastCtx);

// ---------------------------------------------------------------- Explicação de fonte/indicador
type Explain = { title: string; body: string; kind?: string };
const ExplainCtx = createContext<(e: Explain) => void>(() => {});
export const useExplain = () => useContext(ExplainCtx);

// ---------------------------------------------------------------- Confirmação contextual
type ConfirmOpts = { title: string; body?: ReactNode; confirm?: string; cancel?: string; tone?: 'primary' | 'danger' | 'success' | 'purple' };
const ConfirmCtx = createContext<(o: ConfirmOpts) => Promise<boolean>>(async () => false);
export const useConfirm = () => useContext(ConfirmCtx);

export function OverlayProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const [explain, setExplain] = useState<Explain | null>(null);
  const [confirm, setConfirm] = useState<(ConfirmOpts & { resolve: (v: boolean) => void }) | null>(null);
  const seq = useRef(0);

  const toast = useCallback((t: Omit<ToastItem, 'id'>) => {
    const id = ++seq.current;
    setToasts((all) => [...all.slice(-2), { ...t, id }]);
    setTimeout(() => setToasts((all) => all.filter((x) => x.id !== id)), t.tone === 'error' ? 7000 : 4500);
  }, []);

  const ask = useCallback((o: ConfirmOpts) => new Promise<boolean>((resolve) => setConfirm({ ...o, resolve })), []);

  const close = (v: boolean) => {
    confirm?.resolve(v);
    setConfirm(null);
  };

  return (
    <ToastCtx.Provider value={toast}>
      <ExplainCtx.Provider value={setExplain}>
        <ConfirmCtx.Provider value={ask}>
          {children}
          <Sheet open={!!explain} onClose={() => setExplain(null)} title={explain?.title} size="sm">
            <p className="whitespace-pre-line text-[15px] leading-relaxed text-ink-2">{explain?.body}</p>
            <p className="mt-4 rounded-2xl bg-purple-50 p-3 text-[13px] text-purple-900">
              Princípio da IARA Educa: dados oficiais prevalecem sobre estimativas, e nenhum dado ausente é inventado.
            </p>
          </Sheet>
          <Sheet
            open={!!confirm}
            onClose={() => close(false)}
            title={confirm?.title}
            size="sm"
            footer={
              <div className="flex gap-2">
                <button className="h-12 flex-1 rounded-2xl bg-slate-100 font-semibold text-ink hover:bg-slate-200" onClick={() => close(false)}>
                  {confirm?.cancel ?? 'Cancelar'}
                </button>
                <button
                  data-autofocus
                  className={clsx(
                    'h-12 flex-[1.4] rounded-2xl font-semibold text-white',
                    confirm?.tone === 'danger' ? 'bg-red-600' : confirm?.tone === 'success' ? 'bg-green-700' : confirm?.tone === 'purple' ? 'bg-purple-700' : 'bg-blue-700',
                  )}
                  onClick={() => close(true)}
                >
                  {confirm?.confirm ?? 'Confirmar'}
                </button>
              </div>
            }
          >
            <div className="text-[15px] leading-relaxed text-ink-2">{confirm?.body}</div>
          </Sheet>
          {createPortal(
            <div className="pointer-events-none fixed inset-x-0 top-0 z-[90] flex flex-col items-center gap-2 p-3 pt-safe lg:bottom-0 lg:left-auto lg:right-0 lg:top-auto lg:items-end lg:p-6" aria-live="polite">
              <AnimatePresence>
                {toasts.map((t) => (
                  <motion.div
                    key={t.id}
                    layout
                    initial={{ opacity: 0, y: -16, scale: 0.96 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: -10, scale: 0.96 }}
                    className="pointer-events-auto flex w-full max-w-md items-start gap-3 rounded-2xl bg-white p-3.5 shadow-lift ring-1 ring-line"
                    role="status"
                  >
                    {t.tone === 'success' ? <CheckCircle2 className="size-5 text-green-700" /> : t.tone === 'error' ? <XCircle className="size-5 text-red-600" /> : t.tone === 'warning' ? <AlertTriangle className="size-5 text-amber-600" /> : <Info className="size-5 text-blue-700" />}
                    <div className="min-w-0 flex-1">
                      <div className="text-[14.5px] font-semibold">{t.title}</div>
                      {t.description && <div className="text-[13px] text-muted">{t.description}</div>}
                    </div>
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>,
            document.body,
          )}
        </ConfirmCtx.Provider>
      </ExplainCtx.Provider>
    </ToastCtx.Provider>
  );
}
