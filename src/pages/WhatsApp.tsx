import { useState, type ReactNode } from 'react';
import { Link, useNavigate } from 'react-router';
import { ArrowLeft, CheckCheck, MessageCircle, Plane, Printer, UserRound } from 'lucide-react';
import { useSession } from '@/lib/session';
import type { Role } from '@/lib/types';
import { useToast } from '@/components/overlays';
import { IaraAvatar } from '@/components/iara';
import { IaraQr, OpenConversation, WhatsAppCard, WhatsAppGlyph, useIaraWhatsApp } from '@/components/whatsapp';

function Bubble({ children, time = 'agora' }: { children: ReactNode; time?: string }) {
  return (
    <div className="max-w-[88%] rounded-2xl rounded-tl-md bg-white px-3.5 py-2 text-[15px] leading-snug text-ink shadow-[0_1px_1px_rgba(0,0,0,0.08)]">
      {children}
      <div className="mt-0.5 text-right text-[10.5px] text-subtle">{time}</div>
    </div>
  );
}

function Option({ icon: I, label, onClick, busy }: { icon: typeof Plane; label: string; onClick: () => void; busy?: 'self' | 'other' | null }) {
  return (
    <button
      onClick={onClick}
      disabled={!!busy}
      className="flex w-full items-center gap-3 rounded-2xl bg-white px-4 py-3 text-left text-[15px] font-semibold text-[#0B7A4B] shadow-[0_1px_1px_rgba(0,0,0,0.08)] transition hover:bg-green-50 active:scale-[0.99] disabled:opacity-60"
    >
      <I className="size-5 shrink-0" aria-hidden />
      <span className="flex-1">{busy === 'self' ? 'Abrindo a conversa…' : label}</span>
    </button>
  );
}

/**
 * Início da conversa pelo WhatsApp (destino do QR code e do link de conversa).
 * Com o número oficial, o QR code já abre o WhatsApp; esta tela fica para quem chega pelo portal.
 * Na demonstração, abre a conversa simulada da IARA — o mesmo agente que atende no WhatsApp.
 */
