// Caso do apoio interdisciplinar: andamento, registros (técnico sigiloso só para o autor e a chefia), orientações liberadas,
// atribuição (gerência), análise do pedido da família (escola) e conclusão (profissional).
import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { Check, Lock, Send, UserPlus, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { Badge, Button, Card, DataPair, ErrorState, Field, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { APOIO_TIPO, SituacaoApoio } from '@/components/apoio';
import { Crumbs } from '@/components/Crumbs';

export default function ApoioCaso() {
  const { id } = useParams();
  const { can } = useSession();
  const res = useRpc<any>('apoio_caso', { id });
  const toast = useToast();
  const [registrar, setRegistrar] = useState(false);
  const [atribuir, setAtribuir] = useState(false);
  const [analisar, setAnalisar] = useState(false);
  const [concluir, setConcluir] = useState(false);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const c = res.data;
  const aberto = ['ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE'].includes(c.situacao);
  const acao = async (fn: string, args: object, ok: string, fechar: () => void) => {
    try { await rpc(fn, args); toast({ title: ok, tone: 'success' }); fechar(); res.refetch(); }
    catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); }
  };
  return (
    <div>
      <Crumbs items={[{ label: 'Apoio interdisciplinar', to: '/apoio' }, { label: c.numero }]} />
      <PageHeader eyebrow={`${c.area_nome} · ${c.numero}`} title={<span className="inline-flex items-center gap-2">{c.aluno}{c.is_demo && <Simulado />}</span>}
        subtitle={`${c.unidade}${c.etapa ? ` · ${c.etapa}` : ''}${c.aee ? ' · com plano do AEE' : ''}`}
        actions={<div className="flex flex-wrap gap-2">
          {c.pode_analisar && <Button onClick={() => setAnalisar(true)}>Analisar o pedido da família</Button>}
          {c.pode_atribuir && aberto && <Button variant="secondary" icon={UserPlus} onClick={() => setAtribuir(true)}>{c.profissional ? 'Trocar profissional' : 'Atribuir profissional'}</Button>}
          {c.pode_atender && aberto && <Button icon={Send} onClick={() => setRegistrar(true)}>Registrar</Button>}
          {c.pode_atender && aberto && <Button variant="secondary" icon={Check} onClick={() => setConcluir(true)}>Concluir</Button>}
        </div>} />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_320px]">
        <div className="space-y-4">
          <Card className="p-4">
            <div className="mb-1 text-[12px] font-bold uppercase tracking-wide text-subtle">Motivo do encaminhamento · {c.origem === 'FAMILIA' ? 'pedido da família' : c.origem === 'AEE' ? 'AEE' : 'escola'}</div>
            <p className="text-[14.5px]">{c.motivo}</p>
            {c.analise_unidade && <p className="mt-2 text-[13.5px] text-muted"><b>Análise da escola:</b> {c.analise_unidade}</p>}
            {c.conclusao && <p className="mt-2 text-[13.5px] text-green-800"><b>Conclusão:</b> {c.conclusao}</p>}
          </Card>
          <Section title="Registros" subtitle="O registro técnico aparece só para quem o escreveu e para a chefia; as orientações liberadas aparecem para a escola e para a família.">
            <div className="space-y-2">
              {(c.registros as any[]).map((r) => (
                <Card key={r.id} className="p-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="font-semibold">{APOIO_TIPO[r.tipo] ?? r.tipo} · {fmtDate(r.data)}</div>
                    <div className="text-[12.5px] text-muted">{r.autor}</div>
                  </div>
                  {r.registro_tecnico ? <p className="mt-2 rounded-xl bg-slate-50 p-2 text-[13.5px]"><Lock className="mr-1 inline size-3.5 text-slate-500" />{r.registro_tecnico}</p>
                    : r.tem_tecnico ? <p className="mt-2 text-[12.5px] text-muted"><Lock className="mr-1 inline size-3.5" />Registro técnico sigiloso (só o profissional e a chefia).</p> : null}
                  {r.orientacao_escola && <p className="mt-2 text-[13.5px]"><b>Para a escola:</b> {r.orientacao_escola}</p>}
                  {r.orientacao_familia && <p className="mt-2 text-[13.5px]"><b>Para a família:</b> {r.orientacao_familia} <Badge tone={r.familia_ciente_em ? 'green' : 'amber'}>{r.familia_ciente_em ? `ciente ${fmtDateTime(r.familia_ciente_em)}` : 'aguardando ciência'}</Badge></p>}
                </Card>
              ))}
              {(c.registros as any[]).length === 0 && <Card className="p-4 text-[13.5px] text-muted">Ainda sem registros.</Card>}
            </div>
          </Section>
        </div>
        <div className="space-y-3">
          <Card className="space-y-2 p-4">
            <DataPair label="Situação" value={<SituacaoApoio s={c.situacao} />} />
            <DataPair label="Prioridade" value={c.prioridade === 'ALTA' ? <Badge tone="red">alta</Badge> : 'normal'} />
            <DataPair label="Profissional" value={c.profissional ?? '—'} />
            <DataPair label="Pedido em" value={fmtDateTime(c.created_at)} />
            <DataPair label="Encaminhado em" value={fmtDateTime(c.encaminhado_em)} />
            <DataPair label="Atribuído em" value={fmtDateTime(c.atribuido_em)} />
            <DataPair label="1º atendimento" value={fmtDateTime(c.primeiro_atendimento_em)} />
            {c.solicitado_por && <DataPair label="Solicitado por" value={c.solicitado_por} />}
          </Card>
          {can('students.read') && <Link to={`/alunos/${c.student_id}?aba=aee`} className="block text-[13.5px] font-semibold text-purple-700">Ficha do aluno →</Link>}
          {(c.outros as any[]).length > 0 && (
            <Card className="p-4 text-[13.5px]"><div className="mb-1 font-semibold">Outros casos do aluno</div>
              {(c.outros as any[]).map((o) => <Link key={o.id} to={`/apoio/${o.id}`} className="block text-purple-700">{o.numero} · {o.area_nome} · {o.situacao_rotulo}</Link>)}
            </Card>
          )}
        </div>
      </div>
      <RegistrarSheet open={registrar} onClose={() => setRegistrar(false)} onSalvar={(v) => acao('apoio_registrar', { caso_id: c.id, ...v }, 'Registro salvo', () => setRegistrar(false))} />
      <Sheet open={atribuir} onClose={() => setAtribuir(false)} title="Atribuir profissional" subtitle="Primeiro os da área do caso, com quantos casos abertos cada um tem.">
        <div className="space-y-1">
          {((c.profissionais ?? []) as any[]).map((p) => (
            <button key={p.id} type="button" onClick={() => acao('apoio_atribuir', { id: c.id, staff_id: p.id }, `Atribuído a ${p.nome}`, () => setAtribuir(false))}
              className="flex w-full items-center justify-between rounded-xl px-3 py-2 text-left hover:bg-slate-50">
              <span><b>{p.nome}</b> <span className="text-muted">· {p.area === c.area ? 'mesma área' : p.area.toLowerCase().replace('_', ' ')}</span></span>
              <span className="text-[12.5px] text-muted">{p.abertos} abertos</span>
            </button>
          ))}
        </div>
      </Sheet>
      <AnaliseSheet open={analisar} onClose={() => setAnalisar(false)} onSalvar={(aceitar, motivo, alta) => acao('apoio_encaminhar', { id: c.id, aceitar, motivo, prioridade: alta ? 'ALTA' : '' }, aceitar ? 'Encaminhado à gerência' : 'Resposta enviada à família', () => setAnalisar(false))} />
      <ConcluirSheet open={concluir} onClose={() => setConcluir(false)} onSalvar={(t) => acao('apoio_concluir', { id: c.id, conclusao: t }, 'Caso concluído', () => setConcluir(false))} />
    </div>
  );
}

