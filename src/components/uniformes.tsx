// Uniformes e kits escolares — peças das telas: família (tamanhos, código de retirada, avisos com ciência, troca e reposição),
// ficha do aluno (tamanhos, necessidades, retiradas e avisos) e o painel agregado (Prefeito, SEDUC e órgãos externos).
import { useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { QRCodeSVG } from 'qrcode.react';
import { BellRing, Check, CheckCheck, ClipboardList, Map as MapIcon, Package, PackageCheck, Ruler, Shirt, Timer, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtBRL, fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, Section, Segmented, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

export const UK_SIT: Record<string, { label: string; tone: Tone }> = {
  AGUARDANDO_TAMANHO: { label: 'Aguardando o tamanho', tone: 'amber' },
  AGUARDANDO_DECISAO: { label: 'Aguardando decisão', tone: 'amber' },
  AGUARDANDO_MATERIAL: { label: 'Aguardando o material', tone: 'blue' },
  DISPONIVEL: { label: 'Pode retirar', tone: 'purple' },
  RETIRADA: { label: 'Retirado', tone: 'green' },
  PARCIAL: { label: 'Retirado em parte', tone: 'teal' },
  CANCELADA: { label: 'Cancelado', tone: 'gray' },
  NEGADA: { label: 'Não aprovado', tone: 'red' },
};
export const UK_CONTEUDO: Record<string, string> = { UNIFORME: 'Uniforme', KIT: 'Kit escolar', ADAPTADO: 'Material adaptado' };
export const UK_MODELO: Record<string, string> = { SHORTS_SAIA: 'Shorts-saia', BERMUDA: 'Bermuda' };
export const UK_CANAL: Record<string, string> = { PORTAL: 'pelo portal', WHATSAPP: 'pela IARA no WhatsApp', UNIDADE: 'pela unidade', ESTIMATIVA: 'estimado pela idade' };
export const UK_AVISO: Record<string, string> = {
  TAMANHO: 'Pedido de tamanho', RETIRADA: 'Pode retirar', LEMBRETE_RETIRADA: 'Lembrete de retirada', RETIRADA_REGISTRADA: 'Retirada registrada', DECISAO: 'Resposta ao pedido',
};

export function SituacaoUk({ s, vencida }: { s: string; vencida?: boolean }) {
  if (vencida) return <Badge tone="red">Prazo vencido</Badge>;
  const x = UK_SIT[s] ?? { label: s, tone: 'gray' as Tone };
  return <Badge tone={x.tone}>{x.label}</Badge>;
}

/** Como o aviso saiu pelo WhatsApp (sem escrever “simulado”: na demonstração, a bandeirinha). */
export function WhatsAvisoUk({ s, em }: { s: string; em?: string | null }) {
  if (s === 'ENVIADO') return <span className="text-[12.5px] text-muted">WhatsApp {fmtDateTime(em)}</span>;
  if (s === 'SIMULADO') return <span className="inline-flex items-center gap-1 text-[12.5px] text-muted">WhatsApp {fmtDateTime(em)} <MarcaSimulado /></span>;
  if (s === 'AGENDADO') return <span className="text-[12.5px] text-amber-700">Na fila do WhatsApp</span>;
  if (s === 'SEM_WHATSAPP') return <span className="text-[12.5px] text-muted">Só no portal (sem WhatsApp)</span>;
  return null;
}

export const pctBr = (v: number | string | null | undefined) => (v == null ? '—' : `${String(v).replace('.', ',')}%`);

export function itensResumo(itens: any[] | null | undefined) {
  return (itens ?? []).map((i) => `${i.quantidade > 1 ? `${i.quantidade} ` : ''}${i.nome}${i.tamanho ? ` (${i.tamanho})` : ''}`).join(' · ');
}

// ------------------------------------------------------------------ tamanhos
export function TamanhosForm({ grade, sugestao, inicial, onSalvar, salvando, rotulo = 'Salvar os tamanhos' }: {
  grade: Record<string, string[]>; sugestao?: any; inicial?: any; onSalvar: (v: any) => void; salvando?: boolean; rotulo?: string;
}) {
  const base = inicial ?? sugestao ?? {};
  const [modelo, setModelo] = useState<string>(inicial?.modelo ?? '');
  const [sup, setSup] = useState<string>(base.superior ?? '');
  const [inf, setInf] = useState<string>(base.inferior ?? '');
  const [calc, setCalc] = useState<string>(base.calcado != null ? String(base.calcado) : '');
  const roupa = grade?.ROUPA ?? [];
  const calcado = grade?.CALCADO ?? [];
  return (
    <div className="space-y-3">
      {!inicial && sugestao && <p className="text-[12.5px] text-muted">Já deixamos marcado o tamanho mais comum para a idade. Confira com a roupa que a criança usa hoje.</p>}
      <Field label="Modelo da parte de baixo">
        <Segmented value={modelo} onChange={setModelo} items={[{ value: 'SHORTS_SAIA', label: 'Shorts-saia' }, { value: 'BERMUDA', label: 'Bermuda' }]} />
      </Field>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Field label="Parte de cima" hint="Camisetas, jaqueta e blusa de lã">
          <select className={inputCls} value={sup} onChange={(e) => setSup(e.target.value)}>
            <option value="">Escolha…</option>{roupa.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </Field>
        <Field label="Parte de baixo" hint="Calça e shorts-saia ou bermuda">
          <select className={inputCls} value={inf} onChange={(e) => setInf(e.target.value)}>
            <option value="">Escolha…</option>{roupa.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </Field>
        <Field label="Número do calçado" hint="Papete até o Infantil 3; meias a partir do Infantil 4">
          <select className={inputCls} value={calc} onChange={(e) => setCalc(e.target.value)}>
            <option value="">Escolha…</option>{calcado.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </Field>
      </div>
      <Button icon={Ruler} loading={salvando} disabled={!modelo || !sup || !inf || !calc}
        onClick={() => onSalvar({ modelo, superior: sup, inferior: inf, calcado: calc })}>{rotulo}</Button>
    </div>
  );
}

export function TamanhosResumo({ t }: { t: any }) {
  return (
    <span>
      Cima <b>{t.superior}</b> · baixo <b>{t.inferior}</b> · calçado <b>{t.calcado}</b>{t.meia ? <> (meias {t.meia})</> : null} · {UK_MODELO[t.modelo] ?? '—'}
    </span>
  );
}

/** Código de retirada com QR (a unidade digita os 6 números ou lê o QR). */
export function CodigoRetirada({ codigo, unidade, prazo }: { codigo: string; unidade?: string | null; prazo?: string | null }) {
  return (
    <div className="flex items-center gap-4 rounded-2xl bg-purple-50 p-3 ring-1 ring-purple-100">
      <div className="rounded-xl bg-white p-1.5 ring-1 ring-purple-100"><QRCodeSVG value={`IARA-UK:${codigo.replace(/\D/g, '')}`} size={84} /></div>
      <div className="min-w-0">
        <div className="text-[12px] font-bold uppercase tracking-wide text-purple-700">Código de retirada</div>
        <div className="font-mono text-[26px] font-bold tracking-[0.12em] text-purple-900">{codigo}</div>
        <div className="text-[12.5px] text-muted">{unidade ? `Retire no(a) ${unidade}` : 'Retire na unidade'}{prazo ? ` até ${fmtDate(prazo)}` : ''}. Sem o código, leve documento com foto.</div>
      </div>
    </div>
  );
}

// ------------------------------------------------------------------ família
export function UniformesFamilia() {
  const res = useRpc<any>('familia_uniformes', {});
  const qc = useQueryClient();
  const toast = useToast();
  const [salvando, setSalvando] = useState<string | null>(null);
  const [pedir, setPedir] = useState<{ student_id: string; nome: string } | null>(null);
  const [editar, setEditar] = useState<string | null>(null);
  const recarregar = () => qc.invalidateQueries({ queryKey: ['familia_uniformes'] });
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const salvar = async (student_id: string, ano: number, v: any) => {
    setSalvando(`${student_id}:${ano}`);
    try {
      await rpc('familia_uniformes_tamanhos', { student_id, ano, ...v });
      toast({ title: 'Tamanhos registrados', description: 'A escola e a SEDUC já recebem para a compra e a separação.', tone: 'success' });
      setEditar(null);
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally { setSalvando(null); }
  };
  const ciente = async (id: string) => {
    try {
      await rpc('familia_uniformes_ciente', { id });
      toast({ title: 'Ciência registrada', description: 'O aviso foi para o histórico.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  if (!(d.filhos as any[]).length) return <Card><EmptyState compact title="Nenhuma criança matriculada" body="O uniforme e o kit escolar são para alunos matriculados na rede municipal." /></Card>;
  return (
    <div className="space-y-6">
      {(d.avisos as any[]).length > 0 && (
        <Section title="Avisos de uniforme e kit" subtitle="Depois da ciência, o aviso vai para o histórico.">
          <div className="space-y-2">
            {(d.avisos as any[]).map((a) => (
              <Card key={a.id} className="p-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 font-semibold"><BellRing className="size-4 text-purple-600" />{a.titulo}</div>
                    <div className="mt-0.5 text-[12.5px] text-muted">Enviado em {fmtDateTime(a.enviado_em)} · {a.primeiro_nome}</div>
                  </div>
                  <Button size="sm" icon={Check} onClick={() => ciente(a.id)}>Estou ciente</Button>
                </div>
                <p className="mt-2 text-[14px]">{a.texto}</p>
                <div className="mt-1"><WhatsAvisoUk s={a.whatsapp} em={a.whatsapp_em} /></div>
              </Card>
            ))}
          </div>
        </Section>
      )}
      {(d.filhos as any[]).map((f) => (
        <Section key={f.student_id} title={`Uniforme e kit · ${f.primeiro_nome}`} subtitle={f.unidade}
          action={<Button size="sm" variant="secondary" onClick={() => setPedir({ student_id: f.student_id, nome: f.primeiro_nome })}>Pedir troca ou reposição</Button>}>
          <div className="space-y-3">
            {(f.anos as any[]).filter((a) => a.etapa || (a.necessidades as any[]).length).map((a) => {
              const camp = (d.campanhas as any[]).find((c) => c.ano === a.ano);
              const uni = (a.necessidades as any[]).find((n) => n.conteudo === 'UNIFORME' && ['ANUAL', 'ALUNO_NOVO'].includes(n.tipo));
              const podeTamanho = camp?.coleta_aberta && a.etapa !== 'EJA' && (!uni || ['AGUARDANDO_TAMANHO', 'AGUARDANDO_MATERIAL'].includes(uni.situacao));
              const chave = `${f.student_id}:${a.ano}`;
              return (
                <Card key={a.ano} className="space-y-3 p-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="font-semibold">{a.ano} · {a.etapa_rotulo ?? 'sem etapa'}{a.ampliacao ? ' · Ampliação de Jornada' : ''}</div>
                    {camp && <Badge tone={camp.coleta_aberta ? 'amber' : 'gray'}>{camp.coleta_aberta ? `Tamanhos até ${fmtDate(camp.coleta_fim)}` : camp.nome}</Badge>}
                  </div>
                  {a.etapa !== 'EJA' && (a.tamanhos && editar !== chave ? (
                    <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl bg-slate-50 p-3 text-[14px]">
                      <div><TamanhosResumo t={a.tamanhos} /><div className="text-[12px] text-muted">Informado {UK_CANAL[a.tamanhos.canal] ?? ''} em {fmtDateTime(a.tamanhos.informado_em)}</div></div>
                      {podeTamanho && <Button size="sm" variant="ghost" onClick={() => setEditar(chave)}>Corrigir</Button>}
                    </div>
                  ) : podeTamanho ? (
                    <div className="rounded-2xl bg-amber-50 p-3 ring-1 ring-amber-100">
                      <div className="mb-2 font-semibold text-amber-900">Informe os tamanhos do uniforme {a.ano}</div>
                      <TamanhosForm grade={d.grade} sugestao={a.sugestao} inicial={a.tamanhos} salvando={salvando === chave} onSalvar={(v) => salvar(f.student_id, a.ano, v)} />
                    </div>
                  ) : null)}
                  {(a.necessidades as any[]).map((n) => (
                    <div key={n.id} className="rounded-2xl ring-1 ring-line/70">
                      <div className="flex flex-wrap items-center justify-between gap-2 p-3">
                        <div className="min-w-0">
                          <div className="font-semibold">{UK_CONTEUDO[n.conteudo]}{n.tipo !== 'ANUAL' ? ` · ${n.tipo_rotulo}` : ''}</div>
                          <div className="truncate text-[12.5px] text-muted" title={itensResumo(n.itens)}>{itensResumo(n.itens) || '—'}</div>
                        </div>
                        <SituacaoUk s={n.situacao} vencida={n.vencida} />
                      </div>
                      {n.situacao === 'DISPONIVEL' && n.codigo && <div className="px-3 pb-3"><CodigoRetirada codigo={n.codigo} unidade={n.unidade} prazo={n.prazo_retirada} /></div>}
                      {['RETIRADA', 'PARCIAL'].includes(n.situacao) && (
                        <div className="border-t border-line/60 px-3 py-2 text-[13px] text-muted">
                          <PackageCheck className="mr-1 inline size-4 text-green-600" />Retirado em {fmtDateTime(n.retirada_em)} por {n.retirada_por} ({n.retirada_parentesco?.toLowerCase()})
                        </div>
                      )}
                      {n.situacao === 'NEGADA' && n.decisao_motivo && <div className="border-t border-line/60 px-3 py-2 text-[13px] text-red-700">{n.decisao_motivo}</div>}
                    </div>
                  ))}
                </Card>
              );
            })}
            {(f.autorizados as any[]).length > 0 && (
              <p className="text-[12.5px] text-muted"><Users className="mr-1 inline size-4" />Pode retirar: {(f.autorizados as any[]).map((x) => `${x.nome} (${x.parentesco.toLowerCase()})`).join(', ')}. Para incluir alguém, procure a secretaria da escola.</p>
            )}
          </div>
        </Section>
      ))}
      {(d.historico as any[]).length > 0 && (
        <Section title="Histórico de avisos de uniforme e kit">
          <Card className="overflow-hidden">
            <Tabela colunas="150px minmax(180px,1fr) 110px 150px" largura={640} rotulo="Histórico de avisos">
              <TCabecalho><TCelula fixa>Enviado em</TCelula><TCelula>Aviso</TCelula><TCelula>Criança</TCelula><TCelula>Ciência</TCelula></TCabecalho>
              {(d.historico as any[]).map((a) => (
                <TLinha key={a.id}><TCelula fixa>{fmtDateTime(a.enviado_em)}</TCelula><TCelula titulo={a.texto}>{a.titulo}</TCelula><TCelula>{a.primeiro_nome}</TCelula><TCelula>{fmtDateTime(a.ciente_em)}</TCelula></TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
      <p className="text-[12.5px] text-muted">Pela IARA: “tamanho do uniforme”, “código do uniforme”, “kit escolar” ou “trocar o uniforme”. Composição oficial do kit e do uniforme no portal da Prefeitura (Educação → Kit Escolar e Uniforme).</p>
      <PedirSheet alvo={pedir} onClose={() => setPedir(null)} onFeito={recarregar} />
    </div>
  );
}

function PedirSheet({ alvo, onClose, onFeito }: { alvo: { student_id: string; nome: string } | null; onClose: () => void; onFeito: () => void }) {
  const toast = useToast();
  const [tipo, setTipo] = useState('TROCA_TAMANHO');
  const [conteudo, setConteudo] = useState('UNIFORME');
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    if (!alvo) return;
    setBusy(true);
    try {
      const r = await rpc<any>('familia_uniformes_pedir', { student_id: alvo.student_id, tipo, conteudo: tipo === 'TROCA_TAMANHO' ? 'UNIFORME' : conteudo, motivo });
      toast({ title: 'Pedido registrado', description: r.mensagem, tone: 'success' });
      setMotivo('');
      onFeito();
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally { setBusy(false); }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Troca ou reposição · ${alvo?.nome ?? ''}`} subtitle="A unidade analisa e responde aqui e no WhatsApp."
      footer={<Button block loading={busy} disabled={motivo.trim().length < 5} onClick={enviar}>Enviar o pedido</Button>}>
      <div className="space-y-3">
        <Segmented value={tipo} onChange={setTipo} items={[{ value: 'TROCA_TAMANHO', label: 'Troca de tamanho' }, { value: 'REPOSICAO', label: 'Reposição' }]} />
        {tipo === 'REPOSICAO' && <Segmented value={conteudo} onChange={setConteudo} items={[{ value: 'UNIFORME', label: 'Uniforme' }, { value: 'KIT', label: 'Kit escolar' }]} />}
        <Field label={tipo === 'TROCA_TAMANHO' ? 'Que peças não serviram e qual tamanho precisa?' : 'O que aconteceu e quais peças ou materiais?'}>
          <textarea className={inputCls + ' min-h-24 py-2'} value={motivo} onChange={(e) => setMotivo(e.target.value)}
            placeholder={tipo === 'TROCA_TAMANHO' ? 'Ex.: a jaqueta 6 ficou apertada; precisa da 8.' : 'Ex.: a mochila rasgou a alça.'} />
        </Field>
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ ficha do aluno
export function UniformesAluno({ studentId }: { studentId: string }) {
  const res = useRpc<any>('uk_aluno', { student_id: studentId }, { retry: false });
  const qc = useQueryClient();
  const toast = useToast();
  const [tamanhos, setTamanhos] = useState(false);
  const [nova, setNova] = useState(false);
  const [busy, setBusy] = useState(false);
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const atual = (d.anos as any[])[0];
  const recarregar = () => qc.invalidateQueries({ queryKey: ['uk_aluno'] });
  const salvarTamanhos = async (v: any) => {
    setBusy(true);
    try {
      await rpc('uk_tamanhos_registrar', { student_id: studentId, ano: atual?.ano, ...v });
      toast({ title: 'Tamanhos registrados pela unidade', tone: 'success' });
      setTamanhos(false);
      recarregar();
    } catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  const necessidades = (d.anos as any[]).flatMap((a) => (a.necessidades as any[]));
  return (
    <div className="space-y-5">
      {(d.pode_operar || d.pode_adaptado) && (
        <div className="flex flex-wrap gap-2">
          {d.pode_operar && atual && <Button size="sm" variant="secondary" icon={Ruler} onClick={() => setTamanhos(true)}>Informar tamanhos pela família</Button>}
          <Button size="sm" variant="secondary" icon={ClipboardList} onClick={() => setNova(true)}>{d.pode_operar ? 'Registrar necessidade' : 'Pedir material adaptado'}</Button>
          {d.pode_operar && <Link to={`/uniformes?aba=retirada&aluno=${studentId}`} className="inline-flex h-9 items-center gap-1.5 rounded-2xl bg-purple-700 px-3 text-[13px] font-semibold text-white"><PackageCheck className="size-4" />Registrar retirada</Link>}
        </div>
      )}
      <Section title="Tamanhos do uniforme">
        <Card className="overflow-hidden">
          <Tabela colunas="70px 110px minmax(240px,1fr) minmax(200px,1fr)" largura={680} rotulo="Tamanhos por ano">
            <TCabecalho><TCelula fixa>Ano</TCelula><TCelula>Etapa</TCelula><TCelula>Tamanhos</TCelula><TCelula>Informado</TCelula></TCabecalho>
            {(d.anos as any[]).map((a) => (
              <TLinha key={a.ano}>
                <TCelula fixa>{a.ano}</TCelula><TCelula>{a.etapa_rotulo ?? '—'}</TCelula>
                <TCelula>{a.tamanhos ? <TamanhosResumo t={a.tamanhos} /> : <span className="text-muted">Não informado{a.sugestao ? ` (sugestão pela idade: ${a.sugestao.superior})` : ''}</span>}</TCelula>
                <TCelula>{a.tamanhos ? `${UK_CANAL[a.tamanhos.canal] ?? ''} · ${fmtDateTime(a.tamanhos.informado_em)}${a.tamanhos.informado_por ? ` · ${a.tamanhos.informado_por}` : ''}` : '—'}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
      <Section title="Entregas e retiradas" subtitle="Uma linha por entrega: anual, aluno novo, troca, reposição ou material adaptado.">
        <Card className="overflow-hidden">
          {necessidades.length ? (
            <Tabela colunas="60px 150px minmax(220px,1.4fr) 150px minmax(240px,1.2fr)" largura={980} rotulo="Entregas e retiradas">
              <TCabecalho><TCelula fixa>Ano</TCelula><TCelula>Entrega</TCelula><TCelula>Itens</TCelula><TCelula>Situação</TCelula><TCelula>Retirada</TCelula></TCabecalho>
              {necessidades.map((n) => (
                <TLinha key={n.id} alerta={n.vencida}>
                  <TCelula fixa>{n.ano}</TCelula>
                  <TCelula titulo={n.tipo_rotulo}>{UK_CONTEUDO[n.conteudo]}{n.tipo !== 'ANUAL' ? ` · ${n.tipo_rotulo}` : ''}</TCelula>
                  <TCelula titulo={itensResumo(n.itens)}>{itensResumo(n.itens) || n.motivo || '—'}</TCelula>
                  <TCelula livre><SituacaoUk s={n.situacao} vencida={n.vencida} /></TCelula>
                  <TCelula titulo={n.registrado_por ? `Registrado por ${n.registrado_por}` : undefined}>
                    {n.retirada_em ? `${fmtDateTime(n.retirada_em)} · ${n.retirada_por} (${n.retirada_parentesco?.toLowerCase()}) · ${n.codigo_conferido ? 'código' : `documento ${n.retirada_documento ?? ''}`}`
                      : n.situacao === 'DISPONIVEL' ? `Liberado ${fmtDate(n.disponivel_em)} · prazo ${fmtDate(n.prazo_retirada)}` : '—'}
                  </TCelula>
                </TLinha>
              ))}
            </Tabela>
          ) : <EmptyState compact title="Sem entregas registradas" />}
        </Card>
      </Section>
      <Section title="Avisos à família" subtitle="Data e hora do envio, WhatsApp e ciência.">
        <Card className="overflow-hidden">
          {(d.avisos as any[]).length ? (
            <Tabela colunas="150px 170px minmax(220px,1fr) 190px 150px" largura={900} rotulo="Avisos de uniforme e kit">
              <TCabecalho><TCelula fixa>Enviado em</TCelula><TCelula>Tipo</TCelula><TCelula>Texto</TCelula><TCelula>WhatsApp</TCelula><TCelula>Ciência</TCelula></TCabecalho>
              {(d.avisos as any[]).map((a) => (
                <TLinha key={a.id}>
                  <TCelula fixa>{fmtDateTime(a.enviado_em)}</TCelula><TCelula>{UK_AVISO[a.tipo] ?? a.tipo}</TCelula><TCelula titulo={a.texto}>{a.texto}</TCelula>
                  <TCelula livre><WhatsAvisoUk s={a.whatsapp} em={a.whatsapp_em} /></TCelula><TCelula>{a.ciente_em ? fmtDateTime(a.ciente_em) : <Badge tone="amber">aguardando</Badge>}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          ) : <EmptyState compact title="Nenhum aviso" />}
        </Card>
      </Section>
      <p className="text-[12.5px] text-muted"><Users className="mr-1 inline size-4" />Pode retirar: {(d.autorizados as any[]).map((x) => `${x.nome} (${x.parentesco.toLowerCase()})`).join(', ') || 'ninguém cadastrado com permissão de buscar a criança'}.</p>
      <Sheet open={tamanhos} onClose={() => setTamanhos(false)} title={`Tamanhos do uniforme ${atual?.ano ?? ''}`} subtitle="Informados pela família na secretaria ou por telefone.">
        <TamanhosForm grade={d.grade} sugestao={atual?.sugestao} inicial={atual?.tamanhos} salvando={busy} onSalvar={salvarTamanhos} />
      </Sheet>
      <NecessidadeSheet open={nova} onClose={() => setNova(false)} studentId={studentId} soAdaptado={!d.pode_operar} onFeito={recarregar} />
    </div>
  );
}

function NecessidadeSheet({ open, onClose, studentId, soAdaptado, onFeito }: { open: boolean; onClose: () => void; studentId: string; soAdaptado: boolean; onFeito: () => void }) {
  const toast = useToast();
  const [tipo, setTipo] = useState(soAdaptado ? 'ADAPTADO' : 'TROCA_TAMANHO');
  const [conteudo, setConteudo] = useState('UNIFORME');
  const [motivo, setMotivo] = useState('');
  const [itens, setItens] = useState('');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('uk_necessidade_registrar', { student_id: studentId, tipo: soAdaptado ? 'ADAPTADO' : tipo, conteudo, motivo,
        itens: itens.split('\n').map((x) => x.trim()).filter(Boolean) });
      toast({ title: 'Necessidade registrada', tone: 'success' });
      setMotivo(''); setItens('');
      onFeito(); onClose();
    } catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  const t = soAdaptado ? 'ADAPTADO' : tipo;
  return (
    <Sheet open={open} onClose={onClose} title={soAdaptado ? 'Material adaptado (AEE)' : 'Registrar necessidade'}
      subtitle={t === 'ADAPTADO' ? 'A SEDUC analisa e a unidade avisa a família quando chegar.' : 'Entra na lista da unidade para separar e avisar a família.'}
      footer={<Button block loading={busy} onClick={enviar}>Registrar</Button>}>
      <div className="space-y-3">
        {!soAdaptado && (
          <select className={inputCls} value={tipo} onChange={(e) => setTipo(e.target.value)}>
            <option value="ALUNO_NOVO">Aluno novo (entrega da etapa)</option><option value="TROCA_TAMANHO">Troca de tamanho</option>
            <option value="REPOSICAO">Reposição (perda ou dano)</option><option value="ADAPTADO">Material adaptado (AEE)</option>
          </select>
        )}
        {t === 'ALUNO_NOVO' && <Segmented value={conteudo} onChange={setConteudo} items={[{ value: 'UNIFORME', label: 'Uniforme' }, { value: 'KIT', label: 'Kit escolar' }]} />}
        {t === 'REPOSICAO' && <Segmented value={conteudo} onChange={setConteudo} items={[{ value: 'UNIFORME', label: 'Uniforme' }, { value: 'KIT', label: 'Kit escolar' }]} />}
        {t !== 'ALUNO_NOVO' && (
          <>
            <Field label="Motivo"><textarea className={inputCls + ' min-h-20 py-2'} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Field>
            <Field label="Peças ou materiais (um por linha)" hint={t === 'ADAPTADO' ? 'Ex.: caderno com pauta ampliada; tesoura adaptada; material em Braille' : 'Ex.: jaqueta tamanho 8'}>
              <textarea className={inputCls + ' min-h-20 py-2'} value={itens} onChange={(e) => setItens(e.target.value)} />
            </Field>
          </>
        )}
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ painel agregado (Prefeito, SEDUC, órgãos externos)
export function PainelUniformes() {
  const [ano, setAno] = useState<number | null>(null);
  const res = useRpc<any>('uk_estatisticas', ano ? { ano } : {});
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const t = d.totais;
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Segmented value={String(d.ano)} onChange={(v) => setAno(Number(v))} items={(d.anos as number[]).map((a) => ({ value: String(a), label: String(a) }))} />
        <Link to="/mapa?q=uk_retirada" className="inline-flex h-9 items-center gap-1.5 rounded-2xl bg-white px-3 text-[13px] font-semibold ring-1 ring-line hover:ring-purple-200"><MapIcon className="size-4" />Ver no mapa</Link>
      </div>
      {d.campanha && <p className="text-[13px] text-muted">{d.campanha.nome}: coleta de tamanhos {fmtDate(d.campanha.coleta_inicio)} a {fmtDate(d.campanha.coleta_fim)} · entrega {fmtDate(d.campanha.entrega_inicio)} a {fmtDate(d.campanha.entrega_fim)}.</p>}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi compact icon={Users} tone="purple" label="Alunos atendidos" value={fmtInt(t.alunos)} sub={`${fmtInt(t.unidades)} unidades`} />
        <Kpi compact icon={Ruler} tone="amber" label="Tamanhos informados" value={pctBr(t.pct_tamanho ?? 0)} sub={`${fmtInt(t.sem_tamanho)} sem tamanho`} />
        <Kpi compact icon={PackageCheck} tone="green" label="Retirado (do liberado)" value={pctBr(t.pct_retirada)} sub={`${fmtInt(t.retirados)} de ${fmtInt(t.liberados)}`} />
        <Kpi compact icon={Timer} tone="red" label="Prazo vencido" value={fmtInt(t.vencidos)} sub="liberado e não retirado" />
        <Kpi compact icon={Package} tone="blue" label="Aguardando material" value={fmtInt(t.aguardando_material)} sub={`${fmtInt(t.alunos_novos)} alunos novos`} />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <div className="mb-2 font-semibold">Avisos às famílias</div>
          <div className="grid grid-cols-2 gap-2 text-[13.5px]">
            <div>Avisos: <b>{fmtInt(d.avisos.total)}</b></div><div>Ciência: <b>{pctBr(d.avisos.pct_ciencia ?? 0)}</b></div>
            <div>WhatsApp: <b>{fmtInt(d.avisos.whatsapp_enviados + d.avisos.whatsapp_simulados)}</b>{d.avisos.whatsapp_simulados > 0 && <MarcaSimulado className="ml-1" />}</div>
            <div>Só no portal: <b>{fmtInt(d.avisos.sem_whatsapp)}</b></div>
            <div>Na fila agora: <b>{fmtInt(d.avisos.na_fila)}</b></div>
            <div>Retirada com código: <b>{fmtInt(t.com_codigo)}</b> · documento: <b>{fmtInt(t.por_documento)}</b></div>
          </div>
          {d.canais_tamanho && Object.keys(d.canais_tamanho).length > 0 && (
            <p className="mt-2 text-[12.5px] text-muted">Tamanhos: {Object.entries(d.canais_tamanho).map(([k, v]) => `${fmtInt(v as number)} ${UK_CANAL[k] ?? k}`).join(' · ')}</p>
          )}
        </Card>
        <Card className="p-4">
          <div className="mb-2 font-semibold">Trocas, reposições e material adaptado</div>
          {Object.keys(d.pedidos ?? {}).length ? (
            <div className="space-y-1 text-[13.5px]">
              {Object.values(d.pedidos as Record<string, any>).map((p: any) => (
                <div key={p.rotulo} className="flex justify-between gap-2"><span>{p.rotulo}</span><span>{fmtInt(p.abertos)} em aberto · {fmtInt(p.atendidos)} atendidos · {fmtInt(p.negados)} negados</span></div>
              ))}
            </div>
          ) : <p className="text-[13px] text-muted">Nenhum pedido no ano.</p>}
          {d.tutelar != null && <p className="mt-2 text-[13px] font-semibold text-red-700">{fmtInt(d.tutelar)} criança(s) na lista de atenção do Conselho Tutelar.</p>}
        </Card>
      </div>
      <Section title="Por etapa">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(120px,1fr) 100px 140px 140px 140px" largura={640} rotulo="Por etapa">
            <TCabecalho><TCelula fixa>Etapa</TCelula><TCelula>Alunos</TCelula><TCelula>Tamanhos</TCelula><TCelula>Retirado</TCelula><TCelula>Ampliação</TCelula></TCabecalho>
            {(d.por_etapa as any[]).map((e) => (
              <TLinha key={e.etapa}><TCelula fixa>{e.rotulo}</TCelula><TCelula>{fmtInt(e.alunos)}</TCelula><TCelula>{pctBr(e.pct_tamanho)}</TCelula>
                <TCelula>{pctBr(e.pct_retirada)}</TCelula><TCelula>{e.ampliacao ? fmtInt(e.ampliacao) : '—'}</TCelula></TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
      <Section title="Por região" subtitle="As 29 regiões do IBGE (áreas de ponderação). Primeiro, as que menos retiraram.">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(200px,1.4fr) 90px 90px 120px 120px 100px" largura={760} rotulo="Por região">
            <TCabecalho><TCelula fixa>Região</TCelula><TCelula>Unidades</TCelula><TCelula>Alunos</TCelula><TCelula>Tamanhos</TCelula><TCelula>Retirado</TCelula><TCelula>Vencidos</TCelula></TCabecalho>
            {(d.por_regiao as any[]).map((r) => (
              <TLinha key={r.regiao} alerta={(r.pct_retirada ?? 100) < 90}><TCelula fixa>{r.regiao}</TCelula><TCelula>{fmtInt(r.unidades)}</TCelula><TCelula>{fmtInt(r.alunos)}</TCelula>
                <TCelula>{pctBr(r.pct_tamanho)}</TCelula><TCelula>{pctBr(r.pct_retirada)}</TCelula><TCelula>{fmtInt(r.vencidos)}</TCelula></TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
      <Section title="Por unidade" subtitle="Uma linha por unidade; primeiro as que menos retiraram.">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(220px,1.6fr) 70px minmax(140px,1fr) 80px 100px 100px 90px 90px" largura={980} rotulo="Por unidade">
            <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Tipo</TCelula><TCelula>Região</TCelula><TCelula>Alunos</TCelula><TCelula>Tamanhos</TCelula><TCelula>Retirado</TCelula><TCelula>Vencidos</TCelula><TCelula>Aguard.</TCelula></TCabecalho>
            {(d.por_unidade as any[]).map((u) => (
              <TLinha key={u.unit_id} to={`/unidades/${u.unit_id}`} alerta={u.vencidos > 5}>
                <TCelula fixa>{u.nome}</TCelula><TCelula>{u.tipo}</TCelula><TCelula>{u.regiao ?? '—'}</TCelula><TCelula>{fmtInt(u.alunos)}</TCelula>
                <TCelula>{pctBr(u.pct_tamanho)}</TCelula><TCelula>{pctBr(u.pct_retirada)}</TCelula>
                <TCelula>{fmtInt(u.vencidos)}</TCelula><TCelula>{fmtInt(u.aguardando)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
      <Section title="Entregue por item" subtitle={d.custos ? 'Quantidade entregue e valor de referência.' : 'Quantidade entregue.'}>
        <Card className="overflow-hidden">
          <Tabela colunas={d.custos ? 'minmax(240px,1.6fr) 110px 140px' : 'minmax(240px,1.6fr) 110px'} largura={520} rotulo="Entregue por item">
            <TCabecalho><TCelula fixa>Item</TCelula><TCelula>Quantidade</TCelula>{d.custos && <TCelula>Valor</TCelula>}</TCabecalho>
            {(d.entregue_por_item as any[]).map((i) => (
              <TLinha key={i.codigo}><TCelula fixa>{i.nome}</TCelula><TCelula>{fmtInt(i.quantidade)}</TCelula>{d.custos && <TCelula>{i.valor == null ? 'sem preço' : fmtBRL(i.valor)}</TCelula>}</TLinha>
            ))}
          </Tabela>
        </Card>
        {d.custos && (
          <p className="mt-2 inline-flex flex-wrap items-center gap-1 text-[13.5px]">
            Valor de referência entregue: <b>{fmtBRL(d.custos.valor_entregue)}</b> · por aluno atendido: <b>{fmtBRL(d.custos.por_aluno)}</b> ({fmtInt(d.custos.alunos_atendidos)} alunos)
            {d.custos.valor_demo && <MarcaSimulado titulo="Valores fictícios: a SEDUC informa os do contrato" />}
          </p>
        )}
      </Section>
      <Card className="flex flex-wrap gap-6 p-4 text-[13.5px]">
        <div><Shirt className="mr-1 inline size-4" />Estoque da SEDUC: <b>{fmtInt(d.estoque.central_uniforme)}</b> peças · <b>{fmtInt(d.estoque.central_kits)}</b> kits</div>
        <div>Nas unidades: <b>{fmtInt(d.estoque.unidades_uniforme)}</b> peças · <b>{fmtInt(d.estoque.unidades_kits)}</b> kits</div>
        <div><CheckCheck className="mr-1 inline size-4" />Remessas: {Object.entries(d.estoque.remessas ?? {}).map(([k, v]) => `${fmtInt(v as number)} ${String(k).toLowerCase().replace('_', ' ')}`).join(' · ') || 'nenhuma'}</div>
      </Card>
      <p className="text-[12.5px] text-muted">{d.nota}</p>
    </div>
  );
}
