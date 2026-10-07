import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { BellRing, CalendarCheck, CalendarX, FileCheck, Percent } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt, timeAgo } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { ALERTA_FREQ, SITUACAO_ALERTA, SITUACAO_JUSTIFICATIVA, diaCurto, pctTone } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Kpi, PageHeader, Segmented, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';

type Aba = 'alertas' | 'justificativas' | 'turmas' | 'sem_chamada';

/** Frequência: presença dos últimos 30 dias, alertas de ausência (busca ativa), justificativas da família e chamadas pendentes. */
export default function Frequencia() {
  const { me, can } = useSession();
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'alertas') as Aba;
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const painel = useRpc<any>('frequencia_painel', { unit_id: unit });
  const p = painel.data;
  const abertos = (p?.alertas?.ABERTO ?? 0) + (p?.alertas?.EM_ACOMPANHAMENTO ?? 0);
  const setAba = (v: Aba) => setSp({ aba: v }, { replace: true });

  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Frequência<Simulado detail="Chamadas e faltas fictícias, geradas dia a dia sobre o calendário letivo real de 2026." /></span>}
        subtitle="Mínimo legal: 75% no ensino fundamental e 60% na educação infantil (LDB, art. 24 e 31). Faltas seguidas viram alerta para a busca ativa."
        actions={rede ? <UnitSelect value={unit} onChange={setUnit} /> : undefined} />

      {painel.error ? <ErrorState error={painel.error} onRetry={() => painel.refetch()} /> : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi compact icon={Percent} tone="green" label="Presença nos últimos 30 dias" value={p ? `${String(p.presenca_30d ?? '—').replace('.', ',')}%` : '…'} />
          <Kpi compact icon={BellRing} tone="red" label="Alertas em aberto" value={fmtInt(abertos)} sub={`${fmtInt(p?.alertas?.RESOLVIDO)} resolvidos`} onClick={() => setAba('alertas')} />
          <Kpi compact icon={FileCheck} tone="amber" label="Justificativas a avaliar" value={fmtInt(p?.justificativas_pendentes)} onClick={() => setAba('justificativas')} />
          <Kpi compact icon={CalendarX} tone="purple" label="Turmas sem chamada" value={fmtInt(p?.turmas_sem_chamada?.length)} sub={p?.ultimo_dia ? diaCurto(p.ultimo_dia) : undefined} onClick={() => setAba('sem_chamada')} />
        </div>
      )}

      <Tabs className="mt-4" value={aba} onChange={setAba} items={[
        { value: 'alertas', label: 'Alertas', count: abertos },
        { value: 'justificativas', label: 'Justificativas', count: p?.justificativas_pendentes ?? null },
        { value: 'turmas', label: rede && !unit ? 'Por unidade' : 'Por turma' },
        { value: 'sem_chamada', label: 'Sem chamada', count: p?.turmas_sem_chamada?.length ?? null },
      ]} />
      <div className="mt-3">
        {aba === 'alertas' && <Alertas unit={unit} pode={can('frequencia.acompanhar')} />}
        {aba === 'justificativas' && (can('frequencia.acompanhar') ? <Justificativas unit={unit} /> : <Card><EmptyState compact title="Sem acesso" body="Quem avalia as justificativas é a secretaria da unidade." /></Card>)}
        {aba === 'turmas' && (painel.isLoading ? <SkeletonList rows={6} /> : <PorTurma p={p} onUnit={setUnit} />)}
        {aba === 'sem_chamada' && (painel.isLoading ? <SkeletonList rows={4} /> : <SemChamada itens={p?.turmas_sem_chamada ?? []} />)}
      </div>
    </div>
  );
}

