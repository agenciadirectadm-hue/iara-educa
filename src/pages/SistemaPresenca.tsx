import { useMemo, useState } from 'react';
import clsx from 'clsx';
import { ArrowLeft, Download, Info, Printer, Search, TriangleAlert } from 'lucide-react';
import { useRpc, useRpcMutation } from '@/lib/hooks';
import { rpc } from '@/lib/api';
import { fmt1, fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, EmptyState, ErrorState, Meter, PageHeader, Section, Segmented, SkeletonList } from '@/components/ui';

type Mes = { mes: string; dias: number; faltas: number; justificadas: number; integral: boolean; futuro: boolean; parcial: boolean; sem_chamada: number; pct: number | null };
type Aluno = {
  student_id: string; nome: string; nascimento: string; idade: number; turma: string | null; serie: string | null; minimo: number; meses: Mes[];
  situacao: 'ATIVO' | 'TRANSFERIDO' | 'SAIU'; destino: { unidade: string; inep: string | null } | null;
  motivo: { categoria: string; texto: string; detalhe: string } | null; lancado_em: string | null;
};
type Unidade = {
  unidade: { id: number; nome: string; nome_completo: string; inep: string | null }; ano: number; periodo: number; meses: string[]; alunos: Aluno[];
  resumo: { alunos: number; abaixo: number; lancados: number; transferidos: number }; turmas_sem_chamada: string[];
  dias_sem_aula: { titulo: string; tipo: string; inicio: string; fim: string }[]; nota: string;
};
type Periodos = {
  ano: number; atual: { ano: number; periodo: number }; minimos: { de_4_a_5: number; de_6_a_17: number }; rede: boolean;
  unidade: { id: number; nome: string } | null; periodos: { periodo: number; rotulo: string; situacao: 'ENCERRADO' | 'EM_ANDAMENTO' | 'FUTURO' }[];
};
type Rede = { unidades: { id: number; nome: string; tipo: string; alunos: number; abaixo: number; lancados: number }[]; total: { alunos: number; abaixo: number; lancados: number } };

const CURTO = ['', 'Fev–mar', 'Abr–mai', 'Jun–jul', 'Ago–set', 'Out–nov'];
const nomeMes = (m: string) => new Date(Number(m.slice(0, 4)), Number(m.slice(5, 7)) - 1, 15).toLocaleDateString('pt-BR', { month: 'long' });
const pctTexto = (x: Mes) => (x.integral ? '100% (recesso)' : x.pct == null ? (x.futuro ? 'a começar' : x.parcial ? 'ainda sem chamada' : 'sem chamada') : `${fmt1(x.pct)}%${x.parcial ? '*' : ''}`);
const abaixo = (x: Mes, minimo: number) => !x.integral && x.pct != null && x.pct < minimo;
const SITUACAO: Record<Aluno['situacao'], string> = { ATIVO: 'Ativo', TRANSFERIDO: 'Transferido', SAIU: 'Saiu da rede' };

/** Sistema Presença (MEC): frequência dos alunos do Bolsa Família por período, calculada da chamada diária, pronta para lançar
 * no sistema do MEC, com o motivo sugerido para quem ficou abaixo do mínimo e o controle de quem já foi lançado. */
