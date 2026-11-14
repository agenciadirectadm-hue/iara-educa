// Apoio pedagógico interdisciplinar (dentro do AEE): família (serviços, pedido de avaliação, andamento e orientações com ciência),
// ficha do aluno (casos sem o registro técnico) e o encaminhamento pela escola.
import { useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { Baby, Check, HeartHandshake, Phone, Send } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSoDoFilho } from '@/components/filho';
import { fmtDate, fmtDateTime } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

export const APOIO_SIT: Record<string, { label: string; tone: Tone }> = {
  PEDIDO_FAMILIA: { label: 'Pedido da família', tone: 'amber' },
  ENCAMINHADO: { label: 'Encaminhado', tone: 'blue' },
  EM_TRIAGEM: { label: 'Em triagem', tone: 'purple' },
  EM_ATENDIMENTO: { label: 'Em atendimento', tone: 'purple' },
  AGUARDANDO_REDE: { label: 'Aguardando a rede', tone: 'teal' },
  CONCLUIDO: { label: 'Concluído', tone: 'green' },
  NAO_ACEITO: { label: 'Não encaminhado', tone: 'gray' },
  ARQUIVADO: { label: 'Arquivado', tone: 'gray' },
};
export const APOIO_TIPO: Record<string, string> = {
  TRIAGEM: 'Triagem', AVALIACAO: 'Avaliação', ATENDIMENTO: 'Atendimento', ORIENTACAO_FAMILIA: 'Orientação à família', ORIENTACAO_ESCOLA: 'Orientação à escola',
  REUNIAO: 'Reunião', ENCAMINHAMENTO_EXTERNO: 'Encaminhamento à rede', DEVOLUTIVA: 'Devolutiva',
};

export function SituacaoApoio({ s }: { s: string }) {
  const x = APOIO_SIT[s] ?? { label: s, tone: 'gray' as Tone };
  return <Badge tone={x.tone}>{x.label}</Badge>;
}

