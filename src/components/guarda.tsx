// Guarda e restrições judiciais: alerta na ficha do aluno, detalhe para direção e secretaria e o registro/encerramento.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Gavel, ShieldX } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { Badge, Button, Field, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';

export const TIPO_GUARDA: Record<string, string> = {
  GUARDA_UNILATERAL: 'Guarda unilateral', GUARDA_COMPARTILHADA: 'Guarda compartilhada', TUTELA: 'Tutela', ACOLHIMENTO: 'Acolhimento institucional/familiar',
  MEDIDA_PROTETIVA: 'Medida protetiva', PROIBICAO_RETIRADA: 'Proibição de retirada', PROIBICAO_CONTATO: 'Proibição de contato',
  VISITA_SUPERVISIONADA: 'Visita supervisionada', AUTORIZACAO_RETIRADA: 'Autorização de retirada', OUTRA: 'Outra determinação',
};
export const EFEITO_RETIRADA: Record<string, { label: string; tone: 'red' | 'green' | 'gray' }> = {
  NAO_PODE: { label: 'Não pode retirar', tone: 'red' }, PODE: { label: 'Pode retirar', tone: 'green' }, SEM_EFEITO: { label: 'Sem efeito na retirada', tone: 'gray' },
};

export function useRecarregarGuarda() {
  const qc = useQueryClient();
  return () => ['guarda_lista', 'guarda_aluno', 'student_detail'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Faixa na ficha do aluno: quem tem acesso ao detalhe vê as determinações; os demais, só o aviso para consultar a direção. */
export function GuardaAlerta({ studentId, onAbrir }: { studentId: string; onAbrir?: () => void }) {
  const res = useRpc<any>('guarda_aluno', { student_id: studentId }, { retry: false });
  const d = res.data;
  if (!d?.tem_restricao) return null;
  const vigentes = ((d.itens ?? []) as any[]).filter((r) => r.vigente);
  return (
    <div role="alert" className="mb-4 flex items-start gap-3 rounded-3xl bg-red-50 p-3 text-[13.5px] text-red-950 ring-1 ring-red-200">
      <Gavel className="mt-0.5 size-5 shrink-0 text-red-700" aria-hidden />
      <div className="min-w-0 flex-1">
        <b>{d.restricao_retirada ? 'Atenção na retirada: há pessoa que não pode buscar a criança.' : 'Há determinação judicial ou de guarda para este aluno.'}</b>
        {d.detalhe ? (
          <ul className="mt-1 space-y-0.5">
            {vigentes.map((r) => (
              <li key={r.id}>{TIPO_GUARDA[r.tipo]}{r.pessoa_nome ? ` — ${r.pessoa_nome}` : ''}: {EFEITO_RETIRADA[r.efeito_retirada]?.label.toLowerCase()}
                {r.bloquear_portal ? '; sem acesso ao portal' : ''}{r.vigencia_fim ? ` (até ${fmtDate(r.vigencia_fim)})` : ''}</li>
            ))}
          </ul>
        ) : <p className="mt-1">{d.aviso}</p>}
      </div>
      {d.detalhe && onAbrir && <Button size="sm" variant="secondary" onClick={onAbrir}>Ver e registrar</Button>}
    </div>
  );
}

/** Lista do aluno e registro de nova determinação (direção e secretaria). */
export function GuardaAlunoSheet({ studentId, aluno, open, onClose }: { studentId: string | null; aluno?: string; open: boolean; onClose: () => void }) {
  const res = useRpc<any>('guarda_aluno', { student_id: studentId }, { enabled: open && !!studentId, retry: false });
  const recarregar = useRecarregarGuarda();
  const toast = useToast();
  const [tipo, setTipo] = useState('PROIBICAO_RETIRADA');
  const [guardian, setGuardian] = useState('');
  const [pessoa, setPessoa] = useState('');
  const [efeito, setEfeito] = useState('');
  const [portal, setPortal] = useState(false);
  const [descricao, setDescricao] = useState('');
  const [documento, setDocumento] = useState('');
  const [orgao, setOrgao] = useState('');
  const [fim, setFim] = useState('');
  const [encerrar, setEncerrar] = useState<string | null>(null);
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const d = res.data;
  const enviar = async (args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc('guarda_registrar', { student_id: studentId, ...args });
      toast({ title: msg, tone: 'success' });
      setDescricao(''); setDocumento(''); setPessoa(''); setGuardian(''); setEncerrar(null); setMotivo('');
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} size="lg" title={`Guarda e restrições${aluno ? ` · ${aluno}` : ''}`}
      subtitle="Detalhe visível só para a direção e a secretaria (o que é público e o que é privado aguarda decisão da SEDUC).">
      {!d ? <p className="text-[13px] text-muted">Carregando…</p> : (
        <div className="space-y-4 pt-1">
          {((d.itens ?? []) as any[]).map((r) => (
            <div key={r.id} className="rounded-2xl bg-white p-3 text-[13.5px] ring-1 ring-line">
              <div className="flex flex-wrap items-center gap-1.5">
                <b>{TIPO_GUARDA[r.tipo]}</b>{r.pessoa_nome && <span>· {r.pessoa_nome}</span>}
                <Badge tone={EFEITO_RETIRADA[r.efeito_retirada]?.tone}>{EFEITO_RETIRADA[r.efeito_retirada]?.label}</Badge>
                {r.bloquear_portal && <Badge tone="red" icon={ShieldX}>sem acesso ao portal</Badge>}
                <Badge tone={r.vigente ? 'purple' : 'gray'}>{r.situacao === 'ENCERRADA' ? 'encerrada' : r.vigente ? 'vigente' : 'fora da vigência'}</Badge>
              </div>
              <p className="mt-1">{r.descricao}</p>
              <p className="mt-1 text-[12px] text-muted">{r.documento}{r.orgao ? ` · ${r.orgao}` : ''} · desde {fmtDate(r.vigencia_inicio)}{r.vigencia_fim ? ` até ${fmtDate(r.vigencia_fim)}` : ''} · {r.registrado_por_label}</p>
              {r.situacao === 'ENCERRADA' && <p className="mt-1 text-[12px] text-muted">Encerrada em {fmtDate(r.encerrado_em)}: {r.encerramento_motivo}</p>}
              {d.pode_registrar && r.situacao === 'ATIVA' && (encerrar === r.id ? (
                <div className="mt-2 space-y-2">
                  <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo (ex.: decisão revogada, documento)" className={inputCls} />
                  <Button size="sm" loading={busy} disabled={motivo.trim().length < 5} onClick={() => enviar({ encerrar: true, id: r.id, motivo }, 'Registro encerrado')}>Confirmar encerramento</Button>
                </div>
              ) : <Button size="sm" variant="secondary" className="mt-2" onClick={() => setEncerrar(r.id)}>Encerrar</Button>)}
            </div>
          ))}
          {d.pode_registrar && (
            <div className="space-y-3 rounded-3xl bg-slate-50 p-3 ring-1 ring-line">
              <h3 className="font-semibold">Nova determinação</h3>
              <Field label="Tipo">
                <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={inputCls}>{Object.entries(TIPO_GUARDA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
              </Field>
              <Field label="A quem se aplica" hint="Escolha um responsável vinculado ou escreva o nome de outra pessoa.">
                <select value={guardian} onChange={(e) => setGuardian(e.target.value)} className={inputCls}>
                  <option value="">Outra pessoa (escrever o nome)</option>
                  {((d.responsaveis ?? []) as any[]).map((g) => <option key={g.id} value={g.id}>{g.nome}{g.parentesco ? ` (${g.parentesco.toLowerCase()})` : ''}</option>)}
                </select>
              </Field>
              {!guardian && <input value={pessoa} onChange={(e) => setPessoa(e.target.value)} placeholder="Nome da pessoa" className={inputCls} />}
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="Efeito na retirada">
                  <select value={efeito} onChange={(e) => setEfeito(e.target.value)} className={inputCls}>
                    <option value="">Conforme o tipo</option>{Object.entries(EFEITO_RETIRADA).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                  </select>
                </Field>
                <Field label="Vigente até (opcional)"><input type="date" value={fim} onChange={(e) => setFim(e.target.value)} className={inputCls} /></Field>
              </div>
              {guardian && <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={portal} onChange={(e) => setPortal(e.target.checked)} className="size-5 accent-purple-700" />
                Bloquear o acesso desta pessoa às informações da criança no portal e na IARA</label>}
              <Field label="O que a decisão determina"><textarea value={descricao} onChange={(e) => setDescricao(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="Documento de referência"><input value={documento} onChange={(e) => setDocumento(e.target.value)} placeholder="Processo nº, termo, ofício" className={inputCls} /></Field>
                <Field label="Órgão"><input value={orgao} onChange={(e) => setOrgao(e.target.value)} placeholder="Vara, Conselho Tutelar…" className={inputCls} /></Field>
              </div>
              <Button block icon={Gavel} loading={busy} disabled={descricao.trim().length < 10 || documento.trim().length < 3}
                onClick={() => enviar({ tipo, guardian_id: guardian || null, pessoa_nome: pessoa || null, efeito_retirada: efeito || null, bloquear_portal: portal,
                  descricao, documento, orgao, vigencia_fim: fim || null }, 'Determinação registrada')}>Registrar</Button>
            </div>
          )}
        </div>
      )}
    </Sheet>
  );
}
