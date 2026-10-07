import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { AlarmClock, GraduationCap, Sprout, TrendingDown } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, fmtPct } from '@/lib/format';
import { BIMESTRES, NIVEIS, NIVEL_ALFA, SITUACAO_PLANO, fmtNota, notaCor } from '@/lib/pedagogico';
import { Card, EmptyState, ErrorState, Kpi, PageHeader, Section, Segmented, Simulado, SkeletonList, Tabs } from '@/components/ui';
import { BarList } from '@/components/charts';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { RiscoTurma } from './Avaliacao';

type Aba = 'notas' | 'alfabetizacao' | 'risco';

/** Desempenho da rede ou da unidade: notas por componente, alfabetização no 1º e 2º ano e alunos em risco com plano de intervenção. */
export default function Desempenho() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'notas') as Aba;
  const [unit, setUnit] = useState<number | null>(sp.get('unidade') ? Number(sp.get('unidade')) : null);
  const [bim, setBim] = useState<number | null>(null);
  const res = useRpc<any>('desempenho_painel', { unit_id: unit, bimestre: bim });
  const d = res.data;
  const min = Number(d?.media_minima ?? 6);
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Desempenho escolar<Simulado detail="Notas, sondagens e planos fictícios." /></span>}
        subtitle="Notas por componente, alfabetização do 1º e do 2º ano e quem precisa de apoio — com o plano de intervenção de cada aluno."
        actions={rede ? <UnitSelect value={unit} onChange={setUnit} /> : undefined} />
      {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Kpi compact icon={GraduationCap} tone="blue" label={`Alunos avaliados (${d.bimestre}º bim.)`} value={fmtInt(d.alunos_avaliados)} />
            <Kpi compact icon={TrendingDown} tone="red" label="Com nota abaixo da média" value={fmtInt(d.alunos_abaixo)}
              sub={d.alunos_avaliados ? fmtPct((100 * d.alunos_abaixo) / d.alunos_avaliados) : undefined} />
            <Kpi compact icon={Sprout} tone="green" label="Planos de intervenção em andamento" value={fmtInt(d.planos?.ATIVO)}
              sub={`${fmtInt(d.planos?.SUPERADO)} superados`} onClick={() => setSp({ aba: 'risco' }, { replace: true })} />
            <Kpi compact icon={AlarmClock} tone="amber" label="Reavaliações atrasadas" value={fmtInt(d.planos_atrasados)} onClick={() => setSp({ aba: 'risco' }, { replace: true })} />
          </div>
          <Tabs className="mt-4" value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })}
            items={[{ value: 'notas', label: 'Notas' }, { value: 'alfabetizacao', label: 'Alfabetização' }, { value: 'risco', label: 'Alunos em risco' }]} />
          <div className="mt-3">
            {aba === 'notas' && (
              <div className="space-y-4">
                <Segmented value={String(d.bimestre)} onChange={(v) => setBim(Number(v))} items={BIMESTRES.map((b) => ({ value: String(b), label: `${b}º bimestre` }))} />
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                  <Section title="Média por componente" subtitle={`${d.bimestre}º bimestre · média mínima ${fmtNota(min)}`}>
                    <Card className="p-3">
                      {(d.por_componente as any[]).length ? (
                        <BarList max={10} format={(n) => fmtNota(n)} items={(d.por_componente as any[]).map((c) => ({
                          key: c.componente, label: c.componente, value: Number(c.media),
                          sub: `${fmtPct(c.abaixo_pct)} abaixo da média · ${fmtInt(c.lancadas)} notas`,
                          color: Number(c.media) < min + 1 ? 'linear-gradient(90deg,#fb923c,#ef4444)' : undefined,
                        }))} />
                      ) : <EmptyState compact title="Sem notas neste bimestre" />}
                    </Card>
                  </Section>
                  <Section title={unit || !rede ? 'Por turma' : 'Por unidade'} subtitle="Ordenado pela proporção de notas abaixo da média.">
                    <Card className="overflow-hidden">
                      <Tabela colunas="minmax(180px,2fr) 80px 110px" largura={380} rotulo="Desempenho por turma ou unidade">
                        <TCabecalho><TCelula fixa>{unit || !rede ? 'Turma' : 'Unidade'}</TCelula><TCelula className="text-center">Média</TCelula><TCelula className="text-center">Abaixo</TCelula></TCabecalho>
                        {((d.por_turma ?? d.por_unidade ?? []) as any[]).slice(0, 60).map((x) => (
                          <TLinha key={x.class_id ?? x.unit_id} to={x.class_id ? `/turmas/${x.class_id}/avaliacao` : undefined}
                            onClick={x.unit_id && !x.class_id ? () => setUnit(x.unit_id) : undefined} alerta={Number(x.abaixo_pct) >= 20}>
                            <TCelula fixa titulo={x.turma ?? x.unidade} className="font-semibold">{x.turma ?? x.unidade}</TCelula>
                            <TCelula className={`text-center ${notaCor(x.media, min)}`}>{fmtNota(x.media)}</TCelula>
                            <TCelula className="text-center">{fmtPct(x.abaixo_pct)}</TCelula>
                          </TLinha>
                        ))}
                      </Tabela>
                    </Card>
                  </Section>
                </div>
              </div>
            )}
            {aba === 'alfabetizacao' && <AlfabetizacaoRede d={d} />}
            {aba === 'risco' && (rede && !unit ? <PlanosRede d={d} /> : <RiscoTurma unitId={unit ?? me?.unit?.id ?? null} />)}
          </div>
        </>
      )}
    </div>
  );
}

