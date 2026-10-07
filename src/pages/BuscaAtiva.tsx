import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { FileWarning, MessageCircleQuestion, PhoneOff, Scale, Search, ShieldAlert, Sprout, Undo2 } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt, fmtPct } from '@/lib/format';
import { Badge, Card, EmptyState, ErrorState, Kpi, MarcaSimulado, PageHeader, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { AlunoBuscaAtiva, DESTINO_TAREFA, MOTIVO_AUSENCIA, NIVEL_CONTATO, SITUACAO_ENC, STATUS_CONTATO, TIPO_TAREFA } from '@/components/busca-ativa';

type Painel = 'SEM_ESCLARECIMENTO' | 'TAREFAS' | 'CONTATOS' | 'CASOS' | 'ENCAMINHAMENTOS' | 'LEGAIS' | 'URGENTES' | 'RETORNO';

/** Monitoramento de frequência e busca ativa: ausências, contatos com a família, tarefas, casos e encaminhamentos. */
export default function BuscaAtiva() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const painel = (sp.get('painel') ?? 'SEM_ESCLARECIMENTO') as Painel;
  const [unit, setUnit] = useState<number | null>(null);
  const [busca, setBusca] = useState('');
  const q = useDebounced(busca, 300);
  const [aluno, setAluno] = useState<string | null>(null);
  const p = useRpc<any>('busca_ativa_painel', { unit_id: unit });
  const lista = useRpc<any[]>('busca_ativa_lista', { unit_id: unit, painel, q: q || null });
  const d = p.data;
  const ir = (v: Painel) => setSp({ painel: v }, { replace: true });
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · frequência e busca ativa' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Busca ativa escolar<Simulado detail="Ausências, contatos e casos de demonstração; órgãos fictícios." /></span>}
        subtitle="Ausência sem justificativa: a IARA procura a família no mesmo dia. Sem resposta, a equipe assume — lembrete, contato humano, busca ativa, rede de proteção e Conselho Tutelar, sempre com validação humana."
        actions={<>
          {rede && <UnitSelect value={unit} onChange={setUnit} />}
          <Link to="/busca-ativa/regras" className="inline-flex h-10 items-center gap-1.5 rounded-2xl bg-white px-3 text-[14px] font-semibold ring-1 ring-line hover:bg-blue-50"><Scale className="size-4" />Regras e órgãos</Link>
        </>} />
      {p.isLoading ? <SkeletonList rows={3} /> : p.error ? <ErrorState error={p.error} onRetry={() => p.refetch()} /> : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4 xl:grid-cols-7">
          <Kpi compact icon={MessageCircleQuestion} tone="amber" label="Ausências sem esclarecimento" value={fmtInt(d.sem_esclarecimento)} sub={d.taxa_resposta_30d != null ? `${fmtPct(d.taxa_resposta_30d)} das famílias respondem` : undefined} onClick={() => ir('SEM_ESCLARECIMENTO')} />
          <Kpi compact icon={PhoneOff} tone="red" label="Contatos pendentes e falhas" value={fmtInt(d.contatos_pendentes + d.falhas)} sub={`${fmtInt(d.falhas)} falha(s) de entrega`} onClick={() => ir('CONTATOS')} />
          <Kpi compact icon={Search} tone="purple" label="Busca ativa em andamento" value={fmtInt(d.busca_ativa)} onClick={() => ir('CASOS')} />
          <Kpi compact icon={Sprout} tone="blue" label="Encaminhamentos aguardando aprovação" value={fmtInt(d.encaminhamentos_aprovacao)} onClick={() => ir('ENCAMINHAMENTOS')} />
          <Kpi compact icon={FileWarning} tone="red" label="Comunicações legais pendentes" value={fmtInt(d.comunicacoes_legais)} sub="Conselho Tutelar (LDB e ECA)" onClick={() => ir('LEGAIS')} />
          <Kpi compact icon={ShieldAlert} tone="red" label="Casos urgentes" value={fmtInt(d.urgentes)} onClick={() => ir('URGENTES')} />
          <Kpi compact icon={Undo2} tone="green" label="Retorno e acompanhamento" value={fmtInt(d.retorno)} onClick={() => ir('RETORNO')} />
        </div>
      )}
      <Tabs className="mt-4" value={painel} onChange={ir} items={[
        { value: 'SEM_ESCLARECIMENTO', label: 'Sem esclarecimento' }, { value: 'TAREFAS', label: 'Tarefas' }, { value: 'CONTATOS', label: 'Contatos e falhas' },
        { value: 'CASOS', label: 'Busca ativa' }, { value: 'ENCAMINHAMENTOS', label: 'Rede de apoio' }, { value: 'LEGAIS', label: 'Comunicações legais' },
        { value: 'URGENTES', label: 'Urgentes' }, { value: 'RETORNO', label: 'Retorno' },
      ]} />
      <div className="mt-3 space-y-3">
        {painel !== 'CONTATOS' && <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome do aluno (parte do nome)…" className={`${inputCls} h-10 max-w-xs`} aria-label="Buscar aluno" />}
        {lista.isLoading ? <SkeletonList rows={6} /> : lista.error ? <ErrorState error={lista.error} onRetry={() => lista.refetch()} /> : (
          <Card className="overflow-hidden">
            {!lista.data?.length ? <EmptyState compact title="Nada nesta lista" /> : painel === 'SEM_ESCLARECIMENTO' ? (
              <Tabela colunas="minmax(200px,2fr) minmax(150px,1.2fr) 100px 90px 150px" largura={760} rotulo="Ausências sem esclarecimento">
                <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Data</TCelula><TCelula>Nível</TCelula><TCelula>Mensagem</TCelula></TCabecalho>
                {lista.data.map((a) => (
                  <TLinha key={a.id} onClick={() => setAluno(a.student_id)} alerta={a.nivel >= 3} rotulo={a.aluno}>
                    <TCelula fixa titulo={a.aluno} className="font-semibold">{a.aluno}</TCelula>
                    <TCelula titulo={a.unidade}>{a.unidade}</TCelula>
                    <TCelula>{fmtDate(a.data)}</TCelula>
                    <TCelula>{a.nivel}</TCelula>
                    <TCelula livre>{a.contato ? <span className="inline-flex items-center gap-1"><Badge tone={STATUS_CONTATO[a.contato]?.tone ?? 'gray'}>{STATUS_CONTATO[a.contato]?.label}</Badge>{a.contato === 'SIMULADA' && <MarcaSimulado />}</span> : <Badge tone="gray">sem contato</Badge>}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : painel === 'TAREFAS' ? (
              <Tabela colunas="minmax(190px,1.6fr) 180px minmax(240px,2.2fr) 150px 100px" largura={980} rotulo="Tarefas">
                <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Tarefa</TCelula><TCelula>O que fazer</TCelula><TCelula>Com quem</TCelula><TCelula>Prazo</TCelula></TCabecalho>
                {lista.data.map((t) => (
                  <TLinha key={t.id} onClick={() => t.student_id && setAluno(t.student_id)} alerta={t.prioridade === 'URGENTE' || t.atrasada} rotulo={t.aluno}>
                    <TCelula fixa titulo={t.aluno} className="font-semibold">{t.aluno ?? '—'}</TCelula>
                    <TCelula livre><Badge tone={t.prioridade === 'URGENTE' ? 'red' : t.prioridade === 'ALTA' ? 'amber' : 'gray'}>{TIPO_TAREFA[t.tipo] ?? t.tipo}</Badge></TCelula>
                    <TCelula titulo={t.descricao}>{t.descricao}</TCelula>
                    <TCelula>{DESTINO_TAREFA[t.destino]}</TCelula>
                    <TCelula className={t.atrasada ? 'font-semibold text-red-700' : ''}>{fmtDate(t.prazo)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : painel === 'CONTATOS' ? (
              <Tabela colunas="minmax(170px,1.4fr) minmax(150px,1.2fr) 140px 150px minmax(200px,1.6fr)" largura={900} rotulo="Contatos pendentes e falhas">
                <TCabecalho><TCelula fixa>Aluno(s)</TCelula><TCelula>Unidade</TCelula><TCelula>Mensagem</TCelula><TCelula>Situação</TCelula><TCelula>Detalhe</TCelula></TCabecalho>
                {lista.data.map((k) => (
                  <TLinha key={k.id} alerta={k.status === 'FALHA'}>
                    <TCelula fixa className="font-semibold">{k.alunos}</TCelula>
                    <TCelula>{k.unidade}</TCelula>
                    <TCelula>{NIVEL_CONTATO[k.nivel] ?? k.nivel}</TCelula>
                    <TCelula livre><span className="inline-flex items-center gap-1"><Badge tone={STATUS_CONTATO[k.status]?.tone ?? 'gray'}>{STATUS_CONTATO[k.status]?.label}</Badge>{k.status === 'SIMULADA' && <MarcaSimulado />}</span></TCelula>
                    <TCelula className="text-muted">{k.status === 'FALHA' ? `${k.falha} — tarefa de conferir o telefone` : `agendada para ${new Date(k.agendada_para).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}`}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : painel === 'ENCAMINHAMENTOS' || painel === 'LEGAIS' ? (
              <Tabela colunas="minmax(190px,1.6fr) minmax(150px,1.1fr) 180px minmax(200px,1.6fr) minmax(200px,1.4fr)" largura={1000} rotulo="Encaminhamentos">
                <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Situação</TCelula><TCelula>Fundamento</TCelula><TCelula>Destinatário</TCelula></TCabecalho>
                {lista.data.map((e) => (
                  <TLinha key={e.id} onClick={() => setAluno(e.student_id)} alerta={e.obrigatorio && e.situacao !== 'APROVADO'} rotulo={e.aluno}>
                    <TCelula fixa titulo={e.aluno} className="font-semibold">{e.aluno}</TCelula>
                    <TCelula titulo={e.unidade}>{e.unidade}</TCelula>
                    <TCelula livre><Badge tone={SITUACAO_ENC[e.situacao]?.tone ?? 'gray'}>{SITUACAO_ENC[e.situacao]?.label}</Badge></TCelula>
                    <TCelula titulo={e.fundamento}>{e.fundamento}</TCelula>
                    <TCelula titulo={e.orgao}>{e.orgao ?? 'a definir'}{e.orgao && !e.orgao_verificado ? ' (não verificado)' : ''}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : (
              <Tabela colunas="minmax(190px,1.6fr) minmax(150px,1.2fr) 150px minmax(240px,2fr) 110px" largura={940} rotulo="Casos de busca ativa">
                <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Situação</TCelula><TCelula>Motivo</TCelula><TCelula>Acompanhar</TCelula></TCabecalho>
                {lista.data.map((k) => (
                  <TLinha key={k.id} onClick={() => setAluno(k.student_id)} alerta={k.urgente} rotulo={k.aluno}>
                    <TCelula fixa titulo={k.aluno} className="font-semibold">{k.aluno}</TCelula>
                    <TCelula titulo={k.unidade}>{k.unidade}</TCelula>
                    <TCelula livre>{k.urgente ? <Badge tone="red">Urgente</Badge> : <Badge tone="purple">{k.situacao.replace('_', ' ').toLowerCase()}</Badge>}</TCelula>
                    <TCelula titulo={k.motivo}>{k.motivo}</TCelula>
                    <TCelula>{fmtDate(k.acompanhar_em)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            )}
          </Card>
        )}
        {d?.motivos_30d && Object.keys(d.motivos_30d).length > 0 && (
          <p className="text-[12.5px] text-muted">Motivos informados pelas famílias (30 dias): {Object.entries(d.motivos_30d as Record<string, number>).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${MOTIVO_AUSENCIA[k] ?? k} ${fmtInt(v)}`).join(' · ')}.</p>
        )}
      </div>
      <AlunoBuscaAtiva studentId={aluno} onClose={() => setAluno(null)} />
    </div>
  );
}
