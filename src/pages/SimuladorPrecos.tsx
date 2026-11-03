import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import { Calculator, CheckSquare, KeyRound, Lock, LockKeyhole, Save, Square } from 'lucide-react';
import { useRpc, useRpcMutation } from '@/lib/hooks';
import { fmtInt } from '@/lib/format';
import { Badge, Button, Card, ErrorState, PageHeader, Section, SkeletonList } from '@/components/ui';
import { Sheet } from '@/components/overlays';

type Cobranca = 'agente' | 'vaga' | 'profissional' | 'fila' | 'disparador';
type Agente = {
  num: number; nome: string; assuntos: string; tipo: 1 | 2 | 3; criticidade: string; dimensao: string; situacao: string;
  cobranca: Cobranca; disparador: boolean; implantacao: number; mensal: number;
};
type Municipio = {
  id: number; nome: string; uf: string | null; unidades: number | null; ocupadas: number | null; creche: number | null;
  fila_informada: number | null; docentes: number | null; outros: number | null; filas_centrais: number; filas_setor: number;
  conveniadas: number | null; observacao: string | null;
  /** Só vem para o titular: o comercial nunca recebe o desconto. */
  redutor?: number;
  /** 1 − redutor: para o comercial, os preços já saem ajustados, sem rótulo de desconto. */
  fator: number;
};
type Nivel = 'COMERCIAL' | 'TITULAR';
type Param = 'meses' | 'taxa_fila' | 'resp_al' | 'util_al' | 'doc_al' | 'aud_al' | 'u_resp' | 'u_doc' | 'u_aud' | 'w_resp' | 'w_fran'
  | 'w_isen' | 'w_util' | 'o_perg' | 'u_orac' | 'pub_resp' | 'pub_por' | 'pub_tar';
type Dados = { nivel: Nivel; agentes: Agente[]; municipios: Municipio[]; parametros: Record<Param, number>; fonte: string };

const TIPOS = {
  1: 'Tipo 1 — Crítico e de grande porte',
  2: 'Tipo 2 — Importante e de médio porte',
  3: 'Tipo 3 — Apoio e de menor porte',
} as const;
const COBRANCA: Record<Cobranca, string> = {
  agente: 'Por agente', vaga: 'Por vaga ocupada ou demandada', profissional: 'Por profissional', fila: 'Por fila', disparador: 'Por disparador',
};
// agentes cujos custos adicionais só contam quando marcados
const DOC = 'Leitura automática de documentos';
const AUDIO = 'Áudio em texto (transcrição)';
const ORACULO = 'Oráculo do Prefeito';
const PUBLICOS = 'Públicos do Prefeito';

