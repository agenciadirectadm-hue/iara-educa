// Ocorrências — gestão: indicadores (solução, prazos, turmas, idade, assuntos e violência, com a leitura de padrão)
// e os modelos de resposta à família (inclusão, alteração com versão e exclusão).
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Clock, FilePlus2, GitBranch, Hourglass, Pencil, ShieldAlert, Trash2, Undo2, UsersRound } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { MOMENTO_MODELO, PADRAO_OCORRENCIA, TIPO_OCORRENCIA, VIOLENCIA } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Kpi, Meter, Section, SkeletonList, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';

function Barras({ itens, rotulo, valor = 'n', destaque }: { itens: any[]; rotulo: (x: any) => string; valor?: string; destaque?: (x: any) => number | null }) {
  const max = Math.max(1, ...itens.map((x) => Number(x[valor] ?? 0)));
  if (!itens.length) return <EmptyState compact title="Sem registros no período" />;
  return (
    <ul className="space-y-2">
      {itens.map((x, i) => (
        <li key={i} className="grid grid-cols-[minmax(110px,180px)_1fr_auto] items-center gap-2 text-[13px]">
          <span className="truncate" title={rotulo(x)}>{rotulo(x)}</span>
          <Meter value={Number(x[valor] ?? 0)} max={max} tone="purple" />
          <span className="tabular-nums font-semibold">{fmtInt(x[valor])}{destaque && destaque(x) ? <span className="ml-1 font-normal text-red-700">({fmtInt(destaque(x))} c/ violência)</span> : null}</span>
        </li>
      ))}
    </ul>
  );
}