export default function SistemaPresenca() {
  const per = useRpc<Periodos>('presenca_periodos', {});
  const [periodo, setPeriodo] = useState<number | null>(null);
  const [unidade, setUnidade] = useState<number | null>(null);
  if (per.isLoading) return <SkeletonList rows={6} />;
  if (per.error) return <ErrorState error={per.error} onRetry={() => per.refetch()} />;
  const p = per.data!;
  const atual = periodo ?? p.atual.periodo;
  const ano = p.atual.ano;
  const verUnidade = !p.rede || unidade != null;

  return (
    <div>
      <PageHeader eyebrow={p.unidade?.nome ?? 'Secretaria de Educação'} title="Sistema Presença · Bolsa Família"
        subtitle="A frequência de cada aluno do Bolsa Família no período, calculada da chamada diária, pronta para lançar no Sistema Presença do MEC." />
      <Segmented value={String(atual)} onChange={(v) => setPeriodo(Number(v))}
        items={p.periodos.map((x) => ({ value: String(x.periodo), label: `${CURTO[x.periodo]}${x.situacao === 'EM_ANDAMENTO' ? ' · agora' : ''}` }))} />
      <p className="mt-2 text-[12.5px] text-muted">
        {p.periodos.find((x) => x.periodo === atual)?.rotulo} de {ano} · mínimo de {p.minimos.de_4_a_5}% de 4 a 5 anos e {p.minimos.de_6_a_17}% de 6 a 17 anos (Lei 14.601/2023).
      </p>
      <div className="mt-3">
        {verUnidade
          ? <ListaUnidade ano={ano} periodo={atual} unitId={unidade} onVoltar={p.rede ? () => setUnidade(null) : undefined} />
          : <VisaoRede ano={ano} periodo={atual} onAbrir={setUnidade} />}
      </div>
    </div>
  );
}

function VisaoRede({ ano, periodo, onAbrir }: { ano: number; periodo: number; onAbrir: (id: number) => void }) {
  const r = useRpc<Rede>('presenca_rede', { ano, periodo });
  const [q, setQ] = useState('');
  if (r.isLoading) return <SkeletonList rows={8} />;
  if (r.error) return <ErrorState error={r.error} onRetry={() => r.refetch()} />;
  const d = r.data!;
  const lista = d.unidades.filter((u) => !q || u.nome.toLowerCase().includes(q.toLowerCase()));
  return (
    <>
      <div className="mb-3 grid grid-cols-3 gap-2">
        <Card className="p-3"><div className="text-[22px] font-extrabold tabular">{fmtInt(d.total.alunos)}</div><div className="text-[12px] text-muted">alunos acompanhados</div></Card>
        <Card className="p-3"><div className="text-[22px] font-extrabold tabular text-red-700">{fmtInt(d.total.abaixo)}</div><div className="text-[12px] text-muted">abaixo do mínimo</div></Card>
        <Card className="p-3"><div className="text-[22px] font-extrabold tabular text-green-700">{fmtInt(d.total.lancados)}</div><div className="text-[12px] text-muted">já lançados no MEC</div></Card>
      </div>
      <Section title="Unidades" subtitle="As que mais faltam lançar aparecem primeiro. Toque para abrir a lista da unidade.">
        <label className="mb-2 flex items-center gap-2 rounded-2xl bg-white px-3 ring-1 ring-line">
          <Search className="size-4 text-subtle" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar unidade" aria-label="Buscar unidade" className="h-10 flex-1 bg-transparent text-[14px] outline-none" />
        </label>
        <Card className="divide-y divide-line">
          {lista.map((u) => (
            <button key={u.id} type="button" onClick={() => onAbrir(u.id)} className="flex w-full items-center gap-3 px-3 py-2.5 text-left hover:bg-slate-50">
              <div className="min-w-0 flex-1">
                <div className="truncate text-[14px] font-semibold">{u.nome}</div>
                <div className="text-[12px] text-muted">{fmtInt(u.alunos)} alunos · {u.abaixo > 0 ? <span className="font-semibold text-red-700">{fmtInt(u.abaixo)} abaixo do mínimo</span> : 'nenhum abaixo do mínimo'}</div>
              </div>
              <div className="w-28 shrink-0">
                <Meter value={u.lancados} max={Math.max(u.alunos, 1)} tone={u.lancados >= u.alunos ? 'green' : 'purple'} />
                <div className="mt-0.5 text-right text-[11.5px] text-muted tabular">{fmtInt(u.lancados)}/{fmtInt(u.alunos)} lançados</div>
              </div>
            </button>
          ))}
          {lista.length === 0 && <EmptyState compact title="Nenhuma unidade com alunos do Bolsa Família neste filtro." />}
        </Card>
      </Section>
    </>
  );
}

