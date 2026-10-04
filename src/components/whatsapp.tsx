import { useState } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import { QRCodeSVG } from 'qrcode.react';
import { Check, Copy, MessageCircle, Printer, QrCode, Share2 } from 'lucide-react';
import { useBootstrap } from '@/lib/data';
import { Sheet, useToast } from '@/components/overlays';
import { Card, SourceChip } from '@/components/ui';

export const WA_GREEN = '#25D366';
const DEFAULT_PUBLIC_URL = 'https://agenciadirectadm-hue.github.io/iara-educa/';
const DEFAULT_MSG = 'Olá, IARA! Quero atendimento da Educação de Maringá.';

/** 55 + DDD + número → (44) 99999-0000 */
export function fmtWhatsApp(digits: string) {
  const d = digits.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '');
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return digits;
}

/** Endereço público da plataforma: um QR code gerado no localhost precisa abrir no celular de quem escaneia. */
function publicBase(configured?: string | null) {
  if (/^(localhost|127\.0\.0\.1|\[::1\])$/.test(window.location.hostname)) return configured || DEFAULT_PUBLIC_URL;
  return window.location.origin + window.location.pathname;
}

/**
 * Contato da IARA no WhatsApp. Com o número oficial configurado (tenants.settings.iara_whatsapp_numero),
 * o link é o "clique para conversar" do WhatsApp com a mensagem já escrita. Sem ele (demonstração), o QR code
 * e o link abrem a conversa simulada da IARA — nunca um wa.me para número fictício.
 */
export function useIaraWhatsApp() {
  const boot = useBootstrap();
  const w = boot.data?.whatsapp;
  const numero = w?.numero || null;
  const mensagem = w?.mensagem || DEFAULT_MSG;
  const oficial = !!numero;
  const link = oficial
    ? `https://wa.me/${numero}?text=${encodeURIComponent(mensagem)}`
    : `${publicBase(w?.url_publica).replace(/#.*$/, '')}#/whatsapp`;
  const numeroExibicao = oficial ? fmtWhatsApp(numero!) : w?.numero_demo || '(44) 90000-0000';
  const convite = `Fale com a IARA, a assistente virtual da Educação de Maringá, pelo WhatsApp${oficial ? ` ${numeroExibicao}` : ''}: ${link}`;
  return { ready: !!boot.data, oficial, link, numero: numeroExibicao, mensagem, convite };
}

export function WhatsAppGlyph({ className }: { className?: string }) {
  return (
    <span className={clsx('inline-flex shrink-0 items-center justify-center rounded-full text-white', className ?? 'size-10')} style={{ background: WA_GREEN }} aria-hidden>
      <MessageCircle className="size-[55%]" strokeWidth={2.4} />
    </span>
  );
}

export function IaraQr({ value, size = 168, className }: { value: string; size?: number; className?: string }) {
  const logo = Math.round(size * 0.22);
  return (
    <div className={clsx('inline-flex shrink-0 rounded-2xl bg-white p-2.5 ring-1 ring-line', className)}>
      <QRCodeSVG
        value={value}
        size={size}
        level="H"
        marginSize={0}
        fgColor="#0E1A2B"
        title="QR code para conversar com a IARA pelo WhatsApp"
        imageSettings={{ src: './iara/iara-avatar.webp', height: logo, width: logo, excavate: true }}
        className="block h-auto max-w-full"
      />
    </div>
  );
}

/** Ações do contato: abrir a conversa, compartilhar com a família e copiar o link. */
export function useWhatsAppActions() {
  const wa = useIaraWhatsApp();
  const toast = useToast();
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(wa.link);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
      toast({ title: 'Link copiado', description: 'Cole no WhatsApp, SMS ou e-mail de quem você quiser.', tone: 'success' });
    } catch {
      toast({ title: 'Não foi possível copiar', description: wa.link, tone: 'warning' });
    }
  };
  const share = async () => {
    const data = { title: 'IARA no WhatsApp', text: wa.convite };
    if (navigator.share) {
      try {
        await navigator.share(data);
        return;
      } catch (e) {
        if ((e as DOMException)?.name === 'AbortError') return;
      }
    }
    // sem compartilhamento nativo: o WhatsApp abre a lista de contatos com o convite pronto
    window.open(`https://wa.me/?text=${encodeURIComponent(wa.convite)}`, '_blank', 'noopener,noreferrer');
  };
  return { ...wa, copied, copy, share };
}

