// Uniformes e kits escolares — tela da unidade (retirada, alunos, liberação, pedidos, avisos) e da SEDUC (painel, demanda,
// remessas, avisos em lote, campanhas, composição e grade). O Prefeito e os órgãos externos veem só o painel agregado.
import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, Check, Megaphone, PackageCheck, PackageOpen, Pencil, Search, Send, Truck, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtBRL, fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, PageHeader, Section, Segmented, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { UnitSelect } from '@/components/escola';
import { CodigoRetirada, PainelUniformes, SituacaoUk, UK_CANAL, UK_CONTEUDO, UK_MODELO, itensResumo } from '@/components/uniformes';

type Aba = 'retirada' | 'alunos' | 'pedidos' | 'avisos' | 'painel' | 'demanda' | 'remessas' | 'campanhas' | 'composicao';

export default function Uniformes() {
  const { can, me } = useSession();
  const [sp, setSp] = useSearchParams();
  const unidade = can('uk.unidade') && me?.scope === 'UNIT';
  const seduc = can('uk.manage');
  const leitura = can('uk.read');
  const abas: { value: Aba; label: string }[] = [
    ...(unidade ? [{ value: 'retirada' as Aba, label: 'Retirada' }] : []),
    ...(leitura ? [{ value: 'alunos' as Aba, label: unidade ? 'Alunos' : 'Alunos por unidade' }] : []),
    ...(leitura ? [{ value: 'pedidos' as Aba, label: 'Trocas e pedidos' }] : []),
    ...(unidade || seduc ? [{ value: 'avisos' as Aba, label: 'Avisos em lote' }] : []),
    ...(can('uk.estatisticas') ? [{ value: 'painel' as Aba, label: 'Painel' }] : []),
    ...(seduc || can('uk.estatisticas') ? [{ value: 'demanda' as Aba, label: 'Demanda por tamanho' }] : []),
    ...(seduc ? [{ value: 'remessas' as Aba, label: 'Remessas' }, { value: 'campanhas' as Aba, label: 'Campanhas' }] : []),
    { value: 'composicao', label: 'Composição' },
  ];
  const aba = (abas.find((a) => a.value === sp.get('aba'))?.value ?? abas[0]?.value ?? 'composicao') as Aba;
  return (
    <div>
      <PageHeader eyebrow="Rede e logística" title="Uniformes e kits escolares"
        subtitle={unidade ? 'Tamanhos, liberação por etapa ou turma, retirada com código e avisos às famílias (portal e IARA).'
          : 'Coleta de tamanhos, demanda para a compra, remessas às unidades, retirada e estatísticas por etapa, região e unidade.'} />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={abas} />
      <div className="mt-4">
        {aba === 'retirada' && <RetiradaAba />}
        {aba === 'alunos' && <AlunosAba />}
        {aba === 'pedidos' && <PedidosAba />}
        {aba === 'avisos' && <AvisosAba />}
        {aba === 'painel' && <PainelUniformes />}
        {aba === 'demanda' && <DemandaAba />}
        {aba === 'remessas' && <RemessasAba />}
        {aba === 'campanhas' && <CampanhasAba />}
        {aba === 'composicao' && <ComposicaoAba />}
      </div>
    </div>
  );
}

