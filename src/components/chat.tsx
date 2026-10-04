import { Fragment, useEffect, useRef, type ReactNode } from 'react';
import { Link } from 'react-router';
import { AnimatePresence, motion } from 'motion/react';
import clsx from 'clsx';
import { Bot, CheckCheck, Headset, Info, MapPin } from 'lucide-react';
import { cleanLabel, fmtDate, fmtTime } from '@/lib/format';
import { TONE_CLASSES, type Tone } from '@/lib/labels';
import { IaraAvatar } from './iara';

export type ChatMessage = {
  id: string;
  direction: 'IN' | 'OUT';
  sender_type: 'IARA' | 'CIDADAO' | 'OPERADOR' | 'SISTEMA' | string;
  sender?: string | null;
  body: string;
  payload?: { quick_replies?: (string | QuickReply)[]; cards?: ChatCard[]; notice?: string; action?: string } | null;
  status?: string | null;
  at: string;
  pending?: boolean;
};
export type QuickReply = { label: string; action?: string };
export type ChatCard = { title: string; subtitle?: string; lines?: string[]; unit_id?: number; badge?: string; tone?: string };

export const asQuickReply = (q: string | QuickReply): QuickReply => (typeof q === 'string' ? { label: q } : q);

/** Texto das mensagens: **negrito**, quebras de linha e marcadores “•”. Sem HTML vindo do servidor. */
export function RichText({ text }: { text: string }) {
  const lines = (text ?? '').split('\n');
  return (
    <>
      {lines.map((line, i) => (
        <Fragment key={i}>
          {line.split(/(\*\*[^*]+\*\*)/g).map((part, j) =>
            part.startsWith('**') && part.endsWith('**') ? <strong key={j} className="font-bold text-ink">{part.slice(2, -2)}</strong> : <Fragment key={j}>{part}</Fragment>,
          )}
          {i < lines.length - 1 && <br />}
        </Fragment>
      ))}
    </>
  );
}

function CardItem({ card, linkable }: { card: ChatCard; linkable: boolean }) {
  const tone = (card.tone as Tone) in TONE_CLASSES ? (card.tone as Tone) : 'gray';
  const t = TONE_CLASSES[tone];
  const body = (
    <>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="font-display text-[14.5px] font-extrabold leading-tight text-ink">{card.title}</div>
          {card.subtitle && <div className="mt-0.5 text-[12.5px] text-muted">{card.subtitle}</div>}
        </div>
        {card.badge && <span className={clsx('shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold', t.bg, t.text)}>{card.badge}</span>}
      </div>
      {!!card.lines?.filter(Boolean).length && (
        <ul className="mt-1.5 space-y-0.5 text-[12.5px] text-ink-2">
          {card.lines.filter(Boolean).map((l, i) => <li key={i}>{l}</li>)}
        </ul>
      )}
      {card.unit_id && linkable && (
        <div className="mt-2 inline-flex items-center gap-1 text-[12.5px] font-bold text-blue-700"><MapPin className="size-3.5" /> Ver unidade</div>
      )}
    </>
  );
  const cls = clsx('block rounded-2xl bg-white p-3 ring-1 transition', t.ring, card.unit_id && linkable && 'hover:shadow-lift active:scale-[0.99]');
  return card.unit_id && linkable ? <Link to={`/unidades/${card.unit_id}`} className={cls}>{body}</Link> : <div className={cls}>{body}</div>;
}

function DaySeparator({ iso }: { iso: string }) {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(Date.now() - 86_400_000);
  const same = (a: Date, b: Date) => a.toDateString() === b.toDateString();
  const label = same(d, today) ? 'Hoje' : same(d, yesterday) ? 'Ontem' : fmtDate(iso);
  return (
    <div className="my-3 flex justify-center">
      <span className="rounded-full bg-white/80 px-3 py-1 text-[11.5px] font-semibold text-muted shadow-soft ring-1 ring-line/60">{label}</span>
    </div>
  );
}

/**
 * Linha do tempo de uma conversa. `perspective="citizen"`: as mensagens do cidadão ficam à direita (como no WhatsApp);
 * `perspective="operator"`: o cidadão fica à esquerda e IARA/servidor à direita.
 */
export function ChatThread({ messages, perspective, typing, footer, linkCards = true, className }: {
  messages: ChatMessage[];
  perspective: 'citizen' | 'operator';
  typing?: boolean;
  footer?: ReactNode;
  linkCards?: boolean;
  className?: string;
}) {
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => {
    end.current?.scrollIntoView({ block: 'end', behavior: 'smooth' });
  }, [messages.length, typing]);
  const items: ReactNode[] = [];
  let lastDay = '';
  for (const m of messages) {
    const day = new Date(m.at).toDateString();
    if (day !== lastDay) items.push(<DaySeparator key={`d-${day}`} iso={m.at} />);
    lastDay = day;
    items.push(<Bubble key={m.id} m={m} perspective={perspective} linkCards={linkCards} />);
  }
  return (
    <div className={clsx('space-y-1.5', className)} role="log" aria-live="polite" aria-relevant="additions">
      <AnimatePresence initial={false}>
        {items}
        {typing && (
          <motion.div key="typing" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="flex items-end gap-2">
            <IaraAvatar size={30} ring={false} />
            <div className="rounded-3xl rounded-bl-md bg-white px-4 py-3 shadow-soft ring-1 ring-purple-100" aria-label="IARA está digitando">
              <span className="flex gap-1">
                {[0, 1, 2].map((i) => (
                  <motion.span key={i} className="size-2 rounded-full bg-purple-400" animate={{ y: [0, -4, 0], opacity: [0.5, 1, 0.5] }} transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.15 }} />
                ))}
              </span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      {footer}
      <div ref={end} className="h-1" />
    </div>
  );
}

