import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { DOC } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, PageHeader, Segmented, SkeletonList, Tabs } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { useToast } from '@/components/overlays';
import { AbrirArquivo, DecisaoSheet, useRecarregarArquivos } from '@/components/arquivos';
import { CamposPedido } from '@/components/documentos';
import { UnitSelect } from '@/components/escola';

const TIPO_ALT: Record<string, string> = { FOTO: 'Nova foto', ENDERECO: 'Endereço', DADOS: 'Correção de dados' };

/** Fila da área responsável: documentos enviados pelas famílias e pedidos de alteração (foto, endereço, dados) a conferir. */
export default function Validacoes() {
  const { me } = useSession();
  const [sp, setSp] = useSearchParams();
  const aba = sp.get('aba') ?? 'documentos';
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const [area, setArea] = useState('');
  const res = useRpc<any>('validacoes_pendentes', { unit_id: unit, area: area || null });
  const toast = useToast();
  const recarregar = useRecarregarArquivos();
  const [decidir, setDecidir] = useState<{ tipo: 'doc' | 'alt'; item: any } | null>(null);
  const decisao = async (aprovar: boolean, motivo: string, orientacao: string) => {
    try {
      await rpc(decidir!.tipo === 'doc' ? 'documento_decidir' : 'alteracao_decidir', { id: decidir!.item.id, aprovar, motivo, orientacao });
      toast({ title: aprovar ? 'Validado' : 'Recusado', description: 'A família é avisada no portal e pela IARA.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
      throw e;
    }
  };
  const c = res.data?.contagem;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · Central de Vagas e unidades' : me?.unit?.name} title="Validações"
        subtitle="O que as famílias enviaram pelo portal, pela IARA ou pelo WhatsApp: documentos em PDF, fotos das crianças e correções de dados. Valide ou recuse dizendo o motivo e como proceder."
        actions={rede ? <div className="flex flex-wrap gap-2">
          <Segmented value={area} onChange={setArea} items={[{ value: '', label: 'Todas' }, { value: 'CENTRAL', label: 'Sem matrícula (Central)' }, { value: 'UNIDADE', label: 'Unidades' }]} />
          <UnitSelect value={unit} onChange={setUnit} />
        </div> : undefined} />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })}
        items={[{ value: 'documentos', label: 'Documentos', count: c?.documentos ?? null }, { value: 'alteracoes', label: 'Fotos e dados', count: c?.alteracoes ?? null }]} />
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : aba === 'documentos' ? (
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,1.3fr) minmax(140px,1fr) minmax(170px,1fr) 150px 130px 110px" largura={940} rotulo="Documentos a conferir">
              <TCabecalho><TCelula>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Documento</TCelula><TCelula>Recebido</TCelula><TCelula>Arquivo</TCelula><TCelula className="text-right">Decisão</TCelula></TCabecalho>
              {(res.data.documentos as any[]).map((d) => (
                <TLinha key={d.id}>
                  <TCelula fixa titulo={d.aluno}><Link to={`/alunos/${d.student_id}?aba=documentos`} className="font-semibold hover:text-purple-700">{d.aluno}</Link></TCelula>
                  <TCelula>{d.unidade ?? <Badge tone="purple">Central de Vagas</Badge>}</TCelula>
                  <TCelula>{DOC[d.tipo] ?? d.tipo}</TCelula>
                  <TCelula>{fmtDateTime(d.recebido_em)}</TCelula>
                  <TCelula livre>{d.arquivo_id ? <AbrirArquivo id={d.arquivo_id}>Abrir PDF</AbrirArquivo> : <span className="text-muted">sem arquivo</span>}</TCelula>
                  <TCelula livre className="flex justify-end"><Button size="sm" variant="purple" onClick={() => setDecidir({ tipo: 'doc', item: d })}>Conferir</Button></TCelula>
                </TLinha>
              ))}
            </Tabela>
            {!(res.data.documentos as any[]).length && <EmptyState compact title="Nenhum documento aguardando" />}
          </Card>
        ) : (
          <Card className="divide-y divide-line overflow-hidden">
            {(res.data.alteracoes as any[]).map((a) => (
              <div key={a.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <div className="font-semibold"><Link to={`/alunos/${a.student_id}?aba=documentos`} className="hover:text-purple-700">{a.aluno}</Link>
                    <span className="text-[12px] font-normal text-muted"> · {TIPO_ALT[a.tipo]} · {a.unidade ?? 'Central de Vagas'} · {fmtDateTime(a.criado_em)}</span></div>
                  <CamposPedido a={a} />
                </div>
                <Button size="sm" variant="purple" onClick={() => setDecidir({ tipo: 'alt', item: a })}>Conferir</Button>
              </div>
            ))}
            {!(res.data.alteracoes as any[]).length && <EmptyState compact title="Nenhum pedido aguardando" />}
          </Card>
        )}
      </div>
      <p className="mt-3 text-[12px] text-muted">{fmtInt((c?.documentos ?? 0) + (c?.alteracoes ?? 0))} item(ns) no seu escopo. Cada decisão fica na auditoria; a família recebe o resultado com o motivo e a orientação.</p>
      <DecisaoSheet alvo={decidir ? { titulo: decidir.tipo === 'doc' ? `${DOC[decidir.item.tipo] ?? decidir.item.tipo} · ${decidir.item.aluno}` : `${TIPO_ALT[decidir.item.tipo]} · ${decidir.item.aluno}`, subtitulo: 'Abra o arquivo ou confira os dados antes de decidir.' } : null}
        onClose={() => setDecidir(null)} onDecidir={decisao} />
    </div>
  );
}
