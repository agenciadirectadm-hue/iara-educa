// WhatsApp confirmado na escola (migração 099.13). A secretaria confere um documento com foto, gera um QR de uso único
// (vale 10 minutos) e o responsável aponta a câmera: o WhatsApp abre com "VINCULAR <código>" e, ao enviar, o número fica
// ligado a ele no nível mais alto — o que libera, pela IARA, os assuntos protegidos (AEE, ocorrências, transporte,
// documentos e dados cadastrais). Pelo número do cadastro, sem o QR, a família já tem a rotina (frequência, avisos, fila).
import { useEffect, useState } from 'react';
import { CheckCircle2, QrCode, ShieldCheck, ShieldOff } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { Button } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { Alternar, Campo, Secao, Selecao, Texto } from '@/components/cadastro';
import { IaraQr } from '@/components/whatsapp';

type Vinculo = { id: string; numero: string; documento: string; unidade: string | null; por: string | null; desde: string; valido_ate: string;
  revogado_em: string | null; motivo: string | null; vigente: boolean };
type Situacao = {
  numero_cadastro: string | null; vinculo: Vinculo | null; historico: Vinculo[]; canal: string | null; pode_vincular: boolean; demo: boolean;
  troca_pendente: { novo: string; pedido_em: string; confirmado_em: string | null; libera_em: string | null } | null;
};
type Qr = { token: string; texto: string; link: string; numero: string; expira_em: string; responsavel: string };

const DOCUMENTOS: [string, string][] = [
  ['RG', 'RG (identidade)'], ['CIN', 'Carteira de Identidade Nacional'], ['CNH', 'CNH'], ['CTPS', 'Carteira de trabalho'],
  ['PASSAPORTE', 'Passaporte'], ['CRNM', 'Carteira de Registro Nacional Migratório'], ['OUTRO', 'Outro documento com foto'],
];

export function VinculoWhatsApp({ responsavelId }: { responsavelId: string }) {
  const sit = useRpc<Situacao>('familia_vinculo_situacao', { guardian_id: responsavelId });
  const [qrAberto, setQrAberto] = useState(false);
  const [revogar, setRevogar] = useState(false);
  const s = sit.data;
  if (sit.isError || !s) return null;
  const v = s.vinculo;
  return (
    <Secao id="whatsapp-escola" icon={ShieldCheck} titulo="WhatsApp confirmado na escola"
      descricao="Com o número do cadastro, a família já acompanha a rotina pela IARA. Confirmado aqui, com documento, libera também os assuntos protegidos: AEE, ocorrências, transporte, documentos e dados cadastrais."
      acao={s.pode_vincular ? <Button size="sm" variant="purple" icon={QrCode} onClick={() => setQrAberto(true)}>{v ? 'Confirmar de novo' : 'Confirmar com QR'}</Button> : undefined}>
      <div className="space-y-2 text-[14px]">
        <p className="text-ink-2">WhatsApp do cadastro: <b>{s.numero_cadastro ?? 'não informado'}</b></p>
        {v ? (
          <div className="flex flex-wrap items-start gap-3 rounded-2xl bg-green-50 p-3 ring-1 ring-green-200">
            <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-green-700" aria-hidden />
            <div className="min-w-0 flex-1">
              <p className="font-semibold text-green-900">Confirmado na escola: {v.numero}</p>
              <p className="text-[13px] text-green-900/80">
                Desde {fmtDate(v.desde)}{v.unidade ? ` · ${v.unidade}` : ''}{v.por ? ` · por ${v.por}` : ''} · documento {v.documento} · vale até {fmtDate(v.valido_ate)} (reconfirmar na rematrícula)
              </p>
            </div>
            {s.pode_vincular && <Button size="sm" variant="ghost" icon={ShieldOff} onClick={() => setRevogar(true)}>Revogar</Button>}
          </div>
        ) : (
          <p className="rounded-2xl bg-amber-50 p-3 text-[13.5px] text-amber-900 ring-1 ring-amber-200">
            Ainda não confirmado na escola. Na próxima vez que o responsável vier, confira um documento com foto e gere o QR: leva 1 minuto.
          </p>
        )}
        {s.troca_pendente && (
          <p className="rounded-2xl bg-blue-50 p-3 text-[13.5px] text-blue-900 ring-1 ring-blue-200">
            Troca de número pedida pela conversa para {s.troca_pendente.novo}
            {s.troca_pendente.libera_em ? `, confirmada pelo número antigo: vale a partir de ${fmtDateTime(s.troca_pendente.libera_em)}.` : ', aguardando a confirmação pelo número antigo.'}
            {' '}Confirmar aqui com o QR cancela a troca e vale na hora.
          </p>
        )}
      </div>
      {qrAberto && <QrSheet responsavelId={responsavelId} onClose={() => { setQrAberto(false); void sit.refetch(); }} />}
      {revogar && <RevogarSheet responsavelId={responsavelId} onClose={() => { setRevogar(false); void sit.refetch(); }} />}
    </Secao>
  );
}

