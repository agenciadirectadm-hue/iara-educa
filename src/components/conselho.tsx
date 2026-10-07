// Conselho de classe (bimestral e final), prévia do resultado final da unidade e histórico escolar (escola e família).
import { useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { CheckCheck, FileText, Gavel, RotateCcw, Save, ScrollText } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtInt } from '@/lib/format';
import { fmtNota, notaTone } from '@/lib/pedagogico';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, Section, Segmented, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

export const SITUACAO_FINAL: Record<string, { label: string; tone: 'green' | 'blue' | 'red' | 'amber' | 'purple' | 'gray' }> = {
  APROVADO: { label: 'Aprovado', tone: 'green' }, APROVADO_CONSELHO: { label: 'Aprovado pelo conselho', tone: 'blue' }, PROGRESSAO: { label: 'Progressão', tone: 'green' },
  RETIDO: { label: 'Retido', tone: 'red' }, TRANSFERIDO: { label: 'Transferido', tone: 'gray' }, CONSELHO: { label: 'Vai ao conselho', tone: 'amber' }, CURSANDO: { label: 'Cursando', tone: 'purple' },
};
export const ENCAMINHAMENTO: Record<string, string> = {
  REFORCO: 'Reforço escolar', CONVERSA_FAMILIA: 'Conversa com a família', PLANO_INTERVENCAO: 'Plano de intervenção', AVALIACAO_AEE: 'Avaliação do AEE',
  BUSCA_ATIVA: 'Acompanhar frequência', APOIO_PSICOPEDAGOGICO: 'Apoio psicopedagógico', REDE_APOIO: 'Rede de apoio', ELOGIO: 'Elogio',
};
const REDE: Record<string, string> = { MUNICIPAL: 'Rede municipal', ESTADUAL: 'Rede estadual', PARTICULAR: 'Rede particular', OUTRO_MUNICIPIO: 'Outro município' };
const ETAPAS = [{ value: '1', label: '1º bim.' }, { value: '2', label: '2º bim.' }, { value: '3', label: '3º bim.' }, { value: '4', label: '4º bim.' }, { value: '5', label: 'Final' }];

