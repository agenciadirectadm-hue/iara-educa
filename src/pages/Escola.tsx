import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Apple, BellRing, CalendarCheck, CalendarDays, Check, ChevronRight, MessageCircle, NotebookPen, Plus, Send, ShieldAlert, Vote } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, timeAgo } from '@/lib/format';
import { MOTIVO_RESTRICAO, SITUACAO_JUSTIFICATIVA, SITUACAO_RESTRICAO, TIPO_MURAL, diaCurto, pctTone } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Meter, PageHeader, Section, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { ProximosEventos } from '@/components/escola';
import { GradeCardapio } from './Nutricao';
import { AgendaLista, NovaOcorrenciaSheet, OcorrenciaSheet, useRecarregarVidaEscolar } from '@/components/vida-escolar';
import { GRAVIDADE, SITUACAO_OCORRENCIA, TIPO_OCORRENCIA } from '@/lib/escola';
import { AeeFamilia, BoletimView, DeclaracoesFamilia } from '@/components/pedagogico';

type Aba = 'frequencia' | 'cardapio' | 'avisos' | 'calendario' | 'agenda' | 'ocorrencias' | 'boletim' | 'aee' | 'declaracoes';

/** Vida escolar da família: frequência, cardápio de cada filho, avisos da escola e calendário. Tudo também pela IARA. */
export default function Escola() {
  const { me } = useSession();
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'avisos') as Aba;
  const avisos = useRpc<any>('familia_avisos', {}, { enabled: !!me?.guardian });
  const agenda = useRpc<any>('familia_agenda', {}, { enabled: !!me?.guardian });
  const ocorr = useRpc<any>('familia_ocorrencias', {}, { enabled: !!me?.guardian });
  const aee = useRpc<any[]>('familia_aee', {}, { enabled: !!me?.guardian });
  if (me?.scope !== 'GUARDIAN') return <Card><EmptyState title="Área da família" body="Esta página é do portal da família." /></Card>;
  if (!me.guardian) return <Card><EmptyState title="Complete o cadastro da família" body="Depois do cadastro, a vida escolar dos seus filhos aparece aqui." /></Card>;
  const pend = (avisos.data?.nao_lidos ?? 0) + (avisos.data?.enquetes_abertas ?? 0);
  return (
    <div>
      <PageHeader eyebrow="Portal da família" title={<span className="inline-flex items-center gap-2">Vida escolar<Simulado detail="Frequência, cardápio e avisos de demonstração." /></span>}
        subtitle="Tudo isto também pela IARA no WhatsApp: pergunte “faltas da Ana”, “agenda de hoje”, “cardápio da semana” ou “avisos da escola”."
        actions={<Link to="/iara" className="inline-flex h-10 items-center gap-1.5 rounded-2xl bg-purple-700 px-3 text-[14px] font-semibold text-white"><MessageCircle className="size-4" />Perguntar à IARA</Link>} />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={[
        { value: 'avisos', label: 'Avisos', count: pend || null },
        { value: 'agenda', label: 'Agenda', count: agenda.data?.aguardando_ciencia || null },
        { value: 'ocorrencias', label: 'Ocorrências', count: ocorr.data?.aguardando_ciencia || null },
        { value: 'boletim', label: 'Boletim' },
        ...(aee.data?.length ? [{ value: 'aee' as Aba, label: 'AEE', count: aee.data.filter((x) => !x.plano.familia_ciente_em).length || null }] : []),
        { value: 'frequencia', label: 'Frequência' },
        { value: 'cardapio', label: 'Cardápio' },
        { value: 'declaracoes', label: 'Declarações' },
        { value: 'calendario', label: 'Calendário' },
      ]} />
      <div className="mt-3">
        {aba === 'avisos' && <Avisos res={avisos} />}
        {aba === 'agenda' && <AgendaFamilia res={agenda} />}
        {aba === 'ocorrencias' && <OcorrenciasFamilia res={ocorr} />}
        {aba === 'frequencia' && <FrequenciaFamilia />}
        {aba === 'boletim' && <BoletimFamilia />}
        {aba === 'aee' && <AeeFamilia />}
        {aba === 'declaracoes' && <DeclaracoesFamilia />}
        {aba === 'cardapio' && <CardapioFamilia />}
        {aba === 'calendario' && <ProximosEventos dias={120} limite={30} />}
      </div>
    </div>
  );
}

