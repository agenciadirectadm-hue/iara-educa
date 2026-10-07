// Sprint 4 — peças das telas: biblioteca na vida escolar da família, peso e medidas (turma, ficha, painel e família) e patrimônio.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { AlertTriangle, ArrowRightLeft, BookMarked, CheckCheck, ClipboardCheck, PackageX, RotateCcw, Ruler, Save, Search, Upload, Wrench } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtBRL, fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, Section, Segmented, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

// ------------------------------------------------------------------ Biblioteca (família)
export function BibliotecaFamilia() {
  const res = useRpc<any[]>('familia_biblioteca', {});
  const qc = useQueryClient();
  const toast = useToast();
  const [busca, setBusca] = useState<{ student_id: string; nome: string } | null>(null);
  const renovar = async (id: string) => {
    try {
      const r = await rpc<any>('biblioteca_renovar', { id });
      toast({ title: 'Renovado', description: `Devolver até ${fmtDate(r.prevista)}.`, tone: 'success' });
      qc.invalidateQueries({ queryKey: ['familia_biblioteca'] });
    } catch (e) {
      toast({ title: 'Não renovado', description: (e as Error).message, tone: 'error' });
    }
  };
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <EmptyState title="Nenhuma criança matriculada" />;
  return (
    <div className="space-y-5">
      {res.data.map((k) => (
        <Section key={k.student_id} title={`Biblioteca · ${k.primeiro_nome}`} subtitle={`${k.unidade ?? ''} · empréstimo de ${k.prazo_dias} dias${k.prazo_dias === 7 ? ' (sacola literária)' : ''}`}
          action={<Button size="sm" variant="secondary" icon={Search} onClick={() => setBusca({ student_id: k.student_id, nome: k.primeiro_nome })}>Procurar e reservar</Button>}>
          <div className="space-y-2">
            {!(k.ativos as any[]).length && <Card className="p-3 text-[13.5px] text-muted">Nenhum livro com {k.primeiro_nome} agora.</Card>}
            {(k.ativos as any[]).map((x) => (
              <Card key={x.id} className={clsx('flex flex-wrap items-center gap-3 p-3 text-[13.5px]', x.atrasado && 'ring-2 ring-red-200')}>
                <BookMarked className="size-5 text-purple-700" aria-hidden />
                <div className="min-w-0 flex-1"><b>{x.titulo}</b> <span className="text-muted">· {x.autor}</span>
                  <div className={x.atrasado ? 'font-semibold text-red-700' : 'text-muted'}>{x.atrasado ? `Atrasado desde ${fmtDate(x.prevista)} — devolva na escola` : `Devolver até ${fmtDate(x.prevista)}`}</div></div>
                {x.pode_renovar && <Button size="sm" icon={RotateCcw} onClick={() => renovar(x.id)}>Renovar</Button>}
              </Card>
            ))}
            {(k.reservas as any[]).map((r) => (
              <Card key={r.id} className="p-3 text-[13.5px]"><Badge tone={r.situacao === 'DISPONIVEL' ? 'green' : 'amber'}>{r.situacao === 'DISPONIVEL' ? 'Separado na biblioteca' : 'Reservado'}</Badge> {r.titulo}</Card>
            ))}
            {(k.lidos as any[]).length > 0 && (
              <details className="rounded-2xl bg-white p-3 text-[13.5px] ring-1 ring-line"><summary className="cursor-pointer font-semibold">{(k.lidos as any[]).length} livro(s) lido(s) neste ano</summary>
                <ul className="mt-2 space-y-0.5">{(k.lidos as any[]).map((l, i) => <li key={i}>{l.titulo} <span className="text-muted">· {l.autor} · {fmtDate(l.retirada_em)}</span></li>)}</ul>
              </details>
            )}
          </div>
        </Section>
      ))}
      <ReservarSheet alvo={busca} onClose={() => setBusca(null)} />
    </div>
  );
}

