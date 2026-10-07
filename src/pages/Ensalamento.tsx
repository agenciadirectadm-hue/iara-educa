import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Accessibility, AlertTriangle, DoorOpen, LayoutGrid, Plus, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

export const TIPO_SALA: Record<string, string> = {
  SALA_AULA: 'Sala de aula', LABORATORIO: 'Laboratório', BIBLIOTECA: 'Biblioteca', SALA_RECURSOS: 'Sala de recursos', BRINQUEDOTECA: 'Brinquedoteca',
  QUADRA: 'Quadra', REFEITORIO: 'Refeitório', OUTRO: 'Outro',
};

function useRecarregar() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: ['ensalamento'] });
}

/** Ensalamento: as salas de cada unidade, que turma ocupa cada sala em cada turno, salas livres e turmas acima da capacidade da sala. */
export default function Ensalamento() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const res = useRpc<any>('ensalamento', { unit_id: unit });
  const [sala, setSala] = useState<any | null>(null);
  const d = res.data;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Ensalamento<Simulado detail="Salas e ocupação de demonstração." /></span>}
        subtitle="Cada turma na sua sala e turno: sem duas turmas na mesma sala ao mesmo tempo, sem passar da capacidade e com sala acessível para quem precisa."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{d?.pode_editar && <Button icon={Plus} onClick={() => setSala({})}>Nova sala</Button>}</>} />
      {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : d.unit_id ? (
        <Unidade d={d} onSala={setSala} />
      ) : <Rede d={d} onUnidade={setUnit} />}
      <SalaSheet sala={sala} onClose={() => setSala(null)} />
    </div>
  );
}