// ------------------------------------------------------------------ família
export function ApoioFamilia() {
  const res = useRpc<any>('familia_apoio', {});
  const so = useSoDoFilho();
  const qc = useQueryClient();
  const toast = useToast();
  const [pedir, setPedir] = useState(false);
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = { ...res.data, filhos: so(res.data.filhos), casos: so(res.data.casos) };
  const ciente = async (id: string) => {
    try {
      await rpc('familia_apoio_ciente', { id });
      toast({ title: 'Ciência registrada', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['familia_apoio'] });
    } catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); }
  };
  const orientacoes = (d.casos as any[]).flatMap((c) => (c.orientacoes as any[]).map((o) => ({ ...o, caso: c })));
  const pendentes = orientacoes.filter((o) => !o.ciente_em);
  return (
    <div className="space-y-6">
      {pendentes.length > 0 && (
        <Section title="Orientações para a família" subtitle="Depois da ciência, a orientação vai para o histórico.">
          <div className="space-y-2">
            {pendentes.map((o) => (
              <Card key={o.id} className="p-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div><div className="font-semibold">{o.caso.area} · {o.caso.primeiro_nome}</div><div className="text-[12.5px] text-muted">Enviado em {fmtDateTime(o.enviado_em)} · {o.autor}</div></div>
                  <Button size="sm" icon={Check} onClick={() => ciente(o.id)}>Estou ciente</Button>
                </div>
                <p className="mt-2 text-[14px]">{o.texto}</p>
              </Card>
            ))}
          </div>
        </Section>
      )}
      <Section title="Pedidos e acompanhamentos" action={(d.filhos as any[]).length > 0 && <Button size="sm" icon={HeartHandshake} onClick={() => setPedir(true)}>Pedir avaliação</Button>}>
        {(d.casos as any[]).length ? (
          <Card className="overflow-hidden">
            <Tabela colunas="110px 110px minmax(200px,1.2fr) 180px minmax(200px,1.2fr)" largura={860} rotulo="Pedidos e acompanhamentos">
              <TCabecalho><TCelula fixa>Protocolo</TCelula><TCelula>Criança</TCelula><TCelula>Área</TCelula><TCelula>Situação</TCelula><TCelula>Quem atende</TCelula></TCabecalho>
              {(d.casos as any[]).map((c) => (
                <TLinha key={c.id}>
                  <TCelula fixa>{c.numero}</TCelula><TCelula>{c.primeiro_nome}</TCelula><TCelula>{c.area}</TCelula><TCelula livre><SituacaoApoio s={c.situacao} /></TCelula>
                  <TCelula titulo={c.resposta_unidade ?? c.conclusao ?? undefined}>{c.profissional ? `${c.profissional} · ${c.profissional_funcao}` : c.resposta_unidade ?? `pedido em ${fmtDate(c.created_at)}`}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        ) : <Card><EmptyState compact title="Nenhum pedido" body="Se você percebe alguma dificuldade na fala, na aprendizagem, no comportamento ou na visão, peça uma avaliação: a escola analisa com você." /></Card>}
      </Section>
      <Section title="O que o apoio interdisciplinar oferece" subtitle={<span className="inline-flex items-center gap-1"><Phone className="size-3.5" />Gerência: {d.contato.telefone} · {d.contato.email}</span>}>
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
          {(d.areas as any[]).filter((a) => a.codigo !== 'FORMACAO').map((a) => (
            <Card key={a.codigo} className="p-4">
              <div className="font-semibold">{a.nome}</div>
              <p className="mt-1 text-[13.5px] text-muted">{a.resumo}</p>
            </Card>
          ))}
        </div>
      </Section>
      {orientacoes.some((o) => o.ciente_em) && (
        <Section title="Histórico de orientações">
          <Card className="overflow-hidden">
            <Tabela colunas="150px 160px minmax(260px,1fr) 150px" largura={760} rotulo="Histórico de orientações">
              <TCabecalho><TCelula fixa>Enviado em</TCelula><TCelula>Área</TCelula><TCelula>Orientação</TCelula><TCelula>Ciência</TCelula></TCabecalho>
              {orientacoes.filter((o) => o.ciente_em).map((o) => (
                <TLinha key={o.id}><TCelula fixa>{fmtDateTime(o.enviado_em)}</TCelula><TCelula>{o.caso.area}</TCelula><TCelula titulo={o.texto}>{o.texto}</TCelula><TCelula>{fmtDateTime(o.ciente_em)}</TCelula></TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
      <p className="text-[12.5px] text-muted">Pela IARA: “quero uma avaliação com a fonoaudióloga”, “psicóloga da escola” ou “orientação do apoio”. O registro técnico dos profissionais é sigiloso; você recebe o andamento e as orientações.</p>
      <PedirAvaliacaoSheet open={pedir} onClose={() => setPedir(false)} d={d} onFeito={() => qc.invalidateQueries({ queryKey: ['familia_apoio'] })} />
    </div>
  );
}

function PedirAvaliacaoSheet({ open, onClose, d, onFeito }: { open: boolean; onClose: () => void; d: any; onFeito: () => void }) {
  const toast = useToast();
  const [aluno, setAluno] = useState<string>('');
  const [area, setArea] = useState('');
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const sel = aluno || (d.filhos as any[])[0]?.student_id || '';
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_apoio_pedir', { student_id: sel, area, motivo });
      toast({ title: `Pedido ${r.numero}`, description: r.mensagem, tone: 'success' });
      setMotivo(''); setArea('');
      onFeito(); onClose();
    } catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Pedir avaliação" subtitle="O pedido vai para a escola, que analisa com você e encaminha à gerência do apoio interdisciplinar."
      footer={<Button block icon={Send} loading={busy} disabled={!sel || !area || motivo.trim().length < 10} onClick={enviar}>Enviar o pedido</Button>}>
      <div className="space-y-3">
        {(d.filhos as any[]).length > 1 && (
          <Field label="Criança"><select className={inputCls} value={sel} onChange={(e) => setAluno(e.target.value)}>{(d.filhos as any[]).map((f) => <option key={f.student_id} value={f.student_id}>{f.primeiro_nome} · {f.unidade}</option>)}</select></Field>
        )}
        <Field label="Área">
          <select className={inputCls} value={area} onChange={(e) => setArea(e.target.value)}>
            <option value="">Escolha…</option>{(d.areas as any[]).filter((a) => a.pode_pedir).map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
          </select>
        </Field>
        <Field label="O que você tem percebido?" hint="Ex.: troca letras quando fala; tem muita dificuldade para ler; chora todo dia na chegada.">
          <textarea className={inputCls + ' min-h-24 py-2'} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
        </Field>
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ ficha do aluno (aba AEE/Inclusão)
export function ApoioAluno({ studentId }: { studentId: string }) {
  const res = useRpc<any>('apoio_aluno', { student_id: studentId }, { retry: false });
  const [enc, setEnc] = useState(false);
  if (res.isLoading) return <SkeletonList rows={2} />;
  if (res.error) return null;
  const d = res.data;
  return (
    <Section title="Apoio interdisciplinar" subtitle="Psicologia, fonoaudiologia, psicopedagogia, orientação educacional e as demais áreas da gerência."
      action={d.pode_encaminhar && <Button size="sm" icon={Send} onClick={() => setEnc(true)}>Encaminhar</Button>}>
      {(d.casos as any[]).length ? (
        <Card className="overflow-hidden">
          <Tabela colunas="110px minmax(180px,1fr) 170px minmax(180px,1fr) 110px" largura={760} rotulo="Casos do apoio interdisciplinar">
            <TCabecalho><TCelula fixa>Protocolo</TCelula><TCelula>Área</TCelula><TCelula>Situação</TCelula><TCelula>Profissional</TCelula><TCelula>Desde</TCelula></TCabecalho>
            {(d.casos as any[]).map((c) => (
              <TLinha key={c.id} to={`/apoio/${c.id}`}><TCelula fixa>{c.numero}</TCelula><TCelula>{c.area_nome}</TCelula><TCelula livre><SituacaoApoio s={c.situacao} /></TCelula>
                <TCelula>{c.profissional ?? '—'}</TCelula><TCelula>{fmtDate(c.created_at)}</TCelula></TLinha>
            ))}
          </Tabela>
        </Card>
      ) : <Card><EmptyState compact title="Nenhum encaminhamento" /></Card>}
      <EncaminharSheet open={enc} onClose={() => setEnc(false)} areas={d.areas} aluno={{ id: studentId }} onFeito={() => res.refetch()} />
    </Section>
  );
}

/** Encaminhamento pela escola (direção, secretaria escolar ou AEE). Sem aluno escolhido, procura pelo nome. */
export function EncaminharSheet({ open, onClose, areas, aluno, onFeito }: {
  open: boolean; onClose: () => void; areas: { codigo: string; nome: string }[]; aluno?: { id: string; nome?: string }; onFeito?: (c: any) => void;
}) {
  const toast = useToast();
  const [sel, setSel] = useState<{ id: string; nome?: string } | null>(null);
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const busca = useRpc<any>('global_search', { q: dq }, { enabled: open && !aluno && dq.length >= 3 });
  const [area, setArea] = useState('');
  const [motivo, setMotivo] = useState('');
  const [alta, setAlta] = useState(false);
  const [busy, setBusy] = useState(false);
  const alvo = aluno ?? sel;
  const enviar = async () => {
    setBusy(true);
    try {
      const c = await rpc<any>('apoio_encaminhar', { student_id: alvo!.id, area, motivo, prioridade: alta ? 'ALTA' : 'NORMAL' });
      toast({ title: `Encaminhamento ${c.numero}`, description: 'A gerência distribui ao profissional da área.', tone: 'success' });
      setMotivo(''); setArea(''); setSel(null);
      onFeito?.(c); onClose();
    } catch (e) { toast({ title: 'Não encaminhado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Encaminhar ao apoio interdisciplinar" subtitle="Descreva o que a escola observou e o que já tentou. A família acompanha o andamento."
      footer={<Button block icon={Send} loading={busy} disabled={!alvo || !area || motivo.trim().length < 20} onClick={enviar}>Encaminhar</Button>}>
      <div className="space-y-3">
        {!aluno && (sel ? (
          <div className="flex items-center justify-between rounded-2xl bg-purple-50 p-3"><span className="font-semibold">{sel.nome}</span><Button size="sm" variant="ghost" onClick={() => setSel(null)}>Trocar</Button></div>
        ) : (
          <Field label="Aluno">
            <input className={inputCls} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome do aluno (3 letras ou mais)" />
            <div className="mt-1 space-y-0.5">
              {(busca.data?.students ?? []).slice(0, 8).map((s: any) => (
                <button key={s.id} type="button" onClick={() => setSel({ id: s.id, nome: s.name })} className="flex w-full items-center gap-2 rounded-xl px-2 py-1.5 text-left text-[13.5px] hover:bg-slate-50">
                  <Baby className="size-4 text-purple-700" /><span className="truncate font-semibold">{s.name}</span><span className="truncate text-[12px] text-muted">{s.sub}</span>
                </button>
              ))}
            </div>
          </Field>
        ))}
        <Field label="Área"><select className={inputCls} value={area} onChange={(e) => setArea(e.target.value)}><option value="">Escolha…</option>{areas.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}</select></Field>
        <Field label="O que a escola observou e já tentou"><textarea className={inputCls + ' min-h-28 py-2'} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Field>
        <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={alta} onChange={(e) => setAlta(e.target.checked)} />Prioridade alta (sofrimento intenso, risco de evasão ou regressão importante)</label>
      </div>
    </Sheet>
  );
}

export function LinkApoio({ id, children }: { id: string; children: React.ReactNode }) {
  return <Link to={`/apoio/${id}`} className="font-semibold text-purple-700">{children}</Link>;
}
