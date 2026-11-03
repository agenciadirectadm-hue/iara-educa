import { useMemo, useState } from 'react';
import clsx from 'clsx';
import { ChevronDown, EyeOff, Megaphone, Send, ShieldAlert, Users } from 'lucide-react';
import { useDebounced, useRpc, useRpcMutation } from '@/lib/hooks';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { FUNCAO_SERVIDOR } from '@/lib/escola';
import { Badge, Button, Card, ErrorState, PageHeader, Section, Segmented, SkeletonList } from '@/components/ui';
import { Sheet } from '@/components/overlays';

type Publico = 'RESPONSAVEIS' | 'PROFISSIONAIS';
type Opcoes = {
  unidades: { id: number; nome: string; tipo: string; area: number | null }[];
  areas: { id: number; nome: string }[];
  funcoes: string[]; vinculos: string[]; situacoes: string[]; cargas: number[];
  series: { id: number; nome: string }[]; situacoes_aluno: string[];
  modelos: { codigo: string; nome: string; publico: string; categoria: string; corpo: string }[];
  periodo_eleitoral: { eleicao: string; inicio_restricao: string; restrito: boolean };
};
type Contagem = {
  total: number; com_contato: number; sem_contato: number; nao_querem: number;
  por_unidade: { nome: string; n: number }[]; por_regiao: { nome: string; n: number }[]; nota: string;
};
type Filtros = Record<string, (string | number)[] | boolean>;

const SITUACAO_SERVIDOR: Record<string, string> = { ATIVO: 'Em exercício', LICENCA: 'Licença', AFASTADO: 'Afastado', DESLIGADO: 'Desligado' };
const SITUACAO_ALUNO: Record<string, string> = {
  MATRICULADO: 'Matriculado', AGUARDANDO_VAGA: 'Aguardando vaga', TRANSFERENCIA: 'Em transferência', SEM_VINCULO: 'Sem vínculo', INATIVO: 'Inativo',
};
const FORMACAO = [
  { id: '1', nome: 'Nível médio / magistério' }, { id: '2', nome: 'Superior incompleto' }, { id: '3', nome: 'Superior completo' },
  { id: '4', nome: 'Especialização' }, { id: '5', nome: 'Mestrado' }, { id: '6', nome: 'Doutorado' }, { id: '0', nome: 'Sem informação' },
];
const ENVIO: Record<string, { rotulo: string; tom: 'green' | 'amber' | 'red' }> = {
  SIMULADO: { rotulo: 'Simulado (demonstração)', tom: 'amber' }, ENFILEIRADO: { rotulo: 'Enviado', tom: 'green' },
  BLOQUEADO_ELEITORAL: { rotulo: 'Bloqueado: período eleitoral', tom: 'red' },
};

/** Públicos do Prefeito: monta públicos de profissionais e responsáveis com os filtros do IARA, vê só contagens e envia um
 * comunicado pelo WhatsApp oficial, com modelo aprovado. Nenhum nome, telefone ou identificador aparece. */
