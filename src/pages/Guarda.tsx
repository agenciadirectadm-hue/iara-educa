import { useState } from 'react';
import { CalendarClock, Gavel, ShieldX, UserX } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt } from '@/lib/format';
import { Badge, Card, Chip, ErrorState, Kpi, MarcaSimulado, PageHeader, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { BuscarPessoaSheet } from '@/components/Vinculos';
import { EFEITO_RETIRADA, GuardaAlunoSheet, TIPO_GUARDA } from '@/components/guarda';

/** Guarda, tutela, medidas protetivas e restrições de retirada dos alunos da unidade (ou da rede). */
export default function Guarda() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const [busca, setBusca] = useState('');
  const [encerradas, setEncerradas] = useState(false);
  const q = useDebounced(busca, 300);
  const [aberto, setAberto] = useState<{ id: string; nome: string } | null>(null);
  const [buscar, setBuscar] = useState(false);
  const res = useRpc<any>('guarda_lista', { unit_id: unit, busca: q || null, encerradas });
  const c = res.data?.contagem;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Guarda e restrições<Simulado detail="Registros fictícios; números de processo de demonstração." /></span>}
        subtitle="Guarda, tutela, acolhimento, medidas protetivas e quem pode ou não buscar a criança. A restrição de retirada aparece na ficha do aluno; o bloqueio tira o acesso da pessoa ao portal e à IARA."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{res.data?.pode_registrar && <button type="button" onClick={() => setBuscar(true)} className="inline-flex h-10 items-center gap-1.5 rounded-2xl bg-ink px-4 text-[14px] font-semibold text-white"><Gavel className="size-4" />Novo registro</button>}</>} />
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Gavel} tone="purple" label="Determinações vigentes" value={fmtInt(c?.ativas)} />
        <Kpi compact icon={UserX} tone="red" label="Com restrição de retirada" value={fmtInt(c?.retirada)} />
        <Kpi compact icon={ShieldX} tone="red" label="Sem acesso ao portal" value={fmtInt(c?.portal)} />
        <Kpi compact icon={CalendarClock} tone="amber" label="Vencem em 30 dias" value={fmtInt(c?.vencendo)} />
      </div>
      <p className="mt-3 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-950 ring-1 ring-amber-200">
        Visibilidade provisória (decisão da SEDUC pendente): o detalhe fica só com a direção, a secretaria escolar e a Secretaria; professores veem apenas o aviso para consultar a direção.
      </p>
      <Card className="mt-3 flex flex-wrap items-center gap-2 p-3">
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome do aluno…" className={`${inputCls} h-10 max-w-xs`} aria-label="Buscar aluno" />
        <Chip active={encerradas} onClick={() => setEncerradas(!encerradas)}>Incluir encerradas</Chip>
      </Card>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(190px,1.4fr) minmax(130px,1fr) 190px minmax(170px,1.2fr) 150px 160px" largura={1040} rotulo="Guarda e restrições">
              <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Tipo</TCelula><TCelula>Pessoa</TCelula><TCelula>Retirada</TCelula><TCelula>Vigência</TCelula></TCabecalho>
              {(res.data.itens as any[]).map((r) => (
                <TLinha key={r.id} onClick={() => setAberto({ id: r.student_id, nome: r.aluno })} alerta={r.vigente && r.efeito_retirada === 'NAO_PODE'} rotulo={r.aluno}>
                  <TCelula fixa><span className="font-semibold">{r.aluno}</span>{r.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>
                  <TCelula>{r.unidade}</TCelula>
                  <TCelula>{TIPO_GUARDA[r.tipo]}</TCelula>
                  <TCelula titulo={r.pessoa_nome}>{r.pessoa_nome ?? '—'}{r.bloquear_portal ? ' · sem portal' : ''}</TCelula>
                  <TCelula livre><Badge tone={EFEITO_RETIRADA[r.efeito_retirada]?.tone}>{EFEITO_RETIRADA[r.efeito_retirada]?.label}</Badge></TCelula>
                  <TCelula>{r.situacao === 'ENCERRADA' ? 'encerrada' : `${fmtDate(r.vigencia_inicio)}${r.vigencia_fim ? ` → ${fmtDate(r.vigencia_fim)}` : ''}`}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        )}
      </div>
      <BuscarPessoaSheet open={buscar} onClose={() => setBuscar(false)} tipo="aluno" onEscolher={(p) => { setBuscar(false); setAberto(p); }} />
      <GuardaAlunoSheet studentId={aberto?.id ?? null} aluno={aberto?.nome} open={!!aberto} onClose={() => setAberto(null)} />
    </div>
  );
}