function Alertas({ unit, pode }: { unit: number | null; pode: boolean }) {
  const [sit, setSit] = useState<string>('ABERTO');
  const res = useRpc<any[]>('frequencia_alertas', { unit_id: unit, situacao: sit === 'TODOS' ? null : sit });
  const [aberto, setAberto] = useState<any | null>(null);
  const itens = res.data ?? [];
  return (
    <>
      <Segmented className="mb-3" value={sit} onChange={setSit}
        items={[{ value: 'ABERTO', label: 'Abertos' }, { value: 'EM_ACOMPANHAMENTO', label: 'Em acompanhamento' }, { value: 'RESOLVIDO', label: 'Resolvidos' }, { value: 'TODOS', label: 'Todos' }]} />
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(200px,1.3fr) minmax(130px,1fr) 190px 90px 150px" largura={820} rotulo="Alertas de frequência">
            <TCabecalho><TCelula>Aluno</TCelula><TCelula>Turma</TCelula><TCelula>Alerta</TCelula><TCelula>Presença</TCelula><TCelula>Situação</TCelula></TCabecalho>
            {itens.map((a) => (
              <TLinha key={a.id} onClick={pode ? () => setAberto(a) : undefined} alerta={a.situacao === 'ABERTO'} rotulo={a.aluno}>
                <TCelula fixa titulo={a.aluno}><span className="font-semibold">{a.aluno}</span></TCelula>
                <TCelula titulo={`${a.turma} · ${a.unidade}`}>{a.turma} <span className="text-muted">· {a.unidade}</span></TCelula>
                <TCelula><Badge tone={ALERTA_FREQ[a.tipo]?.tone}>{a.tipo === 'AUSENCIA_CONSECUTIVA' ? `${a.consecutivas} faltas seguidas` : ALERTA_FREQ[a.tipo]?.label}</Badge></TCelula>
                <TCelula><Badge tone={pctTone(Number(a.percentual))}>{String(a.percentual).replace('.', ',')}%</Badge></TCelula>
                <TCelula titulo={a.acao ?? ''}><Badge tone={SITUACAO_ALERTA[a.situacao]?.tone}>{SITUACAO_ALERTA[a.situacao]?.label}</Badge></TCelula>
              </TLinha>
            ))}
          </Tabela>
          {!itens.length && <EmptyState compact title="Nenhum alerta nesta situação" />}
        </Card>
      )}
      <AlertaSheet alerta={aberto} onClose={() => setAberto(null)} />
    </>
  );
}

