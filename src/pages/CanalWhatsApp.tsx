import { useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { AlertTriangle, CheckCircle2, Link2, MessageCircle, Power, PowerOff, QrCode, RefreshCw, Smartphone, Terminal, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import { fmtInt, timeAgo } from '@/lib/format';
import { Badge, Button, Card, ErrorState, PageHeader, Section, SkeletonList } from '@/components/ui';
import { useConfirm, useToast } from '@/components/overlays';
import { IaraQr, WhatsAppGlyph } from '@/components/whatsapp';

type Canal = {
  numero: string; numero_formatado: string; nome: string; provedor: string; ativo: boolean; estado: string; online: boolean;
  ultimo_sinal_em: string | null; pareado_em: string | null; ligado_em: string | null; desligado_em: string | null; alterado_por: string | null;
  compartilhado_com: string | null; observacoes: string | null; ponte_configurada: boolean; pode_gerenciar: boolean;
  contatos: number; familias_vinculadas: number; mensagens_24h: number; saida_pendente: number; enviadas_24h: number;
};

const PONTE: Record<string, { label: string; tone: 'green' | 'amber' | 'gray' | 'red' }> = {
  CONECTADO: { label: 'Ponte conectada ao WhatsApp', tone: 'green' },
  AGUARDANDO_PAREAMENTO: { label: 'Aguardando pareamento (QR)', tone: 'amber' },
  DESCONECTADO: { label: 'Ponte desconectada', tone: 'red' },
  SEM_PONTE: { label: 'Nenhuma ponte rodando', tone: 'gray' },
};
const PROVEDOR: Record<string, string> = { BAILEYS: 'Ponte local (Baileys)', EVOLUTION: 'Evolution API', META_CLOUD: 'API oficial da Meta' };

/** WhatsApp da IARA: o número ligado ao agente, a ponte e o interruptor (um sistema de cada vez no mesmo chip). */
export default function CanalWhatsApp() {
  const q = useRpc<Canal>('whatsapp_canal', {}, { refetchInterval: 10_000 });
  const now = useNow(10_000);
  const qc = useQueryClient();
  const confirm = useConfirm();
  const toast = useToast();
  const [busy, setBusy] = useState(false);

  if (q.isLoading) return <SkeletonList rows={4} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const c = q.data!;
  const ponte = c.online ? PONTE.CONECTADO : PONTE[c.estado] ?? PONTE.SEM_PONTE;
  const link = `https://wa.me/${c.numero.replace(/\D/g, '')}`;

  const alternar = async () => {
    const ligar = !c.ativo;
    const ok = await confirm(ligar
      ? {
        title: `Ligar a IARA Educa no ${c.numero_formatado}?`,
        body: <>Este chip é compartilhado com a <b>{c.compartilhado_com ?? 'outra IARA'}</b>. Antes de ligar, confirme que a ponte dela está <b>parada</b> — com as duas ligadas, as duas responderiam às mesmas famílias. Com a ponte desta plataforma rodando, a IARA Educa passa a responder e o QR code do portal da família abre este WhatsApp.</>,
        confirm: 'Ligar', tone: 'success',
      }
      : {
        title: 'Desligar a IARA Educa no WhatsApp?',
        body: 'As mensagens que chegarem deixam de ser respondidas por esta plataforma, a fila de saída pendente é descartada e o QR code do portal volta para a conversa de demonstração. A ponte pode continuar conectada.',
        confirm: 'Desligar', tone: 'danger',
      });
    if (!ok) return;
    setBusy(true);
    try {
      await rpc('whatsapp_canal_ligar', { ativo: ligar });
      await qc.invalidateQueries();
      toast({ title: ligar ? 'WhatsApp ligado' : 'WhatsApp desligado', description: ligar ? 'A IARA Educa responde neste número enquanto a ponte estiver rodando.' : 'A IARA Educa parou de responder neste número.', tone: 'success' });
    } catch (e) {
      toast({ title: 'Não foi possível alterar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <PageHeader eyebrow="Canal de atendimento" title="WhatsApp da IARA"
        subtitle="O número ligado ao agente: as famílias conversam pelo WhatsApp com a mesma IARA do portal, com o mesmo resultado." />

      <Card className="overflow-hidden">
        <div className={clsx('flex flex-wrap items-center gap-4 p-4 sm:p-5', c.ativo ? 'bg-green-50' : 'bg-slate-50')}>
          <WhatsAppGlyph className="size-12" />
          <div className="min-w-0 flex-1">
            <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">{c.nome} · {PROVEDOR[c.provedor] ?? c.provedor}</div>
            <div className="font-display text-[28px] font-black leading-tight tabular">{c.numero_formatado}</div>
            <div className="mt-1 flex flex-wrap items-center gap-2">
              <Badge tone={c.ativo ? 'green' : 'gray'} dot>{c.ativo ? 'LIGADO — a IARA Educa responde' : 'DESLIGADO nesta plataforma'}</Badge>
              <Badge tone={ponte.tone} dot>{ponte.label}</Badge>
              {c.ultimo_sinal_em && <span className="text-[12px] text-muted">último sinal {timeAgo(c.ultimo_sinal_em, now)}</span>}
            </div>
          </div>
          {c.pode_gerenciar && (
            <Button variant={c.ativo ? 'danger' : 'success'} size="lg" icon={c.ativo ? PowerOff : Power} loading={busy} onClick={alternar}>
              {c.ativo ? 'Desligar' : 'Ligar'}
            </Button>
          )}
        </div>
        {c.compartilhado_com && (
          <div className="flex items-start gap-2 border-t border-line bg-amber-50 px-4 py-3 text-[13px] text-amber-900 sm:px-5">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" />
            <span><b>Mesmo chip da {c.compartilhado_com}.</b> Cada sistema tem a sua ponte (aparelho conectado próprio): ligue um de cada vez — pare a ponte de um antes de ligar a do outro.</span>
          </div>
        )}
        {c.ativo && !c.online && (
          <div className="flex items-start gap-2 border-t border-line bg-red-50 px-4 py-3 text-[13px] text-red-900 sm:px-5">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" />
            <span>Ligado, mas sem ponte conectada: ninguém está recebendo as mensagens. Rode a ponte no computador do chip (veja abaixo).</span>
          </div>
        )}
      </Card>

      <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-5">
        {[
          { icon: Users, label: 'Contatos', v: c.contatos },
          { icon: CheckCircle2, label: 'Famílias vinculadas', v: c.familias_vinculadas },
          { icon: MessageCircle, label: 'Mensagens recebidas (24 h)', v: c.mensagens_24h },
          { icon: Smartphone, label: 'Enviadas pela fila (24 h)', v: c.enviadas_24h },
          { icon: RefreshCw, label: 'Na fila de saída', v: c.saida_pendente },
        ].map((k) => (
          <Card key={k.label} className="p-3.5">
            <k.icon className="size-4 text-green-700" />
            <div className="mt-1 font-display text-2xl font-black tabular">{fmtInt(k.v)}</div>
            <div className="text-[12px] text-muted">{k.label}</div>
          </Card>
        ))}
      </div>

      <div className="mt-2 grid grid-cols-1 gap-4 lg:grid-cols-[1.4fr_1fr]">
        <Section title={<span className="inline-flex items-center gap-2"><Terminal className="size-5 text-green-700" />Como ligar e desligar</span>}
          subtitle="No computador onde a ponte roda (o mesmo da IARA Saúde serve).">
          <Card className="p-4 text-[14px]">
            <ol className="space-y-3">
              {[
                ['Primeira vez', <>Na pasta do projeto: <Code>cd whatsapp-ponte</Code> · <Code>npm install</Code> · <Code>npm run configurar</Code> {c.ponte_configurada ? <Badge tone="green">segredo já registrado</Badge> : <Badge tone="amber">registre o hash no banco</Badge>}</>],
                ['Pare a ponte da IARA Saúde', <>Na janela da ponte da Saúde, <Code>Ctrl+C</Code>. Ela continua pareada; só deixa de responder.</>],
                ['Ligue a da Educação', <><Code>npm run ligar</Code> — liga o canal e conecta. Na primeira vez aparece um QR: no celular do chip, <b>WhatsApp → Aparelhos conectados → Conectar aparelho</b> (ou abra <Code>http://localhost:5299</Code>).</>],
                ['Para voltar à Saúde', <><Code>Ctrl+C</Code> nesta ponte (desliga o canal da Educação) e ligue a ponte da Saúde.</>],
              ].map(([t, d], i) => (
                <li key={i} className="flex gap-3">
                  <span className="inline-flex size-7 shrink-0 items-center justify-center rounded-full bg-green-700 text-[13px] font-black text-white">{i + 1}</span>
                  <div><div className="font-semibold">{t}</div><div className="mt-0.5 text-muted">{d}</div></div>
                </li>
              ))}
            </ol>
            <p className="mt-4 rounded-2xl bg-slate-50 p-3 text-[12.5px] text-muted ring-1 ring-line">
              Testar sem celular: <Code>node simular.mjs --ligar +5544900001234 "oi" "2"</Code> mostra o que a IARA responderia (nada é enviado).
              O botão Ligar/Desligar acima é o mesmo interruptor: a ponte pode ficar conectada com o canal desligado.
            </p>
          </Card>
        </Section>

        <Section title={<span className="inline-flex items-center gap-2"><QrCode className="size-5 text-green-700" />Contato para as famílias</span>}
          subtitle={c.ativo ? 'Com o canal ligado, o QR code do portal já abre este WhatsApp.' : 'Desligado: o QR code do portal abre a conversa de demonstração.'}>
          <Card className="flex flex-col items-center gap-3 p-4 text-center">
            <IaraQr value={link} size={170} className={clsx(!c.ativo && 'opacity-40')} />
            <a href={link} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1.5 text-[13.5px] font-semibold text-green-800"><Link2 className="size-4" />{link}</a>
            <Link to="/whatsapp/cartaz" className="text-[13px] font-semibold text-purple-700">Cartaz para imprimir</Link>
          </Card>
        </Section>
      </div>

      <p className="mt-4 text-[12px] text-muted">
        {c.ligado_em && <>Ligado pela última vez {timeAgo(c.ligado_em, now)}{c.alterado_por ? ` (${c.alterado_por})` : ''}. </>}
        Conexão não oficial (WhatsApp Web) pode ser bloqueada pelo WhatsApp sem aviso: para a operação da Prefeitura, migrar para a API oficial da Meta — o gateway já separa o canal do agente.
        Mensagens reais trazem dados pessoais reais: trate como produção (LGPD).
      </p>
    </div>
  );
}

function Code({ children }: { children: ReactNode }) {
  return <code className="rounded-md bg-slate-100 px-1.5 py-0.5 font-mono text-[12.5px] text-ink">{children}</code>;
}