export function OpenConversation({ className, children = 'Abrir conversa' }: { className?: string; children?: string }) {
  const wa = useIaraWhatsApp();
  const cls = clsx('inline-flex h-11 items-center justify-center gap-2 rounded-2xl px-4 text-[15px] font-semibold text-white shadow-[0_8px_20px_-10px_rgb(37_211_102/0.9)] transition active:scale-[0.97]', className);
  const style = { background: '#1FAF55' };
  return wa.oficial ? (
    <a href={wa.link} target="_blank" rel="noreferrer" className={cls} style={style}>
      <MessageCircle className="size-[18px]" aria-hidden /> {children}
    </a>
  ) : (
    <Link to="/whatsapp" className={cls} style={style}>
      <MessageCircle className="size-[18px]" aria-hidden /> {children}
    </Link>
  );
}

/**
 * Cartão "Fale com a IARA pelo WhatsApp": QR code, número e link de conversa, com compartilhamento para os
 * outros membros da família. Mesmo resultado do portal, pelo celular.
 */
export function WhatsAppCard({
  title = 'Fale com a IARA pelo WhatsApp',
  subtitle = 'Vaga, fila, documentos e mudanças da família direto do celular — sem precisar abrir o portal.',
  className,
  plain,
  hideOpen,
}: { title?: string; subtitle?: string; className?: string; plain?: boolean; hideOpen?: boolean }) {
  const a = useWhatsAppActions();
  const body = (
    <>
      <div className="flex items-start gap-3">
        <WhatsAppGlyph />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="font-display text-[17px] font-extrabold leading-tight">{title}</h2>
            {a.ready && !a.oficial && <SourceChip kind="demo" detail="Número oficial a definir pela SEDUC. Na demonstração, o QR code e o link abrem a conversa simulada da IARA." />}
          </div>
          <p className="mt-0.5 text-[13.5px] text-muted">{subtitle}</p>
        </div>
      </div>
      <div className="mt-4 flex items-center gap-3.5">
        <IaraQr value={a.link} size={160} className="w-[118px] sm:w-[150px]" />
        <div className="min-w-0 flex-1">
          <div className="text-[11px] font-bold uppercase tracking-wide text-subtle">Número da IARA</div>
          <div className="mt-0.5 font-display text-[21px] font-black leading-tight tabular tracking-tight sm:text-[24px]">{a.numero}</div>
          {!a.oficial && <span className="mt-1 inline-block rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-800 ring-1 ring-amber-200">número de demonstração</span>}
          <p className="mt-1.5 text-[12.5px] leading-snug text-muted">Aponte a câmera do celular para o código ou toque em “Abrir conversa”. Salve o número para falar quando quiser.</p>
        </div>
      </div>
      <div className="mt-3.5 grid grid-cols-1 gap-2 sm:flex sm:flex-wrap">
        {!hideOpen && <OpenConversation />}
        <button onClick={a.share} className="inline-flex h-11 items-center justify-center gap-2 rounded-2xl bg-white px-4 text-[15px] font-semibold text-ink ring-1 ring-line transition hover:bg-green-50 active:scale-[0.97]">
          <Share2 className="size-[18px]" aria-hidden /> Compartilhar com a família
        </button>
      </div>
      <div className="mt-2.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-[13px] font-semibold">
        <button onClick={a.copy} className="inline-flex items-center gap-1.5 text-green-800">
          {a.copied ? <Check className="size-4" aria-hidden /> : <Copy className="size-4" aria-hidden />} Copiar link de conversa
        </button>
        <Link to="/whatsapp/cartaz" className="inline-flex items-center gap-1.5 text-green-800">
          <Printer className="size-4" aria-hidden /> Imprimir cartaz
        </Link>
      </div>
      <p className="mt-1.5 break-all text-[11.5px] text-subtle">{a.link}</p>
    </>
  );
  if (plain) return <div className={className}>{body}</div>;
  return <Card className={clsx('p-4', className)}>{body}</Card>;
}

/** Botão compacto (ex.: topo do chat) que abre o cartão do WhatsApp numa folha. */
export function WhatsAppButton({ className, label = 'WhatsApp' }: { className?: string; label?: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className={clsx('inline-flex h-9 items-center gap-1.5 rounded-xl px-3 text-[13px] font-semibold text-white', className)}
        style={{ background: '#1FAF55' }}
        aria-label="Conversar com a IARA pelo WhatsApp"
      >
        <QrCode className="size-4" aria-hidden /> {label}
      </button>
      <Sheet open={open} onClose={() => setOpen(false)} title="IARA no seu WhatsApp" subtitle="O mesmo atendimento, pelo celular. Compartilhe com quem cuida das crianças.">
        <WhatsAppCard plain title="Leve a conversa para o WhatsApp" />
      </Sheet>
    </>
  );
}
