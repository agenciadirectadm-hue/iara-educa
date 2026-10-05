import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Search, UserMinus, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { PARENTESCO, SITUACAO_LEGAL } from '@/lib/cadastro';
import { Avatar, Badge, Button, EmptyState, SkeletonList, inputCls } from './ui';
import { Sheet, useToast } from './overlays';
import { Alternar, Campo, Escolha, Selecao } from './cadastro';

export type Vinculo = {
  parentesco: string; principal: boolean; pode_buscar: boolean; recebe_avisos: boolean; situacao_legal: string;
};
export const vinculoPadrao = (): Vinculo => ({ parentesco: '', principal: false, pode_buscar: true, recebe_avisos: true, situacao_legal: 'DECLARADO' });

/** Recarrega tudo que mostra vínculos depois de uma alteração. */
export function useRecarregarCadastros() {
  const qc = useQueryClient();
  return () => {
    for (const k of ['aluno_cadastro', 'responsavel_cadastro', 'student_detail', 'guardian_detail', 'alunos_lista', 'responsaveis_lista']) {
      qc.invalidateQueries({ queryKey: [k] });
    }
  };
}

export function VinculoSheet({ open, onClose, alunoId, responsavelId, titulo, inicial }: {
  open: boolean; onClose: () => void; alunoId: string; responsavelId: string; titulo: string; inicial?: Partial<Vinculo>;
}) {
  const toast = useToast();
  const recarregar = useRecarregarCadastros();
  const [v, setV] = useState<Vinculo>({ ...vinculoPadrao(), ...inicial });
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (open) setV({ ...vinculoPadrao(), ...inicial });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('vinculo_salvar', { aluno_id: alunoId, responsavel_id: responsavelId, ...v });
      toast({ title: 'Vínculo salvo', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Vínculo não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={titulo} subtitle="Parentesco, quem é o principal, quem pode buscar a criança e a situação legal do vínculo."
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={!v.parentesco} onClick={salvar}>Salvar vínculo</Button>}>
      <div className="space-y-3">
        <Campo label="Parentesco" obrigatorio>
          <Selecao value={v.parentesco} onChange={(x) => setV({ ...v, parentesco: x })} opcoes={Object.entries(PARENTESCO)} />
        </Campo>
        <Alternar checked={v.principal} onChange={(x) => setV({ ...v, principal: x })} label="Responsável principal" dica="Recebe primeiro os avisos e é o contato de referência da criança." />
        <Alternar checked={v.pode_buscar} onChange={(x) => setV({ ...v, pode_buscar: x })} label="Pode buscar a criança na unidade" />
        <Alternar checked={v.recebe_avisos} onChange={(x) => setV({ ...v, recebe_avisos: x })} label="Recebe avisos (WhatsApp, SMS ou e-mail)" />
        <Campo label="Situação legal do vínculo" dica={SITUACAO_LEGAL[v.situacao_legal]?.hint}>
          <Escolha nome="Situação legal" value={v.situacao_legal} onChange={(x) => setV({ ...v, situacao_legal: x })}
            opcoes={Object.entries(SITUACAO_LEGAL).map(([k, s]) => [k, s.label] as [string, string])} />
        </Campo>
      </div>
    </Sheet>
  );
}