// última prefeitura aberta neste navegador (só a conveniência de reabrir a mesma)
const MUN_SALVA = 'iara.simulador.prefeitura';
const brl2 = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const brl4 = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 4, maximumFractionDigits: 4 });
// valores sempre no formato R$ x.xxx,xx
const r0 = (n: number) => (n ? brl2.format(n) : '—');
const pct = (n: number) => `${(n * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
// ROUND do Excel: arredonda a metade para longe do zero (as quantidades aqui são sempre positivas)
const arred = (n: number) => Math.round(n);

/** Volumes do município com os agentes marcados: as mesmas regras da calculadora. */
function volumes(m: Municipio, P: Dados['parametros'], agentes: Agente[], marcados: Set<number>) {
  const demandadas = m.fila_informada ?? arred((m.creche ?? 0) * P.taxa_fila);
  const vagas = (m.ocupadas ?? 0) + demandadas;
  const prof = (m.docentes ?? 0) + (m.outros ?? 0);
  const filas = (m.unidades ?? 0) + m.filas_centrais + m.filas_setor;
  const servicos = agentes.filter((a) => a.disparador && marcados.has(a.num)).length;
  return { demandadas, vagas, prof, filas, servicos, disparadores: (m.unidades ?? 0) + servicos, estimada: m.fila_informada == null };
}
type Vol = ReturnType<typeof volumes>;

function quantidade(a: Agente, v: Vol) {
  return { agente: 1, vaga: v.vagas, profissional: v.prof, fila: v.filas, disparador: v.disparadores }[a.cobranca];
}

/** Preço do município: agentes marcados, totais por tipo, redutor (explícito, para o titular) e 1º ano. O fator ajusta os
 * preços sem aparecer (comercial): entra no preço unitário de cada agente, e as linhas e os totais continuam somando certo. */
function preco(agentes: Agente[], v: Vol, marcados: Set<number>, redutor: number, meses: number, fator = 1) {
  const linhas = agentes.map((a) => {
    const q = quantidade(a, v);
    const on = marcados.has(a.num);
    const uImpl = a.implantacao * fator;
    const uMensal = a.mensal * fator;
    return { a, q, on, uImpl, uMensal, impl: on ? q * uImpl : 0, mensal: on ? q * uMensal : 0 };
  });
  const impl = linhas.reduce((s, l) => s + l.impl, 0);
  const mensal = linhas.reduce((s, l) => s + l.mensal, 0);
  return { linhas, impl, mensal, implRed: impl * (1 - redutor), mensalRed: mensal * (1 - redutor), anoRed: (impl + mensal * meses) * (1 - redutor) };
}

/** Custos adicionais do mês, cobrados direto pela Meta, pela Anthropic e pela Groq (não somam ao preço). */
function custos(agentes: Agente[], v: Vol, marcados: Set<number>, P: Dados['parametros']) {
  const marcado = (nome: string) => agentes.some((a) => a.nome === nome && marcados.has(a.num));
  const resp = arred(v.vagas * P.resp_al);
  const itens = [
    { nome: 'Tokens da IARA nas respostas — Claude Sonnet 5.5 (Anthropic)', und: 'resposta', q: resp, u: P.u_resp },
    { nome: 'WhatsApp: respostas (Meta, mensagem de serviço)', und: 'resposta paga', q: P.w_isen ? 0 : Math.max(0, resp - P.w_fran), u: P.w_resp },
    { nome: 'WhatsApp: mensagens de utilidade (Meta)', und: 'mensagem', q: arred(v.vagas * P.util_al), u: P.w_util },
    { nome: 'Leitura de documentos — Claude Sonnet 5.5 (Anthropic)', und: 'documento', q: marcado(DOC) ? arred(v.vagas * P.doc_al) : 0, u: P.u_doc },
    { nome: 'Áudio em texto — Whisper Large v3 (Groq)', und: 'áudio', q: marcado(AUDIO) ? arred(v.vagas * P.aud_al) : 0, u: P.u_aud },
    { nome: 'Oráculo do Prefeito — Claude Opus 5.5 (Anthropic)', und: 'pergunta', q: marcado(ORACULO) ? P.o_perg : 0, u: P.u_orac },
    { nome: 'Públicos do Prefeito: disparos de marketing (Meta)', und: 'disparo',
      q: marcado(PUBLICOS) ? arred((arred(v.vagas * P.pub_resp) + v.prof) * P.pub_por) : 0, u: P.pub_tar },
  ].map((i) => ({ ...i, mensal: i.q * i.u }));
  return { itens, total: itens.reduce((s, i) => s + i.mensal, 0) };
}

/** Simulador de preços (perfil Comercial), fechado por senha. O comercial vê o preço cheio; o titular, com a senha dele, vê e
 * define o redutor de cada prefeitura. Escolha a prefeitura, marque os agentes e veja implantação, mensal, 1º ano e custos
 * adicionais; no fim, todas as prefeituras lado a lado com os mesmos agentes. */
export default function SimuladorPrecos() {
  const acesso = useRpc<{ nivel: Nivel | null }>('simulador_acesso', {}, { staleTime: 0 });
  if (acesso.isLoading) return <SkeletonList rows={4} />;
  if (acesso.error) return <ErrorState error={acesso.error} onRetry={() => acesso.refetch()} />;
  if (!acesso.data?.nivel) return <Bloqueio />;
  return <Simulador />;
}

/** Senha para abrir o simulador: a do comercial ou, em "Acesso do titular", a do titular. */
function Bloqueio() {
  const [titular, setTitular] = useState(false);
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const entrar = useRpcMutation<{ nivel: Nivel; senha: string }, { ok: boolean; erro?: string; restantes?: number }>('simulador_entrar', ['simulador_acesso', 'simulador_precos']);
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setErro(null);
    try {
      const r = await entrar.mutateAsync({ nivel: titular ? 'TITULAR' : 'COMERCIAL', senha });
      if (!r.ok) setErro(`${r.erro ?? 'Senha incorreta.'}${r.restantes != null && r.restantes > 0 ? ` Restam ${r.restantes} tentativa(s).` : ''}`);
    } catch (err) {
      setErro(err instanceof Error ? err.message : 'Não foi possível entrar.');
    }
    setSenha('');
  };
  return (
    <div className="mx-auto max-w-md py-10">
      <Card className="p-6">
        <div className="flex items-center gap-3">
          <span className="inline-flex size-12 items-center justify-center rounded-2xl bg-purple-100 text-purple-800">{titular ? <LockKeyhole className="size-6" /> : <Lock className="size-6" />}</span>
          <div>
            <h1 className="font-display text-xl font-extrabold">{titular ? 'Acesso do titular' : 'Simulador de preços'}</h1>
            <p className="text-[13px] text-muted">{titular ? 'Redutores e preço com desconto. Só para o titular.' : 'Área comercial: entre com a senha.'}</p>
          </div>
        </div>
        <form onSubmit={enviar} className="mt-5 space-y-3">
          <label className="block">
            <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Senha</span>
            <input type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} autoFocus
              className="h-12 w-full rounded-2xl bg-white px-4 text-[16px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500" />
          </label>
          {erro && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">{erro}</p>}
          <Button type="submit" block loading={entrar.isPending} disabled={!senha}>Entrar</Button>
        </form>
        <button type="button" onClick={() => { setTitular(!titular); setErro(null); }} className="mt-4 text-[13px] font-semibold text-purple-700">
          {titular ? 'Voltar ao acesso comercial' : 'Acesso do titular'}
        </button>
      </Card>
    </div>
  );
}

function Simulador() {
  const res = useRpc<Dados>('simulador_precos', {}, { staleTime: 5 * 60_000 });
  const d = res.data;
  const titular = d?.nivel === 'TITULAR';
  const [munId, setMunId] = useState<number | null>(null);
  const [marcados, setMarcados] = useState<Set<number> | null>(null);
  const [redutor, setRedutor] = useState<number | null>(null);
  const [trocar, setTrocar] = useState(false);
  const [verTodas, setVerTodas] = useState(false);
  const [pedirTodas, setPedirTodas] = useState(false);
  const [ajuste, setAjuste] = useState(false);
  const sair = useRpcMutation('simulador_sair', ['simulador_acesso', 'simulador_precos']);
  const salvarRedutor = useRpcMutation<{ municipio_id: number; redutor: number }>('simulador_redutor', ['simulador_precos']);

  useEffect(() => {
    if (d && marcados == null) setMarcados(new Set(d.agentes.map((a) => a.num)));
    if (d && munId == null && d.municipios.length) {
      // a prefeitura da última consulta (neste navegador) ou a primeira
      let salva: number | null = null;
      try { salva = Number(localStorage.getItem(MUN_SALVA)) || null; } catch { /* sem armazenamento: usa a primeira */ }
      setMunId(d.municipios.some((x) => x.id === salva) ? salva : d.municipios[0].id);
    }
  }, [d, marcados, munId]);
  const abrirPrefeitura = (id: number) => {
    setMunId(id);
    try { localStorage.setItem(MUN_SALVA, String(id)); } catch { /* sem armazenamento */ }
  };

  const m = d?.municipios.find((x) => x.id === munId) ?? null;
  useEffect(() => { setRedutor(null); }, [munId]);
  // o comercial nunca vê desconto: só o titular recebe e usa o redutor
  const red = titular ? redutor ?? m?.redutor ?? 0 : 0;

  const calc = useMemo(() => {
    if (!d || !m || !marcados) return null;
    const v = volumes(m, d.parametros, d.agentes, marcados);
    return { v, p: preco(d.agentes, v, marcados, red, d.parametros.meses, titular ? 1 : m.fator), c: custos(d.agentes, v, marcados, d.parametros) };
  }, [d, m, marcados, red, titular]);

  const todas = useMemo(() => {
    if (!d || !marcados) return [];
    return d.municipios.map((x) => {
      const v = volumes(x, d.parametros, d.agentes, marcados);
      return { x, v, p: preco(d.agentes, v, marcados, titular ? x.redutor ?? 0 : 0, d.parametros.meses, titular ? 1 : x.fator), c: custos(d.agentes, v, marcados, d.parametros) };
    });
  }, [d, marcados, titular]);

  if (res.isLoading || !marcados) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!d || !m || !calc) return null;
  const { v, p, c } = calc;
  const alternar = (num: number) => setMarcados((s) => {
    const n = new Set(s);
    if (n.has(num)) n.delete(num);
    else n.add(num);
    return n;
  });

  return (
    <div>
      <PageHeader eyebrow={titular ? 'Comercial · acesso do titular' : 'Comercial · simulação'}
        title={<span className="inline-flex items-center gap-2"><Calculator className="size-6 text-purple-700" />Simulador de preços</span>}
        subtitle={`${titular ? 'Escolha a prefeitura e marque' : 'Marque'} os agentes contratados: implantação, mensal e 1º ano se recalculam na hora. Os custos adicionais são cobrados diretamente pela Meta, pela Anthropic e pela Groq e não entram no preço.`}
        actions={<>
          <Button variant="secondary" size="sm" icon={KeyRound} onClick={() => setTrocar(true)}>Trocar senha</Button>
          <Button variant="secondary" size="sm" icon={Lock} loading={sair.isPending} onClick={() => sair.mutate({})}>Bloquear</Button>
        </>} />
      <TrocarSenha open={trocar} onClose={() => setTrocar(false)} titular={titular} />
      <SenhaTitular open={pedirTodas} onClose={() => setPedirTodas(false)} fn="simulador_ver_todas" titulo="Ver todas" onOk={() => { setPedirTodas(false); setVerTodas(true); }} />
      <AjusteTotal open={ajuste} onClose={() => setAjuste(false)} municipio={m} />

      {/* prefeitura (e, para o titular, o redutor) */}
      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-4">
          {titular ? (
            <label className="min-w-0 flex-1 basis-64">
              <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Prefeitura</span>
              <select value={munId ?? ''} onChange={(e) => abrirPrefeitura(Number(e.target.value))} aria-label="Prefeitura"
                className="h-11 w-full rounded-2xl bg-white px-3 text-[15px] font-semibold ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500">
                {d.municipios.map((x) => <option key={x.id} value={x.id}>{x.nome}{x.uf ? ` – ${x.uf}` : ''}</option>)}
              </select>
            </label>
          ) : (
            // para o comercial, só a prefeitura aberta: as outras ficam ocultas ("Ver todas", no fim, pede a senha do titular)
            <div className="min-w-0 flex-1 basis-64">
              <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Prefeitura</span>
              <div className="font-display text-[22px] font-extrabold leading-tight">{m.nome}{m.uf ? ` – ${m.uf}` : ''}</div>
            </div>
          )}
          {titular && (
            <div>
              <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Redutor (desconto) · só titular</span>
              <span className="flex items-center gap-2">
                <span className="flex h-11 items-center gap-1 rounded-2xl bg-white px-3 ring-1 ring-line focus-within:ring-2 focus-within:ring-purple-500">
                  <input type="number" min={0} max={90} step={1} value={Math.round(red * 1000) / 10}
                    onChange={(e) => setRedutor(Math.min(90, Math.max(0, Number(e.target.value) || 0)) / 100)}
                    className="w-16 bg-transparent text-right text-[15px] font-semibold outline-none" aria-label="Redutor em porcentagem" />
                  <span className="text-[15px] font-semibold text-muted">%</span>
                </span>
                {redutor != null && redutor !== (m.redutor ?? 0) && (
                  <Button size="sm" icon={Save} loading={salvarRedutor.isPending}
                    onClick={() => salvarRedutor.mutate({ municipio_id: m.id, redutor }, { onSuccess: () => setRedutor(null) })}>Salvar</Button>
                )}
              </span>
            </div>
          )}
          <div className="flex gap-2">
            <button type="button" onClick={() => setMarcados(new Set(d.agentes.map((a) => a.num)))}
              className="inline-flex h-11 items-center gap-1.5 rounded-2xl bg-white px-3 text-[13px] font-semibold ring-1 ring-line hover:bg-slate-50"><CheckSquare className="size-4" />Marcar todos</button>
            <button type="button" onClick={() => setMarcados(new Set())}
              className="inline-flex h-11 items-center gap-1.5 rounded-2xl bg-white px-3 text-[13px] font-semibold ring-1 ring-line hover:bg-slate-50"><Square className="size-4" />Desmarcar todos</button>
          </div>
        </div>
        {m.observacao && <p className="mt-2 text-[12px] text-muted">{m.observacao}</p>}
      </Card>

      {/* volumes e totais */}
      <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        <Numero rotulo="Unidades" valor={fmtInt(m.unidades)} />
        <Numero rotulo="Vagas cobradas" valor={fmtInt(v.vagas)} detalhe={`${fmtInt(m.ocupadas)} ocupadas + ${fmtInt(v.demandadas)} na fila${v.estimada ? ' (estimada)' : ''}`} />
        <Numero rotulo="Profissionais" valor={fmtInt(v.prof)} detalhe={`${fmtInt(m.docentes)} docentes + ${fmtInt(m.outros)} outros`} />
        <Numero rotulo="Filas de WhatsApp" valor={fmtInt(v.filas)} detalhe={`${fmtInt(m.unidades)} unidades + ${m.filas_centrais} centrais + ${m.filas_setor} de setor`} />
        <Numero rotulo="Disparadores" valor={fmtInt(v.disparadores)} detalhe={`${fmtInt(m.unidades)} unidades + ${v.servicos} serviços`} />
        <Numero rotulo="Agentes marcados" valor={`${marcados.size} de ${d.agentes.length}`} />
      </div>
      <div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <Numero destaque rotulo={`Implantação${red ? ' com redutor' : ''}`} valor={r0(p.implRed)} onClick={titular ? undefined : () => setAjuste(true)} />
        <Numero destaque rotulo={`Mensal${red ? ' com redutor' : ''}`} valor={r0(p.mensalRed)} onClick={titular ? undefined : () => setAjuste(true)} />
        <Numero destaque rotulo={`Total no 1º ano (${d.parametros.meses} meses)`} valor={r0(p.anoRed)} onClick={titular ? undefined : () => setAjuste(true)} />
        <Numero rotulo="Custos adicionais por mês" valor={r0(c.total)} detalhe="Cobrados direto pela Meta, Anthropic e Groq; não somam" />
      </div>

      {/* agentes */}
      <Section title="Agentes" subtitle="Marque os que a prefeitura vai contratar. Preço unitário por unidade de cobrança.">
        <Card className="overflow-x-auto">
          <table className="w-full min-w-[980px] text-[13px]">
            <thead>
              <tr className="bg-purple-900 text-left text-[12px] font-semibold text-white">
                <th className="w-10 px-2 py-2" />
                <th className="px-2 py-2">Agente</th>
                <th className="px-2 py-2">Cobrança</th>
                <th className="px-2 py-2 text-right">Quantidade</th>
                <th className="px-2 py-2 text-right">Implantação unit.</th>
                <th className="px-2 py-2 text-right">Mensal unit.</th>
                <th className="px-2 py-2 text-right">Implantação</th>
                <th className="px-2 py-2 text-right">Mensal</th>
              </tr>
            </thead>
            <tbody>
              {([1, 2, 3] as const).map((t) => {
                const grupo = p.linhas.filter((l) => l.a.tipo === t);
                return [
                  <tr key={`t${t}`} className="bg-purple-50"><td colSpan={8} className="px-2 py-1.5 font-bold text-purple-900">{TIPOS[t]} ({grupo.length} agentes)</td></tr>,
                  ...grupo.map(({ a, q, on, uImpl, uMensal, impl, mensal }) => (
                    <tr key={a.num} className={clsx('border-b border-line align-top', !on && 'text-subtle')}>
                      <td className="px-2 py-2">
                        <input type="checkbox" checked={on} onChange={() => alternar(a.num)} className="size-4 accent-purple-700" aria-label={`Contratar ${a.nome}`} />
                      </td>
                      <td className="px-2 py-2">
                        <div className="font-semibold text-ink"><span className="text-subtle">{a.num}.</span> {a.nome}
                          {a.situacao !== 'Em funcionamento' && <Badge tone={a.situacao.startsWith('Pendente') ? 'gray' : 'amber'} className="ml-1.5 align-middle">{a.situacao.split(' (')[0]}</Badge>}
                        </div>
                        <div className="mt-0.5 max-w-[520px] text-[12px] leading-snug text-muted">{a.assuntos}</div>
                      </td>
                      <td className="px-2 py-2 whitespace-nowrap">{COBRANCA[a.cobranca]}</td>
                      <td className="px-2 py-2 text-right tabular">{fmtInt(q)}</td>
                      <td className="px-2 py-2 text-right tabular">{a.cobranca === 'agente' ? r0(uImpl) : brl2.format(uImpl)}</td>
                      <td className="px-2 py-2 text-right tabular">{a.cobranca === 'agente' ? r0(uMensal) : brl2.format(uMensal)}</td>
                      <td className="px-2 py-2 text-right font-semibold tabular">{r0(impl)}</td>
                      <td className="px-2 py-2 text-right font-semibold tabular">{r0(mensal)}</td>
                    </tr>
                  )),
                  <tr key={`s${t}`} className="bg-slate-50 font-semibold">
                    <td colSpan={6} className="px-2 py-1.5 text-right">Subtotal tipo {t}</td>
                    <td className="px-2 py-1.5 text-right tabular">{r0(grupo.reduce((s, l) => s + l.impl, 0))}</td>
                    <td className="px-2 py-1.5 text-right tabular">{r0(grupo.reduce((s, l) => s + l.mensal, 0))}</td>
                  </tr>,
                ];
              })}
              {titular ? (
                <>
                  <tr className="font-semibold"><td colSpan={6} className="px-2 py-1.5 text-right">Total dos agentes marcados</td>
                    <td className="px-2 py-1.5 text-right tabular">{r0(p.impl)}</td><td className="px-2 py-1.5 text-right tabular">{r0(p.mensal)}</td></tr>
                  <tr><td colSpan={6} className="px-2 py-1.5 text-right">Redutor ({pct(red)})</td>
                    <td className="px-2 py-1.5 text-right tabular">{red ? `−${r0(p.impl * red)}` : '—'}</td><td className="px-2 py-1.5 text-right tabular">{red ? `−${r0(p.mensal * red)}` : '—'}</td></tr>
                  <tr className="bg-purple-50 text-[14px] font-bold"><td colSpan={6} className="px-2 py-2 text-right">Total com redutor</td>
                    <td className="px-2 py-2 text-right tabular">{r0(p.implRed)}</td><td className="px-2 py-2 text-right tabular">{r0(p.mensalRed)}</td></tr>
                </>
              ) : (
                <tr className="bg-purple-50 text-[14px] font-bold" onClick={() => setAjuste(true)}><td colSpan={6} className="px-2 py-2 text-right">Total dos agentes marcados</td>
                  <td className="px-2 py-2 text-right tabular">{r0(p.impl)}</td><td className="px-2 py-2 text-right tabular">{r0(p.mensal)}</td></tr>
              )}
            </tbody>
          </table>
        </Card>
      </Section>

      {/* custos adicionais */}
      <Section title="Custos adicionais" subtitle="Cobrados do município diretamente pela Meta (WhatsApp), pela Anthropic (Claude) e pela Groq (áudio). Não entram no preço nem são descontados dele.">
        <Card className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-[13px]">
            <thead>
              <tr className="bg-slate-700 text-left text-[12px] font-semibold text-white">
                <th className="px-2 py-2">Item</th><th className="px-2 py-2 text-right">Quantidade no mês</th><th className="px-2 py-2 text-right">Custo unitário</th>
                <th className="px-2 py-2 text-right">Mensal</th><th className="px-2 py-2 text-right">1º ano</th>
              </tr>
            </thead>
            <tbody>
              {c.itens.map((i) => (
                <tr key={i.nome} className={clsx('border-b border-line', !i.q && 'text-subtle')}>
                  <td className="px-2 py-2 font-semibold">{i.nome}</td>
                  <td className="px-2 py-2 text-right tabular">{i.q ? `${fmtInt(i.q)} ${i.und}${i.q === 1 ? '' : 's'}` : '—'}</td>
                  <td className="px-2 py-2 text-right tabular">{brl4.format(i.u)}</td>
                  <td className="px-2 py-2 text-right tabular">{i.mensal ? brl2.format(i.mensal) : '—'}</td>
                  <td className="px-2 py-2 text-right tabular">{i.mensal ? r0(i.mensal * d.parametros.meses) : '—'}</td>
                </tr>
              ))}
              <tr className="bg-slate-50 font-bold"><td colSpan={3} className="px-2 py-2 text-right">Total dos custos adicionais</td>
                <td className="px-2 py-2 text-right tabular">{brl2.format(c.total)}</td><td className="px-2 py-2 text-right tabular">{r0(c.total * d.parametros.meses)}</td></tr>
            </tbody>
          </table>
        </Card>
        <p className="mt-2 text-[12px] text-muted">
          Premissas por aluno, por mês: {d.parametros.resp_al.toLocaleString('pt-BR')} respostas, {d.parametros.util_al.toLocaleString('pt-BR')} mensagens de utilidade,
          {' '}{d.parametros.doc_al.toLocaleString('pt-BR')} documento e {d.parametros.aud_al.toLocaleString('pt-BR')} áudio; franquia de {fmtInt(d.parametros.w_fran)} respostas grátis
          {d.parametros.w_isen ? ' e isenção de governo nas respostas' : ''}. Leitura de documentos, áudio, Oráculo e Públicos só contam com o agente marcado.
        </p>
      </Section>

      {/* todas as prefeituras */}
      {!titular && !verTodas ? (
        <div className="mt-6 flex justify-end">
          <button type="button" onClick={() => setPedirTodas(true)} className="text-[12px] font-semibold text-subtle hover:text-purple-700">Ver todas</button>
        </div>
      ) : (
      <Section title="Todas as prefeituras" subtitle={`Com os agentes marcados acima${titular ? ' e o redutor de cada prefeitura' : ''}. Toque numa linha para abri-la.`}
        action={!titular ? <button type="button" onClick={() => setVerTodas(false)} className="text-[13px] font-semibold text-purple-700">Ocultar</button> : undefined}>
        <Card className="overflow-x-auto">
          <table className="w-full min-w-[860px] text-[13px]">
            <thead>
              <tr className="bg-purple-900 text-left text-[12px] font-semibold text-white">
                <th className="px-2 py-2">Prefeitura</th><th className="px-2 py-2 text-right">Vagas cobradas</th><th className="px-2 py-2 text-right">Profissionais</th>
                {titular && <th className="px-2 py-2 text-right">Redutor</th>}<th className="px-2 py-2 text-right">Implantação</th><th className="px-2 py-2 text-right">Mensal</th>
                <th className="px-2 py-2 text-right">1º ano</th><th className="px-2 py-2 text-right">Custos adicionais/mês</th>
              </tr>
            </thead>
            <tbody>
              {todas.map(({ x, v: vx, p: px, c: cx }) => (
                <tr key={x.id} onClick={() => { abrirPrefeitura(x.id); if (!titular) setVerTodas(false); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
                  className={clsx('cursor-pointer border-b border-line hover:bg-purple-50', x.id === munId && 'bg-purple-50 font-semibold')}>
                  <td className="px-2 py-1.5">{x.nome}{x.uf ? ` – ${x.uf}` : ''}</td>
                  <td className="px-2 py-1.5 text-right tabular">{fmtInt(vx.vagas)}</td>
                  <td className="px-2 py-1.5 text-right tabular">{fmtInt(vx.prof)}</td>
                  {titular && <td className="px-2 py-1.5 text-right tabular">{x.redutor ? pct(x.redutor) : '—'}</td>}
                  <td className="px-2 py-1.5 text-right tabular">{r0(px.implRed)}</td>
                  <td className="px-2 py-1.5 text-right tabular">{r0(px.mensalRed)}</td>
                  <td className="px-2 py-1.5 text-right tabular">{r0(px.anoRed)}</td>
                  <td className="px-2 py-1.5 text-right tabular">{r0(cx.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
        <p className="mt-2 text-[12px] text-muted">{d.fonte} Fila estimada em {pct(d.parametros.taxa_fila)} das matrículas em creche quando a prefeitura não informa.</p>
      </Section>
      )}
    </div>
  );
}

/** Troca de senha: o comercial troca a dele; o titular troca a dele e a do comercial. */
function TrocarSenha({ open, onClose, titular }: { open: boolean; onClose: () => void; titular: boolean }) {
  const [nivel, setNivel] = useState<Nivel>('COMERCIAL');
  const [atual, setAtual] = useState('');
  const [nova, setNova] = useState('');
  const [confirma, setConfirma] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const trocar = useRpcMutation<{ nivel: Nivel; atual: string; nova: string }>('simulador_trocar_senha');
  const fechar = () => { setAtual(''); setNova(''); setConfirma(''); setMsg(null); onClose(); };
  const enviar = (e: React.FormEvent) => {
    e.preventDefault();
    if (nova !== confirma) { setMsg({ ok: false, texto: 'A confirmação não confere com a senha nova.' }); return; }
    trocar.mutate({ nivel, atual, nova }, {
      onSuccess: () => { setMsg({ ok: true, texto: 'Senha trocada.' }); setAtual(''); setNova(''); setConfirma(''); },
      onError: (err) => setMsg({ ok: false, texto: err.message }),
    });
  };
  const campo = 'h-11 w-full rounded-2xl bg-white px-4 text-[15px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500';
  return (
    <Sheet open={open} onClose={fechar} title="Trocar senha" subtitle="Senha nova com 6 ou mais caracteres." size="sm">
      <form onSubmit={enviar} className="space-y-3">
        {titular && (
          <label className="block">
            <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Qual senha</span>
            <select value={nivel} onChange={(e) => setNivel(e.target.value as Nivel)} className={campo}>
              <option value="COMERCIAL">Do acesso comercial</option>
              <option value="TITULAR">Do acesso do titular</option>
            </select>
          </label>
        )}
        <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Senha atual</span>
          <input type="password" autoComplete="current-password" value={atual} onChange={(e) => setAtual(e.target.value)} className={campo} /></label>
        <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Senha nova</span>
          <input type="password" autoComplete="new-password" value={nova} onChange={(e) => setNova(e.target.value)} className={campo} /></label>
        <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Confirme a senha nova</span>
          <input type="password" autoComplete="new-password" value={confirma} onChange={(e) => setConfirma(e.target.value)} className={campo} /></label>
        {msg && <p role="status" className={clsx('rounded-xl px-3 py-2 text-[13px] font-semibold', msg.ok ? 'bg-green-50 text-green-800' : 'bg-red-50 text-red-800')}>{msg.texto}</p>}
        <Button type="submit" block loading={trocar.isPending} disabled={!atual || nova.length < 6 || !confirma}>Trocar senha</Button>
      </form>
    </Sheet>
  );
}

function Numero({ rotulo, valor, detalhe, destaque, onClick }: { rotulo: string; valor: string; detalhe?: string; destaque?: boolean; onClick?: () => void }) {
  const corpo = (
    <>
      <div className={clsx('font-display font-extrabold leading-none tabular', destaque ? 'text-[22px] text-purple-900' : 'text-[20px]')}>{valor}</div>
      <div className="mt-1 text-[12px] font-semibold leading-tight text-ink-2">{rotulo}</div>
      {detalhe && <div className="mt-0.5 text-[11.5px] leading-tight text-muted">{detalhe}</div>}
    </>
  );
  // clicável sem parecer: o ajuste do total não deve chamar a atenção
  return onClick ? (
    <Card as="button" type="button" onClick={onClick} className={clsx('cursor-default p-3 text-left', destaque && 'bg-purple-50 ring-purple-200')}>{corpo}</Card>
  ) : (
    <Card className={clsx('p-3', destaque && 'bg-purple-50 ring-purple-200')}>{corpo}</Card>
  );
}

/** Pede a senha do titular e chama a função (que confere no banco). */
function SenhaTitular({ open, onClose, fn, titulo, onOk }: { open: boolean; onClose: () => void; fn: string; titulo: string; onOk: (senha: string) => void }) {
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const conferir = useRpcMutation<{ senha: string }, { ok: boolean; erro?: string; restantes?: number }>(fn);
  const fechar = () => { setSenha(''); setErro(null); onClose(); };
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setErro(null);
    try {
      const r = await conferir.mutateAsync({ senha });
      if (r.ok) { const s = senha; setSenha(''); onOk(s); return; }
      setErro(`${r.erro ?? 'Senha incorreta.'}${r.restantes != null && r.restantes > 0 ? ` Restam ${r.restantes} tentativa(s).` : ''}`);
    } catch (err) {
      setErro(err instanceof Error ? err.message : 'Não foi possível conferir.');
    }
    setSenha('');
  };
  return (
    <Sheet open={open} onClose={fechar} title={titulo} size="sm">
      <form onSubmit={enviar} className="space-y-3">
        <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Senha</span>
          <input type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} autoFocus
            className="h-11 w-full rounded-2xl bg-white px-4 text-[15px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500" /></label>
        {erro && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">{erro}</p>}
        <Button type="submit" block loading={conferir.isPending} disabled={!senha}>Continuar</Button>
      </form>
    </Sheet>
  );
}

/** Ajuste do total da prefeitura aberta: a senha do titular e o percentual; nada na tela indica que houve ajuste. */
function AjusteTotal({ open, onClose, municipio }: { open: boolean; onClose: () => void; municipio: Municipio }) {
  const [senha, setSenha] = useState<string | null>(null);
  const [percentual, setPercentual] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const salvar = useRpcMutation<{ senha: string; municipio_id: number; percentual: number }, { ok: boolean; erro?: string }>('simulador_ajuste', ['simulador_precos']);
  const fechar = () => { setSenha(null); setPercentual(''); setErro(null); onClose(); };
  if (open && senha == null) {
    return <SenhaTitular open onClose={fechar} fn="simulador_conferir" titulo="Ajuste do total"
      onOk={(s) => { setSenha(s); setPercentual(String(Math.round((1 - municipio.fator) * 1000) / 10)); }} />;
  }
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setErro(null);
    const n = Number(percentual.replace(',', '.'));
    if (!Number.isFinite(n) || n < 0 || n > 90) { setErro('Use um percentual entre 0 e 90.'); return; }
    try {
      const r = await salvar.mutateAsync({ senha: senha ?? '', municipio_id: municipio.id, percentual: n });
      if (r.ok) fechar();
      else setErro(r.erro ?? 'Não foi possível salvar.');
    } catch (err) {
      setErro(err instanceof Error ? err.message : 'Não foi possível salvar.');
    }
  };
  return (
    <Sheet open={open} onClose={fechar} title="Ajuste do total" subtitle={`${municipio.nome}${municipio.uf ? ` – ${municipio.uf}` : ''}`} size="sm">
      <form onSubmit={enviar} className="space-y-3">
        <label className="block"><span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Percentual</span>
          <span className="flex h-11 items-center gap-1 rounded-2xl bg-white px-3 ring-1 ring-line focus-within:ring-2 focus-within:ring-purple-500">
            <input inputMode="decimal" value={percentual} onChange={(e) => setPercentual(e.target.value)} autoFocus
              className="min-w-0 flex-1 bg-transparent text-right text-[15px] font-semibold outline-none" aria-label="Percentual" />
            <span className="text-[15px] font-semibold text-muted">%</span>
          </span></label>
        <p className="text-[12px] text-muted">Reduz implantação e mensal desta prefeitura. 0 tira o ajuste.</p>
        {erro && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">{erro}</p>}
        <Button type="submit" block loading={salvar.isPending}>Aplicar</Button>
      </form>
    </Sheet>
  );
}
