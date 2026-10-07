// Documentos e pedidos de alteração na ficha do aluno (unidade, Central de Vagas e SEDUC) e exclusão de cadastros.
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { CheckCircle2, Clock, FileWarning, Trash2, XCircle } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { DOC, DOC_STATUS } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { AbrirArquivo, DecisaoSheet, EnviarDocumento, Foto, useRecarregarArquivos } from '@/components/arquivos';

export const TIPOS_DOC = ['CERTIDAO', 'CPF', 'COMPROVANTE_ENDERECO', 'CARTAO_SUS', 'VACINACAO', 'CADUNICO', 'DECLARACAO_TRABALHO', 'LAUDO', 'TRANSFERENCIA', 'GUARDA', 'DECISAO_JUDICIAL'];
export const CAMPO_ALUNO: Record<string, string> = {
  social_name: 'Nome social', cpf: 'CPF', nis: 'NIS', sus_card: 'Cartão SUS', birth_certificate: 'Certidão (matrícula)', race_color: 'Cor/raça',
  nationality: 'Nacionalidade', birth_city: 'Cidade de nascimento', birth_state: 'UF de nascimento', endereco: 'Endereço', address_id: 'Endereço',
};
const TIPO_ALT: Record<string, string> = { FOTO: 'Nova foto', ENDERECO: 'Mudança de endereço', DADOS: 'Correção de dados' };
const ORIGEM: Record<string, string> = { PORTAL: 'portal', IARA: 'IARA', WHATSAPP: 'WhatsApp', UNIDADE: 'unidade', SEDUC: 'SEDUC' };

export function StatusDoc({ d }: { d: any }) {
  const st = DOC_STATUS[d.status] ?? { label: d.status, tone: 'gray' as const };
  return <Badge tone={st.tone}>{d.status === 'RECEBIDO' ? 'Aguardando conferência' : d.status === 'REJEITADO' ? 'Recusado' : st.label}</Badge>;
}

/** Diferença pedida (antes → depois), sem mostrar números completos de documento. */
export function CamposPedido({ a }: { a: any }) {
  if (a.tipo === 'FOTO') return <span className="inline-flex items-center gap-2">{a.arquivo_id ? <Foto arquivoId={a.arquivo_id} name={a.aluno ?? 'Aluno'} size={44} /> : null}<span className="text-muted">nova foto enviada pela família</span></span>;
  const campos = Object.keys(a.campos ?? {}).filter((k) => k !== 'address_id' && String(a.anteriores?.[k] ?? '') !== String(a.campos[k] ?? ''));
  return (
    <span className="text-[13px]">
      {campos.map((k) => (
        <span key={k} className="mr-2 inline-block">
          <b>{CAMPO_ALUNO[k] ?? k}:</b> <span className="text-muted line-through">{String(a.anteriores?.[k] ?? '—')}</span> → <span className="font-semibold text-green-800">{String(a.campos[k] ?? '—')}</span>
        </span>
      ))}
      {a.tipo === 'ENDERECO' && a.aplicada && <span className="text-[12px] text-muted">(já vale para a fila; conferir o comprovante)</span>}
    </span>
  );
}