function RegistrarSheet({ open, onClose, onSalvar }: { open: boolean; onClose: () => void; onSalvar: (v: any) => void }) {
  const [v, setV] = useState<any>({ tipo: 'ATENDIMENTO', presenca: 'PRESENTE', data: new Date().toISOString().slice(0, 10) });
  return (
    <Sheet open={open} onClose={onClose} title="Registrar" subtitle="O técnico é sigiloso. As orientações aparecem para a escola e para a família (que dá ciência)."
      footer={<Button block onClick={() => onSalvar(v)}>Salvar o registro</Button>}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Field label="Tipo"><select className={inputCls} value={v.tipo} onChange={(e) => setV({ ...v, tipo: e.target.value })}>{Object.entries(APOIO_TIPO).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
          <Field label="Data"><input type="date" className={inputCls} value={v.data} onChange={(e) => setV({ ...v, data: e.target.value })} /></Field>
        </div>
        <Field label="Presença"><select className={inputCls} value={v.presenca} onChange={(e) => setV({ ...v, presenca: e.target.value })}><option value="PRESENTE">Presente</option><option value="FALTOU">Faltou</option></select></Field>
        <Field label="Registro técnico (sigiloso)"><textarea className={inputCls + ' min-h-24 py-2'} value={v.registro_tecnico ?? ''} onChange={(e) => setV({ ...v, registro_tecnico: e.target.value })} /></Field>
        <Field label="Orientação à escola (liberada)"><textarea className={inputCls + ' min-h-20 py-2'} value={v.orientacao_escola ?? ''} onChange={(e) => setV({ ...v, orientacao_escola: e.target.value })} /></Field>
        <Field label="Orientação à família (liberada, com ciência)"><textarea className={inputCls + ' min-h-20 py-2'} value={v.orientacao_familia ?? ''} onChange={(e) => setV({ ...v, orientacao_familia: e.target.value })} /></Field>
        <Field label="Mudar a situação"><select className={inputCls} value={v.situacao ?? ''} onChange={(e) => setV({ ...v, situacao: e.target.value })}>
          <option value="">Manter</option><option value="EM_TRIAGEM">Em triagem</option><option value="EM_ATENDIMENTO">Em atendimento</option><option value="AGUARDANDO_REDE">Aguardando a rede (saúde ou proteção)</option>
        </select></Field>
      </div>
    </Sheet>
  );
}

function AnaliseSheet({ open, onClose, onSalvar }: { open: boolean; onClose: () => void; onSalvar: (aceitar: boolean, motivo: string, alta: boolean) => void }) {
  const [m, setM] = useState('');
  const [alta, setAlta] = useState(false);
  return (
    <Sheet open={open} onClose={onClose} title="Pedido da família" subtitle="Converse com a família e com a professora. Encaminhe à gerência ou explique à família por que não agora."
      footer={<div className="flex gap-2"><Button variant="danger" icon={X} disabled={m.trim().length < 10} onClick={() => onSalvar(false, m, alta)}>Não encaminhar</Button><Button icon={Send} disabled={m.trim().length < 10} onClick={() => onSalvar(true, m, alta)}>Encaminhar</Button></div>}>
      <Field label="Análise da escola (a família vê se não for encaminhado)"><textarea className={inputCls + ' min-h-24 py-2'} value={m} onChange={(e) => setM(e.target.value)} /></Field>
      <label className="mt-2 flex items-center gap-2 text-[14px]"><input type="checkbox" checked={alta} onChange={(e) => setAlta(e.target.checked)} />Prioridade alta</label>
    </Sheet>
  );
}

function ConcluirSheet({ open, onClose, onSalvar }: { open: boolean; onClose: () => void; onSalvar: (t: string) => void }) {
  const [t, setT] = useState('');
  return (
    <Sheet open={open} onClose={onClose} title="Concluir o caso" subtitle="A conclusão aparece para a escola e para a família." footer={<Button block disabled={t.trim().length < 15} onClick={() => onSalvar(t)}>Concluir</Button>}>
      <textarea className={inputCls + ' min-h-24 py-2'} value={t} onChange={(e) => setT(e.target.value)} placeholder="Ex.: objetivos alcançados; seguir com as orientações em sala." />
    </Sheet>
  );
}
