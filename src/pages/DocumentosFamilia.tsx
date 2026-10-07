import { useState } from 'react';
import { Link } from 'react-router';
import { Bell, MessageCircle, PencilLine } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDateTime } from '@/lib/format';
import { DOC } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, PageHeader, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { AbrirArquivo, EnviarDocumento, Foto, TrocarFoto, useRecarregarArquivos } from '@/components/arquivos';
import { CamposPedido, StatusDoc, TIPOS_DOC } from '@/components/documentos';

const TIPO_ALT: Record<string, string> = { FOTO: 'Nova foto', ENDERECO: 'Mudança de endereço', DADOS: 'Correção de dados' };
const CAMPOS: [string, string][] = [['social_name', 'Nome social'], ['cpf', 'CPF'], ['nis', 'NIS'], ['sus_card', 'Cartão SUS'],
  ['birth_certificate', 'Certidão de nascimento (matrícula)'], ['birth_city', 'Cidade onde nasceu'], ['birth_state', 'UF onde nasceu']];

/** Família: foto, documentos (PDF) e correções de dados de cada criança — tudo entra pendente e a área responsável confere. */
export default function DocumentosFamilia() {
  const { me } = useSession();
  const res = useRpc<any>('familia_documentos', {}, { enabled: !!me?.guardian });
  const [editar, setEditar] = useState<any | null>(null);
  if (me?.scope !== 'GUARDIAN') return <Card><EmptyState title="Área da família" /></Card>;
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  return (
    <div>
      <PageHeader eyebrow="Portal da família" title="Documentos e dados das crianças"
        subtitle="Envie os documentos em PDF e a foto da criança (JPEG ou PNG). Tudo entra na ficha e a escola (ou a Central de Vagas) confere; se algo for recusado, você recebe o motivo e o que fazer."
        actions={<Link to="/iara" className="inline-flex h-10 items-center gap-1.5 rounded-2xl bg-purple-700 px-3 text-[14px] font-semibold text-white"><MessageCircle className="size-4" />Enviar pela IARA</Link>} />
      {(d.avisos as any[]).length > 0 && (
        <Card className="mb-4 divide-y divide-line overflow-hidden">
          {(d.avisos as any[]).slice(0, 4).map((n, i) => (
            <div key={i} className="flex items-start gap-3 px-4 py-3">
              <Bell className="mt-0.5 size-5 text-purple-700" />
              <div className="min-w-0 flex-1"><div className="font-semibold">{n.titulo}</div><div className="text-[13px] text-muted">{n.texto}</div></div>
              <span className="shrink-0 text-[11.5px] text-muted">{fmtDateTime(n.em)}</span>
            </div>
          ))}
        </Card>
      )}
      <div className="space-y-6">
        {(d.criancas as any[]).map((k) => {
          const porTipo = new Map((k.documentos as any[]).map((x) => [x.tipo, x]));
          return (
            <Section key={k.student_id} className="mt-0" title={
              <span className="flex items-center gap-3"><Foto arquivoId={k.foto_arquivo_id} name={k.nome} seed={k.student_id} size={48} />{k.nome}</span>}
              subtitle={k.foto_pendente ? 'Foto nova aguardando conferência' : k.area === 'CENTRAL' ? 'Quem confere: Central de Vagas da SEDUC' : 'Quem confere: secretaria da escola'}
              action={<div className="flex flex-wrap gap-2">
                <TrocarFoto finalidade="FOTO_ALUNO" alvo={k.student_id} rotulo={k.foto_arquivo_id ? 'Trocar foto' : 'Enviar foto'} />
                <Button size="sm" variant="secondary" icon={PencilLine} onClick={() => setEditar(k)}>Corrigir dados</Button>
              </div>}>
              <Card className="divide-y divide-line overflow-hidden">
                {TIPOS_DOC.filter((t) => porTipo.has(t) || ['CERTIDAO', 'CPF', 'COMPROVANTE_ENDERECO', 'CARTAO_SUS', 'VACINACAO'].includes(t)).map((t) => {
                  const doc = porTipo.get(t);
                  return (
                    <div key={t} className="flex flex-wrap items-center gap-3 px-4 py-3">
                      <div className="min-w-0 flex-1">
                        <div className="font-semibold">{DOC[t] ?? t}</div>
                        <div className="text-[12.5px] text-muted">{doc?.arquivo_id ? <AbrirArquivo id={doc.arquivo_id}>{doc.nome ?? 'Abrir PDF'}</AbrirArquivo> : doc ? 'registro sem arquivo' : 'ainda não enviado'}</div>
                        {doc?.status === 'REJEITADO' && (
                          <div className="mt-1 rounded-2xl bg-red-50 p-2 text-[12.5px] text-red-900 ring-1 ring-red-100"><b>Motivo:</b> {doc.motivo_recusa}<br /><b>Como proceder:</b> {doc.orientacao}</div>
                        )}
                      </div>
                      {doc ? <StatusDoc d={doc} /> : <Badge tone="gray">Não enviado</Badge>}
                      {(!doc || ['PENDENTE', 'REJEITADO'].includes(doc.status)) && (
                        <EnviarDocumento studentId={k.student_id} docType={t} rotulo={doc?.status === 'REJEITADO' ? 'Reenviar PDF' : 'Enviar PDF'} variant={doc?.status === 'REJEITADO' ? 'purple' : 'secondary'} />
                      )}
                    </div>
                  );
                })}
              </Card>
              {(k.alteracoes as any[]).length > 0 && (
                <Card className="mt-3 divide-y divide-line overflow-hidden">
                  {(k.alteracoes as any[]).map((a) => (
                    <div key={a.id} className="flex flex-wrap items-center gap-3 px-4 py-2.5">
                      <div className="min-w-0 flex-1 text-[13px]"><b>{TIPO_ALT[a.tipo]}</b> · {fmtDateTime(a.criado_em)}<br /><CamposPedido a={a} />
                        {a.situacao === 'RECUSADA' && <div className="text-red-800">Motivo: {a.motivo_recusa}. Como proceder: {a.orientacao}</div>}</div>
                      <Badge tone={a.situacao === 'PENDENTE' ? 'amber' : a.situacao === 'APROVADA' ? 'green' : 'red'}>{a.situacao === 'PENDENTE' ? 'Aguardando conferência' : a.situacao === 'APROVADA' ? 'Aprovado' : 'Recusado'}</Badge>
                    </div>
                  ))}
                </Card>
              )}
            </Section>
          );
        })}
      </div>
      <p className="mt-4 text-[12px] text-muted">Documento só em PDF, até 10 MB. A foto é reduzida no seu aparelho e sai sem a localização. Endereço e telefone você muda em Minha família (a escola confere o comprovante).</p>
      <CorrigirDados crianca={editar} onClose={() => setEditar(null)} />
    </div>
  );
}