export function DocumentosAluno({ studentId }: { studentId: string }) {
  const res = useRpc<any>('aluno_documentos', { student_id: studentId });
  const toast = useToast();
  const recarregar = useRecarregarArquivos();
  const [decidir, setDecidir] = useState<{ tipo: 'doc' | 'alt'; item: any } | null>(null);
  const [novoTipo, setNovoTipo] = useState('CERTIDAO');
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const docs = d.documentos as any[];
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
  return (
    <div className="space-y-4">
      {d.pode_enviar && (
        <Card className="flex flex-wrap items-end gap-2 p-3">
          <Field label="Anexar documento (PDF)">
            <select value={novoTipo} onChange={(e) => setNovoTipo(e.target.value)} className={`${inputCls} h-10`}>
              {TIPOS_DOC.map((t) => <option key={t} value={t}>{DOC[t] ?? t}</option>)}
            </select>
          </Field>
          <EnviarDocumento studentId={studentId} docType={novoTipo} rotulo="Escolher PDF" variant="primary" />
          <p className="basis-full text-[12px] text-muted">Documento só em PDF (até 10 MB). O que a unidade anexa entra conferido; o que a família envia aguarda a conferência.</p>
        </Card>
      )}
      <Card className="divide-y divide-line overflow-hidden">
        {docs.map((doc) => (
          <div key={doc.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
            {doc.status === 'VALIDADO' ? <CheckCircle2 className="size-5 text-green-700" /> : doc.status === 'REJEITADO' ? <XCircle className="size-5 text-red-600" /> : doc.status === 'RECEBIDO' ? <Clock className="size-5 text-blue-600" /> : <FileWarning className="size-5 text-amber-600" />}
            <div className="min-w-0 flex-1">
              <div className="font-semibold">{DOC[doc.tipo] ?? doc.tipo}</div>
              <div className="text-[12.5px] text-muted">
                {doc.arquivo_id ? <AbrirArquivo id={doc.arquivo_id}>{doc.nome ?? 'Abrir PDF'}</AbrirArquivo> : (doc.is_demo ? 'registro de demonstração, sem arquivo' : 'sem arquivo')}
                {doc.recebido_em ? ` · recebido ${fmtDate(doc.recebido_em)}${doc.origem ? ` pelo(a) ${ORIGEM[doc.origem] ?? doc.origem}` : ''}` : ''}
                {doc.enviado_pela_familia ? ' · enviado pela família' : ''}
                {doc.validado_por ? ` · decidido por ${doc.validado_por}` : ''}
              </div>
              {doc.status === 'REJEITADO' && doc.motivo_recusa && <div className="mt-1 text-[12.5px] text-red-800">Motivo: {doc.motivo_recusa}. Orientação: {doc.orientacao}</div>}
            </div>
            <StatusDoc d={doc} />
            {d.pode_validar && doc.status === 'RECEBIDO' && <Button size="sm" variant="purple" onClick={() => setDecidir({ tipo: 'doc', item: doc })}>Conferir</Button>}
            {d.pode_enviar && doc.status !== 'VALIDADO' && <EnviarDocumento studentId={studentId} docType={doc.tipo} rotulo="Anexar" />}
          </div>
        ))}
        {!docs.length && <EmptyState compact title="Nenhum documento" />}
      </Card>
      <Section title="Pedidos da família" subtitle="Foto, endereço e correções de dados: mudam na ficha depois da conferência." className="mt-2">
        <Card className="divide-y divide-line overflow-hidden">
          {(d.alteracoes as any[]).map((a) => (
            <div key={a.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
              <div className="min-w-0 flex-1">
                <div className="font-semibold">{TIPO_ALT[a.tipo]} <span className="text-[12px] font-normal text-muted">· {fmtDateTime(a.criado_em)} · {ORIGEM[a.origem] ?? a.origem}</span></div>
                <CamposPedido a={a} />
                {a.situacao === 'RECUSADA' && <div className="text-[12.5px] text-red-800">Recusado: {a.motivo_recusa}. Orientação: {a.orientacao}</div>}
              </div>
              <Badge tone={a.situacao === 'PENDENTE' ? 'amber' : a.situacao === 'APROVADA' ? 'green' : 'red'}>{a.situacao === 'PENDENTE' ? 'Aguardando conferência' : a.situacao === 'APROVADA' ? 'Aprovado' : 'Recusado'}</Badge>
              {d.pode_validar && a.situacao === 'PENDENTE' && <Button size="sm" variant="purple" onClick={() => setDecidir({ tipo: 'alt', item: a })}>Conferir</Button>}
            </div>
          ))}
          {!(d.alteracoes as any[]).length && <p className="p-4 text-sm text-muted">Nenhum pedido da família.</p>}
        </Card>
      </Section>
      <DecisaoSheet alvo={decidir ? { titulo: decidir.tipo === 'doc' ? `${DOC[decidir.item.tipo] ?? decidir.item.tipo}` : TIPO_ALT[decidir.item.tipo], subtitulo: 'Confira o arquivo ou os dados antes de decidir.' } : null}
        onClose={() => setDecidir(null)} onDecidir={decisao} />
    </div>
  );
}

/** Exclusão com motivo: sem histórico apaga; com histórico inativa ou desliga (o banco decide e explica). */
export function ExcluirCadastro({ fn, id, nome, voltarPara, rotulo = 'Excluir' }: { fn: string; id: string; nome: string; voltarPara: string; rotulo?: string }) {
  const [aberto, setAberto] = useState(false);
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const navigate = useNavigate();
  const recarregar = useRecarregarArquivos();
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>(fn, { id, motivo });
      toast({ title: r.excluido === false ? 'Cadastro mantido no histórico' : 'Cadastro excluído', description: r.mensagem, tone: 'success' });
      recarregar();
      setAberto(false);
      if (r.excluido !== false) navigate(voltarPara);
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <Button variant="secondary" icon={Trash2} className="text-red-700" onClick={() => setAberto(true)}>{rotulo}</Button>
      <Sheet open={aberto} onClose={() => setAberto(false)} title={`${rotulo}: ${nome}`}
        subtitle="Sem histórico, o cadastro é apagado. Com histórico (matrícula, fila, frequência, turmas, documentos), ele é inativado ou desligado e fica na trilha."
        footer={<Button block size="lg" variant="danger" loading={busy} disabled={motivo.trim().length < 5} onClick={enviar}>Confirmar</Button>}>
        <Field label="Motivo" hint="Fica registrado na auditoria.">
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} maxLength={300} className={`${inputCls} h-auto py-3`} />
        </Field>
      </Sheet>
    </>
  );
}