function BoletimFamilia() {
  const res = useRpc<any[]>('familia_boletim', {});
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <Card><EmptyState compact title="Nenhuma criança matriculada" body="Quando houver matrícula, o boletim aparece aqui." /></Card>;
  return (
    <div className="space-y-6">
      {res.data.map((b) => (
        <Section key={b.student_id} title={b.primeiro_nome}>
          <BoletimView b={b} familia />
        </Section>
      ))}
      <p className="text-[12.5px] text-muted">Pela IARA: “boletim da Ana” ou “como ela está na escola?”.</p>
    </div>
  );
}

/** Resumo para o início e para a página da família: avisos pendentes e a presença de cada filho. */
export function VidaEscolarResumo() {
  const agenda = useRpc<any>('familia_agenda', {});
  const ocorr = useRpc<any>('familia_ocorrencias', {});
  const avisos = useRpc<any>('familia_avisos', {});
  const freq = useRpc<any[]>('familia_frequencia', {});
  const a = avisos.data;
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <Link to="/escola?aba=avisos" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:ring-purple-200">
        <span className="relative inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-purple-500 to-purple-700 text-white"><BellRing className="size-5" />
          {(a?.nao_lidos ?? 0) > 0 && <span className="absolute -right-1 -top-1 inline-flex min-w-5 items-center justify-center rounded-full bg-red-600 px-1 text-[11px] font-bold ring-2 ring-white">{a.nao_lidos}</span>}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block font-semibold">Avisos da escola</span>
          <span className="block truncate text-[12.5px] text-muted">{a ? `${fmtInt(a.nao_lidos)} novo(s) · ${fmtInt(a.pendentes_confirmacao)} pedem ciência · ${fmtInt(a.enquetes_abertas)} enquete(s)` : 'Carregando…'}</span>
        </span>
        <ChevronRight className="size-5 text-subtle" />
      </Link>
      {(freq.data ?? []).map((c) => (
        <Link key={c.student_id} to="/escola?aba=frequencia" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:ring-purple-200">
          <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-700 text-white"><CalendarCheck className="size-5" /></span>
          <span className="min-w-0 flex-1">
            <span className="block font-semibold">Frequência de {c.primeiro_nome}</span>
            <span className="block truncate text-[12.5px] text-muted">{fmtInt(c.faltas)} falta(s) em {fmtInt(c.dias)} dias · mínimo {c.minimo}%</span>
          </span>
          <Badge tone={pctTone(Number(c.percentual), Number(c.minimo))}>{String(c.percentual ?? '—').replace('.', ',')}%</Badge>
        </Link>
      ))}
      <Link to="/escola?aba=agenda" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:ring-purple-200">
        <span className="relative inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-sky-500 to-blue-700 text-white"><NotebookPen className="size-5" />
          {(agenda.data?.aguardando_ciencia ?? 0) > 0 && <span className="absolute -right-1 -top-1 inline-flex min-w-5 items-center justify-center rounded-full bg-red-600 px-1 text-[11px] font-bold ring-2 ring-white">{agenda.data.aguardando_ciencia}</span>}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block font-semibold">Agenda escolar</span>
          <span className="block truncate text-[12.5px] text-muted">{agenda.data ? `${fmtInt(agenda.data.hoje)} para hoje · ${fmtInt(agenda.data.aguardando_ciencia)} pedem ciência` : 'Recados, tarefas e bilhetes'}</span>
        </span>
        <ChevronRight className="size-5 text-subtle" />
      </Link>
      {(ocorr.data?.em_aberto ?? 0) > 0 && (
        <Link to="/escola?aba=ocorrencias" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:ring-purple-200">
          <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-amber-400 to-orange-600 text-white"><ShieldAlert className="size-5" /></span>
          <span className="min-w-0 flex-1">
            <span className="block font-semibold">Ocorrências</span>
            <span className="block truncate text-[12.5px] text-muted">{fmtInt(ocorr.data.em_aberto)} em aberto · {fmtInt(ocorr.data.aguardando_ciencia)} aguardam sua ciência</span>
          </span>
          <ChevronRight className="size-5 text-subtle" />
        </Link>
      )}
      <Link to="/escola?aba=cardapio" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:ring-purple-200">
        <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-lime-500 to-green-700 text-white"><Apple className="size-5" /></span>
        <span className="min-w-0 flex-1"><span className="block font-semibold">Cardápio da semana</span><span className="block truncate text-[12.5px] text-muted">Já com as trocas das restrições validadas</span></span>
        <ChevronRight className="size-5 text-subtle" />
      </Link>
    </div>
  );
}