function ReservarSheet({ alvo, onClose }: { alvo: { student_id: string; nome: string } | null; onClose: () => void }) {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const res = useRpc<any[]>('biblioteca_acervo', { student_id: alvo?.student_id, q: dq || null }, { enabled: !!alvo });
  const qc = useQueryClient();
  const toast = useToast();
  const reservar = async (titulo_id: string) => {
    try {
      const r = await rpc<any>('biblioteca_reservar', { titulo_id, student_id: alvo!.student_id, canal: 'PORTAL' });
      toast({ title: 'Reservado', description: `Posição ${r.posicao} na fila. A família é avisada quando o livro chegar.`, tone: 'success' });
      qc.invalidateQueries({ queryKey: ['familia_biblioteca'] });
    } catch (e) {
      toast({ title: 'Não reservado', description: (e as Error).message, tone: 'error' });
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} size="lg" title={`Acervo da escola de ${alvo?.nome ?? ''}`} subtitle="Livro disponível: é só pedir na escola. Emprestado: dá para reservar.">
      <div className="space-y-3 pt-1">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Título ou autor…" className={inputCls} aria-label="Buscar livro" />
        {res.isLoading ? <SkeletonList rows={4} /> : (
          <ul className="space-y-1.5">
            {((res.data ?? []) as any[]).slice(0, 60).map((t) => (
              <li key={t.id} className="flex items-center gap-2 rounded-2xl bg-white p-2.5 text-[13.5px] ring-1 ring-line">
                <span className="min-w-0 flex-1"><b>{t.titulo}</b> <span className="text-muted">· {t.autor}</span></span>
                {t.disponiveis > 0 ? <Badge tone="green">disponível</Badge> : <Button size="sm" variant="secondary" onClick={() => reservar(t.id)}>Reservar</Button>}
              </li>
            ))}
          </ul>
        )}
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ Peso e medidas
const CLASSE_IMC: Record<string, { label: string; tone: 'green' | 'amber' | 'red' | 'purple' }> = {
  MAGREZA_ACENTUADA: { label: 'Magreza acentuada', tone: 'red' }, MAGREZA: { label: 'Magreza', tone: 'amber' }, EUTROFIA: { label: 'Eutrofia', tone: 'green' },
  RISCO_SOBREPESO: { label: 'Risco de sobrepeso', tone: 'amber' }, SOBREPESO: { label: 'Sobrepeso', tone: 'amber' }, OBESIDADE: { label: 'Obesidade', tone: 'red' },
  OBESIDADE_GRAVE: { label: 'Obesidade grave', tone: 'red' },
};
const num = (v: any, casas = 1) => (v == null ? '—' : Number(v).toFixed(casas).replace('.', ','));

/** Lançamento da turma: peso e altura de cada aluno numa linha; valores fora do esperado pedem conferência. */
export function AntropometriaTurma({ classId }: { classId: string }) {
  const res = useRpc<any>('antropometria_turma', { class_id: classId });
  const qc = useQueryClient();
  const toast = useToast();
  const [vals, setVals] = useState<Record<string, { peso: string; altura: string }>>({});
  const [conferir, setConferir] = useState<any[]>([]);
  const [busy, setBusy] = useState(false);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const salvar = async (confirmar = false) => {
    setBusy(true);
    try {
      const medidas = Object.entries(vals).filter(([, v]) => v.peso || v.altura).map(([student_id, v]) => ({ student_id, ...v }));
      const r = await rpc<any>('antropometria_lancar', { class_id: classId, medidas, confirmar });
      setConferir(r.conferir ?? []);
      toast({ title: `${r.gravados} medida(s) registrada(s)`, description: r.conferir?.length ? `${r.conferir.length} para conferir antes de gravar.` : undefined, tone: r.conferir?.length ? 'warning' : 'success' });
      if (!r.conferir?.length) setVals({});
      qc.invalidateQueries({ queryKey: ['antropometria_turma'] });
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const set = (id: string, k: 'peso' | 'altura', v: string) => setVals({ ...vals, [id]: { peso: vals[id]?.peso ?? '', altura: vals[id]?.altura ?? '', [k]: v } });
  return (
    <div className="space-y-3">
      <p className="text-[13px] text-muted">Peso em kg (ex.: 24,5) e altura em cm (ex.: 121). Proposta: medir em março e em agosto. {d.referencia ? 'Classificação pela referência da OMS importada pela nutrição.' : 'A classificação do estado nutricional aparece quando a nutrição importar a tabela oficial da OMS.'}</p>
      {conferir.length > 0 && (
        <div className="space-y-1 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-950 ring-1 ring-amber-200">
          <b className="flex items-center gap-1"><AlertTriangle className="size-4" />Confira antes de gravar:</b>
          {conferir.map((c) => <p key={c.student_id}>{c.nome}: {c.motivo} (anterior: {num(c.anterior?.peso)} kg, {num(c.anterior?.altura)} cm em {fmtDate(c.anterior?.data)})</p>)}
          <Button size="sm" loading={busy} onClick={() => salvar(true)}>Está certo: gravar assim mesmo</Button>
        </div>
      )}
      <Card className="overflow-hidden">
        <Tabela colunas={`minmax(200px,1.6fr) 150px ${d.pode_lancar ? '110px 110px ' : ''}100px minmax(130px,1fr)`} largura={d.pode_lancar ? 860 : 640} rotulo="Peso e medidas da turma">
          <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Última medida</TCelula>{d.pode_lancar && <><TCelula>Peso (kg)</TCelula><TCelula>Altura (cm)</TCelula></>}<TCelula>IMC</TCelula><TCelula>Situação</TCelula></TCabecalho>
          {(d.alunos as any[]).map((a) => (
            <TLinha key={a.student_id} rotulo={a.nome} alerta={a.ultima?.conferir}>
              <TCelula fixa className="font-semibold">{a.nome}</TCelula>
              <TCelula>{a.ultima ? `${num(a.ultima.peso)} kg · ${num(a.ultima.altura)} cm · ${fmtDate(a.ultima.data)}` : <span className="text-muted">sem medida</span>}</TCelula>
              {d.pode_lancar && <>
                <TCelula livre><input inputMode="decimal" value={vals[a.student_id]?.peso ?? ''} onChange={(e) => set(a.student_id, 'peso', e.target.value)} className={`${inputCls} h-9`} aria-label={`Peso de ${a.nome}`} /></TCelula>
                <TCelula livre><input inputMode="decimal" value={vals[a.student_id]?.altura ?? ''} onChange={(e) => set(a.student_id, 'altura', e.target.value)} className={`${inputCls} h-9`} aria-label={`Altura de ${a.nome}`} /></TCelula>
              </>}
              <TCelula>{num(a.ultima?.imc)}</TCelula>
              <TCelula livre>{a.ultima?.classificacao ? <Badge tone={CLASSE_IMC[a.ultima.classificacao]?.tone}>{CLASSE_IMC[a.ultima.classificacao]?.label}</Badge> : <span className="text-[12px] text-muted">{d.referencia ? '—' : 'aguarda referência'}</span>}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      {d.pode_lancar && <Button icon={Save} loading={busy} disabled={!Object.values(vals).some((v) => v.peso || v.altura)} onClick={() => salvar(false)}>Gravar medidas</Button>}
    </div>
  );
}

/** Curva simples de evolução (peso e altura) para a ficha do aluno e para a família. */
function Evolucao({ medidas }: { medidas: any[] }) {
  if (medidas.length < 2) return null;
  const w = 320, h = 120, pad = 20;
  const xs = medidas.map((_, i) => pad + (i * (w - 2 * pad)) / (medidas.length - 1));
  const serie = (k: string) => {
    const v = medidas.map((m) => Number(m[k]));
    const min = Math.min(...v), max = Math.max(...v);
    return v.map((y, i) => `${xs[i]},${h - pad - ((y - min) / Math.max(max - min, 0.1)) * (h - 2 * pad)}`).join(' ');
  };
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-32 w-full max-w-md" role="img" aria-label="Evolução do peso e da altura">
      <polyline points={serie('altura')} fill="none" stroke="#7A24C5" strokeWidth="2.5" />
      <polyline points={serie('peso')} fill="none" stroke="#0A8F5B" strokeWidth="2.5" strokeDasharray="5 4" />
      {medidas.map((m, i) => <text key={i} x={xs[i]} y={h - 4} fontSize="9" textAnchor="middle" fill="#64748B">{fmtDate(m.data).slice(0, 5)}</text>)}
    </svg>
  );
}

export function AntropometriaView({ d, familia }: { d: any; familia?: boolean }) {
  const ms = (d.medidas ?? []) as any[];
  if (!ms.length) return <EmptyState compact title="Sem medidas registradas" body="A escola mede peso e altura duas vezes por ano." />;
  const ult = ms[ms.length - 1];
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-3 gap-2">
        <Kpi compact icon={Ruler} tone="purple" label="Altura" value={`${num(ult.altura)} cm`} sub={fmtDate(ult.data)} />
        <Kpi compact icon={Ruler} tone="green" label="Peso" value={`${num(ult.peso)} kg`} />
        <Kpi compact icon={Ruler} tone="blue" label="IMC" value={num(ult.imc)} />
      </div>
      {familia ? (ult.leitura && <p className="rounded-2xl bg-slate-50 p-3 text-[13.5px]">{ult.leitura}</p>)
        : ult.classificacao ? <p className="text-[13.5px]">Estado nutricional (OMS): <Badge tone={CLASSE_IMC[ult.classificacao]?.tone}>{CLASSE_IMC[ult.classificacao]?.label}</Badge> · escore z {num(ult.zscore, 2)}</p>
        : <p className="text-[12.5px] text-muted">Classificação aguardando a tabela oficial da OMS (importada pela nutrição).</p>}
      <Evolucao medidas={ms} />
      <p className="text-[12px] text-muted">Linha cheia: altura · tracejada: peso.</p>
      <ul className="space-y-0.5 text-[13px]">{[...ms].reverse().map((m) => <li key={m.id}>{fmtDate(m.data)} — {num(m.peso)} kg · {num(m.altura)} cm · IMC {num(m.imc)}</li>)}</ul>
    </div>
  );
}

export function AntropometriaAluno({ studentId }: { studentId: string }) {
  const res = useRpc<any>('antropometria_aluno', { student_id: studentId }, { retry: false });
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return <AntropometriaView d={res.data} />;
}

export function AntropometriaFamilia() {
  const res = useRpc<any[]>('familia_antropometria', {});
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <EmptyState title="Nenhuma criança matriculada" />;
  return <div className="space-y-5">{res.data.map((d) => <Section key={d.student_id} title={`Peso e altura · ${d.primeiro_nome}`}><AntropometriaView d={d} familia /></Section>)}</div>;
}

/** Painel da nutrição/unidade: cobertura do semestre, distribuição e quem acompanhar; importação da tabela oficial. */
export function AntropometriaPainel({ unitId }: { unitId: number | null }) {
  const res = useRpc<any>('antropometria_painel', { unit_id: unitId });
  const [importar, setImportar] = useState(false);
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const cobertura = d.alunos ? Math.round((100 * d.medidos_semestre) / d.alunos) : 0;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Ruler} tone="purple" label={`Medidos desde ${fmtDate(d.semestre_desde)}`} value={`${cobertura}%`} sub={`${fmtInt(d.medidos_semestre)} de ${fmtInt(d.alunos)} alunos`} />
        <Kpi compact icon={AlertTriangle} tone="amber" label="Medidas para conferir" value={fmtInt(d.conferir)} />
        <Kpi compact icon={ClipboardCheck} tone={d.referencia ? 'green' : 'red'} label="Referência OMS" value={d.referencia ? 'importada' : 'pendente'} sub={d.referencia_fonte ?? 'a nutrição importa a tabela oficial'} />
      </div>
      {d.pode_importar && <Button variant="secondary" icon={Upload} onClick={() => setImportar(true)}>Importar a tabela da OMS (IMC para a idade)</Button>}
      {d.referencia && Object.keys(d.distribuicao ?? {}).length > 0 && (
        <Card className="flex flex-wrap gap-2 p-3">{Object.entries(d.distribuicao).map(([k, n]) => <Badge key={k} tone={CLASSE_IMC[k]?.tone}>{CLASSE_IMC[k]?.label}: {fmtInt(n as number)}</Badge>)}</Card>
      )}
      <Card className="overflow-hidden">
        {d.unidades ? (
          <Tabela colunas="minmax(200px,1.5fr) 90px 90px 100px 90px" largura={620} rotulo="Cobertura por unidade">
            <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Alunos</TCelula><TCelula>Medidos</TCelula><TCelula>Cobertura</TCelula><TCelula>Alerta</TCelula></TCabecalho>
            {(d.unidades as any[]).map((u) => (
              <TLinha key={u.unit_id} rotulo={u.unidade} alerta={(u.cobertura ?? 0) < 50}><TCelula fixa>{u.unidade}</TCelula><TCelula>{fmtInt(u.alunos)}</TCelula><TCelula>{fmtInt(u.medidos)}</TCelula><TCelula>{u.cobertura ?? 0}%</TCelula><TCelula>{fmtInt(u.alerta)}</TCelula></TLinha>
            ))}
          </Tabela>
        ) : (
          <Tabela colunas="minmax(160px,1fr) 90px 90px" largura={420} rotulo="Cobertura por turma">
            <TCabecalho><TCelula fixa>Turma</TCelula><TCelula>Alunos</TCelula><TCelula>Medidos</TCelula></TCabecalho>
            {((d.turmas ?? []) as any[]).map((t) => <TLinha key={t.class_id} to={`/turmas/${t.class_id}/avaliacao?aba=medidas`} rotulo={t.turma}><TCelula fixa>{t.turma}</TCelula><TCelula>{t.alunos}</TCelula><TCelula>{t.medidos}</TCelula></TLinha>)}
          </Tabela>
        )}
      </Card>
      {(d.acompanhar as any[]).length > 0 && (
        <Section title="Acompanhar" subtitle="Medidas a conferir e crianças com magreza ou obesidade grave (com a referência importada).">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,1.5fr) minmax(140px,1fr) 80px 170px 110px" largura={760} rotulo="Acompanhar">
              <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>IMC</TCelula><TCelula>Situação</TCelula><TCelula>Medida</TCelula></TCabecalho>
              {(d.acompanhar as any[]).map((a) => (
                <TLinha key={a.student_id} to={`/alunos/${a.student_id}?aba=medidas`} rotulo={a.nome}>
                  <TCelula fixa>{a.nome}</TCelula><TCelula>{a.unidade}</TCelula><TCelula>{num(a.imc)}</TCelula>
                  <TCelula livre>{a.conferir ? <Badge tone="amber">conferir medida</Badge> : <Badge tone={CLASSE_IMC[a.classificacao]?.tone}>{CLASSE_IMC[a.classificacao]?.label}</Badge>}</TCelula><TCelula>{fmtDate(a.data)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
      <ImportarReferencia open={importar} onClose={() => setImportar(false)} />
    </div>
  );
}

function ImportarReferencia({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [texto, setTexto] = useState('');
  const [fonte, setFonte] = useState('OMS — IMC para a idade (WHO Child Growth Standards 2006 e Growth Reference 2007), tabelas LMS por mês');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('referencia_imc_importar', { texto, fonte });
      toast({ title: `${r.importadas} linha(s) importada(s)`, description: r.erros?.length ? `${r.erros.length} linha(s) com erro.` : 'As medidas foram reclassificadas.', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['antropometria_painel'] });
      onClose();
    } catch (e) {
      toast({ title: 'Não importado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} size="lg" title="Importar a referência da OMS" subtitle="Cole a tabela oficial: uma linha por sexo e idade em meses — sexo;idade_meses;L;M;S."
      footer={<Button block loading={busy} disabled={texto.trim().length < 10 || fonte.trim().length < 10} onClick={enviar}>Importar e reclassificar</Button>}>
      <div className="space-y-3 pt-1">
        <Field label="Fonte (publicação oficial)"><input value={fonte} onChange={(e) => setFonte(e.target.value)} className={inputCls} /></Field>
        <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={10} placeholder={'sexo;idade_meses;L;M;S\nM;61;-0,7387;15,2641;0,08390'} className={`${inputCls} h-auto py-3 font-mono text-[12.5px]`} />
        <p className="text-[12px] text-muted">Os valores vêm das tabelas da OMS publicadas para o IMC para a idade (0 a 5 anos e 5 a 19 anos). A classificação segue os pontos de corte do SISVAN.</p>
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ Patrimônio
const SIT_PAT: Record<string, { label: string; tone: 'green' | 'amber' | 'purple' | 'red' | 'gray' }> = {
  EM_USO: { label: 'Em uso', tone: 'green' }, EM_MANUTENCAO: { label: 'Em manutenção', tone: 'amber' }, EM_TRANSFERENCIA: { label: 'Em transferência', tone: 'purple' },
  AGUARDANDO_BAIXA: { label: 'Aguardando baixa', tone: 'red' }, BAIXADO: { label: 'Baixado', tone: 'gray' },
};
const EST: Record<string, string> = { NOVO: 'Novo', BOM: 'Bom', REGULAR: 'Regular', RUIM: 'Ruim', INSERVIVEL: 'Inservível' };
const EVT: Record<string, string> = {
  CADASTRO: 'Cadastro', TRANSFERENCIA_SOLICITADA: 'Transferência pedida', TRANSFERENCIA_RECEBIDA: 'Transferência recebida', TRANSFERENCIA_RECUSADA: 'Transferência recusada',
  TRANSFERENCIA_CANCELADA: 'Transferência cancelada', MANUTENCAO_ENVIO: 'Enviado ao conserto', MANUTENCAO_RETORNO: 'Voltou do conserto', BAIXA_SOLICITADA: 'Baixa pedida',
  BAIXA_APROVADA: 'Baixa aprovada', BAIXA_NEGADA: 'Baixa negada', INVENTARIO: 'Inventário', ESTADO: 'Estado', LOCAL: 'Local',
};

export function PatrimonioAba({ unitId }: { unitId: number | null }) {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const [sit, setSit] = useState('');
  const [aberto, setAberto] = useState<string | null>(null);
  const [inv, setInv] = useState(false);
  const res = useRpc<any>('patrimonio_lista', { unit_id: unitId, q: dq || null, situacao: sit || null });
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const r = d.resumo;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi compact icon={ClipboardCheck} tone="blue" label="Bens patrimoniais" value={fmtInt(r.itens)} sub={fmtBRL(r.valor)} />
        <Kpi compact icon={Wrench} tone="amber" label="Em manutenção" value={fmtInt(r.em_manutencao)} onClick={() => setSit('EM_MANUTENCAO')} />
        <Kpi compact icon={ArrowRightLeft} tone="purple" label="Em transferência" value={fmtInt(r.em_transferencia)} onClick={() => setSit('EM_TRANSFERENCIA')} />
        <Kpi compact icon={PackageX} tone="red" label="Aguardando baixa" value={fmtInt(r.aguardando_baixa)} onClick={() => setSit('AGUARDANDO_BAIXA')} />
        {d.inventario && <Kpi compact icon={CheckCheck} tone="green" label={`Inventário ${d.inventario.ano}`} value={d.inventario.situacao === 'CONCLUIDO' ? 'concluído' : `${d.inventario.conferidos}/${d.inventario.itens}`}
          sub={d.inventario.nao_localizados ? `${d.inventario.nao_localizados} não localizado(s)` : undefined} onClick={() => setInv(true)} />}
      </div>
      {!d.inventario && unitId && d.pode_editar && <Button variant="secondary" icon={ClipboardCheck} onClick={() => setInv(true)}>Inventário do ano</Button>}
      {(d.a_receber as any[]).length > 0 && (
        <Section title="A receber" subtitle="Transferências que aguardam o aceite desta unidade.">
          <div className="space-y-1.5">{(d.a_receber as any[]).map((m) => (
            <button key={m.id} type="button" onClick={() => setAberto(m.id)} className="flex w-full items-center gap-2 rounded-2xl bg-purple-50 p-2.5 text-left text-[13.5px] ring-1 ring-purple-100">
              <ArrowRightLeft className="size-4 text-purple-700" /><b>{m.patrimonio}</b> {m.nome} <span className="text-muted">· de {m.transferencia?.origem}</span>
            </button>))}</div>
        </Section>
      )}
      {d.baixas && (d.baixas as any[]).length > 0 && (
        <Section title="Baixas para decidir" subtitle="Pedidos das unidades com laudo; a decisão fica no histórico do bem.">
          <div className="space-y-1.5">{(d.baixas as any[]).map((m) => (
            <button key={m.id} type="button" onClick={() => setAberto(m.id)} className="flex w-full items-center gap-2 rounded-2xl bg-red-50 p-2.5 text-left text-[13.5px] ring-1 ring-red-100">
              <PackageX className="size-4 text-red-700" /><b>{m.patrimonio}</b> {m.nome} <span className="text-muted">· {m.unidade} · {m.baixa_motivo}</span>
            </button>))}</div>
        </Section>
      )}
      <Card className="flex flex-wrap items-center gap-2 p-3">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome, número ou local…" className={`${inputCls} h-10 max-w-xs`} aria-label="Buscar bem" />
        <Chip active={!sit} onClick={() => setSit('')}>Todos</Chip>
        {Object.entries(SIT_PAT).filter(([k]) => k !== 'BAIXADO').map(([k, v]) => <Chip key={k} active={sit === k} onClick={() => setSit(k)}>{v.label}</Chip>)}
      </Card>
      <Card className="overflow-hidden">
        <Tabela colunas="120px minmax(200px,1.5fr) 110px 150px minmax(140px,1fr) 120px" largura={900} rotulo="Patrimônio">
          <TCabecalho><TCelula fixa>Patrimônio</TCelula><TCelula>Bem</TCelula><TCelula>Estado</TCelula><TCelula>Situação</TCelula><TCelula>{unitId ? 'Local' : 'Unidade'}</TCelula><TCelula>Valor</TCelula></TCabecalho>
          {(d.itens as any[]).map((m) => (
            <TLinha key={m.id} onClick={() => setAberto(m.id)} rotulo={m.nome} alerta={m.situacao === 'AGUARDANDO_BAIXA'}>
              <TCelula fixa className="font-mono text-[12.5px]">{m.patrimonio}{m.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>
              <TCelula>{m.nome}</TCelula><TCelula>{EST[m.estado] ?? m.estado}</TCelula>
              <TCelula livre><Badge tone={SIT_PAT[m.situacao]?.tone}>{SIT_PAT[m.situacao]?.label}</Badge></TCelula>
              <TCelula>{unitId ? m.localizacao ?? '—' : m.unidade}</TCelula><TCelula>{fmtBRL(m.valor)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <BemSheet id={aberto} onClose={() => setAberto(null)} />
      <InventarioSheet open={inv} unitId={unitId} onClose={() => setInv(false)} />
    </div>
  );
}

function BemSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const res = useRpc<any>('patrimonio_detalhe', { id }, { enabled: !!id });
  const qc = useQueryClient();
  const toast = useToast();
  const [acao, setAcao] = useState('');
  const [txt, setTxt] = useState('');
  const [destino, setDestino] = useState('');
  const [estado, setEstado] = useState('BOM');
  const [custo, setCusto] = useState('');
  const [local, setLocal] = useState('');
  const [busy, setBusy] = useState(false);
  const m = res.data;
  const fazer = async (args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc('patrimonio_acao', { id, ...args });
      toast({ title: msg, tone: 'success' });
      setAcao(''); setTxt(''); setCusto('');
      qc.invalidateQueries({ queryKey: ['patrimonio_lista'] });
      qc.invalidateQueries({ queryKey: ['patrimonio_detalhe'] });
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const acoes = m ? [
    ...(m.pode_mover && m.situacao === 'EM_USO' ? [{ value: 'TRANSFERIR', label: 'Transferir' }, { value: 'MANUTENCAO_ENVIO', label: 'Enviar ao conserto' }] : []),
    ...(m.pode_mover && m.situacao === 'EM_MANUTENCAO' ? [{ value: 'MANUTENCAO_RETORNO', label: 'Voltou do conserto' }] : []),
    ...(m.pode_mover ? [{ value: 'ATUALIZAR', label: 'Estado e local' }, { value: 'SOLICITAR_BAIXA', label: 'Pedir baixa' }] : []),
  ] : [];
  return (
    <Sheet open={!!id} onClose={() => { setAcao(''); onClose(); }} size="lg" title={m ? `${m.patrimonio} · ${m.nome}` : 'Bem'} subtitle={m ? `${m.unidade} · ${m.localizacao ?? 'local não informado'}` : ''}>
      {!m ? <SkeletonList rows={3} /> : (
        <div className="space-y-4 pt-1">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={SIT_PAT[m.situacao]?.tone}>{SIT_PAT[m.situacao]?.label}</Badge><Badge tone="gray">Estado: {EST[m.estado] ?? m.estado}</Badge>
            {m.valor != null && <Badge tone="blue">{fmtBRL(m.valor)}</Badge>}{m.adquirido_em && <Badge tone="gray">desde {fmtDate(m.adquirido_em)}</Badge>}
          </div>
          {m.nota_fiscal && <p className="text-[12.5px] text-muted">{m.nota_fiscal} · {m.fornecedor}</p>}
          {m.transferencia && (
            <div className="rounded-2xl bg-purple-50 p-3 text-[13.5px] ring-1 ring-purple-100">
              Transferência para <b>{m.transferencia.destino}</b>: {m.transferencia.motivo}
              {m.pode_receber && (
                <div className="mt-2 flex flex-wrap gap-2">
                  <input value={local} onChange={(e) => setLocal(e.target.value)} placeholder="Onde vai ficar" className={`${inputCls} h-10 max-w-xs`} />
                  <Button size="sm" loading={busy} onClick={() => fazer({ acao: 'RECEBER', localizacao: local }, 'Bem recebido')}>Receber</Button>
                  <Button size="sm" variant="secondary" loading={busy} disabled={txt.trim().length < 5} onClick={() => fazer({ acao: 'RECUSAR', texto: txt }, 'Transferência recusada')}>Recusar</Button>
                  <input value={txt} onChange={(e) => setTxt(e.target.value)} placeholder="Motivo da recusa" className={`${inputCls} h-10 max-w-xs`} />
                </div>
              )}
              {m.pode_mover && m.situacao === 'EM_TRANSFERENCIA' && <Button size="sm" variant="ghost" className="mt-2" loading={busy} onClick={() => fazer({ acao: 'CANCELAR_TRANSFERENCIA' }, 'Transferência cancelada')}>Cancelar a transferência</Button>}
            </div>
          )}
          {m.pode_decidir_baixa && (
            <div className="space-y-2 rounded-2xl bg-red-50 p-3 text-[13.5px] ring-1 ring-red-100">
              <b>Pedido de baixa:</b> {m.baixa_motivo}
              <textarea value={txt} onChange={(e) => setTxt(e.target.value)} rows={2} placeholder="Parecer" className={`${inputCls} h-auto py-2`} />
              <div className="flex gap-2">
                <Button size="sm" loading={busy} disabled={txt.trim().length < 10} onClick={() => fazer({ acao: 'DECIDIR_BAIXA', aprovar: true, texto: txt }, 'Baixa aprovada')}>Aprovar a baixa</Button>
                <Button size="sm" variant="secondary" loading={busy} disabled={txt.trim().length < 10} onClick={() => fazer({ acao: 'DECIDIR_BAIXA', aprovar: false, texto: txt }, 'Baixa negada')}>Negar</Button>
              </div>
            </div>
          )}
          {acoes.length > 0 && (
            <div className="space-y-2 rounded-3xl bg-slate-50 p-3 ring-1 ring-line">
              <div className="no-scrollbar overflow-x-auto"><Segmented value={acao} onChange={setAcao} items={[{ value: '', label: 'Ações' }, ...acoes]} /></div>
              {acao === 'TRANSFERIR' && (
                <select value={destino} onChange={(e) => setDestino(e.target.value)} className={inputCls}>
                  <option value="">Almoxarifado central (devolução)</option>{((m.unidades ?? []) as any[]).map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
                </select>
              )}
              {['MANUTENCAO_RETORNO', 'ATUALIZAR'].includes(acao) && (
                <div className="grid grid-cols-2 gap-2">
                  <select value={estado} onChange={(e) => setEstado(e.target.value)} className={inputCls}>{Object.entries(EST).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
                  {acao === 'MANUTENCAO_RETORNO' ? <input value={custo} onChange={(e) => setCusto(e.target.value)} inputMode="decimal" placeholder="Custo (R$)" className={inputCls} />
                    : <input value={local} onChange={(e) => setLocal(e.target.value)} placeholder="Novo local" className={inputCls} />}
                </div>
              )}
              {acao && acao !== 'ATUALIZAR' && <textarea value={txt} onChange={(e) => setTxt(e.target.value)} rows={2} placeholder={acao === 'TRANSFERIR' ? 'Motivo da transferência' : acao === 'SOLICITAR_BAIXA' ? 'Por que é inservível (laudo)' : 'Descrição'} className={`${inputCls} h-auto py-2`} />}
              {acao && <Button block loading={busy} onClick={() => fazer({ acao, texto: txt, destino_unit: destino || null, estado, custo: custo.replace(',', '.') || null, localizacao: local || null }, 'Registrado')}>Registrar</Button>}
            </div>
          )}
          <Section title="Histórico">
            <ol className="space-y-1.5 text-[13px]">
              {((m.eventos ?? []) as any[]).map((e, i) => (
                <li key={i} className="rounded-2xl bg-white p-2 ring-1 ring-line"><b>{EVT[e.tipo] ?? e.tipo}</b> · {fmtDateTime(e.em)} · {e.autor}
                  {e.destino && ` · para ${e.destino}`}{e.custo != null && ` · ${fmtBRL(e.custo)}`}{e.texto && <p className="text-muted">{e.texto}</p>}</li>
              ))}
            </ol>
          </Section>
        </div>
      )}
    </Sheet>
  );
}

function InventarioSheet({ open, unitId, onClose }: { open: boolean; unitId: number | null; onClose: () => void }) {
  const res = useRpc<any>('inventario', { acao: 'VER', unit_id: unitId }, { enabled: open });
  const qc = useQueryClient();
  const toast = useToast();
  const [marcas, setMarcas] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const d = res.data;
  const fazer = async (args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc('inventario', args);
      toast({ title: msg, tone: 'success' });
      setMarcas({});
      qc.invalidateQueries({ queryKey: ['inventario'] });
      qc.invalidateQueries({ queryKey: ['patrimonio_lista'] });
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const itens = (d?.itens ?? []) as any[];
  return (
    <Sheet open={open} onClose={onClose} size="lg" title={d?.aberto ? `Inventário ${d.ano}` : 'Inventário do ano'} subtitle={d?.aberto ? `${d.situacao === 'CONCLUIDO' ? 'Concluído' : 'Em andamento'} · ${itens.filter((i) => i.localizado != null).length}/${itens.length} conferidos` : ''}>
      {!d ? <SkeletonList rows={4} /> : !d.aberto ? (
        <div className="space-y-3 pt-1"><p className="text-[13.5px]">O inventário lista todos os bens da unidade para conferir se estão no lugar e em que estado.</p>
          {d.pode_abrir && <Button loading={busy} onClick={() => fazer({ acao: 'ABRIR' }, 'Inventário aberto')}>Abrir o inventário de {new Date().getFullYear()}</Button>}</div>
      ) : (
        <div className="space-y-3 pt-1">
          <ul className="space-y-1">
            {itens.map((it) => {
              const marca = marcas[it.material_id] ?? it.localizado;
              return (
                <li key={it.material_id} className={clsx('flex flex-wrap items-center gap-2 rounded-2xl p-2 text-[13px] ring-1', marca === false ? 'bg-red-50 ring-red-100' : marca ? 'bg-green-50 ring-green-100' : 'bg-white ring-line')}>
                  <span className="font-mono text-[12px]">{it.patrimonio}</span><span className="min-w-0 flex-1">{it.nome} <span className="text-muted">· {it.local_cadastro ?? '—'}</span></span>
                  {d.situacao === 'ABERTO' ? (
                    <span className="flex gap-1">
                      <Chip active={marca === true} onClick={() => setMarcas({ ...marcas, [it.material_id]: true })}>Localizado</Chip>
                      <Chip active={marca === false} onClick={() => setMarcas({ ...marcas, [it.material_id]: false })}>Não achei</Chip>
                    </span>
                  ) : <Badge tone={it.localizado ? 'green' : 'red'}>{it.localizado ? 'localizado' : 'não localizado'}</Badge>}
                </li>
              );
            })}
          </ul>
          {d.situacao === 'ABERTO' && (
            <div className="flex flex-wrap gap-2">
              <Button variant="secondary" loading={busy} disabled={!Object.keys(marcas).length}
                onClick={() => fazer({ acao: 'CONFERIR', itens: Object.entries(marcas).map(([material_id, localizado]) => ({ material_id, localizado, estado: itens.find((i) => i.material_id === material_id)?.estado_cadastro })) }, 'Conferência salva')}>
                Salvar conferência
              </Button>
              <Button loading={busy} disabled={itens.some((i) => i.localizado == null)} onClick={() => fazer({ acao: 'CONCLUIR' }, 'Inventário concluído')}>Concluir</Button>
            </div>
          )}
        </div>
      )}
    </Sheet>
  );
}
