import { useState, type ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, Presentation, RotateCcw, XCircle } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { useBootstrap } from '@/lib/data';
import { fmtInt, timeAgo } from '@/lib/format';
import { Button, Card, Section } from '@/components/ui';
import { useConfirm, useToast } from '@/components/overlays';

type Situacao = {
  davi: { posicao: number | null; pontos: number | null; situacao: string | null };
  davi_ok: boolean;
  criado_por_visitas: { familias: number; criancas: number; protocolos: number; conversas_whatsapp: number };
  ultima_limpeza: string | null;
  whatsapp: { ligado: boolean; online: boolean; somente_autorizados: boolean } | null;
};

/**
 * Rotina de apresentação (Fase 1 do documento de estrutura): antes, conferir o cenário; depois, limpar em um clique
 * o que visitantes, testes e o WhatsApp criaram e reiniciar a família da Maria. Só existe no modo demonstração.
 */
export function RotinaApresentacao() {
  const { can } = useSession();
  const boot = useBootstrap();
  const ativo = can('demo.manage') && boot.data?.tenant.demo_mode === true;
  const q = useRpc<Situacao>('demo_apresentacao_situacao', {}, { enabled: ativo, refetchInterval: 60_000 });
  const qc = useQueryClient();
  const confirm = useConfirm();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  if (!ativo || !q.data) return null;
  const s = q.data;
  const v = s.criado_por_visitas;
  const sujeira = v.familias + v.criancas + v.protocolos + v.conversas_whatsapp;

  const limpar = async () => {
    const ok = await confirm({
      title: 'Limpar a demonstração?',
      body: 'Apaga o que visitantes, testes e o WhatsApp criaram (famílias, crianças, protocolos, conversas e contatos), devolve ao original o que eles alteraram e reinicia a família da Maria. A trilha de auditoria não é apagada.',
      confirm: 'Limpar agora', tone: 'purple',
    });
    if (!ok) return;
    setBusy(true);
    try {
      await rpc('demo_apresentacao_limpar', {});
      await qc.invalidateQueries();
      toast({ title: 'Demonstração limpa', description: 'Pronta para a próxima apresentação.', tone: 'success' });
    } catch (e) {
      toast({ title: 'Não foi possível limpar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  const Item = ({ ok, children }: { ok: boolean; children: ReactNode }) => (
    <li className="flex items-start gap-2">
      {ok ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" /> : <XCircle className="mt-0.5 size-4 shrink-0 text-amber-600" />}
      <span>{children}</span>
    </li>
  );

  return (
    <Section title={<span className="inline-flex items-center gap-2"><Presentation className="size-5 text-purple-700" />Rotina de apresentação</span>}
      subtitle="Antes de apresentar, confira; depois, limpe em um clique.">
      <Card className="p-4 text-[14px]">
        <ul className="space-y-1.5">
          <Item ok={s.davi_ok}>Família da Maria: Davi {s.davi.posicao ? `em ${s.davi.posicao}º lugar` : 'fora da fila'}{s.davi.pontos != null ? ` com ${fmtInt(s.davi.pontos)} pontos` : ''}{s.davi_ok ? '' : ' (o esperado é 1º com 95; a limpeza reinicia)'}.</Item>
          <Item ok={sujeira === 0}>
            {sujeira === 0 ? 'Nada criado por visitas desde a última limpeza.' : `Criado por visitas e testes: ${fmtInt(v.familias)} família(s), ${fmtInt(v.criancas)} criança(s), ${fmtInt(v.protocolos)} protocolo(s), ${fmtInt(v.conversas_whatsapp)} contato(s) de WhatsApp.`}
            {s.ultima_limpeza && <span className="text-muted"> Última limpeza {timeAgo(s.ultima_limpeza)}.</span>}
          </Item>
          <Item ok={!!s.whatsapp && (!s.whatsapp.ligado || s.whatsapp.online)}>
            WhatsApp de teste: {!s.whatsapp ? 'sem canal' : !s.whatsapp.ligado ? 'desligado' : s.whatsapp.online ? 'ligado e com a ponte conectada' : 'ligado, mas a ponte não está dando sinal (ninguém responde)'}
            {s.whatsapp?.somente_autorizados ? ' · só números autorizados' : ''}.
          </Item>
        </ul>
        <div className="mt-3 flex justify-end">
          <Button variant="purple" icon={RotateCcw} loading={busy} onClick={limpar}>Limpar depois da apresentação</Button>
        </div>
      </Card>
    </Section>
  );
}