function Bubble({ m, perspective, linkCards }: { m: ChatMessage; perspective: 'citizen' | 'operator'; linkCards: boolean }) {
  if (m.sender_type === 'SISTEMA') {
    return (
      <motion.div layout="position" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex justify-center py-1">
        <span className="max-w-[90%] rounded-2xl bg-amber-50 px-3 py-1.5 text-center text-[12px] font-medium text-amber-900 ring-1 ring-amber-100">
          <Info className="mr-1 inline size-3.5" />{cleanLabel(m.body)}
        </span>
      </motion.div>
    );
  }
  const fromCitizen = m.sender_type === 'CIDADAO' || m.direction === 'IN';
  const right = perspective === 'citizen' ? fromCitizen : !fromCitizen;
  const isIara = m.sender_type === 'IARA';
  const isOperator = m.sender_type === 'OPERADOR';
  const cards = m.payload?.cards ?? [];
  return (
    <motion.div
      layout="position"
      initial={{ opacity: 0, y: 10, scale: 0.98 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ type: 'spring', stiffness: 380, damping: 30 }}
      className={clsx('flex items-end gap-2', right ? 'justify-end' : 'justify-start')}
    >
      {!right && (isIara ? <IaraAvatar size={30} ring={false} /> : isOperator ? (
        <span className="inline-flex size-[30px] shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-800"><Headset className="size-4" /></span>
      ) : (
        <span className="inline-flex size-[30px] shrink-0 items-center justify-center rounded-full bg-slate-200 text-[11px] font-bold text-slate-700">{(cleanLabel(m.sender) || 'C').slice(0, 1)}</span>
      ))}
      <div className={clsx('min-w-0', cards.length ? 'w-full max-w-[92%] sm:max-w-[80%]' : 'max-w-[85%] sm:max-w-[72%]')}>
        <div
          className={clsx(
            'rounded-3xl px-3.5 py-2.5 text-[14.5px] leading-relaxed shadow-soft',
            right
              ? perspective === 'citizen'
                ? 'rounded-br-md bg-[#DCF7E3] text-ink ring-1 ring-green-100'
                : isOperator ? 'rounded-br-md bg-blue-700 text-white' : 'rounded-br-md bg-purple-700 text-white'
              : isOperator ? 'rounded-bl-md bg-blue-50 text-ink ring-1 ring-blue-100' : 'rounded-bl-md bg-white text-ink-2 ring-1 ring-purple-100/80',
            m.pending && 'opacity-70',
          )}
        >
          {(isIara || isOperator) && (
            <div className={clsx('mb-0.5 flex items-center gap-1 text-[11.5px] font-bold', right && perspective === 'operator' ? 'text-white/80' : isOperator ? 'text-blue-700' : 'text-purple-700')}>
              {isIara ? <Bot className="size-3.5" /> : <Headset className="size-3.5" />}
              {isIara ? 'IARA · assistente virtual' : `${cleanLabel(m.sender) || 'Servidor'} · SEDUC`}
            </div>
          )}
          {!fromCitizen || perspective === 'citizen' ? null : <div className="mb-0.5 text-[11.5px] font-bold text-slate-600">{cleanLabel(m.sender) || 'Cidadão'}</div>}
          <div className={clsx(right && perspective === 'operator' && '[&_strong]:text-white')}><RichText text={m.body} /></div>
          {cards.length > 0 && (
            <div className="mt-2 space-y-2">
              {cards.map((c, i) => <CardItem key={i} card={c} linkable={linkCards} />)}
            </div>
          )}
          {m.payload?.notice && <div className={clsx('mt-1.5 text-[11.5px] italic', right && perspective === 'operator' ? 'text-white/75' : 'text-muted')}>{m.payload.notice}</div>}
          <div className={clsx('mt-0.5 flex items-center justify-end gap-1 text-[10.5px]', right && perspective === 'operator' ? 'text-white/70' : 'text-subtle')}>
            {m.pending ? 'enviando…' : fmtTime(m.at)}
            {right && perspective === 'citizen' && !m.pending && <CheckCheck className="size-3.5 text-blue-500" aria-label="entregue" />}
          </div>
        </div>
      </div>
    </motion.div>
  );
}

export function QuickReplies({ items, onPick, disabled }: { items: QuickReply[]; onPick: (q: QuickReply) => void; disabled?: boolean }) {
  if (!items.length) return null;
  return (
    <div className="no-scrollbar -mx-1 flex gap-2 overflow-x-auto px-1 pb-1" role="group" aria-label="Respostas rápidas">
      {items.map((q, i) => (
        <motion.button
          key={q.label + i}
          type="button"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: i * 0.04 }}
          disabled={disabled}
          onClick={() => onPick(q)}
          className="h-10 shrink-0 rounded-full bg-white px-4 text-[13.5px] font-semibold text-purple-800 shadow-soft ring-1 ring-purple-200 transition hover:bg-purple-50 active:scale-95 disabled:opacity-50"
        >
          {q.label}
        </motion.button>
      ))}
    </div>
  );
}