function Rede({ d, onUnidade }: { d: any; onUnidade: (id: number) => void }) {
  const us = d.unidades as any[];
  const op = us.filter((u) => u.oportunidade);
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={DoorOpen} tone="blue" label="Salas de aula cadastradas" value={fmtInt(us.reduce((s, u) => s + u.salas, 0))} />
        <Kpi compact icon={LayoutGrid} tone="green" label="Salas livres (manhã + tarde)" value={fmtInt(us.reduce((s, u) => s + u.livres_manha + u.livres_tarde, 0))} />
        <Kpi compact icon={Users} tone="amber" label="Unidades com sala livre e fila ≥ 10" value={fmtInt(op.length)} sub="dá para abrir turma" />
        <Kpi compact icon={AlertTriangle} tone="red" label="Turmas acima da capacidade da sala" value={fmtInt(us.reduce((s, u) => s + u.acima, 0))} />
      </div>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(220px,2fr) 80px 110px 110px 90px 110px" largura={760} rotulo="Salas livres por unidade">
          <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Salas</TCelula><TCelula>Livres manhã</TCelula><TCelula>Livres tarde</TCelula><TCelula>Fila</TCelula><TCelula>Acima da sala</TCelula></TCabecalho>
          {us.map((u) => (
            <TLinha key={u.unit_id} onClick={() => onUnidade(u.unit_id)} alerta={u.oportunidade} rotulo={u.unidade}>
              <TCelula fixa titulo={u.unidade} className="font-semibold">{u.unidade}{u.oportunidade && <Badge tone="green" className="ml-1">abrir turma?</Badge>}</TCelula>
              <TCelula>{fmtInt(u.salas)}</TCelula><TCelula>{fmtInt(u.livres_manha)}</TCelula><TCelula>{fmtInt(u.livres_tarde)}</TCelula>
              <TCelula>{fmtInt(u.fila)}</TCelula><TCelula className={u.acima ? 'font-semibold text-red-700' : ''}>{fmtInt(u.acima)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
    </div>
  );
}

function Unidade({ d, onSala }: { d: any; onSala: (s: any) => void }) {
  const [mover, setMover] = useState<any | null>(null);
  const salas = d.salas as any[];
  const aula = salas.filter((s) => s.tipo === 'SALA_AULA');
  const acima = salas.flatMap((s) => s.ocupacao).filter((o: any) => o.acima).length;
  const acess = salas.flatMap((s) => s.ocupacao).filter((o: any) => o.acessibilidade).length;
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi compact icon={DoorOpen} tone="blue" label="Salas de aula" value={fmtInt(aula.length)} sub={`${fmtInt(salas.length - aula.length)} outros espaços`} />
        <Kpi compact icon={LayoutGrid} tone="green" label="Livres de manhã / à tarde" value={`${aula.filter((s) => s.livre_manha).length} / ${aula.filter((s) => s.livre_tarde).length}`} sub={`${fmtInt(d.fila)} na fila da unidade`} />
        <Kpi compact icon={AlertTriangle} tone="red" label="Turmas acima da sala" value={fmtInt(acima)} />
        <Kpi compact icon={Accessibility} tone="amber" label="Precisam de sala acessível" value={fmtInt(acess)} />
        <Kpi compact icon={Users} tone="gray" label="Turmas sem sala" value={fmtInt((d.sem_sala as any[]).length)} />
      </div>
      <p className="text-[12px] text-muted">{d.referencia}</p>
      {(d.conflitos as any[]).length > 0 && (
        <Card className="border-l-4 border-red-500 p-3 text-[13.5px]"><b>Conflito de turno:</b> {(d.conflitos as any[]).map((c) => `${c.sala} (${(c.turmas as string[]).join(', ')})`).join('; ')}</Card>
      )}
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(150px,1fr) 130px 90px minmax(200px,1.4fr) minmax(200px,1.4fr) 70px" largura={920} rotulo="Salas e ocupação">
          <TCabecalho><TCelula fixa>Sala</TCelula><TCelula>Tipo</TCelula><TCelula>Capac.</TCelula><TCelula>Manhã</TCelula><TCelula>Tarde</TCelula><TCelula>Acess.</TCelula></TCabecalho>
          {salas.map((s) => {
            const turno = (t: string) => (s.ocupacao as any[]).filter((o) => o.turno === t || o.turno === 'INTEGRAL');
            const cel = (t: string) => {
              const os = turno(t);
              if (!os.length) return s.tipo === 'SALA_AULA' ? <span className="font-semibold text-emerald-700">livre</span> : <span className="text-muted">—</span>;
              return os.map((o) => (
                <span key={o.class_id} className={clsx('mr-1', (o.acima || o.acessibilidade) && 'font-semibold text-red-700')}>
                  {o.turma} ({o.alunos}){o.acessibilidade && ' · precisa de acessibilidade'}
                </span>
              ));
            };
            return (
              <TLinha key={s.id} onClick={d.pode_editar ? () => onSala(s) : undefined} alerta={(s.ocupacao as any[]).some((o) => o.acima || o.acessibilidade)} rotulo={s.nome}>
                <TCelula fixa className="font-semibold">{s.is_demo && <MarcaSimulado className="mr-1" />}{s.nome}</TCelula>
                <TCelula>{TIPO_SALA[s.tipo] ?? s.tipo}</TCelula>
                <TCelula titulo={s.area_m2 ? `${String(s.area_m2).replace('.', ',')} m² → até ${s.capacidade_area} alunos` : undefined}>{s.capacidade}</TCelula>
                <TCelula>{cel('MANHA')}</TCelula><TCelula>{cel('TARDE')}</TCelula>
                <TCelula>{s.acessivel ? 'sim' : <span className="text-amber-700">não</span>}</TCelula>
              </TLinha>
            );
          })}
        </Tabela>
        {!salas.length && <EmptyState compact title="Nenhuma sala cadastrada" />}
      </Card>
      {d.pode_editar && (
        <Section title="Mudar turma de sala" subtitle="Escolha a turma; o sistema confere turno, capacidade e acessibilidade.">
          <div className="flex flex-wrap gap-1.5">
            {salas.flatMap((s) => (s.ocupacao as any[]).map((o) => ({ ...o, sala: s.nome }))).concat((d.sem_sala as any[]).map((o) => ({ ...o, sala: null })))
              .sort((a, b) => a.turma.localeCompare(b.turma)).map((o) => (
                <Chip key={o.class_id} onClick={() => setMover(o)}>{o.turma} · {o.sala ?? 'sem sala'}</Chip>
              ))}
          </div>
        </Section>
      )}
      <MoverSheet turma={mover} salas={aula.concat(salas.filter((s) => ['BRINQUEDOTECA', 'SALA_RECURSOS'].includes(s.tipo)))} onClose={() => setMover(null)} />
    </div>
  );
}

function MoverSheet({ turma, salas, onClose }: { turma: any | null; salas: any[]; onClose: () => void }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);
  const mover = async (salaId: string | null) => {
    setBusy(salaId ?? 'nenhuma');
    try {
      await rpc('turma_sala', { class_id: turma.class_id, sala_id: salaId });
      toast({ title: salaId ? 'Turma mudou de sala' : 'Turma sem sala', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };
  return (
    <Sheet open={!!turma} onClose={onClose} title={turma ? `${turma.turma} · ${SHIFT[turma.turno] ?? turma.turno}` : ''} subtitle={turma ? `${turma.alunos} alunos · hoje: ${turma.sala ?? 'sem sala'}` : ''}>
      {turma && (
        <div className="space-y-1.5 pt-1">
          {salas.map((s) => {
            const livre = turma.turno === 'MANHA' ? s.livre_manha : turma.turno === 'TARDE' ? s.livre_tarde : s.livre_manha && s.livre_tarde;
            const cabe = turma.alunos <= s.capacidade;
            return (
              <button key={s.id} type="button" disabled={!!busy || s.nome === turma.sala} onClick={() => mover(s.id)}
                className="flex w-full items-center gap-2 rounded-2xl bg-white px-3 py-2 text-left text-[13.5px] ring-1 ring-line hover:bg-blue-50 disabled:opacity-50">
                <span className="flex-1 font-semibold">{s.nome}</span>
                <span className="text-muted">cabe {s.capacidade}</span>
                {!livre && <Badge tone="red">ocupada</Badge>}{livre && !cabe && <Badge tone="amber">pequena</Badge>}{livre && cabe && <Badge tone="green">livre</Badge>}
                {!s.acessivel && <Badge tone="gray">sem acessibilidade</Badge>}
              </button>
            );
          })}
          {turma.sala && <Button variant="ghost" size="sm" loading={busy === 'nenhuma'} onClick={() => mover(null)}>Deixar sem sala</Button>}
        </div>
      )}
    </Sheet>
  );
}

function SalaSheet({ sala, onClose }: { sala: any | null; onClose: () => void }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  if (sala && chave !== (sala.id ?? 'nova')) {
    setChave(sala.id ?? 'nova');
    setF({ nome: sala.nome ?? '', tipo: sala.tipo ?? 'SALA_AULA', capacidade: sala.capacidade ?? 30, area_m2: sala.area_m2 ?? '', acessivel: sala.acessivel ?? true, andar: sala.andar ?? '', observacao: sala.observacao ?? '' });
  }
  const fechar = () => { setChave(null); onClose(); };
  const salvar = async (excluir = false) => {
    setBusy(true);
    try {
      await rpc('sala_salvar', excluir ? { id: sala.id, excluir: true } : { id: sala.id, ...f });
      toast({ title: excluir ? 'Sala excluída' : 'Sala salva', tone: 'success' });
      recarregar();
      fechar();
    } catch (e) {
      toast({ title: 'Não salva', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!sala} onClose={fechar} title={sala?.id ? sala.nome : 'Nova sala'}
      footer={<div className="flex gap-2">{sala?.id && <Button variant="secondary" loading={busy} onClick={() => salvar(true)}>Excluir</Button>}<Button block loading={busy} onClick={() => salvar()}>Salvar</Button></div>}>
      {sala && (
        <div className="space-y-3 pt-1">
          <Field label="Nome"><input value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} className={inputCls} placeholder="Sala 07" /></Field>
          <Field label="Tipo"><select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })} className={inputCls}>{Object.entries(TIPO_SALA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Capacidade (pessoas)"><input type="number" min={1} max={200} value={f.capacidade} onChange={(e) => setF({ ...f, capacidade: Number(e.target.value) })} className={inputCls} /></Field>
            <Field label="Área (m²)" hint="Opcional"><input type="number" step="0.1" value={f.area_m2} onChange={(e) => setF({ ...f, area_m2: e.target.value })} className={inputCls} /></Field>
          </div>
          <Field label="Andar ou bloco"><input value={f.andar} onChange={(e) => setF({ ...f, andar: e.target.value })} className={inputCls} /></Field>
          <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={!!f.acessivel} onChange={(e) => setF({ ...f, acessivel: e.target.checked })} />Acessível (sem degrau, porta larga)</label>
          <Field label="Observação"><input value={f.observacao} onChange={(e) => setF({ ...f, observacao: e.target.value })} className={inputCls} /></Field>
        </div>
      )}
    </Sheet>
  );
}
