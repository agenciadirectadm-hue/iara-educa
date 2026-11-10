// Órgãos externos (Tribunal de Contas, conselhos, Conselho Tutelar e Câmara): a mesma base, sem nomes.
// Conselho Tutelar: além do agregado, as crianças sem retirada muito depois do prazo, por código; a consulta exige motivo e fica auditada.
import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { Lock, Search, ShieldAlert } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, EmptyState, ErrorState, Field, PageHeader, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { PainelUniformes } from '@/components/uniformes';
import { IdebRedePainel } from '@/components/ideb';

type Aba = 'uniformes' | 'ideb' | 'tutelar';

export default function PainelOrgao() {
  const { me, can } = useSession();
  const [sp, setSp] = useSearchParams();
  const abas: { value: Aba; label: string }[] = [
    ...(can('uk.tutelar') ? [{ value: 'tutelar' as Aba, label: 'Crianças para atenção' }] : []),
    { value: 'uniformes', label: 'Uniformes e kits' },
    { value: 'ideb', label: 'Ideb das escolas' },
  ];
  const aba = (abas.find((a) => a.value === sp.get('aba'))?.value ?? abas[0].value) as Aba;
  return (
    <div>
      <PageHeader eyebrow={me?.role_name ?? 'Órgão externo'} title={me?.question ?? 'Painel'}
        subtitle="Dados da rede municipal de educação de Maringá, sem nomes de crianças ou famílias. Toda consulta fica registrada na trilha de auditoria." />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={abas} />
      <div className="mt-4">
        {aba === 'uniformes' && <PainelUniformes />}
        {aba === 'ideb' && <IdebRedePainel />}
        {aba === 'tutelar' && <TutelarAba />}
      </div>
    </div>
  );
}

function TutelarAba() {
  const res = useRpc<any>('uk_tutelar_lista', {});
  const toast = useToast();
  const [codigo, setCodigo] = useState('');
  const [motivo, setMotivo] = useState('');
  const [ficha, setFicha] = useState<any>(null);
  const [busy, setBusy] = useState(false);
  const consultar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('uk_tutelar_consulta', { codigo, motivo });
      if (r.encontrado === false) { setFicha(null); toast({ title: 'Código não encontrado', description: r.mensagem, tone: 'error' }); }
      else setFicha(r);
    }
    catch (e) { setFicha(null); toast({ title: 'Não consultado', description: (e as Error).message, tone: 'error' }); }
    finally { setBusy(false); }
  };
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_380px]">
      <div className="space-y-3">
        <p className="text-[13.5px] text-muted">{res.data.nota} Critério: prazo de retirada vencido há mais de {res.data.dias} dias.</p>
        <Card className="overflow-hidden">
          {(res.data.casos as any[]).length ? (
            <Tabela colunas="110px minmax(200px,1.4fr) minmax(140px,1fr) 100px 110px 80px 80px 80px" largura={980} rotulo="Crianças para atenção">
              <TCabecalho><TCelula fixa>Código</TCelula><TCelula>Unidade</TCelula><TCelula>Região</TCelula><TCelula>Etapa</TCelula><TCelula>Prazo</TCelula><TCelula>Dias</TCelula><TCelula>Avisos</TCelula><TCelula>Ciência</TCelula></TCabecalho>
              {(res.data.casos as any[]).map((c) => (
                <TLinha key={c.codigo} onClick={() => setCodigo(c.codigo)} ativo={codigo === c.codigo} alerta={c.dias > 90}>
                  <TCelula fixa><span className="font-mono">{c.codigo}</span></TCelula><TCelula>{c.unidade}</TCelula><TCelula>{c.regiao ?? '—'}</TCelula><TCelula>{c.etapa}</TCelula>
                  <TCelula>{fmtDate(c.prazo)}</TCelula><TCelula>{fmtInt(c.dias)}</TCelula><TCelula>{fmtInt(c.avisos)}</TCelula><TCelula>{c.ciente ? 'sim' : 'não'}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          ) : <EmptyState compact title="Nenhuma criança nesta lista" />}
        </Card>
      </div>
      <Card className="h-fit space-y-3 p-4">
        <div className="flex items-center gap-2 font-semibold"><ShieldAlert className="size-4 text-red-600" />Consultar um código</div>
        <Field label="Código público"><input className={inputCls + ' font-mono'} value={codigo} onChange={(e) => setCodigo(e.target.value.toUpperCase())} placeholder="F-XXXXXX" /></Field>
        <Field label="Motivo da consulta (fica registrado)"><textarea className={inputCls + ' min-h-20 py-2'} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: acompanhamento de família já atendida pelo Conselho." /></Field>
        <Button block icon={Search} loading={busy} disabled={!codigo || motivo.trim().length < 15} onClick={consultar}>Consultar</Button>
        {ficha && (
          <div className="space-y-1.5 rounded-2xl bg-slate-50 p-3 text-[13.5px]">
            <div className="text-[16px] font-bold">{ficha.nome}</div>
            <div>{ficha.idade} · {ficha.turma} · {ficha.unidade}</div>
            {ficha.bairro && <div>Bairro: {ficha.bairro}</div>}
            {ficha.responsavel && <div>Responsável: <b>{ficha.responsavel.nome}</b> ({ficha.responsavel.parentesco?.toLowerCase()}) · {ficha.responsavel.telefone ?? 'sem telefone'}</div>}
            <div>Prazo de retirada: {fmtDate(ficha.prazo)} ({fmtInt(ficha.dias)} dias)</div>
            <div className="pt-1 font-semibold">Avisos à família</div>
            {(ficha.avisos as any[]).map((a, i) => <div key={i}>{fmtDateTime(a.enviado_em)} · {a.titulo} · {a.ciente_em ? <Badge tone="green">ciente</Badge> : <Badge tone="amber">sem ciência</Badge>}</div>)}
            <p className="pt-1 text-[12px] text-muted"><Lock className="mr-1 inline size-3.5" />{ficha.aviso}</p>
          </div>
        )}
      </Card>
    </div>
  );
}
