import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { ChefHat, Save, UserX } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt } from '@/lib/format';
import { REFEICAO, diaLongo, hojeISO } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Field, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';

/** Lista da cozinha: crianças com restrição validada e a instrução de preparo de cada refeição do dia — sem laudo. */
export default function Cozinha() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(rede ? null : me?.unit?.id ?? null);
  const [data, setData] = useState(hojeISO());
  const res = useRpc<any>('cozinha_lista', { unit_id: unit, data }, { enabled: unit != null });
  const d = res.data;
  const presentes = d ? (d.criancas as any[]).filter((c) => !c.ausente) : [];

  return (
    <div>
      <PageHeader eyebrow={d?.unidade ?? me?.unit?.name ?? 'Cozinha da unidade'}
        title={<span className="inline-flex items-center gap-2">Lista da cozinha<Simulado detail="Crianças e restrições fictícias." /></span>}
        subtitle="Quem tem restrição validada, o que trocar em cada refeição e quem faltou hoje. A cozinha não vê laudo nem diagnóstico."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} todas={null} />}
          <input type="date" value={data} onChange={(e) => e.target.value && setData(e.target.value)} className={clsx(inputCls, 'h-10 w-auto')} aria-label="Dia" /></>} />

      {unit == null ? <Card><EmptyState title="Escolha a unidade" body="A lista da cozinha é sempre de uma unidade." /></Card>
        : res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <Card className="mb-3 flex flex-wrap items-center gap-2 p-3 text-[13.5px]">
            <ChefHat className="size-5 text-green-700" />
            <span className="inline-block font-semibold first-letter:uppercase">{diaLongo(data)}</span>
            {!d.dia_letivo && <Badge tone="gray">Dia sem aula</Badge>}
            <span className="ml-auto"><b>{fmtInt(presentes.length)}</b> refeição(ões) adaptada(s) por refeição · {fmtInt(d.criancas.length - presentes.length)} ausente(s)</span>
          </Card>
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(130px,0.8fr) 110px minmax(200px,1.2fr) minmax(260px,1.6fr)" largura={860} rotulo="Crianças com restrição">
              <TCabecalho><TCelula>Criança</TCelula><TCelula>Turma</TCelula><TCelula>Restrição</TCelula><TCelula>Trocas de hoje · preparo</TCelula></TCabecalho>
              {(d.criancas as any[]).map((c, i) => (
                <TLinha key={i} className={c.ausente ? 'opacity-55' : undefined}>
                  <TCelula fixa titulo={c.aluno}><span className="font-semibold">{c.aluno}</span>{c.ausente && <Badge tone="gray" icon={UserX} className="ml-1">faltou</Badge>}</TCelula>
                  <TCelula>{c.turma}</TCelula>
                  <TCelula titulo={`${c.restricao}${c.detalhe ? ' · ' + c.detalhe : ''}`}>{c.restricao}{c.detalhe ? ` (${c.detalhe})` : ''}</TCelula>
                  <TCelula titulo={c.orientacao}>
                    {(c.trocas as any[]).length
                      ? (c.trocas as any[]).map((t) => `${REFEICAO[t.refeicao]}: ${t.de} → ${t.para ?? 'preparo à parte'}`).join(' · ')
                      : <span className="text-muted">{c.orientacao}</span>}
                  </TCelula>
                </TLinha>
              ))}
            </Tabela>
            {!d.criancas.length && <EmptyState compact title="Nenhuma restrição validada nesta unidade" />}
          </Card>
          <RegistrarRefeicoes unit={unit} data={data} atual={d.refeicoes} />
        </>
      )}
    </div>
  );
}

function RegistrarRefeicoes({ unit, data, atual }: { unit: number; data: string; atual: Record<string, { quantidade: number; adaptadas: number }> }) {
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const [q, setQ] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    setQ(Object.fromEntries(Object.entries(atual ?? {}).map(([k, v]) => [k, String(v.quantidade)])));
  }, [atual]);
  if (!can('cozinha.read')) return null;
  const salvar = async () => {
    setBusy(true);
    try {
      const refeicoes = Object.fromEntries(Object.entries(q).filter(([, v]) => v !== '').map(([k, v]) => [k, { quantidade: Number(v), adaptadas: atual?.[k]?.adaptadas ?? 0 }]));
      await rpc('refeicoes_registrar', { unit_id: unit, data, refeicoes });
      toast({ title: 'Refeições registradas', description: 'Entram no painel da nutrição e na prestação de contas da alimentação escolar.', tone: 'success' });
      ['cozinha_lista', 'nutricao_painel'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Section title="Refeições servidas no dia" subtitle="Preenchido pela cozinha ao fim de cada refeição (vem sugerido pela presença da chamada).">
      <Card className="p-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {['DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR'].map((r) => (
            <Field key={r} label={REFEICAO[r]}>
              <input type="number" min={0} max={5000} inputMode="numeric" value={q[r] ?? ''} onChange={(e) => setQ({ ...q, [r]: e.target.value })} className={inputCls} />
            </Field>
          ))}
        </div>
        <Button className="mt-3" icon={Save} loading={busy} onClick={salvar} disabled={data > hojeISO()}>Registrar refeições</Button>
      </Card>
    </Section>
  );
}
