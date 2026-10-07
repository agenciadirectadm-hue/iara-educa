import { Link } from 'react-router';
import { Lock, ShieldAlert, ShieldCheck } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtInt } from '@/lib/format';
import { Card, Section } from '@/components/ui';

type Painel = {
  periodo_horas: number;
  auditoria: { integra: boolean; total: number; verificados: number; primeira_quebra?: { seq: number; motivo: string } };
  limites_excedidos: Record<string, number>;
  whatsapp_barrados: number;
  eventos: Record<string, number>;
  leituras_sensiveis_por_pessoa: { quem: string; perfil: string; leituras: number }[];
};

const LIMITE: Record<string, string> = {
  ip: 'por endereço (IP)', sessao: 'por sessão', 'nova-sessao': 'criação de sessões', iara: 'conversas com a IARA', rotas: 'rotas e mapas', wa: 'WhatsApp por telefone',
};
const EVENTO: [string, string][] = [
  ['VIEW_SENSITIVE', 'Leituras de dado sensível'], ['CONTROLE_CONSULTA', 'Consultas do controle externo'], ['EXPORT', 'Exportações'],
  ['RULE_VERSION', 'Mudanças de regra'], ['REGRA_MEDIDA_DISTANCIA', 'Troca da medida de distância'], ['PRIORITY_DECISION', 'Decisões de prioridade (laudo)'],
  ['CARGA_PROMOVIDA', 'Cargas de dados promovidas'], ['CARGA_REVERTIDA', 'Cargas revertidas'], ['WHATSAPP_CANAL', 'WhatsApp ligado/desligado'],
  ['WHATSAPP_AUTORIZADOS', 'Mudanças na lista de números'], ['DEMO_PURGE', 'Limpezas da demonstração'],
];

/** Painel de segurança (SEC-MON-04): o que o próprio sistema registra nas últimas 24 h, sem dados pessoais de famílias. */
export function PainelSeguranca() {
  const q = useRpc<Painel>('seguranca_painel', { horas: 24 }, { staleTime: 60_000, refetchInterval: 120_000 });
  if (!q.data) return null;
  const d = q.data;
  const limites = Object.entries(d.limites_excedidos ?? {});
  return (
    <Section title={<span className="inline-flex items-center gap-2"><ShieldCheck className="size-5 text-purple-700" />Segurança nas últimas {d.periodo_horas} h</span>}
      action={<Link to="/auditoria" className="text-sm font-semibold text-purple-700">Trilha de auditoria</Link>}>
      <Card className="p-4 text-[14px]">
        <div className={d.auditoria.integra ? 'flex items-start gap-2 text-green-800' : 'flex items-start gap-2 text-red-800'}>
          <Lock className="mt-0.5 size-4 shrink-0" />
          {d.auditoria.integra
            ? <span>Trilha de auditoria íntegra ({fmtInt(d.auditoria.total)} registros encadeados; os últimos {fmtInt(d.auditoria.verificados)} conferidos agora).</span>
            : <span>Quebra na trilha no registro {d.auditoria.primeira_quebra?.seq}: {d.auditoria.primeira_quebra?.motivo}. Acione o plano de incidentes.</span>}
        </div>
        <div className="mt-2 flex items-start gap-2">
          <ShieldAlert className={limites.length ? 'mt-0.5 size-4 shrink-0 text-amber-600' : 'mt-0.5 size-4 shrink-0 text-green-700'} />
          <span>
            {limites.length
              ? <>Limites de requisição estourados: {limites.map(([k, n]) => `${LIMITE[k] ?? k} (${fmtInt(n)})`).join(' · ')}.</>
              : 'Nenhum limite de requisição estourado.'}
            {d.whatsapp_barrados > 0 && <> {fmtInt(d.whatsapp_barrados)} número(s) fora da lista do WhatsApp.</>}
          </span>
        </div>
        <ul className="mt-3 grid grid-cols-1 gap-x-4 gap-y-1 text-[13px] sm:grid-cols-2">
          {EVENTO.filter(([k]) => d.eventos?.[k]).map(([k, l]) => (
            <li key={k} className="flex justify-between gap-2 border-b border-line/60 py-0.5"><span className="text-muted">{l}</span><b className="tabular">{fmtInt(d.eventos[k])}</b></li>
          ))}
        </ul>
        {d.leituras_sensiveis_por_pessoa.length > 0 && (
          <p className="mt-2 text-[12.5px] text-muted">
            Quem mais leu dado sensível: {d.leituras_sensiveis_por_pessoa.map((x) => `${x.quem} (${x.leituras})`).join(', ')}.
          </p>
        )}
      </Card>
    </Section>
  );
}