function AlfabetizacaoRede({ d }: { d: any }) {
  const series = ['EF1', 'EF2'].map((g) => {
    const rows = (d.alfabetizacao as any[]).filter((x) => x.serie === g);
    const total = rows.reduce((s, x) => s + Number(x.n), 0);
    return { g, rows, total };
  });
  return (
    <div className="space-y-4">
      <p className="text-[13px] text-muted">Última sondagem do bimestre encerrado. Meta de referência: fim do 1º ano no silábico-alfabético; fim do 2º ano alfabético (Compromisso Nacional Criança Alfabetizada).</p>
      {series.map(({ g, rows, total }) => (
        <Section key={g} title={g === 'EF1' ? '1º ano' : '2º ano'} subtitle={`${fmtInt(total)} alunos sondados`}>
          <Card className="p-4">
            {total ? (
              <>
                <div className="flex h-6 overflow-hidden rounded-full bg-slate-100" role="img" aria-label={`Distribuição por nível no ${g === 'EF1' ? '1º' : '2º'} ano`}>
                  {NIVEIS.map((n) => {
                    const q = Number(rows.find((r) => r.nivel === n)?.n ?? 0);
                    return q ? <div key={n} style={{ width: `${(100 * q) / total}%`, background: NIVEL_ALFA[n].cor }} title={`${NIVEL_ALFA[n].label}: ${q}`} /> : null;
                  })}
                </div>
                <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
                  {NIVEIS.map((n) => {
                    const q = Number(rows.find((r) => r.nivel === n)?.n ?? 0);
                    return (
                      <div key={n} className="rounded-2xl bg-slate-50 p-2">
                        <div className="flex items-center gap-1.5 text-[12px] font-semibold"><span className="size-2.5 rounded-full" style={{ background: NIVEL_ALFA[n].cor }} />{NIVEL_ALFA[n].label}</div>
                        <div className="mt-0.5 font-display text-lg font-extrabold">{fmtPct((100 * q) / total)}</div>
                        <div className="text-[11.5px] text-muted">{fmtInt(q)} alunos</div>
                      </div>
                    );
                  })}
                </div>
              </>
            ) : <EmptyState compact title="Sem sondagem registrada" />}
          </Card>
        </Section>
      ))}
    </div>
  );
}

function PlanosRede({ d }: { d: any }) {
  return (
    <div className="space-y-3">
      <Card className="p-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {Object.entries(SITUACAO_PLANO).map(([k, v]) => (
            <div key={k} className="rounded-2xl bg-slate-50 p-3">
              <div className="text-[12px] font-semibold text-muted">{v.label}</div>
              <div className="font-display text-2xl font-extrabold">{fmtInt(d.planos?.[k] ?? 0)}</div>
            </div>
          ))}
        </div>
      </Card>
      <Card><EmptyState compact title="Escolha uma unidade" body="A lista nominal de alunos em risco e os planos de intervenção ficam por unidade (escolha no seletor acima)." /></Card>
    </div>
  );
}
