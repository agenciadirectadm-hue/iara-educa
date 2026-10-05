import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Search, UserMinus, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { PARENTESCO, SITUACAO_LEGAL } from '@/lib/cadastro';
import { Avatar, Badge, Button, Card, EmptyState, SkeletonList, inputCls } from './ui';
import { TCabecalho, TCelula, TLinha, Tabela } from './tabela';
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
    <Sheet open={open} onClose={onClose} size="lg" title={tipo === 'responsavel' ? 'Vincular responsável já cadastrado' : 'Vincular criança já cadastrada'}
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
              <Tabela rotulo="Resultados da busca" largura={560} className="rounded-2xl ring-1 ring-line"
                colunas={tipo === 'responsavel' ? 'minmax(170px,1.6fr) 118px minmax(110px,1fr) 64px' : 'minmax(170px,1.6fr) 74px minmax(120px,1.2fr) minmax(100px,1fr)'}>
                <TCabecalho>
                  {tipo === 'responsavel' ? <><span>Responsável</span><span>CPF</span><span>Bairro</span><span className="text-right">Crianças</span></>
                    : <><span>Criança</span><span>Idade</span><span>Unidade</span><span>Bairro</span></>}
                </TCabecalho>
                {itens.map((i) => (
                  <TLinha key={i.id} onClick={() => onEscolher({ id: i.id, nome: i.nome })} rotulo={`Escolher ${i.nome}`}>
                    <TCelula fixa titulo={i.nome}>
                      <Avatar name={i.nome} seed={i.avatar_seed ?? i.nome} size={24} className="mr-2 inline-flex align-middle" />
                      <span className="font-semibold">{i.nome}</span>
                    </TCelula>
                    {tipo === 'responsavel' ? (
                      <>
                        <TCelula className="tabular text-muted">{i.cpf ?? '—'}</TCelula>
                        <TCelula className="text-muted">{i.bairro ?? '—'}</TCelula>
                        <TCelula className="text-right tabular text-muted">{i.criancas?.length ?? 0}</TCelula>
                      </>
                    ) : (
                      <>
                        <TCelula className="text-muted">{i.idade}</TCelula>
                        <TCelula className="text-muted">{i.unidade?.nome ?? 'sem matrícula'}</TCelula>
                        <TCelula className="text-muted">{i.bairro ?? '—'}</TCelula>
                      </>
                    )}
                  </TLinha>
                ))}
              </Tabela>
            )}
    </Sheet>
  );
}

/** Tabela de vínculos (um por linha): na ficha da criança lista os responsáveis; na do responsável, as crianças. */
export function TabelaVinculos({ quem, vazio, children }: { quem: 'Responsável' | 'Criança'; vazio?: string | false; children: React.ReactNode }) {
  return (
    <Card className="overflow-hidden">
      <Tabela rotulo={quem === 'Responsável' ? 'Responsáveis da criança' : 'Crianças vinculadas'} largura={940}
        colunas="minmax(190px,1.5fr) 132px minmax(170px,1.3fr) 112px minmax(170px,1.4fr) 112px 92px">
        <TCabecalho>
          <span>{quem}</span><span>Parentesco</span><span>Papéis</span><span>Situação legal</span>
          <span>{quem === 'Responsável' ? 'CPF · telefone' : 'Idade · unidade'}</span><span>Vínculo</span><span />
        </TCabecalho>
        {children}
        {vazio && <p className="px-3 py-3 text-[13px] text-muted">{vazio}</p>}
      </Tabela>
    </Card>
  );
}

/** Um vínculo por linha (dentro de TabelaVinculos). */
export function LinhaVinculo({ to, nome, seed, detalhe, v, ate, desde, acoes }: {
  to: string; nome: string; seed: string | number; detalhe?: string; v: Vinculo; ate?: string | null; desde?: string | null; acoes?: React.ReactNode;
}) {
  const papeis = [v.principal && 'principal', v.pode_buscar && 'pode buscar', v.recebe_avisos ? 'recebe avisos' : 'sem avisos'].filter(Boolean).join(' · ');
  return (
    <TLinha className={clsx(ate && 'opacity-60')}>
      <TCelula fixa titulo={nome}>
        <Avatar name={nome} seed={seed} size={24} className="mr-2 inline-flex align-middle" />
        <Link to={to} className="font-semibold hover:text-purple-700">{nome}</Link>
      </TCelula>
      <TCelula>{PARENTESCO[v.parentesco] ?? v.parentesco}</TCelula>
      <TCelula titulo={ate ? 'vínculo encerrado' : papeis} className={clsx('text-[12.5px]', v.principal && !ate ? 'font-semibold text-purple-800' : 'text-muted')}>
        {ate ? 'vínculo encerrado' : papeis}
      </TCelula>
      <TCelula livre><Badge tone={SITUACAO_LEGAL[v.situacao_legal]?.tone ?? 'gray'}>{SITUACAO_LEGAL[v.situacao_legal]?.label ?? v.situacao_legal}</Badge></TCelula>
      <TCelula titulo={detalhe} className="text-[12.5px] text-muted">{detalhe ?? '—'}</TCelula>
      <TCelula className="text-[12.5px] text-muted">{ate ? `até ${fmtDate(ate)}` : desde ? `desde ${fmtDate(desde)}` : '—'}</TCelula>
      <TCelula livre className="flex justify-end gap-1">{!ate && acoes}</TCelula>
    </TLinha>
  );
}