// ------------------------------------------------------------------ retirada (unidade)
function RetiradaAba() {
  const [sp] = useSearchParams();
  const toast = useToast();
  const qc = useQueryClient();
  const [codigo, setCodigo] = useState('');
  const [busca, setBusca] = useState('');
  const [conf, setConf] = useState<any>(null);
  const [busy, setBusy] = useState(false);
  const [marcados, setMarcados] = useState<string[]>([]);
  const [faltando, setFaltando] = useState<{ id: string; item: string }[]>([]);
  const [quem, setQuem] = useState<string>('');
  const [doc, setDoc] = useState('');
  const [obs, setObs] = useState('');
  const termo = useDebounced(busca, 300);
  const lista = useRpc<any>('uk_unidade', { busca: termo, situacao: 'DISPONIVEL' }, { enabled: termo.trim().length >= 3 });
  const conferir = async (args: object) => {
    setBusy(true);
    try {
      const r = await rpc<any>('uk_codigo_conferir', args);
      setConf(r);
      setMarcados((r.disponiveis as any[]).map((n) => n.id));
      setFaltando([]);
      const principal = (r.autorizados as any[]).find((a) => a.principal) ?? r.autorizados[0];
      setQuem(principal ? chaveQuem(principal) : '');
      setDoc(''); setObs('');
    } catch (e) {
      setConf(null);
      toast({ title: 'Não encontrado', description: (e as Error).message, tone: 'error' });
    } finally { setBusy(false); }
  };
  useEffect(() => { const a = sp.get('aluno'); if (a) conferir({ student_id: a }); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const registrar = async () => {
    const a = (conf.autorizados as any[]).find((x) => chaveQuem(x) === quem);
    setBusy(true);
    try {
      const r = await rpc<any>('uk_retirada_registrar', {
        student_id: conf.student_id, ids: marcados, codigo: conf.codigo_ok ? codigo : '', documento: doc, observacao: obs, faltando,
        quem: a?.tipo === 'RESPONSAVEL' ? { guardian_id: a.guardian_id } : a?.tipo === 'AUTORIZADO' ? { autorizacao_id: a.autorizacao_id } : { proprio: true },
      });
      toast({ title: 'Retirada registrada', description: `${r.retirada_por} · ${fmtDateTime(r.em)}. A família recebe a confirmação.`, tone: 'success' });
      setConf(null); setCodigo(''); setBusca('');
      qc.invalidateQueries({ queryKey: ['uk_unidade'] });
    } catch (e) { toast({ title: 'Não registrada', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[360px_1fr]">
      <div className="space-y-3">
        <Card className="space-y-2 p-4">
          <Field label="Código de retirada (6 números)">
            <div className="flex gap-2">
              <input inputMode="numeric" className={inputCls + ' font-mono text-[18px] tracking-[0.2em]'} value={codigo} maxLength={7}
                onChange={(e) => setCodigo(e.target.value.replace(/[^\d ]/g, ''))} onKeyDown={(e) => e.key === 'Enter' && conferir({ codigo })} placeholder="000 000" />
              <Button icon={Check} loading={busy} disabled={codigo.replace(/\D/g, '').length !== 6} onClick={() => conferir({ codigo })}>Conferir</Button>
            </div>
          </Field>
          <p className="text-[12.5px] text-muted">O código está no aviso da família (portal e WhatsApp), com QR.</p>
        </Card>
        <Card className="space-y-2 p-4">
          <Field label="Sem código: procure pelo nome">
            <div className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" />
              <input className={inputCls + ' pl-9'} value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome do aluno (3 letras ou mais)" /></div>
          </Field>
          {(lista.data?.alunos as any[] | undefined)?.slice(0, 8).map((a) => (
            <button key={a.student_id} type="button" onClick={() => conferir({ student_id: a.student_id })}
              className="flex w-full items-center justify-between rounded-xl px-2 py-1.5 text-left text-[13.5px] hover:bg-slate-50">
              <span className="truncate">{a.nome}</span><span className="text-[12px] text-muted">{a.turma}</span>
            </button>
          ))}
        </Card>
      </div>
      <div>
        {!conf ? (
          <Card><EmptyState title="Confira o código ou procure o aluno" body="Aparecem o que está liberado e quem pode retirar (responsáveis com permissão de buscar a criança e autorizados em Guarda e restrições)." /></Card>
        ) : (
          <Card className="space-y-4 p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div><div className="text-[17px] font-bold">{conf.nome}</div><div className="text-[13px] text-muted">{conf.turma}</div></div>
              {conf.codigo_ok ? <Badge tone="green" icon={Check}>Código confere</Badge> : <Badge tone="amber">Sem código: confira o documento</Badge>}
            </div>
            {conf.alerta_guarda && <div className="flex items-center gap-2 rounded-2xl bg-red-50 p-3 text-[13.5px] text-red-800 ring-1 ring-red-100"><AlertTriangle className="size-4" />Há restrição de retirada para esta criança. Só as pessoas da lista abaixo podem retirar.</div>}
            {(conf.disponiveis as any[]).length === 0 ? (
              <EmptyState compact title="Nada liberado para retirada" body={(conf.outras as any[]).length ? `Em andamento: ${(conf.outras as any[]).map((n) => `${UK_CONTEUDO[n.conteudo]} (${n.situacao_rotulo.toLowerCase()})`).join(', ')}.` : undefined} />
            ) : (
              <div className="space-y-2">
                {(conf.disponiveis as any[]).map((n) => (
                  <div key={n.id} className="rounded-2xl p-3 ring-1 ring-line/70">
                    <label className="flex items-center gap-2 font-semibold">
                      <input type="checkbox" checked={marcados.includes(n.id)} onChange={(e) => setMarcados(e.target.checked ? [...marcados, n.id] : marcados.filter((x) => x !== n.id))} />
                      {UK_CONTEUDO[n.conteudo]}{n.tipo !== 'ANUAL' ? ` · ${n.tipo_rotulo}` : ''} {n.etapa_rotulo ? `· ${n.etapa_rotulo}` : ''}
                    </label>
                    <div className="mt-1 flex flex-wrap gap-1.5 pl-6">
                      {(n.itens as any[]).map((i) => {
                        const falta = faltando.some((f) => f.id === n.id && f.item === i.item);
                        return (
                          <button key={i.item ?? i.nome} type="button" title={falta ? 'Marcado como faltando: toque para entregar' : 'Toque se esta peça faltou'}
                            onClick={() => i.item && setFaltando(falta ? faltando.filter((f) => !(f.id === n.id && f.item === i.item)) : [...faltando, { id: n.id, item: i.item }])}
                            className={falta ? 'rounded-full bg-red-50 px-2 py-0.5 text-[12px] text-red-700 line-through ring-1 ring-red-200' : 'rounded-full bg-slate-50 px-2 py-0.5 text-[12px] ring-1 ring-line'}>
                            {i.quantidade > 1 ? `${i.quantidade} ` : ''}{i.nome}{i.tamanho ? ` (${i.tamanho})` : ''}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ))}
                <p className="text-[12px] text-muted">Faltou alguma peça? Toque nela: a retirada fica “em parte” e a peça continua pendente.</p>
              </div>
            )}
            {(conf.disponiveis as any[]).length > 0 && (
              <>
                <Field label="Quem está retirando">
                  <div className="space-y-1">
                    {(conf.autorizados as any[]).map((a) => (
                      <label key={chaveQuem(a)} className="flex items-center gap-2 rounded-xl px-2 py-1.5 text-[14px] hover:bg-slate-50">
                        <input type="radio" name="quem" checked={quem === chaveQuem(a)} onChange={() => setQuem(chaveQuem(a))} />
                        <span className="font-semibold">{a.nome}</span><span className="text-muted">{a.parentesco}{a.documento ? ` · doc. ${a.documento}` : ''}</span>
                      </label>
                    ))}
                    {(conf.autorizados as any[]).length === 0 && <p className="text-[13px] text-red-700">Ninguém com permissão de buscar a criança. Inclua em Guarda e restrições.</p>}
                  </div>
                </Field>
                {!conf.codigo_ok && <Field label="Documento conferido (últimos números)"><input className={inputCls} value={doc} onChange={(e) => setDoc(e.target.value)} placeholder="Ex.: 4521" /></Field>}
                <Field label="Observação (opcional)"><input className={inputCls} value={obs} onChange={(e) => setObs(e.target.value)} /></Field>
                <Button block icon={PackageCheck} loading={busy} disabled={!marcados.length || !quem || (!conf.codigo_ok && doc.trim().length < 3)} onClick={registrar}>Registrar a retirada</Button>
              </>
            )}
          </Card>
        )}
      </div>
    </div>
  );
}
const chaveQuem = (a: any) => a.guardian_id ?? a.autorizacao_id ?? 'proprio';

// ------------------------------------------------------------------ alunos (unidade ou uma unidade escolhida)
function AlunosAba() {
  const { me, can } = useSession();
  const [unit, setUnit] = useState<number | null>(me?.scope === 'UNIT' ? me.unit?.id ?? null : null);
  const [etapa, setEtapa] = useState('');
  const [sit, setSit] = useState('');
  const [busca, setBusca] = useState('');
  const termo = useDebounced(busca, 300);
  const [ano, setAno] = useState<number | null>(null);
  const res = useRpc<any>('uk_unidade', { unit_id: unit, etapa, situacao: sit, busca: termo, ...(ano ? { ano } : {}) }, { enabled: !!unit });
  const [liberar, setLiberar] = useState(false);
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        {me?.scope !== 'UNIT' && <UnitSelect value={unit} onChange={setUnit} todas={null} />}
        {res.data && <Segmented value={String(res.data.ano)} onChange={(v) => setAno(Number(v))} items={(res.data.anos as number[]).map((a) => ({ value: String(a), label: String(a) }))} />}
        <select className={inputCls + ' w-auto'} value={etapa} onChange={(e) => setEtapa(e.target.value)} aria-label="Etapa">
          <option value="">Todas as etapas</option>{((res.data?.por_etapa ?? []) as any[]).map((e) => <option key={e.etapa} value={e.etapa}>{e.rotulo}</option>)}
        </select>
        <select className={inputCls + ' w-auto'} value={sit} onChange={(e) => setSit(e.target.value)} aria-label="Situação">
          <option value="">Todas as situações</option><option value="AGUARDANDO_TAMANHO">Sem tamanho</option><option value="AGUARDANDO_MATERIAL">Aguardando material</option>
          <option value="DISPONIVEL">Pode retirar</option><option value="VENCIDA">Prazo vencido</option><option value="RETIRADA">Retirado</option>
        </select>
        <div className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" /><input className={inputCls + ' w-56 pl-9'} value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar aluno" /></div>
        {res.data?.pode_operar && <Button icon={PackageOpen} onClick={() => setLiberar(true)}>Liberar para retirada</Button>}
      </div>
      {!unit ? <Card><EmptyState title="Escolha a unidade" /></Card> : res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-6">
            <Kpi compact icon={PackageCheck} tone="purple" label="Alunos" value={fmtInt(res.data.contagem.alunos)} />
            <Kpi compact icon={Pencil} tone="amber" label="Sem tamanho" value={fmtInt(res.data.contagem.sem_tamanho)} />
            <Kpi compact icon={Truck} tone="blue" label="Aguardando material" value={fmtInt(res.data.contagem.aguardando_material)} />
            <Kpi compact icon={PackageOpen} tone="teal" label="Pode retirar" value={fmtInt(res.data.contagem.disponiveis)} />
            <Kpi compact icon={AlertTriangle} tone="red" label="Prazo vencido" value={fmtInt(res.data.contagem.vencidas)} />
            <Kpi compact icon={Check} tone="green" label="Retirados" value={fmtInt(res.data.contagem.retiradas)} />
          </div>
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(220px,1.5fr) 120px 100px minmax(200px,1fr) 150px 150px 170px" largura={1180} rotulo="Uniformes e kits por aluno">
              <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Turma</TCelula><TCelula>Etapa</TCelula><TCelula>Tamanhos</TCelula><TCelula>Uniforme</TCelula><TCelula>Kit</TCelula><TCelula>Aviso</TCelula></TCabecalho>
              {(res.data.alunos as any[]).map((a) => (
                <TLinha key={a.student_id} to={can('students.read') ? `/alunos/${a.student_id}?aba=uniforme` : undefined} rotulo={a.nome}
                  alerta={[a.uniforme, a.kit].some((x) => x?.situacao === 'DISPONIVEL' && x?.prazo && x.prazo < new Date().toISOString().slice(0, 10))}>
                  <TCelula fixa>{a.nome}</TCelula><TCelula>{a.turma}</TCelula><TCelula>{a.etapa_rotulo ?? '—'}</TCelula>
                  <TCelula titulo={a.tamanhos ? UK_CANAL[a.tamanhos.canal] : undefined}>{a.tamanhos ? `${a.tamanhos.superior} · ${a.tamanhos.inferior} · ${a.tamanhos.calcado} · ${UK_MODELO[a.tamanhos.modelo] ?? '—'}` : <span className="text-muted">—</span>}</TCelula>
                  <TCelula livre>{a.uniforme ? <SituacaoUk s={a.uniforme.situacao} /> : '—'}</TCelula>
                  <TCelula livre>{a.kit ? <SituacaoUk s={a.kit.situacao} /> : '—'}</TCelula>
                  <TCelula>{a.aviso ? (a.aviso.ciente_em ? `ciente ${fmtDate(a.aviso.ciente_em)}` : `enviado ${fmtDate(a.aviso.enviado_em)}`) : '—'}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
          <LiberarSheet open={liberar} onClose={() => setLiberar(false)} d={res.data} onFeito={() => res.refetch()} />
        </>
      )}
    </div>
  );
}

function LiberarSheet({ open, onClose, d, onFeito }: { open: boolean; onClose: () => void; d: any; onFeito: () => void }) {
  const toast = useToast();
  const [conteudo, setConteudo] = useState('');
  const [etapa, setEtapa] = useState('');
  const [turma, setTurma] = useState('');
  const [busy, setBusy] = useState(false);
  const ir = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('uk_disponibilizar', { ano: d.ano, conteudo, etapa, class_id: turma });
      toast({ title: `${fmtInt(r.liberadas)} item(ns) liberado(s)`, description: `${fmtInt(r.avisos)} família(s) avisada(s) com o código de retirada.${r.sem_tamanho ? ` ${fmtInt(r.sem_tamanho)} ainda sem tamanho.` : ''}`, tone: 'success' });
      onFeito(); onClose();
    } catch (e) { toast({ title: 'Não liberado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Liberar para retirada" subtitle="Só o que já está na unidade. Cada família recebe o aviso com o código, no portal e no WhatsApp (em lotes, das 8h às 19h)."
      footer={<Button block icon={Send} loading={busy} onClick={ir}>Liberar e avisar as famílias</Button>}>
      <div className="space-y-3">
        <Segmented value={conteudo} onChange={setConteudo} items={[{ value: '', label: 'Uniforme e kit' }, { value: 'UNIFORME', label: 'Só uniforme' }, { value: 'KIT', label: 'Só kit' }]} />
        <Field label="Etapa"><select className={inputCls} value={etapa} onChange={(e) => setEtapa(e.target.value)}><option value="">Todas</option>{(d.por_etapa as any[]).map((e) => <option key={e.etapa} value={e.etapa}>{e.rotulo} ({fmtInt(e.aguardando)} aguardando)</option>)}</select></Field>
        <Field label="Turma"><select className={inputCls} value={turma} onChange={(e) => setTurma(e.target.value)}><option value="">Todas</option>{(d.turmas as any[]).map((t) => <option key={t.id} value={t.id}>{t.nome}</option>)}</select></Field>
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ trocas, reposições, alunos novos e material adaptado
function PedidosAba() {
  const res = useRpc<any[]>('uk_pedidos_lista', {});
  const { can, me } = useSession();
  const toast = useToast();
  const [decidir, setDecidir] = useState<any>(null);
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const ir = async (aprovar: boolean) => {
    setBusy(true);
    try {
      await rpc('uk_necessidade_decidir', { id: decidir.id, aprovar, motivo });
      toast({ title: aprovar ? 'Aprovado' : 'Não aprovado', description: 'A família recebe a resposta no portal e no WhatsApp.', tone: 'success' });
      setDecidir(null); setMotivo(''); res.refetch();
    } catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const podeDecidir = (n: any) => n.situacao === 'AGUARDANDO_DECISAO' && (n.conteudo === 'ADAPTADO' ? can('uk.manage') : can('uk.unidade') && me?.scope === 'UNIT');
  return (
    <div className="space-y-3">
      <p className="text-[13px] text-muted">Trocas e reposições pedidas pela família: a unidade decide. Material adaptado do AEE: a SEDUC decide. Aprovado, entra na fila de separação e a família é avisada quando puder retirar.</p>
      <Card className="overflow-hidden">
        {res.data?.length ? (
          <Tabela colunas="minmax(200px,1.3fr) minmax(140px,1fr) 170px minmax(240px,1.6fr) 110px 160px 120px" largura={1200} rotulo="Pedidos">
            <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Pedido</TCelula><TCelula>Motivo e itens</TCelula><TCelula>Em</TCelula><TCelula>Situação</TCelula><TCelula /></TCabecalho>
            {res.data.map((n) => (
              <TLinha key={n.id}>
                <TCelula fixa>{n.aluno}</TCelula><TCelula>{n.unidade}</TCelula><TCelula>{UK_CONTEUDO[n.conteudo]} · {n.tipo_rotulo}</TCelula>
                <TCelula titulo={`${n.motivo ?? ''} ${itensResumo(n.itens)}`}>{n.motivo ?? itensResumo(n.itens)}</TCelula><TCelula>{fmtDate(n.created_at)}</TCelula>
                <TCelula livre><SituacaoUk s={n.situacao} /></TCelula>
                <TCelula livre>{podeDecidir(n) && <Button size="sm" onClick={() => setDecidir(n)}>Decidir</Button>}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : <EmptyState compact title="Nenhum pedido em andamento" />}
      </Card>
      <Sheet open={!!decidir} onClose={() => setDecidir(null)} title={decidir ? `${decidir.tipo_rotulo} · ${decidir.aluno}` : ''} subtitle={decidir?.motivo}
        footer={<div className="flex gap-2"><Button variant="danger" icon={X} loading={busy} onClick={() => ir(false)}>Não aprovar</Button><Button icon={Check} loading={busy} onClick={() => ir(true)}>Aprovar</Button></div>}>
        <p className="mb-2 text-[13.5px]">{itensResumo(decidir?.itens)}</p>
        <Field label="Resposta à família (obrigatória se não aprovar)"><textarea className={inputCls + ' min-h-20 py-2'} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Field>
      </Sheet>
    </div>
  );
}

// ------------------------------------------------------------------ avisos em lote
function AvisosAba() {
  const { me, can } = useSession();
  const res = useRpc<any>('uk_disparos', {});
  const camp = useRpc<any[]>('uk_campanhas', {});
  const toast = useToast();
  const [tipo, setTipo] = useState('TAMANHO');
  const [ano, setAno] = useState<number | null>(null);
  const [unit, setUnit] = useState<number | null>(null);
  const [etapa, setEtapa] = useState('');
  const [busy, setBusy] = useState(false);
  const anoSel = ano ?? camp.data?.find((c) => c.situacao !== 'ENCERRADA' && c.situacao !== 'PLANEJAMENTO')?.ano ?? null;
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('uk_disparo_criar', { tipo, ano: anoSel, unit_id: unit, etapa });
      toast({ title: `${fmtInt(r.total)} família(s) na fila`, description: `Um aviso a cada ${r.intervalo_segundos} s, das 8h às 19h (cerca de ${String(r.previsao_horas).replace('.', ',')} h de envio). Quem recebeu nas últimas 48 h fica de fora.`, tone: 'success' });
      res.refetch();
    } catch (e) { toast({ title: 'Não enviado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <div className="space-y-4">
      <Card className="space-y-3 p-4">
        <div className="font-semibold"><Megaphone className="mr-1 inline size-4" />Novo aviso em lote</div>
        <div className="flex flex-wrap items-end gap-2">
          <Segmented value={tipo} onChange={setTipo} items={[{ value: 'TAMANHO', label: 'Pedir tamanhos' }, { value: 'LEMBRETE_RETIRADA', label: 'Lembrar a retirada' }]} />
          <select className={inputCls + ' w-auto'} value={anoSel ?? ''} onChange={(e) => setAno(Number(e.target.value))} aria-label="Ano">
            {(camp.data ?? []).map((c) => <option key={c.ano} value={c.ano}>{c.nome}</option>)}
          </select>
          {me?.scope !== 'UNIT' && can('uk.manage') && <UnitSelect value={unit} onChange={setUnit} />}
          <select className={inputCls + ' w-auto'} value={etapa} onChange={(e) => setEtapa(e.target.value)} aria-label="Etapa">
            <option value="">Todas as etapas</option>
            {['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5', 'EJA'].map((e) => <option key={e} value={e}>{e.startsWith('INF') ? `Infantil ${e.slice(3)}` : e === 'EJA' ? 'EJA' : `${e.slice(2)}º ano`}</option>)}
          </select>
          <Button icon={Send} loading={busy} disabled={!anoSel} onClick={enviar}>Colocar na fila</Button>
        </div>
        <p className="text-[12.5px] text-muted">Sai pelo WhatsApp da IARA (mesmo número), em lotes, só para quem tem pendência: {tipo === 'TAMANHO' ? 'tamanho ainda não informado' : 'material liberado e não retirado'}. O aviso aparece na hora no portal da família, com data, hora e “Estou ciente”.</p>
      </Card>
      {res.isLoading ? <SkeletonList rows={3} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <p className="text-[13px] text-muted">Na fila agora: <b>{fmtInt(res.data.fila.agendados)}</b>{res.data.fila.ultimo_previsto ? ` · último previsto ${fmtDateTime(res.data.fila.ultimo_previsto)}` : ''} · enviados nas últimas 24 h: <b>{fmtInt(res.data.fila.enviados_24h)}</b> · intervalo {res.data.parametros?.intervalo_segundos} s, das {res.data.parametros?.horario_inicio}h às {res.data.parametros?.horario_fim}h.</p>
          <Card className="overflow-hidden">
            <Tabela colunas="150px 160px 70px minmax(140px,1fr) 110px 90px 90px 110px 90px 90px" largura={1140} rotulo="Avisos em lote">
              <TCabecalho><TCelula fixa>Criado em</TCelula><TCelula>Tipo</TCelula><TCelula>Ano</TCelula><TCelula>Recorte</TCelula><TCelula>Famílias</TCelula><TCelula>WhatsApp</TCelula><TCelula>Portal</TCelula><TCelula>Na fila</TCelula><TCelula>Ciência</TCelula><TCelula>Por</TCelula></TCabecalho>
              {(res.data.disparos as any[]).map((d) => (
                <TLinha key={d.id}>
                  <TCelula fixa>{fmtDateTime(d.criado_em)}</TCelula><TCelula>{d.tipo === 'TAMANHO' ? 'Pedir tamanhos' : 'Lembrar a retirada'}</TCelula><TCelula>{d.ano}</TCelula>
                  <TCelula>{[d.unidade ?? 'Rede', d.etapa].filter(Boolean).join(' · ')}</TCelula><TCelula>{fmtInt(d.total)}</TCelula>
                  <TCelula livre>{fmtInt(d.enviados + d.simulados)}{d.simulados > 0 && <MarcaSimulado className="ml-1" />}</TCelula><TCelula>{fmtInt(d.sem_whatsapp)}</TCelula>
                  <TCelula>{fmtInt(d.na_fila)}</TCelula><TCelula>{fmtInt(d.cientes)}</TCelula><TCelula titulo={d.criado_por}>{d.criado_por}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </>
      )}
    </div>
  );
}

// ------------------------------------------------------------------ demanda por tamanho (base da compra)
function DemandaAba() {
  const [ano, setAno] = useState<number | null>(null);
  const [unit, setUnit] = useState<number | null>(null);
  const camp = useRpc<any[]>('uk_campanhas', {});
  const res = useRpc<any>('uk_demanda', { ano, unit_id: unit });
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        <select className={inputCls + ' w-auto'} value={ano ?? res.data?.ano ?? ''} onChange={(e) => setAno(Number(e.target.value))} aria-label="Ano">
          {(camp.data ?? []).map((c) => <option key={c.ano} value={c.ano}>{c.nome}</option>)}
        </select>
        <UnitSelect value={unit} onChange={setUnit} />
      </div>
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <p className="text-[13.5px]"><b>{fmtInt(res.data.alunos)}</b> alunos · <b>{fmtInt(res.data.informados)}</b> com tamanho informado · <b>{fmtInt(res.data.sem_tamanho)}</b> estimados pela idade.</p>
          {(res.data.uniforme as any[]).map((p) => (
            <Card key={p.codigo} className="p-4">
              <div className="mb-2 flex flex-wrap items-center justify-between gap-2"><div className="font-semibold">{p.nome}</div><div className="text-[13px] text-muted">{fmtInt(p.total)} peças · {fmtInt(p.informado)} informadas · {fmtInt(p.estimado)} estimadas</div></div>
              <div className="flex flex-wrap gap-1.5">
                {(p.tamanhos as any[]).map((t) => (
                  <div key={t.tamanho} className="min-w-16 rounded-xl bg-slate-50 px-2 py-1 text-center ring-1 ring-line/70">
                    <div className="text-[11px] font-bold text-subtle">{t.tamanho}</div><div className="text-[14px] font-semibold">{fmtInt(t.quantidade)}</div>
                  </div>
                ))}
              </div>
            </Card>
          ))}
          <Section title="Kits por etapa">
            <Card className="overflow-hidden">
              <Tabela colunas="minmax(240px,1.5fr) 110px 140px" largura={520} rotulo="Kits">
                <TCabecalho><TCelula fixa>Kit</TCelula><TCelula>Quantidade</TCelula><TCelula>Valor de ref.</TCelula></TCabecalho>
                {(res.data.kits as any[]).map((k) => <TLinha key={k.codigo}><TCelula fixa>{k.nome}</TCelula><TCelula>{fmtInt(k.total)}</TCelula><TCelula>{k.valor_referencia ? fmtBRL(k.valor_referencia * k.total) : '—'}</TCelula></TLinha>)}
              </Tabela>
            </Card>
          </Section>
          <p className="text-[12.5px] text-muted">{res.data.nota}</p>
        </>
      )}
    </div>
  );
}

// ------------------------------------------------------------------ remessas
function RemessasAba() {
  const camp = useRpc<any[]>('uk_campanhas', {});
  const toast = useToast();
  const [ano, setAno] = useState<number | null>(null);
  const [conteudo, setConteudo] = useState('KIT');
  const [estimar, setEstimar] = useState(false);
  const [busy, setBusy] = useState(false);
  const anoSel = ano ?? camp.data?.find((c) => ['COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA'].includes(c.situacao))?.ano ?? null;
  const gerar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('uk_remessas_gerar', { ano: anoSel, conteudo, estimar_faltantes: estimar });
      toast({ title: `${fmtInt(r.pedidos)} remessa(s) gerada(s)`, description: `${fmtInt(r.necessidades)} aluno(s)${r.estimados ? `; ${fmtInt(r.estimados)} com tamanho estimado` : ''}. O almoxarifado despacha em Pedidos de material.`, tone: 'success' });
      camp.refetch();
    } catch (e) { toast({ title: 'Não gerado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <div className="space-y-4">
      <Card className="space-y-3 p-4">
        <div className="font-semibold"><Truck className="mr-1 inline size-4" />Gerar as remessas por unidade</div>
        <p className="text-[13px] text-muted">Um pedido aprovado por unidade, com as peças por tamanho e os kits por etapa de cada aluno. O almoxarifado despacha do estoque da SEDUC (os lotes saem na ordem de entrada) e a unidade confere e recebe; ao receber, o material fica liberado e as famílias são avisadas com o código.</p>
        <div className="flex flex-wrap items-center gap-2">
          <select className={inputCls + ' w-auto'} value={anoSel ?? ''} onChange={(e) => setAno(Number(e.target.value))} aria-label="Ano">{(camp.data ?? []).map((c) => <option key={c.ano} value={c.ano}>{c.nome}</option>)}</select>
          <Segmented value={conteudo} onChange={setConteudo} items={[{ value: 'KIT', label: 'Kits' }, { value: 'UNIFORME', label: 'Uniformes' }]} />
          {conteudo === 'UNIFORME' && <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={estimar} onChange={(e) => setEstimar(e.target.checked)} />Estimar pela idade quem não informou</label>}
          <Button icon={Truck} loading={busy} disabled={!anoSel} onClick={gerar}>Gerar remessas</Button>
        </div>
      </Card>
      <Link to="/materiais?aba=pedidos" className="inline-flex items-center gap-1.5 text-[14px] font-semibold text-purple-700">Ver os pedidos e o estoque no almoxarifado →</Link>
    </div>
  );
}

// ------------------------------------------------------------------ campanhas
function CampanhasAba() {
  const res = useRpc<any[]>('uk_campanhas', {});
  const [edit, setEdit] = useState<any>(null);
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const salvar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('uk_campanha_salvar', edit);
      toast({ title: 'Campanha salva', description: r.geracao?.novas ? `${fmtInt(r.geracao.novas)} necessidade(s) criada(s).` : undefined, tone: 'success' });
      setEdit(null); res.refetch();
    } catch (e) { toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const SIT: Record<string, string> = { PLANEJAMENTO: 'Planejamento', COLETA_TAMANHOS: 'Coleta de tamanhos', SEPARACAO: 'Separação e remessas', ENTREGA: 'Entrega', ENCERRADA: 'Encerrada' };
  return (
    <div className="space-y-3">
      <Button icon={Pencil} onClick={() => setEdit({ ano: (res.data?.[0]?.ano ?? new Date().getFullYear()) + 1, situacao: 'PLANEJAMENTO', prazo_retirada_dias: 30, inclui_uniforme: true, inclui_kit: true })}>Nova campanha</Button>
      <Card className="overflow-hidden">
        <Tabela colunas="70px minmax(180px,1fr) 170px 200px 200px 90px 100px 100px" largura={1100} rotulo="Campanhas">
          <TCabecalho><TCelula fixa>Ano</TCelula><TCelula>Nome</TCelula><TCelula>Situação</TCelula><TCelula>Coleta de tamanhos</TCelula><TCelula>Entrega</TCelula><TCelula>Alunos</TCelula><TCelula>Sem tamanho</TCelula><TCelula>Retirados</TCelula></TCabecalho>
          {(res.data ?? []).map((c) => (
            <TLinha key={c.id} onClick={() => setEdit({ ...c })}>
              <TCelula fixa>{c.ano}</TCelula><TCelula>{c.nome}</TCelula><TCelula livre><Badge tone={c.situacao === 'ENCERRADA' ? 'gray' : 'purple'}>{SIT[c.situacao]}</Badge></TCelula>
              <TCelula>{fmtDate(c.coleta_inicio)} a {fmtDate(c.coleta_fim)}</TCelula><TCelula>{fmtDate(c.entrega_inicio)} a {fmtDate(c.entrega_fim)}</TCelula>
              <TCelula>{fmtInt(c.alunos)}</TCelula><TCelula>{fmtInt(c.sem_tamanho)}</TCelula><TCelula>{fmtInt(c.retiradas)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <Sheet open={!!edit} onClose={() => setEdit(null)} title={edit?.id ? `Campanha ${edit.ano}` : 'Nova campanha'}
        subtitle="Ao abrir a coleta, o sistema cria a necessidade de cada aluno (uniforme e kit da etapa do ano) e acompanha matrículas e transferências."
        footer={<Button block loading={busy} onClick={salvar}>Salvar</Button>}>
        {edit && (
          <div className="grid grid-cols-2 gap-3">
            <Field label="Ano letivo"><input type="number" className={inputCls} value={edit.ano} onChange={(e) => setEdit({ ...edit, ano: Number(e.target.value) })} disabled={!!edit.id} /></Field>
            <Field label="Situação"><select className={inputCls} value={edit.situacao} onChange={(e) => setEdit({ ...edit, situacao: e.target.value })}>{Object.entries(SIT).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field label="Coleta: início"><input type="date" className={inputCls} value={edit.coleta_inicio ?? ''} onChange={(e) => setEdit({ ...edit, coleta_inicio: e.target.value })} /></Field>
            <Field label="Coleta: fim"><input type="date" className={inputCls} value={edit.coleta_fim ?? ''} onChange={(e) => setEdit({ ...edit, coleta_fim: e.target.value })} /></Field>
            <Field label="Entrega: início"><input type="date" className={inputCls} value={edit.entrega_inicio ?? ''} onChange={(e) => setEdit({ ...edit, entrega_inicio: e.target.value })} /></Field>
            <Field label="Entrega: fim"><input type="date" className={inputCls} value={edit.entrega_fim ?? ''} onChange={(e) => setEdit({ ...edit, entrega_fim: e.target.value })} /></Field>
            <Field label="Prazo de retirada (dias)"><input type="number" className={inputCls} value={edit.prazo_retirada_dias ?? 30} onChange={(e) => setEdit({ ...edit, prazo_retirada_dias: Number(e.target.value) })} /></Field>
            <div className="flex flex-col justify-end gap-1 text-[14px]">
              <label className="flex items-center gap-2"><input type="checkbox" checked={edit.inclui_uniforme} onChange={(e) => setEdit({ ...edit, inclui_uniforme: e.target.checked })} />Uniforme</label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={edit.inclui_kit} onChange={(e) => setEdit({ ...edit, inclui_kit: e.target.checked })} />Kit escolar</label>
            </div>
          </div>
        )}
      </Sheet>
    </div>
  );
}

// ------------------------------------------------------------------ composição oficial, grade e valores
function ComposicaoAba() {
  const res = useRpc<any>('uk_catalogo', {});
  const toast = useToast();
  const [aberto, setAberto] = useState<string | null>(null);
  const [grade, setGrade] = useState<{ grade: string; texto: string } | null>(null);
  const [preco, setPreco] = useState<{ codigo: string; nome: string; valor: string } | null>(null);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const itens = d.itens as any[];
  const salvarGrade = async () => {
    try {
      await rpc('uk_grade_salvar', { grade: grade!.grade, tamanhos: grade!.texto.split(/[,;\n]+/).map((x) => x.trim()).filter(Boolean) });
      toast({ title: 'Grade salva', tone: 'success' }); setGrade(null); res.refetch();
    } catch (e) { toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' }); }
  };
  const salvarPreco = async () => {
    try {
      await rpc('uk_item_salvar', { codigo: preco!.codigo, valor_referencia: preco!.valor.replace(',', '.') });
      toast({ title: 'Valor salvo', tone: 'success' }); setPreco(null); res.refetch();
    } catch (e) { toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' }); }
  };
  const gradeTexto = (g: string) => (d.grade as any[]).filter((x) => x.grade === g && x.ativo).map((x) => x.tamanho).join(', ');
  return (
    <div className="space-y-5">
      <p className="text-[13px] text-muted">Fontes oficiais: {(d.fontes as any[]).map((f, i) => <span key={f.url}>{i > 0 && ' · '}<a className="font-semibold text-purple-700" href={f.url} target="_blank" rel="noreferrer">{f.rotulo}</a></span>)}.</p>
      <Section title="Uniforme escolar" subtitle="Peças por aluno; o modelo da parte de baixo (shorts-saia ou bermuda) é escolhido pela família.">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(200px,1.4fr) 70px 120px minmax(220px,1.4fr) 130px" largura={820} rotulo="Uniforme">
            <TCabecalho><TCelula fixa>Peça</TCelula><TCelula>Qtde</TCelula><TCelula>Tamanho</TCelula><TCelula>Etapas</TCelula><TCelula>Valor de ref.</TCelula></TCabecalho>
            {itens.filter((i) => i.tipo === 'UNIFORME').map((i) => (
              <TLinha key={i.codigo} onClick={d.pode_gerir ? () => setPreco({ codigo: i.codigo, nome: i.nome, valor: i.valor_referencia ?? '' }) : undefined}>
                <TCelula fixa titulo={i.descricao}>{i.nome}{i.descricao ? ` · ${i.descricao}` : ''}</TCelula><TCelula>{i.quantidade}</TCelula>
                <TCelula>{({ SUPERIOR: 'parte de cima', INFERIOR: 'parte de baixo', CALCADO: 'calçado', MEIA: 'faixa da meia' } as Record<string, string>)[i.medida] ?? '—'}</TCelula>
                <TCelula titulo={i.etapas_rotulo}>{i.etapas_rotulo}</TCelula>
                <TCelula livre>{i.valor_referencia ? <span className="inline-flex items-center gap-1">{fmtBRL(i.valor_referencia)}{i.valor_demo && <MarcaSimulado titulo="Valor fictício" />}</span> : '—'}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
      <Section title="Kits escolares por etapa" subtitle="Composição 2025 e 2026 (documento oficial). Toque num kit para ver os itens.">
        <div className="space-y-2">
          {itens.filter((i) => i.tipo === 'KIT').map((k) => (
            <Card key={k.codigo} className="overflow-hidden">
              <button type="button" onClick={() => setAberto(aberto === k.codigo ? null : k.codigo)} className="flex w-full items-center justify-between gap-2 p-3 text-left">
                <div className="min-w-0"><div className="font-semibold">{k.nome}</div><div className="text-[12.5px] text-muted">{k.etapas_rotulo}{k.so_ampliacao ? ' · alunos da Ampliação de Jornada (soma ao kit do ano)' : ''} · {(k.composicao as any[]).length} itens</div></div>
                <span className="inline-flex items-center gap-1 text-[13px]">{k.valor_referencia ? fmtBRL(k.valor_referencia) : ''}{k.valor_demo && k.valor_referencia && <MarcaSimulado titulo="Valor fictício" />}</span>
              </button>
              {aberto === k.codigo && (
                <div className="border-t border-line/60">
                  <Tabela colunas="70px 80px minmax(220px,1.2fr) minmax(260px,1.6fr)" largura={760} rotulo={`Itens do ${k.nome}`}>
                    <TCabecalho><TCelula fixa>Qtde</TCelula><TCelula>Unid.</TCelula><TCelula>Item</TCelula><TCelula>Especificação</TCelula></TCabecalho>
                    {(k.composicao as any[]).map((c, i) => <TLinha key={i}><TCelula fixa>{String(c.quantidade).replace('.00', '')}</TCelula><TCelula>{c.unidade}</TCelula><TCelula titulo={c.item}>{c.item}</TCelula><TCelula titulo={c.especificacao}>{c.especificacao}</TCelula></TLinha>)}
                  </Tabela>
                  {d.pode_gerir && <div className="p-3"><Button size="sm" variant="ghost" onClick={() => setPreco({ codigo: k.codigo, nome: k.nome, valor: k.valor_referencia ?? '' })}>Valor de referência</Button></div>}
                </div>
              )}
            </Card>
          ))}
        </div>
      </Section>
      <Section title="Grade de tamanhos" subtitle="A usual, até a SEDUC cadastrar a do contrato.">
        <Card className="space-y-2 p-4 text-[14px]">
          {['ROUPA', 'CALCADO', 'MEIA'].map((g) => (
            <div key={g} className="flex flex-wrap items-center justify-between gap-2">
              <div><b>{g === 'ROUPA' ? 'Roupas' : g === 'CALCADO' ? 'Calçado (papete)' : 'Meias (pelo número do calçado)'}:</b> {gradeTexto(g)}</div>
              {d.pode_gerir && g !== 'MEIA' && <Button size="sm" variant="ghost" icon={Pencil} onClick={() => setGrade({ grade: g, texto: gradeTexto(g) })}>Editar</Button>}
            </div>
          ))}
        </Card>
      </Section>
      <Sheet open={!!grade} onClose={() => setGrade(null)} title="Editar a grade" subtitle="Tamanhos separados por vírgula, na ordem." footer={<Button block onClick={salvarGrade}>Salvar a grade</Button>}>
        {grade && <textarea className={inputCls + ' min-h-24 py-2'} value={grade.texto} onChange={(e) => setGrade({ ...grade, texto: e.target.value })} />}
      </Sheet>
      <Sheet open={!!preco} onClose={() => setPreco(null)} title={`Valor de referência · ${preco?.nome ?? ''}`} subtitle="Valor unitário do contrato (R$). Aparece para o Tribunal de Contas e os conselhos."
        footer={<Button block onClick={salvarPreco}>Salvar</Button>}>
        {preco && <input className={inputCls} inputMode="decimal" value={preco.valor} onChange={(e) => setPreco({ ...preco, valor: e.target.value })} placeholder="0,00" />}
      </Sheet>
      <p className="text-[12.5px] text-muted">Dúvidas sobre tamanho: a família informa pelo portal (Vida escolar → Uniforme e kit) ou pela IARA (“tamanho do uniforme”). <CodigoInfo /></p>
    </div>
  );
}

function CodigoInfo() {
  return <span>A retirada usa o código de 6 números do aviso (com QR); sem o código, a unidade confere um documento com foto.</span>;
}

export { CodigoRetirada };