function CorrigirDados({ crianca, onClose }: { crianca: any | null; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregarArquivos();
  const [campos, setCampos] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_alterar_aluno', { student_id: crianca.student_id, campos: Object.fromEntries(Object.entries(campos).filter(([, v]) => v.trim())) });
      toast({ title: 'Pedido enviado', description: r.mensagem, tone: 'success' });
      recarregar();
      setCampos({});
      onClose();
    } catch (e) {
      toast({ title: 'Pedido não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!crianca} onClose={onClose} title={`Corrigir dados de ${crianca?.primeiro_nome ?? ''}`} subtitle="Preencha só o que está errado. Os dados mudam na ficha depois da conferência."
      footer={<Button block size="lg" loading={busy} disabled={!Object.values(campos).some((v) => v.trim())} onClick={enviar}>Enviar para conferência</Button>}>
      <div className="space-y-3 pt-1">
        {CAMPOS.map(([k, l]) => (
          <Field key={k} label={l} hint={crianca?.dados?.[k] ? `Hoje: ${crianca.dados[k]}` : undefined}>
            <input value={campos[k] ?? ''} onChange={(e) => setCampos({ ...campos, [k]: e.target.value })} maxLength={120} className={inputCls} />
          </Field>
        ))}
      </div>
    </Sheet>
  );
}