function Avisos({ res }: { res: any }) {
  const qc = useQueryClient();
  const toast = useToast();
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const itens = (res.data?.avisos ?? []) as any[];
  const recarregar = () => ['familia_avisos'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
  const ler = async (a: any, confirmar = false) => {
    try {
      await rpc('familia_aviso_ler', { id: a.id, confirmar });
      if (confirmar) toast({ title: 'Ciência confirmada', description: 'A escola vê a sua confirmação.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    }
  };
  const votar = async (a: any, opcao: number) => {
    try {
      await rpc('familia_enquete_responder', { id: a.id, opcao });
      toast({ title: 'Resposta registrada', description: 'Obrigado! Você pode mudar até a enquete fechar.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    }
  };
  if (!itens.length) return <Card><EmptyState compact title="Nenhum aviso" body="Quando a escola ou a SEDUC publicar algo para a sua família, aparece aqui e na IARA." /></Card>;
  return (
    <div className="space-y-3">
      {itens.map((a) => {
        const t = TIPO_MURAL[a.tipo] ?? { label: a.tipo, tone: 'gray' as const };
        const total = a.votos ? (a.votos as any[]).reduce((s, v) => s + v.votos, 0) || 1 : 1;
        return (
          <Card key={a.id} className={clsx('p-4', !a.lido && 'ring-2 ring-purple-300')}>
            <div className="flex flex-wrap items-center gap-1.5">
              {!a.lido && <span className="size-2 rounded-full bg-purple-600" aria-label="Não lido" />}
              <Badge tone={t.tone}>{t.label}</Badge>
              <span className="text-[12px] font-semibold text-muted">{a.unidade ?? 'SEDUC Maringá'} · {timeAgo(a.publicado_em)} · para {a.filhos}</span>
            </div>
            <h3 className="mt-1.5 font-display text-[17px] font-extrabold leading-snug">{a.titulo}</h3>
            <p className="mt-1 whitespace-pre-line text-[14px] text-ink-2">{a.texto}</p>
            {a.data_evento && <p className="mt-1.5 text-[13px] font-semibold text-teal-800"><CalendarDays className="mr-1 inline size-4" />{diaCurto(a.data_evento)}</p>}
            {a.tipo === 'ENQUETE' && (
              <div className="mt-3 space-y-1.5">
                {(a.opcoes as string[]).map((o, i) => {
                  const v = a.votos?.[i]?.votos ?? 0;
                  const minha = a.minha_resposta === i + 1;
                  return a.votos ? (
                    <button key={o} onClick={() => votar(a, i + 1)} className={clsx('block w-full rounded-2xl px-3 py-2 text-left ring-1', minha ? 'bg-amber-50 ring-amber-300' : 'bg-white ring-line')}>
                      <div className="flex justify-between text-[13px]"><span className="font-semibold">{minha && <Check className="mr-1 inline size-4 text-amber-700" />}{o}</span><span className="tabular text-muted">{Math.round((100 * v) / total)}%</span></div>
                      <Meter value={v} max={total} tone="amber" className="mt-1" />
                    </button>
                  ) : (
                    <Button key={o} block variant="secondary" icon={Vote} onClick={() => votar(a, i + 1)}>{o}</Button>
                  );
                })}
              </div>
            )}
            <div className="mt-3 flex flex-wrap gap-2">
              {a.exige_confirmacao && !a.confirmado && <Button size="sm" variant="purple" icon={Check} onClick={() => ler(a, true)}>Estou ciente</Button>}
              {a.exige_confirmacao && a.confirmado && <Badge tone="green" icon={Check}>Ciência confirmada</Badge>}
              {!a.lido && !a.exige_confirmacao && a.tipo !== 'ENQUETE' && <Button size="sm" variant="secondary" onClick={() => ler(a)}>Marcar como lido</Button>}
            </div>
          </Card>
        );
      })}
    </div>
  );
}

function FrequenciaFamilia() {
  const res = useRpc<any[]>('familia_frequencia', {});
  const [justificar, setJustificar] = useState<{ kid: any; data: string } | null>(null);
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const kids = res.data ?? [];
  if (!kids.length) return <Card><EmptyState compact title="Nenhuma criança matriculada" /></Card>;
  return (
    <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
      {kids.map((c) => {
        const pct = Number(c.percentual);
        const justificadas = new Set((c.justificativas as any[]).filter((j) => j.situacao !== 'RECUSADA').map((j) => j.data));
        return (
          <Card key={c.student_id} className="p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="font-display text-lg font-extrabold">{c.primeiro_nome}</div>
                <div className="text-[12.5px] text-muted">{c.turma} · {c.unidade}</div>
              </div>
              <div className="text-right">
                <div className={clsx('font-display text-3xl font-black tabular', pctTone(pct, Number(c.minimo)) === 'red' ? 'text-red-700' : 'text-green-700')}>{String(c.percentual ?? '—').replace('.', ',')}%</div>
                <div className="text-[11.5px] text-muted">mínimo {c.minimo}%</div>
              </div>
            </div>
            <Meter value={pct} max={100} tone={pct < Number(c.minimo) ? 'red' : 'green'} className="mt-2" />
            <p className="mt-2 text-[13px] text-ink-2">{fmtInt(c.faltas)} falta(s) em {fmtInt(c.dias)} dias letivos{c.justificadas ? ` · ${fmtInt(c.justificadas)} justificada(s)` : ''}{c.consecutivas >= 3 ? ` · ${c.consecutivas} seguidas` : ''}.</p>
            <div className="mt-3 divide-y divide-line rounded-2xl ring-1 ring-line">
              {(c.faltas_recentes as any[]).length ? (c.faltas_recentes as any[]).map((f) => (
                <div key={f.data} className="flex items-center gap-2 px-3 py-2 text-[13px]">
                  <span className="w-[86px] shrink-0 font-semibold capitalize">{diaCurto(f.data)}</span>
                  <span className="min-w-0 flex-1 truncate text-muted">{f.tipo === 'FALTA_JUSTIFICADA' ? `Justificada${f.justificativa ? ' · ' + f.justificativa : ''}` : 'Falta'}</span>
                  {f.tipo === 'FALTA' && (justificadas.has(f.data)
                    ? <Badge tone={SITUACAO_JUSTIFICATIVA[(c.justificativas as any[]).find((j) => j.data === f.data)?.situacao]?.tone ?? 'amber'}>{SITUACAO_JUSTIFICATIVA[(c.justificativas as any[]).find((j) => j.data === f.data)?.situacao]?.label ?? 'Enviada'}</Badge>
                    : <Button size="sm" variant="soft" onClick={() => setJustificar({ kid: c, data: f.data })}>Justificar</Button>)}
                </div>
              )) : <p className="px-3 py-2 text-[13px] text-muted">Nenhuma falta recente. 👏</p>}
            </div>
          </Card>
        );
      })}
      <JustificarSheet alvo={justificar} onClose={() => setJustificar(null)} />
    </div>
  );
}

function JustificarSheet({ alvo, onClose }: { alvo: { kid: any; data: string } | null; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [motivo, setMotivo] = useState('');
  const [atestado, setAtestado] = useState(false);
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_justificar_falta', { student_id: alvo!.kid.student_id, data: alvo!.data, motivo, atestado, canal: 'PORTAL' });
      toast({ title: 'Justificativa enviada', description: r.mensagem, tone: 'success' });
      qc.invalidateQueries({ queryKey: ['familia_frequencia'] });
      setMotivo(''); setAtestado(false);
      onClose();
    } catch (e) {
      toast({ title: 'Não enviada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Justificar a falta de ${alvo?.kid.primeiro_nome ?? ''}`} subtitle={alvo ? diaCurto(alvo.data) : ''}
      footer={<Button block size="lg" loading={busy} disabled={motivo.trim().length < 5} onClick={enviar}>Enviar para a escola</Button>}>
      <div className="space-y-4 pt-1">
        <Field label="Motivo" hint="Conte em poucas palavras. Não precisa dizer o diagnóstico.">
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} maxLength={300} className={`${inputCls} h-auto py-3`} />
        </Field>
        <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={atestado} onChange={(e) => setAtestado(e.target.checked)} className="size-5 accent-purple-700" />Tenho atestado e vou entregar na secretaria</label>
      </div>
    </Sheet>
  );
}

function CardapioFamilia() {
  const res = useRpc<any[]>('familia_cardapio', {});
  const catalogo = useRpc<any>('cardapio', {});
  const [informar, setInformar] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="space-y-4">
      {(res.data ?? []).map((c) => (
        <Section key={c.student_id} className="mt-0" title={`Cardápio de ${c.primeiro_nome}`} subtitle={`${c.unidade} · refeições do turno da ${c.turno === 'MANHA' ? 'manhã' : c.turno === 'TARDE' ? 'tarde' : 'noite'}`}
          action={<Button size="sm" variant="secondary" icon={Plus} onClick={() => setInformar(c)}>Informar restrição</Button>}>
          {(c.restricoes as any[]).length > 0 && (
            <div className="mb-2 flex flex-wrap gap-1.5">
              {(c.restricoes as any[]).map((r, i) => <Badge key={i} tone={SITUACAO_RESTRICAO[r.situacao]?.tone}>{r.descricao.split(' (')[0]} · {SITUACAO_RESTRICAO[r.situacao]?.label}</Badge>)}
            </div>
          )}
          <Card className="p-3">{c.cardapio ? <GradeCardapio f={c.cardapio} /> : <EmptyState compact title="Cardápio ainda não publicado" />}</Card>
        </Section>
      ))}
      <InformarRestricao kid={informar} catalogo={catalogo.data?.restricoes ?? []} onClose={() => setInformar(null)} />
    </div>
  );
}

function InformarRestricao({ kid, catalogo, onClose }: { kid: any | null; catalogo: any[]; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [codigo, setCodigo] = useState('');
  const [detalhe, setDetalhe] = useState('');
  const [busy, setBusy] = useState(false);
  const sel = catalogo.find((r) => r.codigo === codigo);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_informar_restricao', { student_id: kid.student_id, codigo, detalhe });
      toast({ title: 'Restrição informada', description: r.mensagem, tone: 'success' });
      qc.invalidateQueries({ queryKey: ['familia_cardapio'] });
      setCodigo(''); setDetalhe('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!kid} onClose={onClose} title={`Restrição alimentar de ${kid?.primeiro_nome ?? ''}`} subtitle="A nutrição da SEDUC confere; a cozinha recebe só a instrução de preparo."
      footer={<Button block size="lg" loading={busy} disabled={!codigo} onClick={enviar}>Informar</Button>}>
      <div className="space-y-4 pt-1">
        <Field label="Restrição">
          <select value={codigo} onChange={(e) => setCodigo(e.target.value)} className={inputCls}>
            <option value="">Escolha…</option>
            {catalogo.map((r) => <option key={r.codigo} value={r.codigo}>{r.descricao}</option>)}
          </select>
        </Field>
        {sel && <p className="text-[13px]"><Badge tone={MOTIVO_RESTRICAO[sel.motivo]?.tone}>{MOTIVO_RESTRICAO[sel.motivo]?.label}</Badge> {sel.exige_laudo ? 'Precisa de laudo: leve à secretaria da unidade.' : 'Não precisa de laudo.'}</p>}
        {codigo === 'FRUTA_LAUDO' && (
          <Field label="Qual fruta?">
            <select value={detalhe} onChange={(e) => setDetalhe(e.target.value)} className={inputCls}>
              <option value="">Escolha…</option>
              {[['banana', 'Banana'], ['maca', 'Maçã'], ['mamao', 'Mamão'], ['laranja', 'Laranja'], ['melancia', 'Melancia'], ['pera', 'Pera']].map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </Field>
        )}
      </div>
    </Sheet>
  );
}

/** Crianças matriculadas da família (para escolher a quem se refere o bilhete ou a ocorrência). */
function useFilhos() {
  const f = useRpc<any[]>('familia_frequencia', {});
  return ((f.data ?? []) as any[]).map((k) => ({ id: k.student_id as string, nome: k.primeiro_nome as string }));
}

function AgendaFamilia({ res }: { res: any }) {
  const toast = useToast();
  const recarregar = useRecarregarVidaEscolar();
  const filhos = useFilhos();
  const [bilhete, setBilhete] = useState(false);
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const ciente = async (a: any) => {
    try {
      await rpc('familia_agenda_ciente', { id: a.id, student_id: a.filho_id });
      toast({ title: 'Ciência registrada', description: 'A professora vê a sua confirmação.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    }
  };
  return (
    <>
      <div className="mb-3 flex justify-end"><Button variant="purple" icon={Send} onClick={() => setBilhete(true)}>Mandar bilhete para a escola</Button></div>
      <Card className="overflow-hidden"><AgendaLista itens={res.data?.itens ?? []} familia onCiente={ciente} /></Card>
      <BilheteSheet open={bilhete} onClose={() => setBilhete(false)} filhos={filhos} />
    </>
  );
}

function BilheteSheet({ open, onClose, filhos }: { open: boolean; onClose: () => void; filhos: { id: string; nome: string }[] }) {
  const toast = useToast();
  const recarregar = useRecarregarVidaEscolar();
  const [filho, setFilho] = useState('');
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);
  const alvo = filho || (filhos.length === 1 ? filhos[0].id : '');
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_agenda_enviar', { student_id: alvo, texto });
      toast({ title: 'Bilhete enviado', description: r.mensagem, tone: 'success' });
      recarregar();
      setTexto('');
      onClose();
    } catch (e) {
      toast({ title: 'Não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Bilhete para a escola" subtitle="Vai para a agenda da turma: a professora e a direção veem na hora."
      footer={<Button block size="lg" icon={Send} loading={busy} disabled={!alvo || texto.trim().length < 3} onClick={enviar}>Enviar</Button>}>
      <div className="space-y-4 pt-1">
        {filhos.length > 1 && (
          <Field label="Sobre qual criança">
            <select value={filho} onChange={(e) => setFilho(e.target.value)} className={inputCls}>
              <option value="">Escolha…</option>
              {filhos.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
            </select>
          </Field>
        )}
        <Field label="Bilhete" hint="Ex.: saída mais cedo, quem vai buscar, um aviso para a professora.">
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} maxLength={1000} className={`${inputCls} h-auto py-3`} />
        </Field>
      </div>
    </Sheet>
  );
}

function OcorrenciasFamilia({ res }: { res: any }) {
  const filhos = useFilhos();
  const [aberta, setAberta] = useState<string | null>(null);
  const [nova, setNova] = useState(false);
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const itens = (res.data?.ocorrencias ?? []) as any[];
  return (
    <>
      <div className="mb-3 flex justify-end"><Button variant="purple" icon={Plus} onClick={() => setNova(true)}>Relatar algo à escola</Button></div>
      {!itens.length ? <Card><EmptyState compact title="Nenhuma ocorrência" body="Quando a escola registrar algo sobre seus filhos, ou você relatar, aparece aqui e na IARA." /></Card> : (
        <div className="space-y-2">
          {itens.map((o) => (
            <button key={o.id} onClick={() => setAberta(o.id)} className={clsx('block w-full rounded-3xl bg-white p-4 text-left shadow-soft ring-1 transition hover:ring-purple-200',
              o.aguarda_ciencia ? 'ring-2 ring-purple-300' : 'ring-line/70')}>
              <div className="flex flex-wrap items-center gap-1.5">
                <Badge tone={TIPO_OCORRENCIA[o.tipo]?.tone}>{TIPO_OCORRENCIA[o.tipo]?.label}</Badge>
                {o.gravidade !== 'LEVE' && <Badge tone={GRAVIDADE[o.gravidade]?.tone}>{GRAVIDADE[o.gravidade]?.label}</Badge>}
                <Badge tone={SITUACAO_OCORRENCIA[o.situacao]?.tone}>{SITUACAO_OCORRENCIA[o.situacao]?.label}</Badge>
                <span className="text-[12px] text-muted">{o.primeiro_nome} · {diaCurto(o.ocorrida_em?.slice(0, 10))} · {o.origem === 'FAMILIA' ? 'relatada por você' : 'registrada pela escola'}</span>
              </div>
              <p className="mt-1.5 text-[14px]">{o.descricao}</p>
              {o.aguarda_ciencia && <p className="mt-1 text-[12.5px] font-semibold text-purple-800">Toque para ler e dar ciência</p>}
              {(o.eventos as any[]).length > 0 && <p className="mt-1 text-[12.5px] text-muted">{(o.eventos as any[]).length} resposta(s) · última: {(o.eventos as any[])[(o.eventos as any[]).length - 1].texto}</p>}
            </button>
          ))}
        </div>
      )}
      <OcorrenciaSheet id={aberta} onClose={() => setAberta(null)} />
      <NovaOcorrenciaSheet open={nova} onClose={() => setNova(false)} alunos={filhos} familia />
    </>
  );
}