function AlertaSheet({ alerta, onClose }: { alerta: any | null; onClose: () => void }) {
  const [acao, setAcao] = useState('');
  const [busy, setBusy] = useState(false);
  const qc = useQueryClient();
  const toast = useToast();
  const salvar = async (situacao: string) => {
    setBusy(true);
    try {
      await rpc('frequencia_alerta_tratar', { id: alerta.id, situacao, acao });
      toast({ title: situacao === 'RESOLVIDO' ? 'Alerta resolvido' : 'Acompanhamento registrado', description: 'Fica na ficha do aluno e na auditoria.', tone: 'success' });
      ['frequencia_alertas', 'frequencia_painel'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
      setAcao('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alerta} onClose={onClose} title={alerta?.aluno ?? ''} subtitle={alerta ? `${alerta.turma} · ${alerta.unidade} · detectado ${timeAgo(alerta.detectado_em)}` : ''}
      footer={<div className="flex gap-2"><Button variant="secondary" className="flex-1" loading={busy} disabled={acao.trim().length < 10} onClick={() => salvar('EM_ACOMPANHAMENTO')}>Em acompanhamento</Button>
        <Button variant="success" className="flex-1" loading={busy} disabled={acao.trim().length < 10} onClick={() => salvar('RESOLVIDO')}>Resolvido</Button></div>}>
      {alerta && (
        <div className="space-y-3 pt-1">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={ALERTA_FREQ[alerta.tipo]?.tone}>{alerta.tipo === 'AUSENCIA_CONSECUTIVA' ? `${alerta.consecutivas} faltas seguidas` : ALERTA_FREQ[alerta.tipo]?.label}</Badge>
            <Badge tone={pctTone(Number(alerta.percentual))}>Presença {String(alerta.percentual).replace('.', ',')}%</Badge>
          </div>
          {alerta.acao && <p className="rounded-2xl bg-slate-50 p-3 text-[13.5px] ring-1 ring-line"><b>Último registro:</b> {alerta.acao} {alerta.tratado_por ? `(${alerta.tratado_por})` : ''}</p>}
          <Field label="O que foi feito" hint="Ligação, visita, conversa com a família, encaminhamento ao Conselho Tutelar… (mínimo 10 caracteres). Evite dados de saúde.">
            <textarea value={acao} onChange={(e) => setAcao(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} />
          </Field>
        </div>
      )}
    </Sheet>
  );
}

function Justificativas({ unit }: { unit: number | null }) {
  const [todas, setTodas] = useState('pendentes');
  const res = useRpc<any[]>('frequencia_justificativas', { unit_id: unit, todas: todas === 'todas' });
  const qc = useQueryClient();
  const toast = useToast();
  const avaliar = async (j: any, aceitar: boolean) => {
    try {
      await rpc('frequencia_justificativa_avaliar', { id: j.id, aceitar });
      toast({ title: aceitar ? 'Falta justificada' : 'Justificativa recusada', description: 'A família vê a resposta no portal e pela IARA.', tone: 'success' });
      ['frequencia_justificativas', 'frequencia_painel'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  const itens = res.data ?? [];
  return (
    <>
      <Segmented className="mb-3" value={todas} onChange={setTodas} items={[{ value: 'pendentes', label: 'A avaliar' }, { value: 'todas', label: 'Todas' }]} />
      {res.isLoading ? <SkeletonList rows={4} /> : (
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(190px,1.2fr) 120px 90px minmax(180px,1.4fr) 210px" largura={860} rotulo="Justificativas de falta">
            <TCabecalho><TCelula>Aluno</TCelula><TCelula>Turma</TCelula><TCelula>Dia</TCelula><TCelula>Motivo</TCelula><TCelula className="text-right">Avaliação</TCelula></TCabecalho>
            {itens.map((j) => (
              <TLinha key={j.id}>
                <TCelula fixa titulo={j.aluno}><span className="font-semibold">{j.aluno}</span></TCelula>
                <TCelula>{j.turma}</TCelula>
                <TCelula>{diaCurto(j.data)}</TCelula>
                <TCelula titulo={j.motivo}>{j.atestado && <Badge tone="purple" className="mr-1">Atestado</Badge>}{j.motivo}</TCelula>
                <TCelula livre className="flex justify-end gap-1.5">
                  {j.situacao === 'ENVIADA' ? (<>
                    <Button size="sm" variant="secondary" onClick={() => avaliar(j, false)}>Recusar</Button>
                    <Button size="sm" variant="success" onClick={() => avaliar(j, true)}>Aceitar</Button>
                  </>) : <Badge tone={SITUACAO_JUSTIFICATIVA[j.situacao]?.tone}>{SITUACAO_JUSTIFICATIVA[j.situacao]?.label}</Badge>}
                </TCelula>
              </TLinha>
            ))}
          </Tabela>
          {!itens.length && <EmptyState compact title="Nenhuma justificativa a avaliar" body="As famílias enviam pelo portal ou pela IARA no WhatsApp." />}
        </Card>
      )}
    </>
  );
}

function PorTurma({ p, onUnit }: { p: any; onUnit: (id: number) => void }) {
  if (p?.por_unidade) {
    const itens = p.por_unidade as any[];
    return (
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,1fr) 120px 120px" largura={460} rotulo="Presença por unidade">
          <TCabecalho><TCelula>Unidade</TCelula><TCelula>Presença 30 dias</TCelula><TCelula>Alertas abertos</TCelula></TCabecalho>
          {itens.map((u) => (
            <TLinha key={u.id} onClick={() => onUnit(u.id)} rotulo={u.nome}>
              <TCelula fixa><span className="font-semibold">{u.nome}</span></TCelula>
              <TCelula><Badge tone={pctTone(Number(u.presenca), 85)}>{String(u.presenca).replace('.', ',')}%</Badge></TCelula>
              <TCelula className={u.alertas ? 'font-semibold text-red-700' : 'text-muted'}>{fmtInt(u.alertas)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
    );
  }
  const itens = (p?.por_turma ?? []) as any[];
  return (
    <Card className="overflow-hidden">
      <Tabela colunas="minmax(160px,1fr) 100px 130px 140px" largura={520} rotulo="Presença por turma">
        <TCabecalho><TCelula>Turma</TCelula><TCelula>Turno</TCelula><TCelula>Presença 30 dias</TCelula><TCelula className="text-right">Chamada</TCelula></TCabecalho>
        {itens.map((t) => (
          <TLinha key={t.id} to={`/turmas/${t.id}/chamada`}>
            <TCelula fixa><span className="font-semibold">{t.turma}</span></TCelula>
            <TCelula>{SHIFT[t.turno] ?? t.turno}</TCelula>
            <TCelula><Badge tone={pctTone(Number(t.presenca), 85)}>{String(t.presenca).replace('.', ',')}%</Badge></TCelula>
            <TCelula className="text-right font-semibold text-blue-700"><CalendarCheck className="mr-1 inline size-4" />Abrir</TCelula>
          </TLinha>
        ))}
      </Tabela>
      {!itens.length && <EmptyState compact title="Sem chamadas nos últimos 30 dias" />}
    </Card>
  );
}

function SemChamada({ itens }: { itens: any[] }) {
  return (
    <Card className="overflow-hidden">
      <Tabela colunas="minmax(160px,1fr) minmax(160px,1fr) 110px" largura={480} rotulo="Turmas sem chamada">
        <TCabecalho><TCelula>Turma</TCelula><TCelula>Unidade</TCelula><TCelula>Dia</TCelula></TCabecalho>
        {itens.map((t) => (
          <TLinha key={t.id} to={`/turmas/${t.id}/chamada?data=${t.data}`} alerta>
            <TCelula fixa><span className="font-semibold">{t.turma}</span></TCelula><TCelula>{t.unidade}</TCelula><TCelula>{fmtDate(t.data)}</TCelula>
          </TLinha>
        ))}
      </Tabela>
      {!itens.length && <EmptyState compact title="Todas as turmas com chamada" body="No último dia letivo, todas as turmas registraram a chamada." />}
    </Card>
  );
}
