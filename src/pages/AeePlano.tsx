import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router';
import { Accessibility, CalendarPlus, Check, Lock, PenLine, ShieldCheck } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { DIAS_AEE, DIA_AEE_LONGO, MODALIDADE_AEE, PRESENCA_AEE, RECURSOS_AEE, SITUACAO_AEE } from '@/lib/pedagogico';
import { Badge, Button, Card, DataPair, EmptyState, ErrorState, Field, PageHeader, Section, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { Foto } from '@/components/arquivos';
import { useRecarregarPedagogico } from '@/components/pedagogico';
import { AtendimentoSheet } from './Aee';

/** Plano de AEE de um aluno: necessidade (sensível), plano, atendimentos e presença. */
export default function AeePlano() {
  const { id } = useParams();
  const { can } = useSession();
  const res = useRpc<any>('aee_plano', { student_id: id });
  const [editar, setEditar] = useState(false);
  const [atend, setAtend] = useState(false);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const a = d.aluno;
  const p = d.plano;
  const st = p ? SITUACAO_AEE[p.situacao] : null;
  const vigente = p && p.situacao !== 'ENCERRADO';
  return (
    <div>
      <PageHeader eyebrow={<span className="inline-flex items-center gap-1">Plano de AEE<Simulado detail="Plano e atendimentos fictícios." /></span>}
        title={<span className="inline-flex items-center gap-3"><Foto arquivoId={a.foto_arquivo_id} name={a.nome} size={48} />{a.nome_social ?? a.nome}</span>}
        subtitle={`${a.idade ?? ''} · ${a.serie ?? ''} · ${a.turma ?? ''} · ${a.unidade ?? ''}`}
        actions={<>
          {can('students.read') && <Link to={`/alunos/${a.id}`} className="inline-flex h-11 items-center rounded-2xl bg-white px-4 text-[15px] font-semibold ring-1 ring-line hover:bg-blue-50">Ficha do aluno</Link>}
          {d.pode_editar && <Button icon={PenLine} variant="purple" onClick={() => setEditar(true)}>{vigente ? 'Editar o plano' : 'Elaborar plano'}</Button>}
        </>} />

      <Card className="p-4">
        <div className="mb-3 flex items-center gap-2 rounded-2xl bg-purple-50 p-3 text-[13px] text-purple-900"><Lock className="size-4" />Dado sensível (LGPD): esta consulta foi registrada na trilha de auditoria. O regente vê só as orientações para a sala.</div>
        <dl className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <DataPair label="Necessidade educacional" value={d.necessidade?.special_education_need ?? 'Não informada'} />
          <DataPair label="Alertas de saúde" value={d.necessidade?.medical_alerts ?? 'Nenhum registrado'} />
          <DataPair label="Profissional de apoio (mediador)" value={d.mediador ? `${d.mediador.nome} · desde ${fmtDate(d.mediador.desde)}` : 'Sem mediador(a)'} />
        </dl>
      </Card>

      {p ? (
        <Section title="Plano de atendimento" className="mt-4" action={st && <Badge tone={st.tone}>{st.label}</Badge>}>
          <Card className="space-y-4 p-4">
            <dl className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <DataPair label="Professor(a) do AEE" value={p.profissional ?? '—'} />
              <DataPair label="Onde" value={`${MODALIDADE_AEE[p.modalidade] ?? p.modalidade}${p.local ? ` · ${p.local}` : ''}`} />
              <DataPair label="Quando" value={`${(p.dias as string[]).map((x) => DIA_AEE_LONGO[x] ?? x).join(' e ') || '—'}${p.turno ? ` · ${SHIFT[p.turno]?.toLowerCase() ?? p.turno}` : ''} · ${p.duracao_min} min`} />
              <DataPair label="Início" value={fmtDate(p.inicio)} />
              <DataPair label="Revisão" value={<span className={p.revisao_vencida ? 'font-semibold text-red-700' : ''}>{fmtDate(p.revisar_em)}{p.revisao_vencida ? ' (vencida)' : ''}</span>} />
              <DataPair label="Ciência da família" value={p.familia_ciente_em ? <span className="inline-flex items-center gap-1 text-green-800"><ShieldCheck className="size-4" />{fmtDateTime(p.familia_ciente_em)}</span> : 'Aguardando'} />
            </dl>
            {p.avaliacao_inicial && <Bloco titulo="Avaliação inicial (potencialidades e barreiras)">{p.avaliacao_inicial}</Bloco>}
            <Bloco titulo="Objetivos">{p.objetivos}</Bloco>
            {p.recursos?.length > 0 && <div><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Recursos de acessibilidade</div>
              <div className="mt-1 flex flex-wrap gap-1.5">{(p.recursos as any[]).map((r) => <Badge key={r.codigo} tone="blue">{r.rotulo}</Badge>)}</div></div>}
            {p.orientacoes_sala && <Bloco titulo="Orientações para a sala de aula (o que o regente vê)">{p.orientacoes_sala}</Bloco>}
            {p.articulacao_familia && <Bloco titulo="Articulação com a família">{p.articulacao_familia}</Bloco>}
            {p.motivo_encerramento && <Bloco titulo="Motivo do encerramento">{p.motivo_encerramento}</Bloco>}
            <div className="text-[12px] text-muted">Elaborado por {p.criado_por ?? '—'} em {fmtDateTime(p.criado_em)}{p.alterado_em ? ` · alterado em ${fmtDateTime(p.alterado_em)}` : ''}</div>
          </Card>
        </Section>
      ) : (
        <Card className="mt-4"><EmptyState title="Sem plano de AEE" body="O aluno tem indicação de AEE, mas o plano ainda não foi elaborado." action={d.pode_editar ? <Button icon={Accessibility} variant="purple" onClick={() => setEditar(true)}>Elaborar plano</Button> : undefined} /></Card>
      )}

      {p && (
        <Section title="Atendimentos" className="mt-4"
          subtitle={d.presenca?.previstos ? `Presença nos últimos 60 dias: ${d.presenca.presencas} de ${d.presenca.previstos} (${d.presenca.percentual ?? '—'}%)` : undefined}
          action={d.pode_editar && ['ATIVO', 'EM_REVISAO'].includes(p.situacao) ? <Button size="sm" icon={CalendarPlus} onClick={() => setAtend(true)}>Registrar atendimento</Button> : undefined}>
          <Card className="overflow-hidden">
            {(d.atendimentos as any[]).length ? (
              <Tabela colunas="110px 130px minmax(220px,2fr) minmax(200px,1.6fr)" largura={760} rotulo="Atendimentos">
                <TCabecalho><TCelula fixa>Data</TCelula><TCelula>Presença</TCelula><TCelula>Atividade</TCelula><TCelula>Observação</TCelula></TCabecalho>
                {(d.atendimentos as any[]).map((x) => (
                  <TLinha key={x.id} alerta={x.presenca === 'FALTA'}>
                    <TCelula fixa>{fmtDate(x.data)}</TCelula>
                    <TCelula livre><Badge tone={PRESENCA_AEE[x.presenca]?.tone ?? 'gray'}>{PRESENCA_AEE[x.presenca]?.label ?? x.presenca}</Badge></TCelula>
                    <TCelula titulo={x.atividade}>{x.atividade ?? '—'}</TCelula>
                    <TCelula titulo={x.observacao} className="text-muted">{x.observacao ?? ''}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : <EmptyState compact title="Nenhum atendimento registrado" />}
          </Card>
        </Section>
      )}

      {(d.historico as any[]).length > 0 && (
        <Section title="Planos anteriores" className="mt-4">
          <Card className="divide-y divide-line">
            {(d.historico as any[]).map((h) => <div key={h.id} className="px-4 py-2 text-[13.5px]">{SITUACAO_AEE[h.situacao]?.label} · desde {fmtDate(h.inicio)}{h.motivo_encerramento ? ` · ${h.motivo_encerramento}` : ''}</div>)}
          </Card>
        </Section>
      )}

      <PlanoAeeSheet open={editar} onClose={() => setEditar(false)} d={d} />
      <AtendimentoSheet alvo={atend && p ? { plano_id: p.id, aluno: a.nome } : null} onClose={() => setAtend(false)} />
    </div>
  );
}

function Bloco({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return <div><div className="text-[12px] font-bold uppercase tracking-wide text-subtle">{titulo}</div><p className="mt-0.5 text-[14.5px] leading-relaxed">{children}</p></div>;
}

function PlanoAeeSheet({ open, onClose, d }: { open: boolean; onClose: () => void; d: any }) {
  const p = d.plano && d.plano.situacao !== 'ENCERRADO' ? d.plano : null;
  const [f, setF] = useState<any>({});
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarPedagogico();
  useEffect(() => {
    if (!open) return;
    setF({
      situacao: p?.situacao ?? 'EM_ELABORACAO', profissional_id: p?.profissional_id ?? d.profissionais?.[0]?.id ?? '', modalidade: p?.modalidade ?? 'SRM_PROPRIA',
      dias: p?.dias ?? [], turno: p?.turno ?? (d.aluno.turno === 'MANHA' ? 'TARDE' : 'MANHA'), duracao_min: p?.duracao_min ?? 50,
      avaliacao_inicial: p?.avaliacao_inicial ?? '', objetivos: p?.objetivos ?? '', recursos: (p?.recursos ?? []).map((r: any) => r.codigo),
      orientacoes_sala: p?.orientacoes_sala ?? '', articulacao_familia: p?.articulacao_familia ?? '', revisar_em: p?.revisar_em ?? '', motivo_encerramento: '',
    });
  }, [open]);
  const set = (k: string, v: any) => setF((x: any) => ({ ...x, [k]: v }));
  const toggle = (k: 'dias' | 'recursos', v: string) => set(k, (f[k] as string[]).includes(v) ? (f[k] as string[]).filter((x) => x !== v) : [...f[k], v]);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('aee_plano_salvar', { ...f, id: p?.id ?? null, student_id: d.aluno.id });
      toast({ title: 'Plano salvo', description: f.situacao === 'ATIVO' ? 'A família recebe o aviso para confirmar ciência.' : undefined, tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  if (!open) return null;
  return (
    <Sheet open={open} onClose={onClose} size="lg" title={p ? 'Editar o plano de AEE' : 'Elaborar o plano de AEE'} subtitle={d.aluno.nome}
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={(f.objetivos ?? '').trim().length < 20} onClick={salvar}>Salvar plano</Button>}>
      <div className="space-y-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Field label="Situação">
            <select value={f.situacao} onChange={(e) => set('situacao', e.target.value)} className={`${inputCls} h-11`}>
              {Object.entries(SITUACAO_AEE).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
            </select>
          </Field>
          <Field label="Professor(a) do AEE" hint="Os mais próximos da escola do aluno.">
            <select value={f.profissional_id} onChange={(e) => set('profissional_id', e.target.value)} className={`${inputCls} h-11`}>
              <option value="">—</option>
              {(d.profissionais as any[]).map((x) => <option key={x.id} value={x.id}>{x.nome} · {x.unidade}{x.km != null ? ` (${String(x.km).replace('.', ',')} km)` : ''}</option>)}
            </select>
          </Field>
          <Field label="Onde">
            <select value={f.modalidade} onChange={(e) => set('modalidade', e.target.value)} className={`${inputCls} h-11`}>
              {Object.entries(MODALIDADE_AEE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Turno">
              <select value={f.turno} onChange={(e) => set('turno', e.target.value)} className={`${inputCls} h-11`}>
                <option value="MANHA">Manhã</option><option value="TARDE">Tarde</option><option value="NOITE">Noite</option>
              </select>
            </Field>
            <Field label="Duração (min)"><input type="number" min={20} max={240} value={f.duracao_min} onChange={(e) => set('duracao_min', Number(e.target.value))} className={`${inputCls} h-11`} /></Field>
          </div>
        </div>
        <Field label="Dias do atendimento">
          <div className="flex flex-wrap gap-2">
            {DIAS_AEE.map((x) => (
              <button key={x.value} type="button" onClick={() => toggle('dias', x.value)}
                className={`inline-flex h-9 items-center gap-1 rounded-full px-3 text-[13px] font-semibold ring-1 ${(f.dias ?? []).includes(x.value) ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white ring-line'}`}>
                {(f.dias ?? []).includes(x.value) && <Check className="size-3.5" />}{x.label}
              </button>
            ))}
          </div>
        </Field>
        <Field label="Avaliação inicial" hint="Potencialidades, barreiras e como o aluno aprende melhor (fica só com a equipe autorizada).">
          <textarea value={f.avaliacao_inicial} onChange={(e) => set('avaliacao_inicial', e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
        </Field>
        <Field label="Objetivos" hint="A família vê os objetivos.">
          <textarea value={f.objetivos} onChange={(e) => set('objetivos', e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
        </Field>
        <Field label="Recursos de acessibilidade">
          <div className="flex flex-wrap gap-2">
            {Object.entries(RECURSOS_AEE).map(([k, v]) => (
              <button key={k} type="button" onClick={() => toggle('recursos', k)}
                className={`inline-flex min-h-9 items-center gap-1 rounded-full px-3 py-1 text-left text-[12.5px] font-semibold ring-1 ${(f.recursos ?? []).includes(k) ? 'bg-blue-700 text-white ring-blue-700' : 'bg-white ring-line'}`}>
                {(f.recursos ?? []).includes(k) && <Check className="size-3.5" />}{v}
              </button>
            ))}
          </div>
        </Field>
        <Field label="Orientações para a sala de aula" hint="O(a) regente vê só isto — sem diagnóstico. Obrigatório para ativar.">
          <textarea value={f.orientacoes_sala} onChange={(e) => set('orientacoes_sala', e.target.value)} rows={3} maxLength={2000} className={`${inputCls} h-auto py-3`} />
        </Field>
        <Field label="Articulação com a família">
          <textarea value={f.articulacao_familia} onChange={(e) => set('articulacao_familia', e.target.value)} rows={2} maxLength={1000} className={`${inputCls} h-auto py-3`} />
        </Field>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Field label="Revisar em" hint="Se em branco: 180 dias."><input type="date" value={f.revisar_em ?? ''} onChange={(e) => set('revisar_em', e.target.value)} className={`${inputCls} h-11`} /></Field>
          {f.situacao === 'ENCERRADO' && <Field label="Motivo do encerramento"><input value={f.motivo_encerramento} onChange={(e) => set('motivo_encerramento', e.target.value)} maxLength={300} className={`${inputCls} h-11`} /></Field>}
        </div>
      </div>
    </Sheet>
  );
}