/** Conselho de classe da turma: análise por aluno, deliberação, encaminhamentos e ata; o final fecha o resultado do ano. */
export function ConselhoTurma({ classId }: { classId: string }) {
  const [etapa, setEtapa] = useState<string | null>(null);
  const res = useRpc<any>('conselho_turma', { class_id: classId, etapa: etapa ? Number(etapa) : null });
  const qc = useQueryClient();
  const toast = useToast();
  const [aluno, setAluno] = useState<any | null>(null);
  const [cab, setCab] = useState<{ participantes: string; ata: string; data: string } | null>(null);
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const k = d.conselho;
  const final = d.etapa === 5;
  const form = cab ?? { participantes: k?.participantes ?? '', ata: k?.ata ?? '', data: k?.data ?? new Date().toISOString().slice(0, 10) };
  const salvar = async (args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc('conselho_salvar', { class_id: classId, etapa: d.etapa, ...args });
      toast({ title: msg, tone: 'success' });
      setCab(null); setMotivo('');
      qc.invalidateQueries({ queryKey: ['conselho_turma'] });
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const min = Number(d.media_minima);
  const alunos = d.alunos as any[];
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Segmented value={String(d.etapa)} onChange={setEtapa} items={ETAPAS} />
        {k ? <Badge tone={k.situacao === 'CONCLUIDO' ? 'green' : 'amber'}>{k.situacao === 'CONCLUIDO' ? `Concluído em ${fmtDate(k.concluido_em)}` : 'Em registro'}</Badge> : <Badge tone="gray">Ainda não registrado</Badge>}
        {k?.is_demo && <MarcaSimulado />}
      </div>
      {final && <p className="rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-950 ring-1 ring-amber-200">{d.final_liberado ? 'Conselho final: fecha o resultado do ano no histórico escolar.' : 'Prévia: o conselho final só fecha depois do 4º bimestre. A situação de cada aluno é calculada com as notas lançadas até agora.'} {d.regras}</p>}
      <Card className="overflow-hidden">
        <Tabela colunas={`minmax(200px,1.6fr) 80px 90px ${final ? '170px ' : ''}minmax(160px,1fr) minmax(200px,1.4fr)`} largura={final ? 1000 : 860} rotulo="Alunos no conselho">
          <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Abaixo</TCelula><TCelula>Frequência</TCelula>{final && <TCelula>Situação</TCelula>}<TCelula>Sinais</TCelula><TCelula>Deliberação</TCelula></TCabecalho>
          {alunos.map((a) => {
            const del = a.deliberacao;
            const sit = del?.situacao ?? a.calculada?.situacao;
            return (
              <TLinha key={a.student_id} onClick={() => setAluno(a)} alerta={a.abaixo >= 3 || (a.frequencia != null && a.frequencia < 75) || sit === 'CONSELHO'} rotulo={a.nome}>
                <TCelula fixa><span className="font-semibold">{a.nome}</span>{a.aee && <Badge tone="purple" className="ml-1">AEE</Badge>}</TCelula>
                <TCelula>{a.abaixo ? <Badge tone="red">{a.abaixo}</Badge> : <span className="text-muted">0</span>}</TCelula>
                <TCelula className={clsx(a.frequencia != null && a.frequencia < 75 && 'font-semibold text-red-700')}>{a.frequencia != null ? `${String(a.frequencia).replace('.', ',')}%` : '—'}</TCelula>
                {final && <TCelula livre>{sit ? <Badge tone={SITUACAO_FINAL[sit]?.tone}>{SITUACAO_FINAL[sit]?.label}</Badge> : '—'}</TCelula>}
                <TCelula titulo={[a.plano && 'plano ativo', a.ocorrencias && `${a.ocorrencias} ocorrência(s)`, a.busca_ativa && 'busca ativa', a.alfabetizacao && `alfabetização: ${a.alfabetizacao.toLowerCase()}`].filter(Boolean).join(' · ')}>
                  {[a.plano && 'plano', a.ocorrencias ? `${a.ocorrencias} ocorr.` : null, a.busca_ativa && 'busca ativa', a.alfabetizacao?.toLowerCase()].filter(Boolean).join(' · ') || '—'}
                </TCelula>
                <TCelula titulo={del?.observacao}>{(del?.encaminhamentos ?? []).map((e: string) => ENCAMINHAMENTO[e]).join(', ') || del?.observacao || <span className="text-muted">—</span>}</TCelula>
              </TLinha>
            );
          })}
        </Tabela>
      </Card>
      <Section title={final ? 'Médias anuais da turma' : `Médias do ${d.etapa}º bimestre`}>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
          {(d.componentes as any[]).map((c) => (
            <Card key={c.nome} className="p-3 text-[13px]"><div className="font-semibold">{c.nome}</div>
              <div><Badge tone={notaTone(c.media_turma, min)}>{fmtNota(c.media_turma)}</Badge> <span className="text-muted">{fmtInt(c.abaixo)} abaixo</span></div></Card>
          ))}
        </div>
      </Section>
      <Card className="space-y-3 p-4">
        <h3 className="flex items-center gap-2 font-semibold"><ScrollText className="size-4" />Ata do conselho</h3>
        <div className="grid gap-3 sm:grid-cols-[160px_1fr]">
          <Field label="Data"><input type="date" value={form.data} disabled={!d.pode_conduzir} onChange={(e) => setCab({ ...form, data: e.target.value })} className={inputCls} /></Field>
          <Field label="Participantes"><input value={form.participantes} disabled={!d.pode_conduzir} onChange={(e) => setCab({ ...form, participantes: e.target.value })} className={inputCls} /></Field>
        </div>
        <Field label="Síntese da análise da turma"><textarea value={form.ata} disabled={!d.pode_conduzir} onChange={(e) => setCab({ ...form, ata: e.target.value })} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
        {d.pode_conduzir && (
          <div className="flex flex-wrap gap-2">
            <Button variant="secondary" icon={Save} loading={busy} onClick={() => salvar({ ...form }, 'Conselho salvo')}>Salvar</Button>
            <Button icon={CheckCheck} loading={busy} disabled={final && !d.final_liberado} onClick={() => salvar({ ...form, concluir: true }, final ? 'Resultado final fechado' : 'Conselho concluído')}>
              {final ? 'Fechar o resultado do ano' : 'Concluir o conselho'}
            </Button>
          </div>
        )}
        {d.pode_reabrir && (
          <div className="flex flex-wrap items-center gap-2">
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo da reabertura" className={`${inputCls} h-10 max-w-md`} />
            <Button variant="secondary" icon={RotateCcw} loading={busy} disabled={motivo.trim().length < 10} onClick={() => salvar({ reabrir: true, motivo }, 'Conselho reaberto')}>Reabrir</Button>
          </div>
        )}
      </Card>
      <DeliberacaoSheet aluno={aluno} conselho={d} onClose={() => setAluno(null)} onSalvar={(del) => salvar({ deliberacoes: [del] }, 'Registrado')} busy={busy} />
    </div>
  );
}

