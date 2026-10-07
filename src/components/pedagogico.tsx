// Sprint 2 (pedagógico): boletim, plano de intervenção, declarações e o AEE visto pela família.
import { useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { Accessibility, Check, FileBadge, Printer, ShieldCheck, Sprout, Undo2 } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import {
  BIMESTRES, CICLO_ALFA, DIA_AEE_LONGO, LEITURA, MODALIDADE_AEE, MOTIVO_RISCO, NIVEL_ALFA, PRESENCA_AEE, SITUACAO_DECLARACAO, SITUACAO_PLANO,
  TIPO_DECLARACAO, fmtNota, notaCor,
} from '@/lib/pedagogico';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

const CHAVES = ['notas_turma', 'boletim', 'familia_boletim', 'risco_lista', 'desempenho_painel', 'alfabetizacao_turma', 'aee_lista', 'aee_plano',
  'aee_painel', 'familia_aee', 'declaracoes_aluno', 'familia_declaracoes', 'aee_orientacoes_turma'];
export function useRecarregarPedagogico() {
  const qc = useQueryClient();
  return () => CHAVES.forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

export function NivelBadge({ nivel, curto }: { nivel?: string | null; curto?: boolean }) {
  if (!nivel) return <span className="text-subtle">—</span>;
  const n = NIVEL_ALFA[nivel];
  return <Badge tone={n?.tone ?? 'gray'}>{curto ? n?.curto : n?.label ?? nivel}</Badge>;
}

/** Boletim de um aluno: notas por componente e bimestre (fundamental) ou pareceres (educação infantil), alfabetização, frequência e planos. */
export function BoletimView({ b, familia }: { b: any; familia?: boolean }) {
  if (!b || b.sem_matricula) return <Card><EmptyState compact title="Sem matrícula ativa" body="O boletim aparece quando a criança está matriculada na rede." /></Card>;
  const min = Number(b.media_minima ?? 6);
  const freq = b.frequencia ?? {};
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2 text-[13px] text-muted">
        <Badge tone="blue">{b.serie}</Badge><span>{b.turma} · {b.unidade}</span>
        <span>· frequência <b className={Number(freq.percentual) < Number(freq.minimo ?? 75) ? 'text-red-700' : 'text-ink'}>{freq.percentual != null ? `${String(freq.percentual).replace('.', ',')}%` : '—'}</b> (mínimo {freq.minimo}%)</span>
      </div>
      {b.parecer ? (
        <Section title="Pareceres descritivos" subtitle="Na educação infantil, a avaliação é descritiva: o desenvolvimento da criança em cada bimestre.">
          <div className="space-y-2">
            {(b.pareceres as any[]).map((p) => (
              <Card key={p.bimestre} className="p-4">
                <div className="text-[12px] font-bold uppercase tracking-wide text-purple-700">{p.bimestre}º bimestre</div>
                <p className="mt-1 text-[14.5px] leading-relaxed">{p.texto}</p>
                {!familia && p.autor && <div className="mt-1 text-[12px] text-muted">{p.autor}</div>}
              </Card>
            ))}
            {!(b.pareceres as any[]).length && <Card><EmptyState compact title="Parecer ainda não registrado" /></Card>}
          </div>
        </Section>
      ) : (
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(170px,2fr) repeat(4, 64px) 76px" largura={560} rotulo="Notas por componente e bimestre">
            <TCabecalho>
              <TCelula fixa>Componente</TCelula>{BIMESTRES.map((i) => <TCelula key={i} className="text-center">{i}º bim.</TCelula>)}<TCelula className="text-center">Média</TCelula>
            </TCabecalho>
            {(b.componentes as any[]).map((c) => (
              <TLinha key={c.nome} alerta={c.media != null && Number(c.media) < min}>
                <TCelula fixa titulo={c.nome} className="font-semibold">{c.nome}{c.recuperou ? <span className="ml-1 text-[11px] font-normal text-blue-700">rec.</span> : null}</TCelula>
                {BIMESTRES.map((i) => <TCelula key={i} className={`text-center ${notaCor(c.bimestres?.[String(i)], min)}`}>{fmtNota(c.bimestres?.[String(i)])}</TCelula>)}
                <TCelula className={`text-center ${notaCor(c.media, min)}`}>{fmtNota(c.media)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
          <p className="border-t border-line px-4 py-2 text-[12px] text-muted">Média mínima {fmtNota(min)}. A recuperação paralela substitui a nota do bimestre quando é maior (“rec.”).</p>
        </Card>
      )}
      {(b.alfabetizacao as any[])?.length > 0 && (
        <Section title="Alfabetização" subtitle="Sondagem da escrita (hipóteses da psicogênese) e da leitura, ao longo do ano.">
          <Card className="flex flex-wrap gap-2 p-3">
            {(b.alfabetizacao as any[]).map((a) => (
              <div key={a.ciclo} className="min-w-[140px] flex-1 rounded-2xl bg-slate-50 p-3">
                <div className="text-[11px] font-bold uppercase tracking-wide text-subtle">{CICLO_ALFA[a.ciclo] ?? a.ciclo}</div>
                <div className="mt-1"><NivelBadge nivel={a.nivel} /></div>
                <div className="mt-1 text-[12px] text-muted">{LEITURA[a.leitura] ?? ''}</div>
              </div>
            ))}
          </Card>
        </Section>
      )}
      {(b.planos as any[])?.length > 0 && (
        <Section title="Plano de apoio" subtitle={familia ? 'O que a escola está fazendo para a criança avançar.' : 'Planos de intervenção do ano.'}>
          <div className="space-y-2">
            {(b.planos as any[]).map((p) => <PlanoCard key={p.id} p={p} familia={familia} />)}
          </div>
        </Section>
      )}
    </div>
  );
}

export function PlanoCard({ p, familia, acoes }: { p: any; familia?: boolean; acoes?: React.ReactNode }) {
  const st = SITUACAO_PLANO[p.situacao] ?? { label: p.situacao, tone: 'gray' as const };
  return (
    <Card className="p-4">
      <div className="flex flex-wrap items-center gap-2">
        <Sprout className="size-4 text-green-700" />
        <span className="font-semibold">{p.objetivo}</span>
        <Badge tone={st.tone}>{st.label}</Badge>
        {p.atrasado && <Badge tone="red">Reavaliação atrasada</Badge>}
        {!familia && (p.motivos as string[]).map((m) => <Badge key={m} tone={MOTIVO_RISCO[m]?.tone ?? 'gray'}>{MOTIVO_RISCO[m]?.label ?? m}</Badge>)}
      </div>
      <p className="mt-1 text-[13.5px]"><b>Ações:</b> {p.acoes}</p>
      <div className="mt-1 text-[12.5px] text-muted">
        {p.responsavel ? `${p.responsavel} · ` : ''}desde {fmtDate(p.inicio)}{p.situacao === 'ATIVO' ? ` · reavaliar em ${fmtDate(p.reavaliar_em)}` : ''}
      </div>
      {p.resultado && <p className="mt-1 text-[13px] text-green-800"><b>Resultado:</b> {p.resultado}</p>}
      {acoes && <div className="mt-2 flex flex-wrap gap-2">{acoes}</div>}
    </Card>
  );
}

/** Novo plano de intervenção ou reavaliação de um plano em andamento. */
export function PlanoSheet({ alvo, onClose }: { alvo: { student_id: string; aluno: string; motivos?: string[]; plano?: any; reavaliar?: boolean } | null; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  const [motivos, setMotivos] = useState<string[]>([]);
  const [objetivo, setObjetivo] = useState('');
  const [acoes, setAcoes] = useState('');
  const [quando, setQuando] = useState('');
  const [situacao, setSituacao] = useState('SUPERADO');
  const [resultado, setResultado] = useState('');
  const [busy, setBusy] = useState(false);
  const [chave, setChave] = useState<string | null>(null);
  const k = alvo ? `${alvo.student_id}|${alvo.plano?.id ?? ''}|${alvo.reavaliar ? 'r' : 'n'}` : null;
  if (k !== chave) {
    setChave(k);
    setMotivos(alvo?.plano?.motivos ?? alvo?.motivos ?? []);
    setObjetivo(alvo?.plano?.objetivo ?? '');
    setAcoes(alvo?.plano?.acoes ?? '');
    setQuando('');
    setResultado('');
    setSituacao('SUPERADO');
  }
  const enviar = async () => {
    if (!alvo) return;
    setBusy(true);
    try {
      if (alvo.reavaliar) await rpc('plano_reavaliar', { id: alvo.plano.id, situacao, resultado, reavaliar_em: quando || null });
      else await rpc('plano_salvar', { id: alvo.plano?.id ?? null, student_id: alvo.student_id, motivos, objetivo, acoes, reavaliar_em: quando || null });
      toast({ title: alvo.reavaliar ? 'Reavaliação registrada' : 'Plano registrado', description: alvo.reavaliar ? undefined : 'A família recebe o aviso no portal e pela IARA.', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const ok = alvo?.reavaliar ? resultado.trim().length >= 10 : motivos.length > 0 && objetivo.trim().length >= 10 && acoes.trim().length >= 10;
  return (
    <Sheet open={!!alvo} onClose={onClose} title={alvo?.reavaliar ? `Reavaliar o plano · ${alvo?.aluno}` : `Plano de intervenção · ${alvo?.aluno ?? ''}`}
      subtitle={alvo?.reavaliar ? alvo?.plano?.objetivo : 'Objetivo claro, ações combinadas e data para reavaliar. A família vê o objetivo e as ações (não vê os indicadores).'}
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={!ok} onClick={enviar}>{alvo?.reavaliar ? 'Registrar reavaliação' : 'Salvar plano'}</Button>}>
      {alvo?.reavaliar ? (
        <div className="space-y-3">
          <Field label="Situação">
            <select value={situacao} onChange={(e) => setSituacao(e.target.value)} className={`${inputCls} h-11`}>
              <option value="SUPERADO">Superado — atingiu o objetivo</option><option value="ATIVO">Continuar — ajustar e reavaliar de novo</option>
              <option value="ENCAMINHADO">Encaminhado (avaliação multiprofissional, AEE, saúde)</option><option value="ENCERRADO">Encerrado (transferência ou outro motivo)</option>
            </select>
          </Field>
          <Field label="Resultado" hint="O que mudou nas notas, na leitura ou na frequência.">
            <textarea value={resultado} onChange={(e) => setResultado(e.target.value)} rows={3} maxLength={600} className={`${inputCls} h-auto py-3`} />
          </Field>
          {situacao === 'ATIVO' && <Field label="Próxima reavaliação"><input type="date" value={quando} onChange={(e) => setQuando(e.target.value)} className={`${inputCls} h-11`} /></Field>}
        </div>
      ) : (
        <div className="space-y-3">
          <Field label="Motivo(s)">
            <div className="flex flex-wrap gap-2">
              {Object.entries(MOTIVO_RISCO).map(([m, v]) => (
                <button key={m} type="button" onClick={() => setMotivos(motivos.includes(m) ? motivos.filter((x) => x !== m) : [...motivos, m])}
                  className={`inline-flex h-9 items-center gap-1 rounded-full px-3 text-[13px] font-semibold ring-1 ${motivos.includes(m) ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white ring-line'}`}>
                  {motivos.includes(m) && <Check className="size-3.5" />}{v.label}
                </button>
              ))}
            </div>
          </Field>
          <Field label="Objetivo"><input value={objetivo} onChange={(e) => setObjetivo(e.target.value)} maxLength={300} placeholder="Ex.: ler frases simples até o fim do bimestre" className={`${inputCls} h-11`} /></Field>
          <Field label="Ações" hint="Quem faz o quê e quando: contraturno, reagrupamento, atividades diferenciadas, contato com a família.">
            <textarea value={acoes} onChange={(e) => setAcoes(e.target.value)} rows={4} maxLength={1000} className={`${inputCls} h-auto py-3`} />
          </Field>
          <Field label="Reavaliar em" hint="Se ficar em branco: daqui a 45 dias."><input type="date" value={quando} onChange={(e) => setQuando(e.target.value)} className={`${inputCls} h-11`} /></Field>
        </div>
      )}
    </Sheet>
  );
}

// ---------------------------------------------------------------- Declarações
/** Declarações de um aluno (escola) ou dos filhos (família): emitir, abrir para imprimir, revogar (secretaria). */
export function DeclaracoesAluno({ studentId }: { studentId: string }) {
  const res = useRpc<any>('declaracoes_aluno', { student_id: studentId });
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return <DeclaracoesBloco studentId={studentId} disponiveis={res.data.pode_emitir ? res.data.disponiveis : []} itens={res.data.itens} podeRevogar={res.data.pode_revogar} />;
}

export function DeclaracoesFamilia() {
  const res = useRpc<any[]>('familia_declaracoes', {});
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <Card><EmptyState compact title="Nenhuma criança no cadastro" /></Card>;
  return (
    <div className="space-y-5">
      {res.data.map((k) => (
        <Section key={k.student_id} title={k.primeiro_nome}>
          <DeclaracoesBloco studentId={k.student_id} disponiveis={k.disponiveis} itens={k.itens} familia />
        </Section>
      ))}
      <p className="text-[12.5px] text-muted">Também pela IARA: “preciso da declaração de matrícula” ou “declaração de frequência para o Bolsa Família”. Quem recebe confere a autenticidade pelo código, sem senha.</p>
    </div>
  );
}

function DeclaracoesBloco({ studentId, disponiveis, itens, familia, podeRevogar }: { studentId: string; disponiveis: string[]; itens: any[]; familia?: boolean; podeRevogar?: boolean }) {
  const toast = useToast();
  const navigate = useNavigate();
  const recarregar = useRecarregarPedagogico();
  const [busy, setBusy] = useState<string | null>(null);
  const [revogar, setRevogar] = useState<any | null>(null);
  const emitir = async (tipo: string) => {
    setBusy(tipo);
    try {
      const d = await rpc<any>('declaracao_emitir', { student_id: studentId, tipo, canal: familia ? 'PORTAL' : 'UNIDADE' });
      recarregar();
      navigate(`/declaracao/${d.id}`);
    } catch (e) {
      toast({ title: 'Não emitida', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };
  return (
    <div className="space-y-3">
      {disponiveis.length > 0 ? (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          {disponiveis.map((t) => (
            <button key={t} type="button" disabled={!!busy} onClick={() => emitir(t)}
              className="flex items-start gap-3 rounded-3xl bg-white p-4 text-left shadow-soft ring-1 ring-line/70 transition hover:ring-purple-300 disabled:opacity-60">
              <span className="inline-flex size-10 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-purple-500 to-purple-700 text-white"><FileBadge className="size-5" /></span>
              <span className="min-w-0">
                <span className="block font-semibold">{busy === t ? 'Emitindo…' : TIPO_DECLARACAO[t]?.label ?? t}</span>
                <span className="block text-[12.5px] text-muted">{TIPO_DECLARACAO[t]?.hint}</span>
              </span>
            </button>
          ))}
        </div>
      ) : familia ? <p className="text-[13px] text-muted">Declaração sai para criança matriculada na rede ou inscrita na fila de espera.</p> : null}
      <Card className="overflow-hidden">
        {itens.length ? (
          <Tabela colunas="minmax(190px,2fr) 150px 110px 100px 90px minmax(120px,1fr)" largura={820} rotulo="Declarações emitidas">
            <TCabecalho><TCelula fixa>Declaração</TCelula><TCelula>Código</TCelula><TCelula>Emitida</TCelula><TCelula>Validade</TCelula><TCelula>Situação</TCelula><TCelula /></TCabecalho>
            {itens.map((d) => {
              const st = SITUACAO_DECLARACAO[d.situacao] ?? { label: d.situacao, tone: 'gray' as const };
              return (
                <TLinha key={d.id}>
                  <TCelula fixa titulo={d.conteudo?.titulo} className="font-semibold">{d.conteudo?.titulo ?? TIPO_DECLARACAO[d.tipo]?.label}</TCelula>
                  <TCelula className="font-mono text-[12.5px]">{d.codigo}</TCelula>
                  <TCelula>{fmtDate(d.emitida_em)}</TCelula>
                  <TCelula>{fmtDate(d.valida_ate)}</TCelula>
                  <TCelula livre><Badge tone={st.tone}>{st.label}</Badge></TCelula>
                  <TCelula livre className="flex justify-end gap-1">
                    <Link to={`/declaracao/${d.id}`} className="inline-flex h-8 items-center gap-1 rounded-xl px-2 text-[12.5px] font-semibold text-blue-700 hover:bg-blue-50"><Printer className="size-4" />Abrir</Link>
                    {podeRevogar && d.situacao === 'VALIDA' && <button type="button" onClick={() => setRevogar(d)} className="inline-flex h-8 items-center gap-1 rounded-xl px-2 text-[12.5px] font-semibold text-red-700 hover:bg-red-50"><Undo2 className="size-4" />Revogar</button>}
                  </TCelula>
                </TLinha>
              );
            })}
          </Tabela>
        ) : <EmptyState compact title="Nenhuma declaração emitida" />}
      </Card>
      <RevogarSheet d={revogar} onClose={() => setRevogar(null)} />
    </div>
  );
}

function RevogarSheet({ d, onClose }: { d: any | null; onClose: () => void }) {
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('declaracao_revogar', { id: d.id, motivo });
      toast({ title: 'Declaração revogada', description: 'A verificação pública passa a mostrar “revogada”.', tone: 'success' });
      recarregar();
      setMotivo('');
      onClose();
    } catch (e) {
      toast({ title: 'Não revogada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!d} onClose={onClose} title={`Revogar ${d?.codigo ?? ''}`} subtitle="Use quando a declaração saiu com erro ou deixou de valer. Fica na trilha de auditoria."
      footer={<Button block size="lg" variant="danger" loading={busy} disabled={motivo.trim().length < 10} onClick={enviar}>Revogar</Button>}>
      <Field label="Motivo"><textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} maxLength={300} className={`${inputCls} h-auto py-3`} /></Field>
    </Sheet>
  );
}

// ---------------------------------------------------------------- AEE na família
export function AeeFamilia() {
  const res = useRpc<any[]>('familia_aee', {});
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) {
    return <Card><EmptyState compact title="Nenhum plano de AEE em andamento" body="O atendimento educacional especializado é para crianças com deficiência, TEA ou altas habilidades. Para pedir avaliação, fale com a escola ou com a IARA." /></Card>;
  }
  const ciente = async (id: string) => {
    try {
      await rpc('familia_aee_ciente', { plano_id: id });
      toast({ title: 'Ciência confirmada', description: 'O(a) professor(a) do AEE vê a sua confirmação.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  return (
    <div className="space-y-4">
      {res.data.map((x) => {
        const p = x.plano;
        return (
          <Card key={p.id} className="p-4">
            <div className="flex flex-wrap items-center gap-2">
              <Accessibility className="size-5 text-purple-700" />
              <span className="font-display text-[17px] font-extrabold">{x.primeiro_nome}</span>
              <Badge tone="purple">{MODALIDADE_AEE[p.modalidade] ?? p.modalidade}</Badge>
              {p.situacao === 'EM_REVISAO' && <Badge tone="amber">Em revisão</Badge>}
            </div>
            <div className="mt-2 grid grid-cols-1 gap-3 text-[14px] sm:grid-cols-2">
              <div><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Quando</div>
                {(p.dias as string[]).map((d) => DIA_AEE_LONGO[d] ?? d).join(' e ')}{p.turno ? ` · ${SHIFT[p.turno]?.toLowerCase() ?? p.turno}` : ''} · {p.duracao_min} min</div>
              <div><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Com quem e onde</div>{p.profissional ?? '—'}{p.local ? ` · ${p.local}` : ''}</div>
              <div className="sm:col-span-2"><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Objetivos</div>{p.objetivos}</div>
              {(p.recursos as any[]).length > 0 && <div className="sm:col-span-2"><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Recursos</div>{(p.recursos as any[]).map((r) => r.rotulo).join(' · ')}</div>}
              {p.articulacao_familia && <div className="sm:col-span-2"><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Com a família</div>{p.articulacao_familia}</div>}
            </div>
            {x.presenca?.previstos > 0 && (
              <div className="mt-3 text-[13px] text-muted">Presença nos últimos 60 dias: <b className="text-ink">{x.presenca.presencas} de {x.presenca.previstos}</b> atendimentos</div>
            )}
            {(x.atendimentos as any[]).length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {(x.atendimentos as any[]).map((a) => <Badge key={a.data} tone={PRESENCA_AEE[a.presenca]?.tone ?? 'gray'}>{fmtDate(a.data)} · {PRESENCA_AEE[a.presenca]?.label}</Badge>)}
              </div>
            )}
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {p.familia_ciente_em ? <Badge tone="green" icon={ShieldCheck}>Ciente desde {fmtDateTime(p.familia_ciente_em)}</Badge>
                : <Button size="sm" variant="purple" icon={Check} onClick={() => ciente(p.id)}>Estou ciente do plano</Button>}
              <span className="text-[12px] text-muted">Revisão prevista: {fmtDate(p.revisar_em)}</span>
            </div>
          </Card>
        );
      })}
      <p className="text-[12.5px] text-muted">Diagnóstico e laudo não aparecem aqui: ficam só com a equipe autorizada. Pela IARA: “plano do AEE”.</p>
    </div>
  );
}