export default function PublicosPrefeito() {
  const op = useRpc<Opcoes>('publicos_opcoes', {}, { staleTime: 10 * 60_000 });
  const [publico, setPublico] = useState<Publico>('RESPONSAVEIS');
  const [filtros, setFiltros] = useState<Filtros>({});
  const [envio, setEnvio] = useState(false);
  const chave = useDebounced(JSON.stringify({ publico, filtros }), 400);
  const cont = useRpc<Contagem>('publicos_contar', JSON.parse(chave), { enabled: !!op.data });
  const hist = useRpc<any[]>('publicos_historico', {});

  if (op.isLoading) return <SkeletonList rows={6} />;
  if (op.error) return <ErrorState error={op.error} onRetry={() => op.refetch()} />;
  const o = op.data!;
  const lista = (k: string) => (Array.isArray(filtros[k]) ? (filtros[k] as (string | number)[]) : []);
  const marca = (k: string, v: (string | number)[]) => setFiltros((f) => ({ ...f, [k]: v }));
  const liga = (k: string) => setFiltros((f) => ({ ...f, [k]: !f[k] }));
  const trocar = (p: Publico) => { setPublico(p); setFiltros({}); };
  const c = cont.data;

  return (
    <div>
      <PageHeader eyebrow="Gabinete do Prefeito" title={<span className="inline-flex items-center gap-2"><Users className="size-6 text-purple-700" />Públicos do Prefeito</span>}
        subtitle="Monte um público com os filtros do IARA e veja quantas pessoas ele tem. Os nomes e os contatos nunca aparecem: o comunicado sai pelo WhatsApp oficial, com modelo aprovado e registro na auditoria." />

      {o.periodo_eleitoral.restrito && (
        <p role="alert" className="mb-3 flex items-start gap-2 rounded-2xl bg-red-50 p-3 text-[13px] font-semibold text-red-800">
          <ShieldAlert className="mt-0.5 size-4 shrink-0" />Período eleitoral: comunicados ficam bloqueados até a eleição (Lei 9.504/97, art. 73).
        </p>
      )}

      <Segmented value={publico} onChange={(v) => trocar(v as Publico)} items={[{ value: 'RESPONSAVEIS', label: 'Responsáveis' }, { value: 'PROFISSIONAIS', label: 'Profissionais' }]} />

      <div className="mt-3 grid grid-cols-1 gap-4 lg:grid-cols-[1.1fr_1fr]">
        {/* filtros */}
        <Card className="p-4">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="font-display text-[16px] font-extrabold">Filtros</h2>
            <button type="button" onClick={() => setFiltros({})} className="text-[13px] font-semibold text-purple-700">Limpar</button>
          </div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <Multi rotulo={publico === 'RESPONSAVEIS' ? 'Unidade dos filhos' : 'Unidade'} itens={o.unidades.map((u) => ({ id: u.id, nome: u.nome }))}
              valor={lista('unidades')} onChange={(v) => marca('unidades', v)} busca />
            <Multi rotulo={publico === 'RESPONSAVEIS' ? 'Região de moradia' : 'Região da unidade'} itens={o.areas} valor={lista('areas')} onChange={(v) => marca('areas', v)} busca />
            <Multi rotulo="Tipo de unidade" itens={[{ id: 'CMEI', nome: 'CMEI' }, { id: 'ESCOLA', nome: 'Escola' }]} valor={lista('tipos')} onChange={(v) => marca('tipos', v)} />
            {publico === 'PROFISSIONAIS' ? (
              <>
                <Multi rotulo="Função" itens={o.funcoes.map((x) => ({ id: x, nome: FUNCAO_SERVIDOR[x] ?? x }))} valor={lista('funcoes')} onChange={(v) => marca('funcoes', v)} />
                <Multi rotulo="Vínculo" itens={o.vinculos.map((x) => ({ id: x, nome: x }))} valor={lista('vinculos')} onChange={(v) => marca('vinculos', v)} />
                <Multi rotulo="Situação" itens={o.situacoes.map((x) => ({ id: x, nome: SITUACAO_SERVIDOR[x] ?? x }))} valor={lista('situacoes')} onChange={(v) => marca('situacoes', v)} />
                <Multi rotulo="Formação" itens={FORMACAO} valor={lista('formacao')} onChange={(v) => marca('formacao', v)} />
                <Multi rotulo="Carga horária semanal" itens={o.cargas.map((x) => ({ id: String(x), nome: `${x} horas` }))} valor={lista('carga')} onChange={(v) => marca('carga', v)} />
              </>
            ) : (
              <>
                <Multi rotulo="Série dos filhos" itens={o.series.map((s) => ({ id: String(s.id), nome: s.nome }))} valor={lista('series')} onChange={(v) => marca('series', v)} />
                <Multi rotulo="Turno dos filhos" itens={Object.entries(SHIFT).map(([id, nome]) => ({ id, nome }))} valor={lista('turnos')} onChange={(v) => marca('turnos', v)} />
                <Multi rotulo="Situação dos filhos" itens={o.situacoes_aluno.map((x) => ({ id: x, nome: SITUACAO_ALUNO[x] ?? x }))} valor={lista('situacoes_aluno')} onChange={(v) => marca('situacoes_aluno', v)} />
              </>
            )}
          </div>
          {publico === 'RESPONSAVEIS' && (
            <div className="mt-3 flex flex-wrap gap-2">
              {([['fila', 'Filho na fila de espera'], ['transporte', 'Usa transporte escolar'], ['aee', 'Filho no AEE'],
                ['alerta_frequencia', 'Alerta de frequência'], ['cadunico', 'CadÚnico']] as [string, string][]).map(([k, rot]) => (
                <button key={k} type="button" onClick={() => liga(k)} aria-pressed={!!filtros[k]}
                  className={clsx('rounded-full px-3 py-1.5 text-[13px] font-semibold ring-1', filtros[k] ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white text-ink-2 ring-line hover:bg-slate-50')}>
                  {rot}
                </button>
              ))}
            </div>
          )}
        </Card>

        {/* contagem */}
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            <Card className="col-span-2 bg-purple-50 p-4 ring-purple-200">
              <div className="font-display text-[34px] font-black leading-none text-purple-900 tabular">{c ? fmtInt(c.total) : '…'}</div>
              <div className="mt-1 text-[13px] font-semibold text-ink-2">{publico === 'RESPONSAVEIS' ? 'responsáveis' : 'profissionais'} neste público</div>
            </Card>
            <Card className="p-3"><div className="text-[20px] font-extrabold tabular text-green-700">{c ? fmtInt(c.com_contato) : '…'}</div><div className="text-[12px] text-muted">recebem pelo WhatsApp</div></Card>
            <Card className="p-3"><div className="text-[20px] font-extrabold tabular">{c ? fmtInt(c.sem_contato + c.nao_querem) : '…'}</div><div className="text-[12px] text-muted">sem contato ({c ? fmtInt(c.sem_contato) : '…'}) ou pediram para não receber ({c ? fmtInt(c.nao_querem) : '…'})</div></Card>
          </div>
          {c && (c.por_unidade.length > 0 || c.por_regiao.length > 0) && (
            <Card className="grid grid-cols-1 gap-3 p-3 sm:grid-cols-2">
              <Recorte titulo="Mais pessoas por unidade" itens={c.por_unidade} />
              <Recorte titulo="Mais pessoas por região" itens={c.por_regiao} />
            </Card>
          )}
          <p className="flex items-start gap-1.5 text-[12px] text-muted"><EyeOff className="mt-0.5 size-3.5 shrink-0" />{c?.nota ?? 'Só contagens: nomes e contatos nunca aparecem.'}</p>
          <Button block icon={Megaphone} disabled={!c?.total} onClick={() => setEnvio(true)}>Enviar comunicado a este público</Button>
        </div>
      </div>

      <Enviar open={envio} onClose={() => setEnvio(false)} publico={publico} filtros={filtros} total={c?.total ?? 0} comContato={c?.com_contato ?? 0}
        modelos={o.modelos.filter((m) => m.publico === 'TODOS' || m.publico === publico)} restrito={o.periodo_eleitoral.restrito} />

      <Section title="Comunicados enviados" subtitle="Os últimos 30, com o público e o resultado.">
        {hist.isLoading ? <SkeletonList rows={3} /> : (hist.data ?? []).length === 0 ? (
          <p className="text-[13px] text-muted">Nenhum comunicado ainda.</p>
        ) : (
          <Card className="divide-y divide-line">
            {(hist.data ?? []).map((h) => (
              <div key={h.id} className="flex flex-wrap items-start gap-x-3 gap-y-1 px-4 py-3 text-[13px]">
                <div className="min-w-0 flex-1">
                  <div className="font-semibold">{h.modelo} · {h.publico === 'RESPONSAVEIS' ? 'Responsáveis' : 'Profissionais'}</div>
                  <div className="truncate text-muted" title={h.texto}>{h.texto}</div>
                </div>
                <div className="text-right">
                  <Badge tone={ENVIO[h.situacao]?.tom ?? 'gray'}>{ENVIO[h.situacao]?.rotulo ?? h.situacao}</Badge>
                  <div className="mt-0.5 text-[12px] text-muted">{fmtInt(h.enviados)} de {fmtInt(h.total)} · {fmtDateTime(h.criado_em)}</div>
                </div>
              </div>
            ))}
          </Card>
        )}
      </Section>
    </div>
  );
}

/** Seleção múltipla compacta: "Todas" ou "N escolhidas"; abre a lista (com busca, se pedida). */
function Multi({ rotulo, itens, valor, onChange, busca }: {
  rotulo: string; itens: { id: string | number; nome: string }[]; valor: (string | number)[]; onChange: (v: (string | number)[]) => void; busca?: boolean;
}) {
  const [q, setQ] = useState('');
  const vistos = useMemo(() => (q ? itens.filter((i) => i.nome.toLowerCase().includes(q.toLowerCase())) : itens), [itens, q]);
  const sel = new Set(valor.map(String));
  return (
    <details className="group rounded-2xl bg-white ring-1 ring-line open:ring-purple-300">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-3 py-2">
        <span className="min-w-0 flex-1">
          <span className="block text-[11.5px] font-bold uppercase tracking-wide text-subtle">{rotulo}</span>
          <span className="block truncate text-[13.5px] font-semibold">{valor.length === 0 ? 'Todas' : valor.length === 1 ? itens.find((i) => String(i.id) === String(valor[0]))?.nome ?? '1 escolhida' : `${valor.length} escolhidas`}</span>
        </span>
        <ChevronDown className="size-4 text-subtle transition group-open:rotate-180" />
      </summary>
      <div className="border-t border-line p-2">
        {busca && <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar…" aria-label={`Buscar em ${rotulo}`}
          className="mb-2 h-9 w-full rounded-xl bg-slate-50 px-3 text-[13px] outline-none ring-1 ring-line focus:ring-purple-400" />}
        <div className="max-h-52 overflow-y-auto">
          {vistos.map((i) => (
            <label key={i.id} className="flex cursor-pointer items-center gap-2 rounded-lg px-1.5 py-1 text-[13px] hover:bg-purple-50">
              <input type="checkbox" className="size-4 accent-purple-700" checked={sel.has(String(i.id))}
                onChange={() => onChange(sel.has(String(i.id)) ? valor.filter((v) => String(v) !== String(i.id)) : [...valor, i.id])} />
              <span className="truncate">{i.nome}</span>
            </label>
          ))}
        </div>
        {valor.length > 0 && <button type="button" onClick={() => onChange([])} className="mt-1 text-[12.5px] font-semibold text-purple-700">Limpar</button>}
      </div>
    </details>
  );
}

function Recorte({ titulo, itens }: { titulo: string; itens: { nome: string; n: number }[] }) {
  if (!itens.length) return null;
  const max = Math.max(...itens.map((i) => i.n));
  return (
    <div>
      <div className="mb-1 text-[12px] font-semibold text-ink-2">{titulo}</div>
      {itens.map((i) => (
        <div key={i.nome} className="mb-1 text-[12.5px]">
          <div className="flex justify-between gap-2"><span className="truncate">{i.nome}</span><span className="font-semibold tabular">{fmtInt(i.n)}</span></div>
          <span className="block h-1 rounded-full bg-slate-100"><span className="block h-full rounded-full bg-purple-500" style={{ width: `${(100 * i.n) / max}%` }} /></span>
        </div>
      ))}
    </div>
  );
}

/** Envio do comunicado: modelo aprovado, texto, prévia e confirmação com o número de pessoas. */
function Enviar({ open, onClose, publico, filtros, total, comContato, modelos, restrito }: {
  open: boolean; onClose: () => void; publico: Publico; filtros: Filtros; total: number; comContato: number;
  modelos: Opcoes['modelos']; restrito: boolean;
}) {
  const [modelo, setModelo] = useState('');
  const [texto, setTexto] = useState('');
  const [res, setRes] = useState<any | null>(null);
  const enviar = useRpcMutation<any, any>('publicos_enviar', ['publicos_historico']);
  const m = modelos.find((x) => x.codigo === modelo) ?? modelos[0];
  const fechar = () => { setRes(null); setTexto(''); onClose(); };
  return (
    <Sheet open={open} onClose={fechar} title="Enviar comunicado" subtitle={`${fmtInt(total)} pessoas no público · ${fmtInt(comContato)} recebem pelo WhatsApp`} size="md">
      {res ? (
        <div className="space-y-3 text-[14px]">
          <Badge tone={ENVIO[res.situacao]?.tom ?? 'gray'}>{ENVIO[res.situacao]?.rotulo ?? res.situacao}</Badge>
          <p>{res.situacao === 'BLOQUEADO_ELEITORAL' ? 'Nada foi enviado: período eleitoral.' : `${fmtInt(res.enviados)} de ${fmtInt(res.total)} pessoas recebem a mensagem.`}
            {res.situacao === 'SIMULADO' && ' Na demonstração, o envio só fica registrado: nenhuma mensagem sai.'}</p>
          <Card className="bg-slate-50 p-3 text-[13px]">{res.mensagem}</Card>
          <Button block onClick={fechar}>Fechar</Button>
        </div>
      ) : (
        <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); enviar.mutate({ publico, filtros, modelo: m?.codigo, texto }, { onSuccess: (r) => setRes(r) }); }}>
          {restrito && <p className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">Período eleitoral: o envio será registrado, mas bloqueado.</p>}
          <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Modelo aprovado</span>
            <select value={m?.codigo ?? ''} onChange={(e) => setModelo(e.target.value)} className="h-11 w-full rounded-2xl bg-white px-3 text-[14px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500">
              {modelos.map((x) => <option key={x.codigo} value={x.codigo}>{x.nome} ({x.categoria === 'MARKETING' ? 'marketing' : 'utilidade'})</option>)}
            </select></label>
          <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Mensagem ({texto.length}/700)</span>
            <textarea value={texto} onChange={(e) => setTexto(e.target.value.slice(0, 700))} rows={4}
              className="w-full rounded-2xl bg-white p-3 text-[14px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500" /></label>
          {m && texto && <Card className="bg-slate-50 p-3 text-[13px]"><span className="text-[11.5px] font-bold uppercase text-subtle">Prévia</span><br />{m.corpo.replace('{texto}', texto)}</Card>}
          {enviar.error && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">{enviar.error.message}</p>}
          <Button type="submit" block icon={Send} loading={enviar.isPending} disabled={texto.trim().length < 10 || !m}>Enviar para {fmtInt(comContato)} pessoas</Button>
          <p className="text-[12px] text-muted">O envio fica na auditoria, com o público e o texto. Quem pediu para não receber fica de fora.</p>
        </form>
      )}
    </Sheet>
  );
}