function DeliberacaoSheet({ aluno, conselho, onClose, onSalvar, busy }: { aluno: any | null; conselho: any; onClose: () => void; onSalvar: (d: object) => void; busy: boolean }) {
  const [f, setF] = useState<any>(null);
  const [chave, setChave] = useState<string | null>(null);
  if (aluno && chave !== aluno.student_id) {
    setChave(aluno.student_id);
    const del = aluno.deliberacao;
    setF({ encaminhamentos: del?.encaminhamentos ?? [], observacao: del?.observacao ?? '', comunicar_familia: del?.comunicar_familia ?? true, situacao: del?.situacao ?? '', justificativa: del?.justificativa ?? '' });
  }
  const final = conselho.etapa === 5;
  const conduz = conselho.pode_conduzir;
  const min = Number(conselho.media_minima);
  return (
    <Sheet open={!!aluno} onClose={() => { setChave(null); onClose(); }} size="lg" title={aluno?.nome ?? ''} subtitle={final ? 'Conselho final' : `Conselho do ${conselho.etapa}º bimestre`}
      footer={(conduz || conselho.pode_observar) && f ? <Button block icon={Save} loading={busy} onClick={() => { onSalvar({ student_id: aluno.student_id, ...f, situacao: conduz && final ? f.situacao || null : null }); setChave(null); onClose(); }}>Salvar</Button> : undefined}>
      {aluno && f && (
        <div className="space-y-4 pt-1">
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(aluno.medias ?? {}).map(([c, m]) => <Badge key={c} tone={notaTone(m as number, min)}>{c}: {fmtNota(m as number)}</Badge>)}
            <Badge tone={aluno.frequencia != null && aluno.frequencia < 75 ? 'red' : 'gray'}>Frequência {aluno.frequencia != null ? `${String(aluno.frequencia).replace('.', ',')}%` : '—'}</Badge>
          </div>
          {final && aluno.calculada && (
            <div className="rounded-2xl bg-slate-50 p-3 text-[13px] ring-1 ring-line">
              <b>Situação calculada:</b> <Badge tone={SITUACAO_FINAL[aluno.calculada.situacao]?.tone}>{SITUACAO_FINAL[aluno.calculada.situacao]?.label}</Badge>
              {(aluno.calculada.motivos ?? []).map((m: string, i: number) => <p key={i} className="mt-1 text-muted">{m}</p>)}
            </div>
          )}
          {conduz && (
            <Field label="Encaminhamentos">
              <div className="flex flex-wrap gap-1.5">
                {Object.entries(ENCAMINHAMENTO).map(([k2, v]) => (
                  <Chip key={k2} active={f.encaminhamentos.includes(k2)} onClick={() => setF({ ...f, encaminhamentos: f.encaminhamentos.includes(k2) ? f.encaminhamentos.filter((x: string) => x !== k2) : [...f.encaminhamentos, k2] })}>{v}</Chip>
                ))}
              </div>
            </Field>
          )}
          <Field label="Observação do conselho"><textarea value={f.observacao} onChange={(e) => setF({ ...f, observacao: e.target.value })} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
          {conduz && <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={f.comunicar_familia} onChange={(e) => setF({ ...f, comunicar_familia: e.target.checked })} className="size-5 accent-purple-700" />Avisar a família dos encaminhamentos</label>}
          {conduz && final && (
            <>
              <Field label="Deliberação final">
                <select value={f.situacao} onChange={(e) => setF({ ...f, situacao: e.target.value })} className={inputCls}>
                  <option value="">Manter a situação calculada</option>
                  {['APROVADO', 'APROVADO_CONSELHO', 'PROGRESSAO', 'RETIDO'].map((s) => <option key={s} value={s}>{SITUACAO_FINAL[s].label}</option>)}
                </select>
              </Field>
              {['APROVADO_CONSELHO', 'RETIDO'].includes(f.situacao) && (
                <Field label="Justificativa (obrigatória)"><textarea value={f.justificativa} onChange={(e) => setF({ ...f, justificativa: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
              )}
            </>
          )}
        </div>
      )}
    </Sheet>
  );
}

/** Prévia do resultado final da unidade: quem vai ao conselho, por frequência ou por média — dá tempo de agir antes do fim do ano. */
export function ResultadoPrevia({ unitId }: { unitId: number | null }) {
  const res = useRpc<any>('resultado_previa', { unit_id: unitId }, { enabled: !!unitId });
  if (!unitId) return <EmptyState title="Escolha a unidade" body="A prévia do resultado final é calculada por unidade." />;
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const r = d.resumo ?? {};
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={CheckCheck} tone="green" label="Aprovados" value={fmtInt(r.APROVADO)} />
        <Kpi compact icon={CheckCheck} tone="blue" label="Progressão (educação infantil, 1º e 2º ano)" value={fmtInt(r.PROGRESSAO)} />
        <Kpi compact icon={Gavel} tone="amber" label="Vão ao conselho final" value={fmtInt(r.CONSELHO)} />
      </div>
      <p className="text-[12.5px] text-muted">{d.regras}</p>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(140px,1fr) 80px 120px minmax(220px,2fr)" largura={640} rotulo="Turmas">
          <TCabecalho><TCelula fixa>Turma</TCelula><TCelula>Alunos</TCelula><TCelula>Ao conselho</TCelula><TCelula>Conselhos do ano</TCelula></TCabecalho>
          {(d.turmas as any[]).map((t) => (
            <TLinha key={t.class_id} to={`/turmas/${t.class_id}/avaliacao?aba=conselho`} alerta={t.conselho > 0} rotulo={t.turma}>
              <TCelula fixa className="font-semibold">{t.turma}</TCelula><TCelula>{fmtInt(t.alunos)}</TCelula><TCelula>{t.conselho ? <Badge tone="amber">{t.conselho}</Badge> : '0'}</TCelula>
              <TCelula>{((t.conselhos ?? []) as any[]).map((c) => `${c.etapa === 5 ? 'final' : c.etapa + 'º'}${c.situacao === 'CONCLUIDO' ? ' ✓' : ''}`).join(' · ') || '—'}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      {(d.conselho as any[]).length > 0 && (
        <Section title="Alunos que vão ao conselho final" subtitle="Ainda dá tempo: reforço, conversa com a família, busca ativa.">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,1.5fr) 120px minmax(260px,2fr)" largura={720} rotulo="Alunos ao conselho">
              <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Turma</TCelula><TCelula>Motivo</TCelula></TCabecalho>
              {(d.conselho as any[]).map((a) => (
                <TLinha key={a.student_id} to={`/alunos/${a.student_id}`} rotulo={a.nome}>
                  <TCelula fixa className="font-semibold">{a.nome}</TCelula><TCelula>{a.turma}</TCelula><TCelula titulo={(a.motivos ?? []).join(' · ')}>{(a.motivos ?? []).join(' · ')}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
    </div>
  );
}

/** Histórico escolar: anos concluídos (na rede ou fora dela) e o ano em curso. */
export function HistoricoView({ h, familia, onEmitir }: { h: any; familia?: boolean; onEmitir?: () => void }) {
  const anos = (h.anos ?? []) as any[];
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-[13px] text-muted">{anos.length} ano(s) concluído(s){h.registro ? ` · código ${h.registro}` : ''}</p>
        {onEmitir && anos.length > 0 && <Button size="sm" icon={FileText} onClick={onEmitir}>Emitir histórico escolar</Button>}
      </div>
      {h.em_curso && (
        <Card className="p-3 text-[13.5px] ring-2 ring-purple-200">
          <div className="flex flex-wrap items-center gap-2"><b>{h.em_curso.ano} · {h.em_curso.serie}</b><Badge tone="purple">Cursando</Badge>
            {!familia && h.em_curso.calculada?.situacao && <Badge tone={SITUACAO_FINAL[h.em_curso.calculada.situacao]?.tone}>prévia: {SITUACAO_FINAL[h.em_curso.calculada.situacao]?.label}</Badge>}</div>
          <div className="text-muted">{h.em_curso.unidade} · {h.em_curso.turma}{h.em_curso.calculada?.frequencia != null ? ` · frequência ${String(h.em_curso.calculada.frequencia).replace('.', ',')}%` : ''}</div>
        </Card>
      )}
      {[...anos].reverse().map((a) => (
        <Card key={a.ano} className="p-3 text-[13.5px]">
          <div className="flex flex-wrap items-center gap-2"><b>{a.ano} · {a.serie}</b><Badge tone={SITUACAO_FINAL[a.situacao]?.tone}>{SITUACAO_FINAL[a.situacao]?.label}</Badge>
            {a.rede !== 'MUNICIPAL' && <Badge tone="gray">{REDE[a.rede]}</Badge>}{a.is_demo && <MarcaSimulado />}</div>
          <div className="text-muted">{a.unidade}{a.turma ? ` · ${a.turma}` : ''} · {a.carga_horaria} h · frequência {String(a.frequencia ?? '—').replace('.', ',')}%</div>
          {(a.componentes as any[]).length > 0 ? (
            <div className="mt-2 flex flex-wrap gap-1.5">{(a.componentes as any[]).map((c) => <Badge key={c.nome} tone={notaTone(c.media)}>{c.nome}: {fmtNota(c.media)}</Badge>)}</div>
          ) : a.parecer ? <p className="mt-1 italic text-ink-2">{a.parecer}</p> : null}
          {a.observacao && <p className="mt-1 text-[12.5px] text-muted">{a.observacao}</p>}
        </Card>
      ))}
      {!anos.length && !h.em_curso && <EmptyState compact title="Sem histórico registrado" />}
    </div>
  );
}

export function HistoricoAluno({ studentId }: { studentId: string }) {
  const res = useRpc<any>('historico_aluno', { student_id: studentId });
  const toast = useToast();
  const emitir = async () => {
    try {
      const d = await rpc<any>('declaracao_emitir', { student_id: studentId, tipo: 'HISTORICO' });
      window.location.hash = `#/declaracao/${d.id}`;
    } catch (e) {
      toast({ title: 'Não emitido', description: (e as Error).message, tone: 'error' });
    }
  };
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return <HistoricoView h={res.data} onEmitir={emitir} />;
}

export function HistoricoFamilia() {
  const res = useRpc<any[]>('familia_historico', {});
  const toast = useToast();
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) return <EmptyState title="Nenhuma criança matriculada" />;
  return (
    <div className="space-y-5">
      {res.data.map((h) => (
        <Section key={h.student_id} title={`Histórico escolar · ${h.primeiro_nome}`}>
          <HistoricoView h={h} familia onEmitir={async () => {
            try {
              const d = await rpc<any>('declaracao_emitir', { student_id: h.student_id, tipo: 'HISTORICO', canal: 'PORTAL' });
              window.location.hash = `#/declaracao/${d.id}`;
            } catch (e) {
              toast({ title: 'Não emitido', description: (e as Error).message, tone: 'error' });
            }
          }} />
        </Section>
      ))}
      <p className="text-[12px] text-muted">O histórico emitido tem código e QR code para conferir a autenticidade; a escola de destino confere em <Link to="/verificar" className="underline">Verificar declaração</Link>.</p>
    </div>
  );
}