function ListaUnidade({ ano, periodo, unitId, onVoltar }: { ano: number; periodo: number; unitId: number | null; onVoltar?: () => void }) {
  const args = { ano, periodo, ...(unitId ? { unit_id: unitId } : {}) };
  const u = useRpc<Unidade>('presenca_unidade', args);
  const lancar = useRpcMutation('presenca_lancar', ['presenca_unidade', 'presenca_rede']);
  const [filtro, setFiltro] = useState<'todos' | 'abaixo' | 'falta'>('todos');
  const [q, setQ] = useState('');
  const [baixando, setBaixando] = useState(false);
  const lista = useMemo(() => (u.data?.alunos ?? []).filter((a) =>
    (filtro === 'todos' || (filtro === 'abaixo' ? !!a.motivo : !a.lancado_em)) && (!q || a.nome.toLowerCase().includes(q.toLowerCase()))), [u.data, filtro, q]);

  if (u.isLoading) return <SkeletonList rows={8} />;
  if (u.error) return <ErrorState error={u.error} onRetry={() => u.refetch()} />;
  const d = u.data!;
  const parcial = d.alunos.some((a) => a.meses.some((m) => m.parcial));

  async function baixar() {
    setBaixando(true);
    try {
      const x = await rpc<Unidade>('presenca_unidade', { ...args, exportar: true });
      const [m1, m2] = x.meses.map(nomeMes);
      const cab = ['Aluno', 'Nascimento', 'Turma', 'Série', 'Situação', 'Escola de destino', 'INEP de destino', 'Mínimo %',
        `${m1} %`, `${m1} faltas`, `${m2} %`, `${m2} faltas`, 'Abaixo do mínimo', 'Motivo sugerido', 'Detalhe', 'Lançado no Sistema Presença em'];
      const lin = x.alunos.map((a) => [a.nome, fmtDate(a.nascimento), a.turma ?? '', a.serie ?? '', SITUACAO[a.situacao], a.destino?.unidade ?? '', a.destino?.inep ?? '', a.minimo,
        ...a.meses.flatMap((m) => [m.integral ? '100' : m.pct == null ? '' : String(m.pct).replace('.', ','), m.faltas]),
        a.motivo ? 'sim' : 'não', a.motivo?.texto ?? '', a.motivo?.detalhe ?? '', a.lancado_em ? fmtDateTime(a.lancado_em) : '']);
      const csv = [cab, ...lin].map((l) => l.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(';')).join('\r\n');
      const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
      const link = Object.assign(document.createElement('a'), { href: url, download: `presenca_${x.unidade.nome.replace(/\W+/g, '_')}_${ano}_${periodo}.csv` });
      link.click();
      URL.revokeObjectURL(url);
    } finally { setBaixando(false); }
  }

  function imprimir() {
    const [m1, m2] = d.meses.map(nomeMes);
    const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));
    const linhas = d.alunos.map((a) => `<tr><td>${esc(a.nome)}<br><small>${fmtDate(a.nascimento)} · ${esc(a.turma ?? '')}</small></td>`
      + a.meses.map((m) => `<td class="${abaixo(m, a.minimo) ? 'baixa' : ''}">${pctTexto(m)}</td>`).join('')
      + `<td>${a.motivo ? esc(a.motivo.texto) : ''}</td><td>${a.situacao === 'ATIVO' ? '' : esc(SITUACAO[a.situacao] + (a.destino ? ` → ${a.destino.unidade} (INEP ${a.destino.inep ?? '—'})` : ''))}</td><td class="caixa"></td></tr>`).join('');
    const w = window.open('', '_blank');
    if (!w) return;
    w.document.write(`<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Sistema Presença · ${esc(d.unidade.nome)}</title><style>
      body{font:12px Arial,sans-serif;margin:16mm} h1{font-size:16px;margin:0} p{margin:4px 0 10px;color:#444}
      table{width:100%;border-collapse:collapse} th,td{border:1px solid #bbb;padding:4px 6px;text-align:left;vertical-align:top}
      th{background:#f1f1f1} td.baixa{color:#b00;font-weight:bold} td.caixa{width:22px} small{color:#666}
      @page{size:A4 landscape;margin:10mm}</style></head><body>
      <h1>Sistema Presença · Bolsa Família — ${esc(d.unidade.nome_completo)}${d.unidade.inep ? ` (INEP ${d.unidade.inep})` : ''}</h1>
      <p>${CURTO[periodo]} de ${ano} · ${d.resumo.alunos} alunos · ${d.resumo.abaixo} abaixo do mínimo · gerado pelo IARA Educa em ${new Date().toLocaleString('pt-BR')}</p>
      <table><thead><tr><th>Aluno</th><th>${m1}</th><th>${m2}</th><th>Motivo sugerido (escolher o código no Sistema Presença)</th><th>Situação</th><th>✓</th></tr></thead><tbody>${linhas}</tbody></table>
      <p>${esc(d.nota)}</p></body></html>`);
    w.document.close();
    w.focus();
    w.print();
  }

  return (
    <>
      {onVoltar && <Button size="sm" variant="ghost" icon={ArrowLeft} onClick={onVoltar} className="mb-2">Todas as unidades</Button>}
      <div className="mb-3 flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 className="font-display text-[18px] font-extrabold">{d.unidade.nome}</h2>
          <div className="text-[12.5px] text-muted">{d.unidade.inep ? `INEP ${d.unidade.inep}` : 'Sem código INEP no cadastro'}</div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="secondary" icon={Printer} onClick={imprimir} disabled={!d.alunos.length}>Imprimir lista</Button>
          <Button size="sm" variant="secondary" icon={Download} loading={baixando} onClick={baixar} disabled={!d.alunos.length}>Baixar planilha</Button>
        </div>
      </div>

      <div className="mb-3 grid grid-cols-3 gap-2">
        <Card className="p-3"><div className="text-[22px] font-extrabold tabular">{fmtInt(d.resumo.alunos)}</div><div className="text-[12px] text-muted">alunos do Bolsa Família</div></Card>
        <Card className="p-3"><div className="text-[22px] font-extrabold tabular text-red-700">{fmtInt(d.resumo.abaixo)}</div><div className="text-[12px] text-muted">abaixo do mínimo (pedem motivo)</div></Card>
        <Card className="p-3">
          <div className="text-[22px] font-extrabold tabular text-green-700">{fmtInt(d.resumo.lancados)}<span className="text-[14px] text-muted">/{fmtInt(d.resumo.alunos)}</span></div>
          <Meter value={d.resumo.lancados} max={Math.max(d.resumo.alunos, 1)} tone="green" className="mt-1" />
          <div className="mt-0.5 text-[12px] text-muted">já lançados no MEC</div>
        </Card>
      </div>

      {d.turmas_sem_chamada.length > 0 && (
        <p role="alert" className="mb-2 flex items-start gap-2 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-900">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          Dias letivos sem chamada registrada em {d.turmas_sem_chamada.length} turma(s) ({d.turmas_sem_chamada.slice(0, 6).join(', ')}{d.turmas_sem_chamada.length > 6 ? '…' : ''}). Complete a chamada antes de lançar.
        </p>
      )}
      {parcial && <p className="mb-2 text-[12.5px] text-muted">* Mês em andamento: o percentual ainda vai mudar até o fim do mês.</p>}

      <div className="mb-2 flex flex-wrap items-center gap-2">
        <Segmented value={filtro} onChange={(v) => setFiltro(v as typeof filtro)}
          items={[{ value: 'todos', label: `Todos (${d.alunos.length})` }, { value: 'abaixo', label: `Abaixo do mínimo (${d.resumo.abaixo})` }, { value: 'falta', label: `Falta lançar (${d.resumo.alunos - d.resumo.lancados})` }]} />
        <label className="flex min-w-[200px] flex-1 items-center gap-2 rounded-2xl bg-white px-3 ring-1 ring-line">
          <Search className="size-4 text-subtle" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar aluno" aria-label="Buscar aluno" className="h-10 flex-1 bg-transparent text-[14px] outline-none" />
        </label>
      </div>

      <Card className="divide-y divide-line">
        <div className="hidden grid-cols-[1.6fr_0.6fr_0.6fr_1.6fr_auto] gap-3 px-3 py-2 text-[11.5px] font-bold uppercase tracking-wide text-subtle md:grid">
          <span>Aluno</span><span className="capitalize">{nomeMes(d.meses[0])}</span><span className="capitalize">{nomeMes(d.meses[1])}</span><span>Motivo sugerido</span><span>Lançado</span>
        </div>
        {lista.map((a) => (
          <div key={a.student_id} className="grid grid-cols-2 gap-x-3 gap-y-1 px-3 py-2.5 md:grid-cols-[1.6fr_0.6fr_0.6fr_1.6fr_auto] md:items-center">
            <div className="col-span-2 min-w-0 md:col-span-1">
              <div className="truncate text-[14px] font-semibold">{a.nome}</div>
              <div className="text-[12px] text-muted">
                {fmtDate(a.nascimento)} · {a.idade} anos · {a.turma ?? 'sem turma'} · mínimo {a.minimo}%
                {a.situacao !== 'ATIVO' && <> · <b className="text-ink-2">{SITUACAO[a.situacao]}{a.destino ? ` → ${a.destino.unidade}${a.destino.inep ? ` (INEP ${a.destino.inep})` : ''}` : ''}</b></>}
              </div>
            </div>
            {a.meses.map((m) => (
              <div key={m.mes} className="text-[13.5px]">
                <span className="text-[11px] capitalize text-muted md:hidden">{nomeMes(m.mes)}: </span>
                <span className={clsx('font-semibold tabular', abaixo(m, a.minimo) ? 'text-red-700' : m.pct == null && !m.integral ? 'text-muted' : 'text-ink')}>{pctTexto(m)}</span>
                {m.faltas > 0 && <span className="block text-[11.5px] text-muted">{m.faltas} falta(s){m.justificadas ? `, ${m.justificadas} justif.` : ''}</span>}
              </div>
            ))}
            <div className="col-span-2 text-[13px] md:col-span-1">
              {a.motivo ? (
                <>
                  <Badge tone={a.motivo.categoria === 'BUSCA_ATIVA' ? 'red' : a.motivo.categoria === 'SEM_JUSTIFICATIVA' ? 'amber' : 'purple'}>{a.motivo.texto}</Badge>
                  <div className="mt-0.5 text-[11.5px] text-muted">{a.motivo.detalhe}</div>
                </>
              ) : <span className="text-[12.5px] text-muted">Dentro do mínimo</span>}
            </div>
            <label className="col-span-2 flex items-center gap-2 text-[13px] md:col-span-1">
              <input type="checkbox" className="size-5 accent-green-700" checked={!!a.lancado_em} disabled={lancar.isPending}
                onChange={(e) => lancar.mutate({ student_id: a.student_id, ano, periodo, lancado: e.target.checked })} aria-label={`Lançado no Sistema Presença: ${a.nome}`} />
              <span className="md:sr-only">{a.lancado_em ? `Lançado em ${fmtDateTime(a.lancado_em)}` : 'Marcar como lançado'}</span>
            </label>
          </div>
        ))}
        {lista.length === 0 && <EmptyState compact title={d.alunos.length ? 'Ninguém neste filtro.' : 'Nenhum aluno do Bolsa Família nesta unidade.'} />}
      </Card>
      {lancar.error && <p role="alert" className="mt-2 text-[13px] font-semibold text-red-700">{lancar.error.message}</p>}

      <div className="mt-3 space-y-1.5 text-[12.5px] text-muted">
        {d.dias_sem_aula.length > 0 && (
          <p>Dias sem aula no período (não contam): {d.dias_sem_aula.map((x) => `${x.titulo} (${fmtDate(x.inicio)}${x.fim !== x.inicio ? ` a ${fmtDate(x.fim)}` : ''})`).join('; ')}.</p>
        )}
        <p className="flex items-start gap-1.5"><Info className="mt-0.5 size-3.5 shrink-0" />{d.nota} Greve, calamidade ou reforma que interrompa as aulas se registra no Sistema Presença como situação coletiva.</p>
      </div>
    </>
  );
}
