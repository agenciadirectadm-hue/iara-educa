import { useEffect, useMemo, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import { Accessibility, CalendarCheck, NotebookPen, PenLine, Save, Sprout } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { BIMESTRES, CICLO_ALFA, LEITURA, MOTIVO_RISCO, NIVEIS, NIVEL_ALFA, fmtNota, notaCor } from '@/lib/pedagogico';
import { Badge, Button, Card, EmptyState, ErrorState, Field, PageHeader, Segmented, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { NivelBadge, PlanoCard, PlanoSheet, useRecarregarPedagogico } from '@/components/pedagogico';
import { ConselhoTurma } from '@/components/conselho';
import { AntropometriaTurma } from '@/components/sprint4';

type Aba = 'notas' | 'alfabetizacao' | 'risco' | 'aee' | 'conselho' | 'medidas';

/** Avaliação da turma: notas por componente (ou pareceres na educação infantil), sondagem de alfabetização, alunos em risco e orientações do AEE. */
export default function Avaliacao() {
  const { id } = useParams();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'notas') as Aba;
  const [bim, setBim] = useState<number | null>(null);
  const res = useRpc<any>('notas_turma', { class_id: id, bimestre: bim });
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const alfa = ['EF1', 'EF2'].includes(d.turma.serie);
  const tabs = [
    { value: 'notas' as Aba, label: d.parecer ? 'Pareceres' : 'Notas' },
    ...(alfa ? [{ value: 'alfabetizacao' as Aba, label: 'Alfabetização' }] : []),
    ...(!d.parecer ? [{ value: 'risco' as Aba, label: 'Em risco' }] : []),
    ...(can('aee.orientacoes') ? [{ value: 'aee' as Aba, label: 'AEE na sala' }] : []),
    { value: 'conselho' as Aba, label: 'Conselho de classe' },
    ...(can('antropometria.read') ? [{ value: 'medidas' as Aba, label: 'Peso e altura' }] : []),
  ];
  return (
    <div>
      <PageHeader eyebrow={<span className="inline-flex items-center gap-1">{d.turma.unidade}<Simulado detail="Notas, pareceres e sondagens fictícios." /></span>}
        title={`Avaliação · ${d.turma.nome}`} subtitle={`Turno ${SHIFT[d.turma.turno]?.toLowerCase() ?? ''} · média mínima ${fmtNota(d.media_minima)} · ${d.bimestre_atual}º bimestre em andamento`}
        actions={<>
          <Link to={`/turmas/${id}/chamada`} className="inline-flex h-11 items-center gap-1.5 rounded-2xl bg-white px-4 text-[15px] font-semibold ring-1 ring-line hover:bg-blue-50"><CalendarCheck className="size-4" />Chamada</Link>
          <Link to={`/turmas/${id}/diario`} className="inline-flex h-11 items-center gap-1.5 rounded-2xl bg-white px-4 text-[15px] font-semibold ring-1 ring-line hover:bg-blue-50"><NotebookPen className="size-4" />Diário</Link>
        </>} />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={tabs} />
      <div className="mt-3">
        {aba === 'notas' && (d.parecer ? <Pareceres d={d} bim={d.bimestre} setBim={setBim} /> : <Notas d={d} setBim={setBim} />)}
        {aba === 'alfabetizacao' && alfa && <Alfabetizacao classId={id!} />}
        {aba === 'risco' && <RiscoTurma classId={id!} />}
        {aba === 'aee' && <AeeSala classId={id!} />}
        {aba === 'conselho' && <ConselhoTurma classId={id!} />}
        {aba === 'medidas' && <AntropometriaTurma classId={id!} />}
      </div>
    </div>
  );
}

function SeletorBimestre({ valor, atual, onChange }: { valor: number; atual: number; onChange: (b: number) => void }) {
  return (
    <Segmented value={String(valor)} onChange={(v) => onChange(Number(v))}
      items={BIMESTRES.filter((b) => b <= Math.max(atual, 1)).map((b) => ({ value: String(b), label: `${b}º bim.` }))} />
  );
}

function Notas({ d, setBim }: { d: any; setBim: (b: number) => void }) {
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  const comps = d.componentes as any[];
  const [comp, setComp] = useState<string>(() => (comps.find((c) => c.pode_lancar) ?? comps[0])?.nome ?? '');
  const atual = comps.find((c) => c.nome === comp);
  const [edit, setEdit] = useState<Record<string, { nota: string; rec: string }>>({});
  const [busy, setBusy] = useState(false);
  const alunos = d.alunos as any[];
  const min = Number(d.media_minima);
  // ao trocar componente/bimestre, recomeça a edição a partir do que está gravado
  useEffect(() => {
    setEdit(Object.fromEntries(alunos.map((a) => [a.id, { nota: campo(a.notas?.[comp]?.nota), rec: campo(a.notas?.[comp]?.rec) }])));
  }, [comp, d.bimestre, alunos]);
  const alterados = useMemo(() => alunos.filter((a) => {
    const e = edit[a.id];
    if (!e) return false;
    return (e.nota || '') !== campo(a.notas?.[comp]?.nota) || (e.rec || '') !== campo(a.notas?.[comp]?.rec);
  }), [edit, alunos, comp]);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('notas_lancar', { class_id: d.turma.id, componente: comp, bimestre: d.bimestre,
        notas: alterados.map((a) => ({ student_id: a.id, nota: edit[a.id].nota.replace(',', '.'), rec: edit[a.id].rec.replace(',', '.') })) });
      toast({ title: 'Notas salvas', description: `${alterados.length} aluno(s) · ${comp}. A família vê no boletim e pela IARA.`, tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const pode = !!atual?.pode_lancar && d.bimestre <= d.bimestre_atual;
  const media = (() => {
    const v = alunos.map((a) => a.notas?.[comp]?.final).filter((x) => x != null).map(Number);
    return v.length ? v.reduce((s, x) => s + x, 0) / v.length : null;
  })();
  const abaixo = alunos.filter((a) => a.notas?.[comp]?.final != null && Number(a.notas[comp].final) < min).length;
  return (
    <div className="space-y-3">
      <Card className="flex flex-wrap items-end gap-3 p-3">
        <Field label="Componente">
          <select value={comp} onChange={(e) => setComp(e.target.value)} className={`${inputCls} h-10 min-w-56`}>
            {comps.map((c) => <option key={c.nome} value={c.nome}>{c.nome}{c.pode_lancar ? ' ✎' : ''}</option>)}
          </select>
        </Field>
        <SeletorBimestre valor={d.bimestre} atual={d.bimestre_atual} onChange={setBim} />
        <div className="ml-auto text-[13px] text-muted">
          {atual?.professor ? <>Professor(a): <b className="text-ink">{atual.professor}</b> · </> : null}
          média da turma <b className={notaCor(media, min)}>{fmtNota(media)}</b> · {fmtInt(abaixo)} abaixo da média
        </div>
      </Card>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,2fr) 96px 110px 70px 86px" largura={600} rotulo={`Notas de ${comp}`}>
          <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula className="text-center">Nota</TCelula><TCelula className="text-center">Recuperação</TCelula><TCelula className="text-center">Final</TCelula><TCelula className="text-center">Média ano</TCelula></TCabecalho>
          {alunos.map((a) => {
            const n = a.notas?.[comp];
            const e = edit[a.id] ?? { nota: '', rec: '' };
            return (
              <TLinha key={a.id} alerta={n?.final != null && Number(n.final) < min}>
                <TCelula fixa titulo={a.nome} className="font-semibold">{a.nome}{a.aee && <Accessibility className="ml-1 inline size-3.5 text-purple-700" aria-label="AEE" />}</TCelula>
                <TCelula livre className="text-center">
                  {pode ? <input inputMode="decimal" value={e.nota} onChange={(ev) => setEdit({ ...edit, [a.id]: { ...e, nota: ev.target.value } })} aria-label={`Nota de ${a.nome}`}
                    className="h-8 w-16 rounded-xl bg-white text-center ring-1 ring-line focus:ring-2 focus:ring-blue-400" /> : <span className={notaCor(n?.nota, min)}>{fmtNota(n?.nota)}</span>}
                </TCelula>
                <TCelula livre className="text-center">
                  {pode ? <input inputMode="decimal" value={e.rec} onChange={(ev) => setEdit({ ...edit, [a.id]: { ...e, rec: ev.target.value } })} aria-label={`Recuperação de ${a.nome}`}
                    className="h-8 w-16 rounded-xl bg-white text-center ring-1 ring-line focus:ring-2 focus:ring-blue-400" /> : <span>{fmtNota(n?.rec)}</span>}
                </TCelula>
                <TCelula className={`text-center ${notaCor(n?.final, min)}`}>{fmtNota(n?.final)}</TCelula>
                <TCelula className={`text-center ${notaCor(a.medias?.[comp], min)}`}>{fmtNota(a.medias?.[comp])}</TCelula>
              </TLinha>
            );
          })}
        </Tabela>
        {!alunos.length && <EmptyState compact title="Turma sem alunos ativos" />}
      </Card>
      {pode ? (
        <div className="sticky bottom-3 flex items-center justify-end gap-3">
          <span className="text-[13px] text-muted">{alterados.length ? `${alterados.length} alteração(ões) por salvar` : 'Notas de 0 a 10, com uma casa decimal.'}</span>
          <Button icon={Save} loading={busy} disabled={!alterados.length} onClick={salvar}>Salvar notas</Button>
        </div>
      ) : <p className="text-[12.5px] text-muted">{atual ? 'Só o(a) professor(a) do componente (ou a gestão da unidade) lança estas notas.' : ''}</p>}
    </div>
  );
}

/** Nota no campo de edição, com vírgula (pt-BR). */
const campo = (n: number | string | null | undefined) => (n == null ? '' : String(n).replace('.', ','));

function Pareceres({ d, bim, setBim }: { d: any; bim: number; setBim: (b: number) => void }) {
  const [alvo, setAlvo] = useState<any | null>(null);
  const alunos = d.alunos as any[];
  const feitos = alunos.filter((a) => a.parecer).length;
  return (
    <div className="space-y-3">
      <Card className="flex flex-wrap items-center gap-3 p-3">
        <SeletorBimestre valor={bim} atual={d.bimestre_atual} onChange={setBim} />
        <span className="text-[13px] text-muted">{fmtInt(feitos)} de {fmtInt(alunos.length)} pareceres registrados</span>
      </Card>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,1.2fr) minmax(260px,3fr) 110px" largura={700} rotulo="Pareceres da turma">
          <TCabecalho><TCelula fixa>Criança</TCelula><TCelula>Parecer</TCelula><TCelula /></TCabecalho>
          {alunos.map((a) => (
            <TLinha key={a.id} onClick={d.pode_parecer ? () => setAlvo(a) : undefined} rotulo={`Parecer de ${a.nome}`}>
              <TCelula fixa titulo={a.nome} className="font-semibold">{a.nome}</TCelula>
              <TCelula titulo={a.parecer} className={a.parecer ? '' : 'text-subtle'}>{a.parecer ?? 'Ainda não registrado'}</TCelula>
              <TCelula livre className="text-right">{d.pode_parecer && <span className="inline-flex items-center gap-1 text-[12.5px] font-semibold text-blue-700"><PenLine className="size-4" />{a.parecer ? 'Editar' : 'Escrever'}</span>}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <ParecerSheet alvo={alvo} classId={d.turma.id} bim={bim} onClose={() => setAlvo(null)} />
    </div>
  );
}

function ParecerSheet({ alvo, classId, bim, onClose }: { alvo: any | null; classId: string; bim: number; onClose: () => void }) {
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  useEffect(() => setTexto(alvo?.parecer ?? ''), [alvo]);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('parecer_salvar', { class_id: classId, student_id: alvo.id, bimestre: bim, texto });
      toast({ title: 'Parecer salvo', description: 'A família vê no boletim e pela IARA.', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Parecer do ${bim}º bimestre · ${alvo?.nome ?? ''}`} subtitle="Descreva o desenvolvimento: interações, linguagem, movimento, autonomia e o que vamos incentivar."
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={texto.trim().length < 20} onClick={salvar}>Salvar parecer</Button>}>
      <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={8} maxLength={4000} className={`${inputCls} h-auto py-3`} aria-label="Parecer" />
      <div className="mt-1 text-right text-[12px] text-muted">{texto.length}/4000</div>
    </Sheet>
  );
}

function Alfabetizacao({ classId }: { classId: string }) {
  const [ciclo, setCiclo] = useState<string | null>(null);
  const res = useRpc<any>('alfabetizacao_turma', { class_id: classId, ciclo });
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  const [edit, setEdit] = useState<Record<string, { nivel: string; leitura: string }>>({});
  const [busy, setBusy] = useState(false);
  const d = res.data;
  useEffect(() => {
    if (d) setEdit(Object.fromEntries((d.alunos as any[]).map((a) => [a.id, { nivel: a.atual?.nivel ?? '', leitura: a.atual?.leitura ?? '' }])));
  }, [d]);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const alunos = d.alunos as any[];
  const total = Object.values(d.distribuicao as Record<string, number>).reduce((s, n) => s + n, 0);
  const alterados = alunos.filter((a) => (edit[a.id]?.nivel ?? '') !== (a.atual?.nivel ?? '') || (edit[a.id]?.leitura ?? '') !== (a.atual?.leitura ?? ''));
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('alfabetizacao_lancar', { class_id: classId, ciclo: d.ciclo, registros: alterados.map((a) => ({ student_id: a.id, ...edit[a.id] })) });
      toast({ title: 'Sondagem salva', description: `${alterados.length} aluno(s).`, tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="space-y-3">
      <Card className="space-y-3 p-3">
        <Segmented value={d.ciclo} onChange={setCiclo} items={Object.entries(CICLO_ALFA).map(([v, l]) => ({ value: v, label: l.replace(' bimestre', ' bim.') }))} />
        {total > 0 ? (
          <div>
            <div className="flex h-4 overflow-hidden rounded-full bg-slate-100" role="img" aria-label="Distribuição por nível">
              {NIVEIS.map((n) => (d.distribuicao[n] ? <div key={n} style={{ width: `${(100 * d.distribuicao[n]) / total}%`, background: NIVEL_ALFA[n].cor }} title={`${NIVEL_ALFA[n].label}: ${d.distribuicao[n]}`} /> : null))}
            </div>
            <div className="mt-2 flex flex-wrap gap-3 text-[12.5px]">
              {NIVEIS.map((n) => <span key={n} className="inline-flex items-center gap-1"><span className="size-2.5 rounded-full" style={{ background: NIVEL_ALFA[n].cor }} />{NIVEL_ALFA[n].label}: <b>{d.distribuicao[n] ?? 0}</b></span>)}
            </div>
          </div>
        ) : <p className="text-[13px] text-muted">Sondagem deste ciclo ainda não registrada.</p>}
      </Card>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,2fr) 220px 160px minmax(160px,1.4fr)" largura={780} rotulo="Sondagem de alfabetização">
          <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Escrita</TCelula><TCelula>Leitura</TCelula><TCelula>Ao longo do ano</TCelula></TCabecalho>
          {alunos.map((a) => (
            <TLinha key={a.id}>
              <TCelula fixa titulo={a.nome} className="font-semibold">{a.nome}</TCelula>
              <TCelula livre>
                {d.pode_lancar ? (
                  <select value={edit[a.id]?.nivel ?? ''} onChange={(e) => setEdit({ ...edit, [a.id]: { ...edit[a.id], nivel: e.target.value } })} aria-label={`Nível de escrita de ${a.nome}`}
                    className="h-8 w-full rounded-xl bg-white px-2 text-[13px] ring-1 ring-line">
                    <option value="">—</option>{NIVEIS.map((n) => <option key={n} value={n}>{NIVEL_ALFA[n].label}</option>)}
                  </select>
                ) : <NivelBadge nivel={a.atual?.nivel} />}
              </TCelula>
              <TCelula livre>
                {d.pode_lancar ? (
                  <select value={edit[a.id]?.leitura ?? ''} onChange={(e) => setEdit({ ...edit, [a.id]: { ...edit[a.id], leitura: e.target.value } })} aria-label={`Leitura de ${a.nome}`}
                    className="h-8 w-full rounded-xl bg-white px-2 text-[13px] ring-1 ring-line">
                    <option value="">—</option>{Object.entries(LEITURA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                  </select>
                ) : <span>{LEITURA[a.atual?.leitura] ?? '—'}</span>}
              </TCelula>
              <TCelula livre className="flex gap-1">
                {(a.historico as any[]).map((h) => <span key={h.ciclo} title={`${CICLO_ALFA[h.ciclo]}: ${NIVEL_ALFA[h.nivel]?.label}`} className="size-3 rounded-full" style={{ background: NIVEL_ALFA[h.nivel]?.cor }} />)}
              </TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      {d.pode_lancar && (
        <div className="sticky bottom-3 flex items-center justify-end gap-3">
          <span className="text-[13px] text-muted">{alterados.length ? `${alterados.length} alteração(ões) por salvar` : 'Hipóteses da psicogênese da escrita (Ferreiro e Teberosky).'}</span>
          <Button icon={Save} loading={busy} disabled={!alterados.length} onClick={salvar}>Salvar sondagem</Button>
        </div>
      )}
    </div>
  );
}

export function RiscoTurma({ classId, unitId }: { classId?: string; unitId?: number | null }) {
  const res = useRpc<any>('risco_lista', { class_id: classId ?? null, unit_id: unitId ?? null }, { enabled: !!classId || !!unitId, retry: false });
  const [alvo, setAlvo] = useState<any | null>(null);
  const [sit, setSit] = useState<'todos' | 'sem' | 'com'>('todos');
  if (!classId && !unitId) return <Card><EmptyState compact title="Escolha uma unidade" body="A lista de alunos em risco é por unidade." /></Card>;
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const itens = (d.itens as any[]).filter((x) => sit === 'todos' || (sit === 'sem' ? !x.plano || x.plano.situacao !== 'ATIVO' : x.plano?.situacao === 'ATIVO'));
  return (
    <div className="space-y-3">
      <Card className="flex flex-wrap items-center gap-2 p-3 text-[13px]">
        <Segmented value={sit} onChange={setSit} items={[{ value: 'todos', label: `Todos (${d.total})` }, { value: 'sem', label: `Sem plano (${d.total - d.com_plano})` }, { value: 'com', label: `Com plano (${d.com_plano})` }]} />
        <span className="ml-auto inline-flex flex-wrap gap-1.5">{Object.entries(d.por_motivo as Record<string, number>).map(([m, n]) => <Badge key={m} tone={MOTIVO_RISCO[m]?.tone ?? 'gray'}>{MOTIVO_RISCO[m]?.label ?? m}: {n}</Badge>)}</span>
      </Card>
      <Card className="overflow-hidden">
        {itens.length ? (
          <Tabela colunas="minmax(190px,1.6fr) 110px minmax(200px,1.6fr) minmax(200px,1.6fr) 120px" largura={900} rotulo="Alunos em risco">
            <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Turma</TCelula><TCelula>Motivo</TCelula><TCelula>Indicadores</TCelula><TCelula>Plano</TCelula></TCabecalho>
            {itens.map((x) => (
              <TLinha key={x.student_id} alerta={!x.plano || x.plano.situacao !== 'ATIVO'} onClick={d.pode_planejar ? () => setAlvo(x) : undefined} rotulo={`Plano de ${x.aluno}`}>
                <TCelula fixa titulo={x.aluno} className="font-semibold">{x.aluno}</TCelula>
                <TCelula>{x.turma}</TCelula>
                <TCelula livre className="flex flex-wrap gap-1">{(x.motivos as string[]).map((m) => <Badge key={m} tone={MOTIVO_RISCO[m]?.tone ?? 'gray'}>{MOTIVO_RISCO[m]?.label ?? m}</Badge>)}</TCelula>
                <TCelula titulo={indicadoresTxt(x.indicadores)} className="text-[12.5px] text-muted">{indicadoresTxt(x.indicadores)}</TCelula>
                <TCelula livre>{x.plano ? <Badge tone={x.plano.situacao === 'ATIVO' ? (x.plano.atrasado ? 'red' : 'blue') : 'green'}>{x.plano.situacao === 'ATIVO' ? (x.plano.atrasado ? 'Reavaliar' : 'Em andamento') : 'Superado'}</Badge> : <Badge tone="amber">Sem plano</Badge>}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : <EmptyState compact title="Nenhum aluno nesta lista" />}
      </Card>
      <p className="text-[12.5px] text-muted">Em risco: média abaixo do mínimo em Português, Matemática ou em 2+ componentes; frequência a menos de 5 pontos do mínimo legal; ou alfabetização atrasada a partir do 2º bimestre.</p>
      <RiscoSheet alvo={alvo} onClose={() => setAlvo(null)} />
    </div>
  );
}

function indicadoresTxt(i: any) {
  const p: string[] = [];
  if (i?.componentes_abaixo?.length) p.push(`Abaixo: ${(i.componentes_abaixo as string[]).join(', ')}`);
  if (i?.frequencia != null) p.push(`Freq. ${String(i.frequencia).replace('.', ',')}%`);
  if (i?.nivel) p.push(`${NIVEL_ALFA[i.nivel]?.label ?? i.nivel} (${CICLO_ALFA[i.ciclo] ?? i.ciclo})`);
  return p.join(' · ');
}

function RiscoSheet({ alvo, onClose }: { alvo: any | null; onClose: () => void }) {
  const [plano, setPlano] = useState<any | null>(null);
  return (
    <>
      <Sheet open={!!alvo && !plano} onClose={onClose} title={alvo?.aluno} subtitle={`${alvo?.turma ?? ''} · ${indicadoresTxt(alvo?.indicadores)}`}>
        {alvo?.plano ? (
          <PlanoCard p={alvo.plano} acoes={alvo.plano.situacao === 'ATIVO' ? (
            <>
              <Button size="sm" variant="purple" onClick={() => setPlano({ student_id: alvo.student_id, aluno: alvo.aluno, plano: alvo.plano, reavaliar: true })}>Reavaliar</Button>
              <Button size="sm" variant="secondary" onClick={() => setPlano({ student_id: alvo.student_id, aluno: alvo.aluno, plano: alvo.plano })}>Ajustar o plano</Button>
            </>
          ) : <Button size="sm" variant="purple" icon={Sprout} onClick={() => setPlano({ student_id: alvo.student_id, aluno: alvo.aluno, motivos: alvo.motivos })}>Novo plano</Button>} />
        ) : (
          <div className="space-y-3">
            <p className="text-[14px]">Ainda não há plano de intervenção para este aluno.</p>
            <Button icon={Sprout} variant="purple" onClick={() => setPlano({ student_id: alvo.student_id, aluno: alvo.aluno, motivos: alvo.motivos })}>Montar plano de intervenção</Button>
          </div>
        )}
        {alvo && <Link to={`/alunos/${alvo.student_id}?aba=boletim`} className="mt-3 inline-block text-[13px] font-semibold text-blue-700">Ver o boletim completo</Link>}
      </Sheet>
      <PlanoSheet alvo={plano} onClose={() => { setPlano(null); onClose(); }} />
    </>
  );
}

function AeeSala({ classId }: { classId: string }) {
  const res = useRpc<any[]>('aee_orientacoes_turma', { class_id: classId });
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <Card><EmptyState compact title="Nenhum aluno com AEE nesta turma" /></Card>;
  return (
    <div className="space-y-3">
      {res.data.map((x) => (
        <Card key={x.student_id} className="p-4">
          <div className="flex flex-wrap items-center gap-2">
            <Accessibility className="size-5 text-purple-700" /><span className="font-semibold">{x.aluno}</span>
            {x.mediador && <Badge tone="teal">Mediador(a): {x.mediador}</Badge>}
            {x.plano ? <Badge tone="purple">AEE com {x.plano.profissional ?? '—'}</Badge> : <Badge tone="amber">Plano de AEE em elaboração</Badge>}
          </div>
          {x.plano?.orientacoes_sala && <p className="mt-2 text-[14px] leading-relaxed"><b>Na sala:</b> {x.plano.orientacoes_sala}</p>}
          {x.plano?.recursos?.length > 0 && <div className="mt-2 flex flex-wrap gap-1.5">{(x.plano.recursos as any[]).map((r) => <Badge key={r.codigo} tone="blue">{r.rotulo}</Badge>)}</div>}
        </Card>
      ))}
      <p className="text-[12.5px] text-muted">Só as orientações para a sala e os recursos: o diagnóstico e o plano completo ficam com o(a) professor(a) do AEE e a gestão (LGPD).</p>
    </div>
  );
}