function QrSheet({ responsavelId, onClose }: { responsavelId: string; onClose: () => void }) {
  const toast = useToast();
  const [doc, setDoc] = useState('RG');
  const [conferido, setConferido] = useState(false);
  const [qr, setQr] = useState<Qr | null>(null);
  const [gerando, setGerando] = useState(false);
  const [agora, setAgora] = useState(() => Date.now());
  // enquanto o QR está na tela, confere a cada 3 s se o responsável já enviou a mensagem
  const sit = useRpc<Situacao>('familia_vinculo_situacao', { guardian_id: responsavelId }, { enabled: !!qr, refetchInterval: qr ? 3000 : false });
  const pronto = !!qr && !!sit.data?.vinculo && Date.parse(sit.data.vinculo.desde) >= Date.parse(qr.expira_em) - 10 * 60_000 - 5_000;
  useEffect(() => {
    if (!qr || pronto) return;
    const t = setInterval(() => setAgora(Date.now()), 1000);
    return () => clearInterval(t);
  }, [qr, pronto]);
  const resta = qr ? Math.max(0, Math.round((Date.parse(qr.expira_em) - agora) / 1000)) : 0;

  async function gerar() {
    setGerando(true);
    try {
      setQr(await rpc<Qr>('familia_vinculo_qr', { guardian_id: responsavelId, documento_tipo: doc, documento_conferido: conferido }));
      setAgora(Date.now());
    } catch (e) {
      toast({ title: 'QR não gerado', description: (e as Error).message, tone: 'error' });
    } finally {
      setGerando(false);
    }
  }

  return (
    <Sheet open onClose={onClose} title="Confirmar o WhatsApp na escola" subtitle="O responsável aponta a câmera do celular para o QR e envia a mensagem que abrir."
      footer={!qr ? <Button block variant="purple" icon={QrCode} loading={gerando} disabled={!conferido} onClick={gerar}>Gerar QR (vale 10 minutos)</Button>
        : <Button block variant="secondary" onClick={onClose}>{pronto ? 'Concluir' : 'Fechar'}</Button>}>
      {!qr ? (
        <div className="space-y-3">
          <Campo label="Documento com foto conferido" obrigatorio>
            <Selecao value={doc} onChange={setDoc} opcoes={DOCUMENTOS} vazio={false} />
          </Campo>
          <Alternar checked={conferido} onChange={setConferido} label="Conferi o documento com foto, e é a pessoa deste cadastro"
            dica="O QR liga o WhatsApp de quem estiver com o celular. Gere só com o responsável à sua frente." />
        </div>
      ) : pronto ? (
        <div className="flex flex-col items-center gap-3 py-6 text-center">
          <CheckCircle2 className="size-14 text-green-700" aria-hidden />
          <p className="font-display text-lg font-extrabold">WhatsApp confirmado</p>
          <p className="text-[14px] text-muted">{sit.data?.vinculo?.numero} ficou ligado a {qr.responsavel}. A IARA já mandou a confirmação no WhatsApp.</p>
        </div>
      ) : resta === 0 ? (
        <div className="space-y-3 py-4 text-center">
          <p className="font-semibold">O QR venceu.</p>
          <Button variant="purple" icon={QrCode} onClick={() => { setQr(null); setConferido(false); }}>Gerar outro</Button>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-3 text-center">
          <IaraQr value={qr.link} size={220} />
          <p className="text-[14px] text-ink-2">
            Peça para <b>{qr.responsavel.split(' ')[0]}</b> apontar a câmera do celular. O WhatsApp abre com a mensagem <b>{qr.texto}</b>: é só enviar.
          </p>
          <p className="text-[13px] text-muted">
            Se a câmera não abrir o WhatsApp, a pessoa pode mandar <b>{qr.texto}</b> para {qr.numero}. Vale por mais {Math.floor(resta / 60)}:{String(resta % 60).padStart(2, '0')}.
          </p>
          <p className="text-[12.5px] text-muted">Aguardando a mensagem…</p>
        </div>
      )}
    </Sheet>
  );
}

function RevogarSheet({ responsavelId, onClose }: { responsavelId: string; onClose: () => void }) {
  const toast = useToast();
  const [motivo, setMotivo] = useState('');
  const [salvando, setSalvando] = useState(false);
  async function confirmar() {
    setSalvando(true);
    try {
      await rpc('familia_vinculo_revogar', { guardian_id: responsavelId, motivo });
      toast({ title: 'Confirmação revogada', description: 'O número volta ao nível do cadastro: só a rotina pela IARA.', tone: 'success' });
      onClose();
    } catch (e) {
      toast({ title: 'Não revogado', description: (e as Error).message, tone: 'error' });
    } finally {
      setSalvando(false);
    }
  }
  return (
    <Sheet open onClose={onClose} title="Revogar o WhatsApp confirmado" subtitle="Use quando o celular for perdido, trocado ou estiver com outra pessoa."
      footer={<Button block variant="danger" icon={ShieldOff} loading={salvando} disabled={motivo.trim().length < 5} onClick={confirmar}>Revogar</Button>}>
      <Campo label="Motivo" obrigatorio>
        <Texto value={motivo} onChange={setMotivo} placeholder="Ex.: responsável informou que perdeu o celular" />
      </Campo>
    </Sheet>
  );
}