export function WhatsAppEntry() {
  const wa = useIaraWhatsApp();
  const { login, me } = useSession();
  const navigate = useNavigate();
  const toast = useToast();
  const [busy, setBusy] = useState<Role | null>(null);
  const isFamily = me?.scope === 'GUARDIAN';

  const start = async (role: Role) => {
    setBusy(role);
    try {
      await login(role, null);
      navigate('/iara', { replace: true });
    } catch (e) {
      toast({ title: 'Não foi possível iniciar a conversa', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="min-h-dvh bg-[#EFEAE2] pb-safe">
      <header className="sticky top-0 z-10 bg-[#0B6E4F] pt-safe text-white shadow">
        <div className="mx-auto flex max-w-5xl items-center gap-3 px-3 py-2.5">
          <Link to="/entrar" className="inline-flex size-10 items-center justify-center rounded-full hover:bg-white/10" aria-label="Voltar ao portal">
            <ArrowLeft className="size-5" />
          </Link>
          <IaraAvatar size={40} ring={false} />
          <div className="min-w-0 flex-1">
            <div className="truncate font-semibold">IARA · Educação Maringá</div>
            <div className="truncate text-[12.5px] text-white/80">assistente virtual · responde na hora</div>
          </div>
          {!wa.oficial && <span className="rounded-full bg-white/15 px-2.5 py-1 text-[11px] font-semibold">demonstração</span>}
        </div>
      </header>

      <main className="mx-auto grid max-w-5xl gap-6 px-3 py-5 md:grid-cols-[1fr_380px] md:px-6">
        <section className="space-y-2.5" aria-label="Início da conversa">
          <div className="mx-auto w-fit rounded-lg bg-white/80 px-3 py-1 text-[12px] text-ink-2 shadow-sm">Hoje</div>
          <Bubble>Oi! Eu sou a <b>IARA</b>, assistente virtual da Secretaria Municipal de Educação de Maringá. 👋</Bubble>
          <Bubble>
            Por aqui você procura vaga em creche e escola, acompanha a fila, envia documentos e avisa mudanças da família —
            nascimento, mudança de endereço ou chegada de outra cidade. O que eu não puder resolver na hora, passo para a escola
            ou para a Secretaria com protocolo e prazo.
          </Bubble>

          {wa.oficial ? (
            <div className="space-y-2 pt-2">
              <OpenConversation className="w-full">Abrir no meu WhatsApp</OpenConversation>
              <p className="text-center text-[12.5px] text-ink-2">A mensagem “{wa.mensagem}” já vai escrita. É só enviar.</p>
            </div>
          ) : isFamily ? (
            <div className="space-y-2 pt-2">
              <Bubble>Que bom te ver de novo{me?.guardian?.name ? `, ${me.guardian.name.split(' ')[0]}` : ''}! Vamos continuar?</Bubble>
              <Option icon={MessageCircle} label="Continuar minha conversa" onClick={() => navigate('/iara')} />
            </div>
          ) : (
            <div className="space-y-2 pt-2">
              <Bubble>Para começar, me conta:</Bubble>
              <Option icon={Plane} busy={busy ? (busy === 'CIDADAO_NOVO' ? 'self' : 'other') : null} label="É minha primeira vez / acabamos de chegar a Maringá" onClick={() => start('CIDADAO_NOVO')} />
              <Option icon={UserRound} busy={busy ? (busy === 'CIDADAO' ? 'self' : 'other') : null} label="Já tenho cadastro (família de demonstração)" onClick={() => start('CIDADAO')} />
            </div>
          )}

          <div className="flex items-center justify-center gap-1.5 pt-3 text-[12px] text-ink-2">
            <CheckCheck className="size-4 text-[#34B7F1]" aria-hidden />
            {wa.oficial ? 'Conversa oficial da Secretaria Municipal de Educação.' : 'Demonstração: nenhuma mensagem real é enviada.'}
          </div>
        </section>

        <aside className="space-y-3">
          <WhatsAppCard hideOpen title="Compartilhe com a família" subtitle="Escaneie o código em outro celular — ou do computador para o celular — ou envie o link de conversa para quem também cuida das crianças." />
        </aside>
      </main>
    </div>
  );
}

/** Cartaz A4 para imprimir e afixar na escola, no CMEI e nos pontos de atendimento. */
export function WhatsAppPoster() {
  const wa = useIaraWhatsApp();
  return (
    <div className="min-h-dvh bg-slate-100 py-6 print:bg-white print:py-0">
      <style>{'@page { size: A4; margin: 10mm; }'}</style>
      <div className="mx-auto mb-4 flex max-w-[190mm] items-center justify-between gap-2 px-4 print:hidden">
        <Link to="/whatsapp" className="inline-flex h-10 items-center gap-1.5 rounded-xl bg-white px-3 text-sm font-semibold ring-1 ring-line">
          <ArrowLeft className="size-4" /> Voltar
        </Link>
        <button onClick={() => window.print()} className="inline-flex h-10 items-center gap-1.5 rounded-xl bg-purple-700 px-4 text-sm font-semibold text-white">
          <Printer className="size-4" /> Imprimir cartaz
        </button>
      </div>

      <article className="mx-auto flex max-w-[190mm] flex-col items-center rounded-3xl bg-white px-8 py-10 text-center shadow-lift print:max-w-none print:rounded-none print:px-0 print:py-0 print:shadow-none">
        <div className="text-[13px] font-bold uppercase tracking-[0.18em] text-purple-700">Prefeitura de Maringá · Secretaria Municipal de Educação</div>
        <img src="./iara/iara-full.webp" alt="" className="mt-4 h-44 w-auto" />
        <h1 className="mt-3 font-display text-[40px] font-black leading-[1.05] text-ink">
          Fale com a <span className="text-purple-700">IARA</span>
          <br />pelo WhatsApp
        </h1>
        <p className="mt-3 max-w-[150mm] text-[18px] leading-snug text-ink-2">
          Vaga em creche e escola, fila de espera, documentos e mudanças da família — direto do seu celular, a qualquer hora.
        </p>

        <div className="mt-6 rounded-[28px] p-3" style={{ background: 'linear-gradient(135deg,#25D366,#7A24C5)' }}>
          <IaraQr value={wa.link} size={300} className="rounded-[20px] p-4" />
        </div>

        <div className="mt-5 flex items-center gap-3">
          <WhatsAppGlyph className="size-12" />
          <span className="font-display text-[44px] font-black tabular tracking-tight text-ink">{wa.numero}</span>
        </div>
        <p className="mt-1 break-all text-[13px] text-subtle">{wa.link}</p>

        <ol className="mt-7 grid w-full max-w-[160mm] grid-cols-3 gap-4 text-left">
          {[
            ['1', 'Aponte a câmera do celular para o código.'],
            ['2', 'Toque no link que aparecer na tela.'],
            ['3', 'Envie a mensagem: a IARA responde na hora.'],
          ].map(([n, t]) => (
            <li key={n} className="rounded-2xl bg-slate-50 p-3.5 ring-1 ring-line">
              <span className="inline-flex size-8 items-center justify-center rounded-full bg-purple-700 font-display text-[16px] font-black text-white">{n}</span>
              <p className="mt-2 text-[15px] font-semibold leading-snug text-ink">{t}</p>
            </li>
          ))}
        </ol>

        <p className="mt-7 text-[13px] text-muted">
          A IARA resolve na hora cadastro, fila, endereço e documentos. O que precisar de decisão da escola ou da Secretaria vira protocolo, com prazo.
        </p>
        {!wa.oficial && (
          <p className="mt-3 rounded-xl bg-amber-50 px-3 py-2 text-[12px] font-semibold text-amber-900 ring-1 ring-amber-200">
            Demonstração — número oficial a definir pela SEDUC. Hoje o código abre a conversa simulada da IARA.
          </p>
        )}
      </article>
    </div>
  );
}

export default WhatsAppEntry;