export function EncerrarVinculoSheet({ open, onClose, alunoId, responsavelId, nome }: {
  open: boolean; onClose: () => void; alunoId: string; responsavelId: string; nome: string;
}) {
  const toast = useToast();
  const recarregar = useRecarregarCadastros();
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (open) setMotivo('');
  }, [open]);
  const encerrar = async () => {
    setBusy(true);
    try {
      await rpc('vinculo_encerrar', { aluno_id: alunoId, responsavel_id: responsavelId, motivo });
      toast({ title: 'Vínculo encerrado', description: 'Fica no histórico da criança.', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não foi possível encerrar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Encerrar vínculo" subtitle={`${nome} deixa de responder pela criança a partir de hoje. O vínculo não é apagado: fica no histórico, com o motivo.`}
      footer={<Button block size="lg" variant="danger" icon={UserMinus} loading={busy} disabled={motivo.trim().length < 5} onClick={encerrar}>Encerrar vínculo</Button>}>
      <Campo label="Motivo" obrigatorio dica="Ex.: mudança de guarda, falecimento, erro de cadastro. Fica na auditoria.">
        <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} maxLength={300} className={clsx(inputCls, 'h-auto py-2.5')} />
      </Campo>
    </Sheet>
  );
}

/** Busca uma pessoa já cadastrada (responsável ou criança) para vincular. */
export function BuscarPessoaSheet({ open, onClose, tipo, onEscolher, ignorar = [] }: {
  open: boolean; onClose: () => void; tipo: 'responsavel' | 'aluno'; onEscolher: (p: { id: string; nome: string }) => void; ignorar?: string[];
}) {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  useEffect(() => {
    if (open) setQ('');
  }, [open]);
  const res = useRpc<any>(tipo === 'responsavel' ? 'responsaveis_lista' : 'alunos_lista', { q: dq, limite: 12 }, { enabled: open && dq.trim().length >= 3 });
  const itens = ((res.data?.itens ?? []) as any[]).filter((i) => !ignorar.includes(i.id));
  return (
    <Sheet open={open} onClose={onClose} title={tipo === 'responsavel' ? 'Vincular responsável já cadastrado' : 'Vincular criança já cadastrada'}
      subtitle={tipo === 'responsavel' ? 'Busque pelo nome ou CPF. Se não encontrar, cadastre um responsável novo.' : 'Busque pelo nome, código da rede ou CPF.'}>
      <div className="relative mb-3">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="Digite ao menos 3 letras" className={clsx(inputCls, 'pl-11')} aria-label="Buscar" />
        {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
      </div>
      {dq.trim().length < 3 ? <p className="text-[13px] text-muted">Digite o nome (ou o CPF) para buscar.</p>
        : res.isLoading ? <SkeletonList rows={4} />
          : !itens.length ? <EmptyState compact title="Ninguém encontrado" body="Confira a grafia ou cadastre uma pessoa nova." />
            : (
              <div className="divide-y divide-line overflow-hidden rounded-2xl ring-1 ring-line">
                {itens.map((i) => (
                  <button key={i.id} onClick={() => onEscolher({ id: i.id, nome: i.nome })} className="flex w-full items-center gap-3 px-3 py-2.5 text-left hover:bg-purple-50">
                    <Avatar name={i.nome} seed={i.avatar_seed ?? i.nome} size={38} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-semibold">{i.nome}</span>
                      <span className="block truncate text-[12px] text-muted">
                        {tipo === 'responsavel' ? `CPF ${i.cpf ?? '—'} · ${i.bairro ?? 'sem endereço'} · ${i.criancas?.length ?? 0} criança(s)` : `${i.idade} · ${i.unidade?.nome ?? 'sem matrícula'} · ${i.bairro ?? ''}`}
                      </span>
                    </span>
                  </button>
                ))}
              </div>
            )}
    </Sheet>
  );
}

/** Linha de um vínculo (na ficha da criança mostra o responsável; na do responsável, a criança). */
export function LinhaVinculo({ to, nome, seed, detalhe, v, ate, desde, acoes }: {
  to: string; nome: string; seed: string | number; detalhe?: string; v: Vinculo; ate?: string | null; desde?: string | null; acoes?: React.ReactNode;
}) {
  return (
    <div className={clsx('flex flex-wrap items-center gap-3 px-3 py-3 sm:flex-nowrap', ate && 'opacity-60')}>
      <Avatar name={nome} seed={seed} size={42} />
      <div className="min-w-0 flex-1">
        <Link to={to} className="block truncate font-semibold hover:text-purple-700">{nome}</Link>
        <div className="mt-0.5 flex flex-wrap items-center gap-1 text-[12px]">
          <Badge tone="gray">{PARENTESCO[v.parentesco] ?? v.parentesco}</Badge>
          {v.principal && !ate && <Badge tone="purple">Principal</Badge>}
          {v.pode_buscar && !ate && <Badge tone="blue">Pode buscar</Badge>}
          {!v.recebe_avisos && !ate && <Badge tone="gray">Sem avisos</Badge>}
          <Badge tone={SITUACAO_LEGAL[v.situacao_legal]?.tone ?? 'gray'}>{SITUACAO_LEGAL[v.situacao_legal]?.label ?? v.situacao_legal}</Badge>
          {ate ? <span className="text-muted">encerrado em {fmtDate(ate)}</span> : desde ? <span className="text-subtle">desde {fmtDate(desde)}</span> : null}
        </div>
        {detalhe && <div className="mt-0.5 truncate text-[12px] text-muted">{detalhe}</div>}
      </div>
      {acoes && !ate && <div className="flex shrink-0 gap-1.5">{acoes}</div>}
    </div>
  );
}
