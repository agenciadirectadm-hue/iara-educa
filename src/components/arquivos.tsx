// Foto (com envio), envio de documento em PDF, abertura protegida e decisão (validar ou recusar com motivo e orientação).
import { useRef, useState, type ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Camera, FileText, FileUp, Loader2 } from 'lucide-react';
import { DOC_MAX_BYTES, abrirArquivo, enviarArquivo, prepararFoto, useArquivoUrl, type Finalidade } from '@/lib/arquivos';
import { Avatar, Button, Field, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';

const RECARREGAR = ['aluno_documentos', 'familia_documentos', 'validacoes_pendentes', 'pessoal_ficha', 'student_detail', 'familia_frequencia'];
export function useRecarregarArquivos() {
  const qc = useQueryClient();
  return () => RECARREGAR.forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Foto da pessoa (ou as iniciais enquanto não houver foto). */
export function Foto({ arquivoId, name, seed, size = 40, className }: { arquivoId?: string | null; name: string; seed?: string | number; size?: number; className?: string }) {
  const url = useArquivoUrl(arquivoId);
  if (arquivoId && url.data) {
    return <img src={url.data} alt={`Foto de ${name}`} width={size} height={size} className={clsx('shrink-0 rounded-full object-cover ring-2 ring-white', className)} style={{ width: size, height: size }} />;
  }
  return <Avatar name={name} seed={seed} size={size} className={className} />;
}

/** Botão que escolhe a foto, prepara (reduz e tira metadados) e envia. */
export function TrocarFoto({ finalidade, alvo, rotulo = 'Trocar foto', variant = 'secondary', onDone }: {
  finalidade: Extract<Finalidade, 'FOTO_ALUNO' | 'FOTO_SERVIDOR'>; alvo: string; rotulo?: string; variant?: 'secondary' | 'soft' | 'ghost'; onDone?: (r: any) => void;
}) {
  const ref = useRef<HTMLInputElement>(null);
  const toast = useToast();
  const recarregar = useRecarregarArquivos();
  const [busy, setBusy] = useState(false);
  const escolher = async (f: File | undefined) => {
    if (!f) return;
    setBusy(true);
    try {
      const foto = await prepararFoto(f);
      const r = await enviarArquivo({ finalidade, ...(finalidade === 'FOTO_ALUNO' ? { student_id: alvo } : { staff_id: alvo }), nome: f.name }, foto);
      toast({ title: r.aplicada === false ? 'Foto enviada para conferência' : 'Foto atualizada', description: r.mensagem, tone: 'success' });
      recarregar();
      onDone?.(r);
    } catch (e) {
      toast({ title: 'Foto não enviada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
      if (ref.current) ref.current.value = '';
    }
  };
  return (
    <>
      <input ref={ref} type="file" accept="image/jpeg,image/png" className="hidden" onChange={(e) => escolher(e.target.files?.[0])} />
      <Button size="sm" variant={variant} icon={busy ? Loader2 : Camera} disabled={busy} onClick={() => ref.current?.click()}>{rotulo}</Button>
    </>
  );
}

/** Envio de documento: só PDF, até 10 MB; entra na ficha (o da família fica aguardando a conferência). */
export function EnviarDocumento({ studentId, docType, rotulo = 'Enviar PDF', variant = 'secondary', onDone }: {
  studentId: string; docType: string; rotulo?: string; variant?: 'secondary' | 'soft' | 'purple' | 'primary'; onDone?: (r: any) => void;
}) {
  const ref = useRef<HTMLInputElement>(null);
  const toast = useToast();
  const recarregar = useRecarregarArquivos();
  const [busy, setBusy] = useState(false);
  const escolher = async (f: File | undefined) => {
    if (!f) return;
    if (f.type !== 'application/pdf' && !f.name.toLowerCase().endsWith('.pdf')) {
      toast({ title: 'Documento só em PDF', description: 'Foto é aceita apenas como foto da criança. Se o documento está em papel, use um aplicativo de digitalização para gerar o PDF.', tone: 'error' });
      return;
    }
    if (f.size > DOC_MAX_BYTES) {
      toast({ title: 'Arquivo maior que 10 MB', tone: 'error' });
      return;
    }
    setBusy(true);
    try {
      const r = await enviarArquivo({ finalidade: 'DOCUMENTO', student_id: studentId, doc_type: docType, nome: f.name }, f);
      toast({ title: r.status === 'RECEBIDO' ? 'Documento enviado' : 'Documento anexado', description: r.mensagem, tone: 'success' });
      recarregar();
      onDone?.(r);
    } catch (e) {
      toast({ title: 'Documento não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
      if (ref.current) ref.current.value = '';
    }
  };
  return (
    <>
      <input ref={ref} type="file" accept="application/pdf" className="hidden" onChange={(e) => escolher(e.target.files?.[0])} />
      <Button size="sm" variant={variant} icon={busy ? Loader2 : FileUp} disabled={busy} onClick={() => ref.current?.click()}>{rotulo}</Button>
    </>
  );
}

export function AbrirArquivo({ id, children }: { id: string; children?: ReactNode }) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  return (
    <button type="button" disabled={busy} className="inline-flex items-center gap-1 text-[13px] font-semibold text-blue-700 hover:underline disabled:opacity-60"
      onClick={async () => {
        setBusy(true);
        try { await abrirArquivo(id); } catch (e) { toast({ title: 'Não foi possível abrir', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
      }}>
      {busy ? <Loader2 className="size-4 animate-spin" /> : <FileText className="size-4" />}{children ?? 'Abrir'}
    </button>
  );
}

const ORIENTACOES = [
  'Envie um PDF legível, com o documento inteiro e sem cortes.',
  'Envie o documento em nome da criança ou do responsável cadastrado.',
  'Leve o original à secretaria da unidade para conferência.',
  'Envie a versão atualizada (o documento enviado está vencido).',
];

/** Decisão: validar, ou recusar dizendo o motivo e como a família deve proceder (a família é avisada no portal e pela IARA). */
export function DecisaoSheet({ alvo, onClose, onDecidir }: {
  alvo: { titulo: string; subtitulo?: string } | null; onClose: () => void; onDecidir: (aprovar: boolean, motivo: string, orientacao: string) => Promise<void>;
}) {
  const [motivo, setMotivo] = useState('');
  const [orient, setOrient] = useState('');
  const [busy, setBusy] = useState(false);
  const decidir = async (aprovar: boolean) => {
    setBusy(true);
    try {
      await onDecidir(aprovar, motivo, orient);
      setMotivo(''); setOrient('');
      onClose();
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={alvo?.titulo ?? ''} subtitle={alvo?.subtitulo}
      footer={<div className="flex gap-2">
        <Button variant="danger" className="flex-1" loading={busy} disabled={motivo.trim().length < 5 || orient.trim().length < 10} onClick={() => decidir(false)}>Recusar</Button>
        <Button variant="success" className="flex-1" loading={busy} onClick={() => decidir(true)}>Validar</Button>
      </div>}>
      <div className="space-y-4 pt-1">
        <p className="text-[13.5px] text-muted">Para validar, basta tocar em Validar. Para recusar, diga o motivo e como a família deve proceder: ela recebe o aviso no portal e pela IARA.</p>
        <Field label="Motivo da recusa"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={200} placeholder="Ex.: documento ilegível" className={inputCls} /></Field>
        <Field label="Como proceder">
          <textarea value={orient} onChange={(e) => setOrient(e.target.value)} rows={3} maxLength={500} className={`${inputCls} h-auto py-3`} />
        </Field>
        <div className="flex flex-wrap gap-1.5">
          {ORIENTACOES.map((o) => <button key={o} type="button" onClick={() => setOrient(o)} className="rounded-full bg-slate-100 px-3 py-1.5 text-left text-[12px] font-semibold text-ink-2 hover:bg-purple-50">{o}</button>)}
        </div>
      </div>
    </Sheet>
  );
}