/** Indicadores para desenhar a resposta: o que é padrão amplo (formação e conscientização), foco localizado ou caso isolado. */
export function OcorrenciasIndicadores({ unitId }: { unitId: number | null }) {
  const res = useRpc<any>('ocorrencias_indicadores', { unit_id: unitId });
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const r = d.resumo;
  const leitura = (d.leitura as any[]);
  return (
    <div>
      <p className="text-[13px] text-muted">Período: {fmtDate(d.periodo.de)} a {fmtDate(d.periodo.ate)} · sem os elogios. Limiares da leitura de padrão: proposta para validação da SEDUC.</p>
      <div className="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-6">
        <Kpi compact icon={UsersRound} tone="blue" label="Registros" value={fmtInt(r.total)} sub={`${fmtInt(r.da_familia)} relatados pela família`} />
        <Kpi compact icon={Undo2} tone="green" label="Solucionadas" value={`${String(r.taxa_solucao ?? 0).replace('.', ',')}%`} sub={`${fmtInt(r.encerradas)} encerradas`} />
        <Kpi compact icon={Clock} tone="purple" label="Tempo médio de solução" value={r.tempo_medio_dias != null ? `${String(r.tempo_medio_dias).replace('.', ',')} dias` : '—'} />
        <Kpi compact icon={Hourglass} tone="red" label="Prazo vencido" value={fmtInt(r.vencidas)} sub={`${fmtInt(r.abertas + r.em_acompanhamento)} em aberto`} />
        <Kpi compact icon={GitBranch} tone="amber" label="2ª instância (SEDUC)" value={fmtInt(r.segunda_instancia)} sub={`${fmtInt(r.pedidos_familia)} a pedido da família`} />
        <Kpi compact icon={ShieldAlert} tone="red" label="Com violência" value={fmtInt(r.com_violencia)} sub={`${fmtInt(r.comunicacoes_ct)} comunicação(ões) ao CT`} />
      </div>

      <Section title="Leitura de padrão" subtitle="Por assunto e por tipo de violência: separa o que pede formação e conscientização do que é foco localizado ou caso isolado.">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(200px,1.4fr) 70px 80px 80px 80px 150px minmax(240px,2fr)" largura={1040} rotulo="Leitura de padrão">
            <TCabecalho><TCelula fixa>Grupo</TCelula><TCelula>Registros</TCelula><TCelula>Alunos</TCelula><TCelula>Turmas</TCelula><TCelula>Unidades</TCelula><TCelula>Leitura</TCelula><TCelula>Encaminhamento sugerido</TCelula></TCabecalho>
            {leitura.map((x) => (
              <TLinha key={x.dim + x.chave} rotulo={x.chave}>
                <TCelula fixa>{x.dim === 'VIOLENCIA' ? <span className="inline-flex items-center gap-1"><ShieldAlert className="size-3.5 text-red-700" aria-hidden />{VIOLENCIA[x.chave]?.label ?? x.chave}</span> : TIPO_OCORRENCIA[x.chave]?.label ?? x.chave}</TCelula>
                <TCelula>{fmtInt(x.n)}</TCelula><TCelula>{fmtInt(x.alunos)}</TCelula><TCelula>{fmtInt(x.turmas)}</TCelula><TCelula>{fmtInt(x.unidades)}</TCelula>
                <TCelula livre><Badge tone={PADRAO_OCORRENCIA[x.padrao]?.tone}>{PADRAO_OCORRENCIA[x.padrao]?.label}</Badge></TCelula>
                <TCelula titulo={`${PADRAO_OCORRENCIA[x.padrao]?.acao} Maior turma: ${x.maior_turma ?? '—'} (${x.maior_turma_pct ?? 0}%).`}>{PADRAO_OCORRENCIA[x.padrao]?.acao}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>

      {(d.focos as any[]).length > 0 && (
        <Section title="Focos" subtitle="Turmas com 4 ou mais registros de convivência e alunos com 3 ou mais registros no período.">
          <Card className="overflow-hidden">
            <Tabela colunas="150px minmax(200px,1.5fr) 90px 120px minmax(180px,1fr)" largura={780} rotulo="Focos">
              <TCabecalho><TCelula fixa>Leitura</TCelula><TCelula>Turma · unidade</TCelula><TCelula>Registros</TCelula><TCelula>Com violência</TCelula><TCelula>Assunto principal</TCelula></TCabecalho>
              {(d.focos as any[]).map((f, i) => (
                <TLinha key={i} rotulo={`${f.turma} ${f.unidade}`} alerta={f.violencia >= 3}>
                  <TCelula fixa livre><Badge tone={PADRAO_OCORRENCIA[f.padrao]?.tone}>{f.padrao === 'REINCIDENTE' ? 'Aluno reincidente' : 'Turma em foco'}</Badge></TCelula>
                  <TCelula>{f.turma} · {f.unidade}</TCelula><TCelula>{fmtInt(f.n)}</TCelula><TCelula>{fmtInt(f.violencia)}</TCelula>
                  <TCelula>{TIPO_OCORRENCIA[f.principal]?.label ?? f.principal}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Tipos de violência"><Card className="p-4"><Barras itens={d.por_violencia} rotulo={(x) => VIOLENCIA[x.violencia]?.label ?? x.violencia} /></Card></Section>
        <Section title="Assuntos"><Card className="p-4"><Barras itens={d.por_tipo} rotulo={(x) => TIPO_OCORRENCIA[x.tipo]?.label ?? x.tipo} /></Card></Section>
        <Section title="Idade na data do registro"><Card className="p-4"><Barras itens={d.por_idade} rotulo={(x) => x.faixa} destaque={(x) => x.violencia} /></Card></Section>
        <Section title="Por série (a cada mil matrículas)"><Card className="p-4"><Barras itens={d.por_serie} rotulo={(x) => x.serie} valor="por_mil" /></Card></Section>
        <Section title="Em aberto há"><Card className="p-4"><Barras itens={d.aging} rotulo={(x) => x.faixa} /></Card></Section>
        <Section title="Por mês"><Card className="p-4"><Barras itens={d.por_mes} rotulo={(x) => new Date(`${x.mes}T12:00:00`).toLocaleDateString('pt-BR', { month: 'short', year: 'numeric' })} destaque={(x) => x.violencia} /></Card></Section>
      </div>

      <Section title="Turmas com mais registros">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(220px,1.5fr) 90px 120px 90px minmax(160px,1fr)" largura={720} rotulo="Turmas">
            <TCabecalho><TCelula fixa>Turma · unidade</TCelula><TCelula>Registros</TCelula><TCelula>Com violência</TCelula><TCelula>Alunos</TCelula><TCelula>Assunto principal</TCelula></TCabecalho>
            {(d.turmas as any[]).map((t) => (
              <TLinha key={t.class_id} rotulo={t.turma}>
                <TCelula fixa>{t.turma} · {t.unidade}</TCelula><TCelula>{fmtInt(t.n)}</TCelula><TCelula>{fmtInt(t.violencia)}</TCelula><TCelula>{fmtInt(t.alunos)}</TCelula>
                <TCelula>{TIPO_OCORRENCIA[t.principal]?.label ?? t.principal}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>

      {d.unidades && (
        <Section title="Unidades com mais registros" subtitle="Taxa a cada cem matrículas, para comparar unidades de tamanhos diferentes.">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(220px,1.5fr) 90px 110px 120px 90px" largura={640} rotulo="Unidades">
              <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Registros</TCelula><TCelula>Por 100 alunos</TCelula><TCelula>Com violência</TCelula><TCelula>Abertas</TCelula></TCabecalho>
              {(d.unidades as any[]).map((u) => (
                <TLinha key={u.unit_id} rotulo={u.unidade}>
                  <TCelula fixa>{u.unidade}</TCelula><TCelula>{fmtInt(u.n)}</TCelula><TCelula>{String(u.por_cem ?? '—').replace('.', ',')}</TCelula><TCelula>{fmtInt(u.violencia)}</TCelula><TCelula>{fmtInt(u.abertas)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
    </div>
  );
}

/** Modelos de resposta à família: um por linha; alteração gera nova versão e a exclusão fica no histórico. */
export function ModelosResposta() {
  const res = useRpc<any>('ocorrencia_modelos', {});
  const [aberto, setAberto] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-[13px] text-muted">Campos que o sistema preenche: {(d.campos as string[]).join(', ')}. Sem linguagem de ameaça ou de culpa; sem dados de outras crianças.</p>
        {d.pode_editar && <Button icon={FilePlus2} onClick={() => setAberto({})}>Novo modelo</Button>}
      </div>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,1.2fr) 200px minmax(160px,1fr) minmax(280px,2.5fr) 70px 130px" largura={1120} rotulo="Modelos de resposta">
          <TCabecalho><TCelula fixa>Modelo</TCelula><TCelula>Momento</TCelula><TCelula>Assuntos</TCelula><TCelula>Texto</TCelula><TCelula>Versão</TCelula><TCelula>Alterado em</TCelula></TCabecalho>
          {(d.modelos as any[]).map((m) => (
            <TLinha key={m.id} onClick={() => setAberto(m)} rotulo={m.titulo}>
              <TCelula fixa><span className="font-semibold">{m.titulo}</span></TCelula>
              <TCelula>{MOMENTO_MODELO[m.momento] ?? m.momento}</TCelula>
              <TCelula titulo={(m.tipos as string[]).map((t) => TIPO_OCORRENCIA[t]?.label ?? t).join(', ')}>{(m.tipos as string[]).length ? (m.tipos as string[]).map((t) => TIPO_OCORRENCIA[t]?.label ?? t).join(', ') : 'Todos'}</TCelula>
              <TCelula titulo={m.texto}>{m.texto}</TCelula>
              <TCelula>v{m.versao}</TCelula>
              <TCelula titulo={m.alterado_por_label}>{fmtDate(m.alterado_em)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <ModeloSheet modelo={aberto} podeEditar={d.pode_editar} onClose={() => setAberto(null)} />
    </div>
  );
}

function ModeloSheet({ modelo, podeEditar, onClose }: { modelo: any | null; podeEditar: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const novo = modelo && !modelo.codigo;
  const [titulo, setTitulo] = useState('');
  const [momento, setMomento] = useState('SOLUCAO');
  const [tipos, setTipos] = useState<string[]>([]);
  const [texto, setTexto] = useState('');
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const hist = useRpc<any>('ocorrencia_modelos', { codigo: modelo?.codigo, excluidos: true }, { enabled: !!modelo?.codigo });
  if (modelo && chave !== (modelo.id ?? 'novo')) {
    setChave(modelo.id ?? 'novo');
    setTitulo(modelo.titulo ?? ''); setMomento(modelo.momento ?? 'SOLUCAO'); setTipos(modelo.tipos ?? []); setTexto(modelo.texto ?? '');
  }
  const salvar = async (excluir = false) => {
    setBusy(true);
    try {
      await rpc('ocorrencia_modelo_salvar', excluir ? { codigo: modelo.codigo, excluir: true } : { codigo: modelo?.codigo ?? null, titulo, momento, tipos, texto });
      toast({ title: excluir ? 'Modelo excluído' : novo ? 'Modelo incluído' : 'Nova versão do modelo salva', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['ocorrencia_modelos'] });
      qc.invalidateQueries({ queryKey: ['ocorrencia_detalhe'] });
      setChave(null);
      onClose();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const exemplo = texto.replaceAll('{aluno}', 'Ana').replaceAll('{unidade}', 'E.M. Exemplo').replaceAll('{data}', '06/10/2026').replaceAll('{prazo}', '16/10/2026')
    .replaceAll('{solucao}', 'Conversamos com a turma e combinamos acompanhar o recreio.');
  return (
    <Sheet open={!!modelo} onClose={() => { setChave(null); onClose(); }} title={novo ? 'Novo modelo de resposta' : modelo?.titulo} subtitle={novo ? '' : `${modelo?.codigo} · versão ${modelo?.versao}`} size="lg"
      footer={podeEditar ? (
        <div className="flex gap-2">
          {!novo && <Button variant="secondary" icon={Trash2} loading={busy} onClick={() => salvar(true)}>Excluir</Button>}
          <Button block icon={Pencil} loading={busy} disabled={titulo.trim().length < 3 || texto.trim().length < 20} onClick={() => salvar(false)}>{novo ? 'Incluir' : 'Salvar nova versão'}</Button>
        </div>
      ) : undefined}>
      <div className="space-y-4 pt-1">
        <Field label="Título"><input value={titulo} onChange={(e) => setTitulo(e.target.value)} disabled={!podeEditar} className={inputCls} /></Field>
        <Field label="Momento">
          <select value={momento} onChange={(e) => setMomento(e.target.value)} disabled={!podeEditar || !novo} className={inputCls}>
            {Object.entries(MOMENTO_MODELO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
        <Field label="Assuntos" hint="Nenhum marcado: vale para todos.">
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(TIPO_OCORRENCIA).map(([k, v]) => (
              <label key={k} className="inline-flex items-center gap-1.5 rounded-full bg-white px-2.5 py-1 text-[12.5px] ring-1 ring-line">
                <input type="checkbox" className="size-4 accent-purple-700" disabled={!podeEditar} checked={tipos.includes(k)} onChange={(e) => setTipos(e.target.checked ? [...tipos, k] : tipos.filter((x) => x !== k))} />{v.label}
              </label>
            ))}
          </div>
        </Field>
        <Field label="Texto" hint="Use {aluno}, {unidade}, {data}, {prazo} e {solucao}.">
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} disabled={!podeEditar} rows={6} maxLength={1500} className={`${inputCls} h-auto py-3`} />
        </Field>
        {texto.trim().length > 0 && <div className="rounded-2xl bg-slate-50 p-3 text-[13px]"><b className="block text-[11.5px] uppercase text-muted">Como a família lê</b>{exemplo}</div>}
        {!novo && (hist.data?.historico ?? []).length > 0 && (
          <div>
            <h3 className="mb-1 text-[13px] font-semibold">Histórico</h3>
            <ol className="space-y-1 text-[12.5px]">
              {(hist.data.historico as any[]).map((h) => (
                <li key={h.id} className="rounded-2xl bg-white p-2 ring-1 ring-line">
                  <span className="font-semibold">v{h.versao}</span> · {fmtDateTime(h.alterado_em)} · {h.alterado_por_label}{!h.ativo && <Badge tone="gray" className="ml-1">excluído</Badge>}
                  <p className="text-muted">{h.texto}</p>
                </li>
              ))}
            </ol>
          </div>
        )}
      </div>
    </Sheet>
  );
}
