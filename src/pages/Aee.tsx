import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { Accessibility, AlarmClock, CalendarCheck, Check, FilePenLine, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { firstName, fmtDate, fmtInt, fmtPct } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { MODALIDADE_AEE, SITUACAO_AEE } from '@/lib/pedagogico';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { BarList } from '@/components/charts';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { useRecarregarPedagogico } from '@/components/pedagogico';
import { IaraMascot } from '@/components/iara';

const FILTROS = [{ value: '', label: 'Todos' }, { value: 'SEM_PLANO', label: 'Sem plano' }, { value: 'EM_ELABORACAO', label: 'Em elaboração' },
  { value: 'REVISAO_VENCIDA', label: 'Revisão vencida' }, { value: 'EM_REVISAO', label: 'Em revisão' }, { value: 'ATIVO', label: 'Ativos' }];

/** AEE: alunos com deficiência, TEA ou altas habilidades, o plano de cada um e os atendimentos. Também é o início do(a) professor(a) do AEE. */
export default function Aee() {
  const { me, can } = useSession();
  const prof = me?.role === 'PROFESSOR_AEE';
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const sit = sp.get('s') ?? (prof ? 'MEUS' : '');
  const [unit, setUnit] = useState<number | null>(null);
  const [busca, setBusca] = useState('');
  const q = useDebounced(busca, 300);
  const nominal = can('aee.read') && (!rede || unit != null || q.length >= 3);
  const lista = useRpc<any>('aee_lista', { unit_id: unit, situacao: sit || null, q: q || null }, { enabled: nominal });
  const painel = useRpc<any>('aee_painel', { unit_id: unit }, { enabled: !prof });
  const set = (k: string, v: string) => {
    const p = new URLSearchParams(sp);
    if (v) p.set(k, v); else p.delete(k);
    setSp(p, { replace: true });
  };
  const c = lista.data?.contagem;
  return (
    <div>
      {prof ? (
        <div className="flex items-end gap-2">
          <div className="min-w-0 flex-1 pb-2">
            <div className="text-[13px] font-bold uppercase tracking-[0.12em] text-purple-700">Sala de recursos · {me?.unit?.name}</div>
            <h1 className="mt-1 font-display text-[28px] font-black leading-[1.08] text-ink sm:text-4xl">Bom trabalho, {firstName(me?.staff?.name ?? me?.display_name)}!</h1>
            <p className="mt-1.5 text-[15px] text-muted">Seus alunos do AEE (da sua escola e das que você atende), o plano de cada um e os atendimentos de hoje.</p>
          </div>
          <IaraMascot height={130} mood="wave" className="-mb-1 hidden shrink-0 sm:block" />
        </div>
      ) : (
        <PageHeader eyebrow={rede ? 'SEDUC · educação especial' : me?.unit?.name}
          title={<span className="inline-flex items-center gap-2">Atendimento educacional especializado<Simulado detail="Planos e atendimentos fictícios." /></span>}
          subtitle="Plano de AEE de cada aluno, quem atende, onde e quando, e a presença nos atendimentos. Diagnóstico só para quem tem permissão."
          actions={rede ? <UnitSelect value={unit} onChange={setUnit} /> : undefined} />
      )}

      {prof && lista.data && <Hoje itens={lista.data.hoje ?? []} dia={lista.data.dia} />}

      {!prof && painel.data && <Painel d={painel.data} onUnidade={rede ? setUnit : undefined} />}

      {can('aee.read') && (
        <Section title={prof ? 'Meus alunos' : 'Alunos com AEE'} className="mt-4"
          subtitle={!nominal ? 'Escolha a unidade (ou busque pelo nome) para ver a lista nominal.' : undefined}>
          <Card className="mb-3 space-y-2 p-3">
            <div className="flex flex-wrap gap-2">
              {(prof ? [{ value: 'MEUS', label: 'Que eu atendo' }, ...FILTROS] : FILTROS).map((f) => (
                <Chip key={f.value || 'todos'} active={sit === f.value} onClick={() => set('s', f.value)}>{f.label}{c && contagemDe(c, f.value) != null ? ` (${contagemDe(c, f.value)})` : ''}</Chip>
              ))}
            </div>
            <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome do aluno (parte do nome)…" className={`${inputCls} h-10 max-w-xs`} aria-label="Buscar aluno" />
          </Card>
          {!nominal ? null : lista.isLoading ? <SkeletonList rows={6} /> : lista.error ? <ErrorState error={lista.error} onRetry={() => lista.refetch()} /> : (
            <Card className="overflow-hidden">
              {(lista.data.itens as any[]).length ? (
                <Tabela colunas="minmax(190px,1.6fr) minmax(170px,1.3fr) minmax(150px,1.2fr) 130px minmax(150px,1.2fr) 110px 70px" largura={1100} rotulo="Alunos com AEE">
                  <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Necessidade</TCelula><TCelula>Escola e turma</TCelula><TCelula>Plano</TCelula><TCelula>Professor(a) do AEE</TCelula><TCelula>Revisão</TCelula><TCelula className="text-center">Pres.</TCelula></TCabecalho>
                  {(lista.data.itens as any[]).map((x) => {
                    const p = x.plano;
                    const st = p ? SITUACAO_AEE[p.situacao] : null;
                    return (
                      <TLinha key={x.student_id} to={`/aee/${x.student_id}`} alerta={!p || p.situacao === 'ENCERRADO' || p.revisao_vencida} rotulo={`Plano de AEE de ${x.aluno}`}>
                        <TCelula fixa titulo={x.aluno} className="font-semibold">{x.aluno}</TCelula>
                        <TCelula titulo={x.necessidade}>{x.necessidade ?? '—'}</TCelula>
                        <TCelula titulo={`${x.unidade} · ${x.turma}`}>{x.unidade} · {x.turma}</TCelula>
                        <TCelula livre>{st ? <Badge tone={st.tone}>{st.label}</Badge> : <Badge tone="red">Sem plano</Badge>}</TCelula>
                        <TCelula titulo={p?.profissional}>{p?.profissional ?? '—'}{p?.meu ? ' (você)' : ''}</TCelula>
                        <TCelula className={p?.revisao_vencida ? 'font-semibold text-red-700' : ''}>{p ? fmtDate(p.revisar_em) : '—'}</TCelula>
                        <TCelula className="text-center">{x.presenca != null ? `${x.presenca}%` : '—'}</TCelula>
                      </TLinha>
                    );
                  })}
                </Tabela>
              ) : <EmptyState compact title="Nenhum aluno nesta lista" />}
            </Card>
          )}
        </Section>
      )}
    </div>
  );
}

function contagemDe(c: any, f: string): number | null {
  const m: Record<string, string> = { '': 'total', SEM_PLANO: 'sem_plano', EM_ELABORACAO: 'elaboracao', REVISAO_VENCIDA: 'vencidas', EM_REVISAO: 'revisao', ATIVO: 'ativos', MEUS: 'meus' };
  return c?.[m[f]] ?? null;
}

function Painel({ d, onUnidade }: { d: any; onUnidade?: (id: number) => void }) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Accessibility} tone="purple" label="Alunos com AEE" value={fmtInt(d.alunos)} sub={`${fmtInt(d.com_mediador)} com mediador(a)`} />
        <Kpi compact icon={FilePenLine} tone="red" label="Sem plano de AEE" value={fmtInt(d.sem_plano)} sub={`${fmtInt(d.em_elaboracao)} em elaboração`} />
        <Kpi compact icon={AlarmClock} tone="amber" label="Revisão vencida" value={fmtInt(d.revisao_vencida)} sub={`${fmtInt(d.em_revisao)} em revisão`} />
        <Kpi compact icon={CalendarCheck} tone="green" label="Presença nos atendimentos (30 dias)" value={fmtPct(d.presenca_30d)} sub={`${fmtInt(d.atendimentos_30d)} atendimentos`} />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Por necessidade" subtitle="Contagem agregada (sem nomes).">
          <Card className="p-3">
            <BarList items={(d.por_necessidade as any[]).map((n) => ({ key: n.necessidade, label: n.necessidade, value: n.alunos, sub: `${fmtInt(n.com_plano)} com plano ativo` }))} />
          </Card>
        </Section>
        {d.por_unidade ? (
          <Section title="Unidades com mais pendências" subtitle="Alunos sem plano e revisões vencidas.">
            <Card className="overflow-hidden">
              <Tabela colunas="minmax(180px,2fr) 70px 90px 90px" largura={420} rotulo="AEE por unidade">
                <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula className="text-center">Alunos</TCelula><TCelula className="text-center">Sem plano</TCelula><TCelula className="text-center">Vencidas</TCelula></TCabecalho>
                {(d.por_unidade as any[]).slice(0, 40).map((u) => (
                  <TLinha key={u.unit_id} onClick={onUnidade ? () => onUnidade(u.unit_id) : undefined} alerta={u.sem_plano > 0}>
                    <TCelula fixa titulo={u.unidade} className="font-semibold">{u.unidade}</TCelula>
                    <TCelula className="text-center">{fmtInt(u.alunos)}</TCelula>
                    <TCelula className="text-center">{fmtInt(u.sem_plano)}</TCelula>
                    <TCelula className="text-center">{fmtInt(u.vencidas)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            </Card>
          </Section>
        ) : (
          <Section title="Como é o atendimento">
            <Card className="p-3">
              <BarList items={Object.entries(d.por_modalidade as Record<string, number>).map(([k, v]) => ({ key: k, label: MODALIDADE_AEE[k] ?? k, value: v }))} />
              <div className="mt-2 text-[12.5px] text-muted">Professores(as) do AEE: {(d.professores as any[]).map((p) => `${p.nome} (${p.alunos})`).join(' · ') || '—'}</div>
            </Card>
          </Section>
        )}
      </div>
    </div>
  );
}

/** Atendimentos do dia do(a) professor(a) do AEE: presença com um toque; a atividade é pedida quando presente. */
function Hoje({ itens, dia }: { itens: any[]; dia: string }) {
  const [alvo, setAlvo] = useState<any | null>(null);
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  const falta = async (x: any) => {
    try {
      await rpc('aee_atendimento_registrar', { plano_id: x.plano_id, presenca: 'FALTA' });
      toast({ title: `Falta registrada · ${firstName(x.aluno)}`, tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  return (
    <Section title="Atendimentos de hoje" className="mt-4" action={<Simulado detail="Alunos e atendimentos fictícios." />}
      subtitle={['SAB', 'DOM'].includes(dia) ? 'Fim de semana: sem atendimentos.' : `${itens.length} atendimento(s) previstos para hoje.`}>
      {itens.length ? (
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(190px,2fr) 90px minmax(170px,1.5fr) 210px" largura={700} rotulo="Atendimentos de hoje">
            <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Turno</TCelula><TCelula>Onde</TCelula><TCelula>Presença</TCelula></TCabecalho>
            {itens.map((x) => (
              <TLinha key={x.plano_id}>
                <TCelula fixa titulo={x.aluno} className="font-semibold"><Link to={`/aee/${x.student_id}`} className="hover:underline">{x.aluno}</Link></TCelula>
                <TCelula>{SHIFT[x.turno] ?? x.turno ?? '—'}</TCelula>
                <TCelula titulo={x.local}>{x.modalidade === 'ITINERANTE' ? `Itinerante · ${x.local ?? ''}` : x.local ?? '—'}</TCelula>
                <TCelula livre className="flex gap-1.5">
                  {x.registro ? <Badge tone={x.registro === 'PRESENTE' ? 'green' : 'red'}>{x.registro === 'PRESENTE' ? 'Presente' : 'Faltou'}</Badge> : (
                    <>
                      <Button size="sm" variant="success" icon={Check} onClick={() => setAlvo(x)}>Presente</Button>
                      <Button size="sm" variant="secondary" icon={X} onClick={() => falta(x)}>Faltou</Button>
                    </>
                  )}
                </TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      ) : <Card><EmptyState compact title="Nenhum atendimento hoje" body="Os dias de atendimento estão no plano de cada aluno." /></Card>}
      <AtendimentoSheet alvo={alvo} onClose={() => setAlvo(null)} />
    </Section>
  );
}

export function AtendimentoSheet({ alvo, onClose }: { alvo: { plano_id: string; aluno: string } | null; onClose: () => void }) {
  const [presenca, setPresenca] = useState('PRESENTE');
  const [atividade, setAtividade] = useState('');
  const [obs, setObs] = useState('');
  const [data, setData] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('aee_atendimento_registrar', { plano_id: alvo!.plano_id, presenca, atividade, observacao: obs, data: data || null });
      toast({ title: 'Atendimento registrado', description: 'A família vê a presença no portal e pela IARA.', tone: 'success' });
      recarregar();
      setAtividade('');
      setObs('');
      setData('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Atendimento · ${alvo?.aluno ?? ''}`} subtitle="Presença e o que foi trabalhado. A observação fica só com a equipe."
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={presenca === 'PRESENTE' && atividade.trim().length < 5} onClick={enviar}>Registrar</Button>}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Field label="Presença">
            <select value={presenca} onChange={(e) => setPresenca(e.target.value)} className={`${inputCls} h-11`}>
              <option value="PRESENTE">Presente</option><option value="FALTA">Faltou</option><option value="FALTA_JUSTIFICADA">Falta justificada</option><option value="CANCELADO">Atendimento cancelado</option>
            </select>
          </Field>
          <Field label="Data" hint="Hoje, se em branco."><input type="date" value={data} onChange={(e) => setData(e.target.value)} className={`${inputCls} h-11`} /></Field>
        </div>
        <Field label="Atividade"><input value={atividade} onChange={(e) => setAtividade(e.target.value)} maxLength={200} placeholder="Ex.: prancha de comunicação — pedidos e escolhas" className={`${inputCls} h-11`} /></Field>
        <Field label="Observação (interna)"><textarea value={obs} onChange={(e) => setObs(e.target.value)} rows={3} maxLength={600} className={`${inputCls} h-auto py-3`} /></Field>
      </div>
    </Sheet>
  );
}

