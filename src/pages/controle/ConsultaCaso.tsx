// Consulta de um caso pelo controle externo: só com o protocolo informado pela família e o motivo (atendimento da
// Defensoria, procedimento do MP). Mostra a situação, a posição, os critérios, quem está à frente (sem identificação),
// as ofertas e a linha do tempo. Cada consulta fica registrada na auditoria e na trilha de governança.
import { useState } from 'react';
import clsx from 'clsx';
import { CheckCircle2, Circle, FileSearch, History, Lock, ShieldCheck, Stethoscope, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { CASE_STATUS, DOC, DOC_STATUS, FLAG, OFFER_STATUS, QUEUE_STATUS } from '@/lib/labels';
import { Badge, Button, Card, DataPair, Field, MarcaSimulado, PageHeader, Section, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { LinkMetodologia, TresDistanciasInscricao } from '@/components/distancias';
import { PontosCriterio } from '@/components/PontosCriterio';

const ORIGEM = [
  ['DEFENSORIA', 'Atendimento da Defensoria Pública'],
  ['MP', 'Procedimento do Ministério Público'],
  ['CONSELHO', 'Conselho Tutelar'],
  ['OUTRO', 'Outro'],
] as const;

const TIPO_OFERTA: Record<string, { rotulo: string; tone: 'green' | 'blue' | 'purple' | 'gray' }> = {
  NA_ORDEM: { rotulo: 'ao 1º da fila', tone: 'green' },
  ALTERNATIVA: { rotulo: 'em outra unidade', tone: 'blue' },
  LAUDO: { rotulo: 'fora da ordem por laudo', tone: 'purple' },
  SEM_REGISTRO: { rotulo: 'sem registro da posição', tone: 'gray' },
};

export default function ConsultaCaso() {
  const exemplos = useRpc<any[]>('controle_protocolos_demo', {}, { staleTime: 10 * 60_000 });
  const [protocolo, setProtocolo] = useState('');
  const [origem, setOrigem] = useState<string>('DEFENSORIA');
  const [numero, setNumero] = useState('');
  const [busy, setBusy] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [r, setR] = useState<any>(null);
  const motivo = `${ORIGEM.find((o) => o[0] === origem)?.[1]}${numero.trim() ? ` nº ${numero.trim()}` : ''}`;
  const pronto = protocolo.trim().length >= 5 && numero.trim().length >= 2;

  const consultar = async () => {
    setBusy(true);
    setErro(null);
    try {
      setR(await rpc<any>('controle_caso', { protocolo: protocolo.trim(), motivo }));
    } catch (e) {
      setErro((e as Error).message);
      setR(null);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <PageHeader eyebrow="Controle externo · consulta de caso" title="Consultar um caso pelo protocolo"
        subtitle="Para atender uma família: com o número do protocolo que ela informou, veja a situação, a posição, os critérios aplicados e quem está à frente — sem identificar as outras crianças." />

      <Card className="p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-[1fr_1fr_1fr]">
          <Field label="Protocolo informado pela família" hint="Ex.: MGA-2026-000123 (no portal da família, em Protocolos, ou na conversa da IARA)">
            <input value={protocolo} onChange={(e) => setProtocolo(e.target.value.toUpperCase())} placeholder="MGA-2026-000000" className={clsx(inputCls, 'font-mono')} />
          </Field>
          <Field label="Origem da consulta">
            <select value={origem} onChange={(e) => setOrigem(e.target.value)} className={inputCls}>
              {ORIGEM.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </Field>
          <Field label="Número do atendimento / procedimento" hint="Fica registrado como motivo da consulta">
            <input value={numero} onChange={(e) => setNumero(e.target.value)} placeholder="Ex.: 123/2026" className={inputCls} />
          </Field>
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-3">
          <Button variant="purple" icon={FileSearch} disabled={!pronto} loading={busy} onClick={consultar}>Consultar e registrar acesso</Button>
          <span className="inline-flex items-center gap-1.5 text-[12.5px] text-muted"><Lock className="size-3.5" />A consulta fica na auditoria: quem, quando, qual protocolo e o motivo.</span>
        </div>
        {(exemplos.data ?? []).length > 0 && (
          <div className="mt-4 rounded-2xl bg-amber-50/70 p-3 ring-1 ring-amber-100">
            <div className="mb-2 flex items-center gap-1.5 text-[12.5px] font-semibold text-amber-950"><MarcaSimulado />Protocolos fictícios para testar</div>
            <div className="flex flex-wrap gap-2">
              {(exemplos.data as any[]).map((x) => (
                <button key={x.protocolo} type="button" onClick={() => { setProtocolo(x.protocolo); if (!numero) setNumero('123/2026'); }}
                  className="rounded-2xl bg-white px-3 py-2 text-left text-[12.5px] ring-1 ring-amber-200 transition hover:ring-amber-400">
                  <span className="block font-mono font-semibold">{x.protocolo}</span>
                  <span className="block text-muted">{x.rotulo} · {x.descricao}</span>
                </button>
              ))}
            </div>
          </div>
        )}
        {erro && <p className="mt-3 rounded-2xl bg-red-50 p-3 text-[13.5px] text-red-800 ring-1 ring-red-100">{erro}</p>}
      </Card>

      {r && !r.encontrado && (
        <Card className="mt-4 flex items-start gap-3 bg-amber-50 p-4 ring-1 ring-amber-200">
          <X className="mt-0.5 size-5 shrink-0 text-amber-800" />
          <p className="text-[14px] text-amber-950">{r.mensagem} <span className="text-amber-800">(A tentativa também foi registrada.)</span></p>
        </Card>
      )}
      {r?.encontrado && <Resultado r={r} />}
    </div>
  );
}

function Resultado({ r }: { r: any }) {
  const p = r.protocolo;
  const f = r.fila;
  return (
    <div className="mt-4 space-y-4">
      <Card className="flex flex-wrap items-center gap-x-3 gap-y-1 bg-blue-50 p-3 text-[13px] text-blue-950 ring-1 ring-blue-100">
        <ShieldCheck className="size-4 text-blue-800" />
        <span>Acesso registrado em {fmtDateTime(r.consultado_em)} · motivo: <b>{r.motivo}</b></span>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1.2fr]">
        <Card className="p-4">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-mono text-[15px] font-bold">{p.numero}</span>
            <Badge tone={CASE_STATUS[p.status]?.tone ?? 'gray'}>{CASE_STATUS[p.status]?.label ?? p.status}</Badge>
            {p.vencido && <Badge tone="red">prazo vencido</Badge>}
            <MarcaSimulado />
          </div>
          <div className="mt-1 text-[13.5px] font-semibold">{p.tipo}</div>
          <dl className="mt-3 grid grid-cols-2 gap-3">
            <DataPair label="Aberto em" value={fmtDateTime(p.aberto_em)} />
            <DataPair label="Prazo" value={p.prazo ? fmtDateTime(p.prazo) : '—'} />
            <DataPair label="Criança" value={r.crianca ? `${r.crianca.nome} · ${r.crianca.idade}` : '—'} />
            <DataPair label="Faixa pela idade" value={r.crianca?.faixa_pela_idade ?? '—'} />
            <DataPair label="Responsável" value={r.responsavel?.nome ?? '—'} />
            <DataPair label="Telefone" value={<span className="inline-flex items-center gap-1">{r.responsavel?.telefone ?? '—'}<Lock className="size-3 text-subtle" /></span>} />
          </dl>
        </Card>

        {f ? (
          <Card className="overflow-hidden">
            <div className="bg-gradient-to-br from-purple-700 to-purple-900 p-4 text-white">
              <div className="text-[12px] font-bold uppercase tracking-wide text-purple-200">{f.faixa} · {f.unidade}</div>
              <div className="mt-1 flex items-end gap-3">
                <div className="font-display text-5xl font-black leading-none">{f.posicao ? `${f.posicao}º` : QUEUE_STATUS[f.status]?.label}</div>
                {f.posicao && <div className="pb-1 text-[13px] text-purple-100">de {fmtInt(f.aguardando)} aguardando · {fmtInt(f.pontos)} pontos</div>}
              </div>
              <div className="mt-2 flex flex-wrap gap-1.5 text-[12px]">
                <span className="rounded-full bg-white/15 px-2.5 py-0.5 font-mono font-semibold">{f.codigo}</span>
                <span className="rounded-full bg-white/15 px-2.5 py-0.5">na fila desde {fmtDate(f.entrada)} ({fmtInt(f.dias)} dias)</span>
                <span className="rounded-full bg-white/15 px-2.5 py-0.5">regras {f.regras}</span>
                {f.ordem_conferida != null && (
                  <span className={clsx('inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 font-semibold', f.ordem_conferida ? 'bg-green-500/90' : 'bg-red-500/90')}>
                    {f.ordem_conferida ? <CheckCircle2 className="size-3.5" /> : <X className="size-3.5" />}{f.ordem_conferida ? 'ordem conferida' : 'ordem divergente'}
                  </span>
                )}
              </div>
            </div>
            <ul className="space-y-2 p-4">
              {(f.criterios as any[]).map((b) => (
                <li key={b.code} className="flex items-start gap-2">
                  {b.analysis ? <Stethoscope className={clsx('mt-0.5 size-4 shrink-0', b.applied ? 'text-purple-700' : 'text-slate-300')} />
                    : b.applied ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" /> : <Circle className="mt-0.5 size-4 shrink-0 text-slate-300" />}
                  <div className="min-w-0 flex-1 text-[13.5px]">
                    <div className="flex justify-between gap-2"><span className={b.applied ? 'font-semibold' : 'text-muted'}>{b.name}</span>
                      {b.analysis ? <Badge tone={b.applied ? 'purple' : 'gray'}>sob análise</Badge> : <PontosCriterio weight={b.weight} applied={b.applied} />}</div>
                    <div className="text-[12px] text-muted">{b.evidence}</div>
                    {b.code === 'TERRITORIO_2KM' && b.distancias && (
                      <div className="mt-1 flex flex-wrap items-center gap-2"><TresDistanciasInscricao breakdown={f.criterios} /><LinkMetodologia className="text-[12px]">como medimos</LinkMetodologia></div>
                    )}
                  </div>
                </li>
              ))}
            </ul>
            {f.vagas_ofertaveis > 0 && f.posicao > 1 && (
              <p className="border-t border-line bg-amber-50 px-4 py-2 text-[12.5px] text-amber-950">
                Há {fmtInt(f.vagas_ofertaveis)} vaga(s) ofertável(is) nesta faixa da unidade: devem ser ofertadas a partir do 1º da fila.
              </p>
            )}
          </Card>
        ) : <Card className="p-4 text-[13.5px] text-muted">Este protocolo não tem inscrição na fila.</Card>}
      </div>

      {f && (f.a_frente as any[]).length > 0 && (
        <Section title="Quem está à frente (sem identificação)" subtitle="Código público, pontos, critérios e data de entrada de cada inscrição à frente nesta fila." className="mt-0">
          <Card className="overflow-hidden">
            <Tabela rotulo="Inscrições à frente" largura={620} colunas="70px 110px 70px minmax(200px,1fr) 100px">
              <TCabecalho><span>Posição</span><span>Código</span><span className="text-right">Pontos</span><span>Critérios</span><span>Entrada</span></TCabecalho>
              {(f.a_frente as any[]).map((x) => (
                <TLinha key={x.codigo}>
                  <TCelula className="font-display font-black text-purple-800">{x.posicao}º</TCelula>
                  <TCelula className="font-mono text-[12.5px]">{x.codigo}</TCelula>
                  <TCelula className="text-right tabular">{fmtInt(x.pontos)}</TCelula>
                  <TCelula><span className="inline-flex gap-1">{(x.criterios ?? []).map((c: string) => <Badge key={c} tone="purple">{FLAG[c]?.short ?? c}</Badge>)}{!(x.criterios ?? []).length && <span className="text-muted">—</span>}</span></TCelula>
                  <TCelula className="tabular text-muted">{fmtDate(x.entrada)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
            <p className="border-t border-line bg-slate-50 px-4 py-2 text-[12px] text-muted">Mais pontos vêm primeiro; com a mesma pontuação, vale a data de entrada.</p>
          </Card>
        </Section>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Ofertas de vaga" className="mt-0">
          <Card className="divide-y divide-line overflow-hidden">
            {(r.ofertas as any[]).length === 0 && <p className="p-4 text-[13.5px] text-muted">Nenhuma oferta registrada.</p>}
            {(r.ofertas as any[]).map((o, i) => (
              <div key={i} className="flex flex-wrap items-center gap-2 px-4 py-3 text-[13.5px]">
                <span className="min-w-0 flex-1"><b>{o.unidade}</b><span className="block text-[12px] text-muted">{fmtDateTime(o.quando)}{o.motivo_recusa ? ` · recusa: ${o.motivo_recusa}` : ''}</span></span>
                <Badge tone={TIPO_OFERTA[o.tipo]?.tone ?? 'gray'}>{TIPO_OFERTA[o.tipo]?.rotulo ?? o.tipo}</Badge>
                <Badge tone={OFFER_STATUS[o.status]?.tone ?? 'gray'}>{OFFER_STATUS[o.status]?.label ?? o.status}</Badge>
              </div>
            ))}
          </Card>
        </Section>
        <Section title="Documentos" className="mt-0">
          <Card className="divide-y divide-line overflow-hidden">
            {(r.documentos as any[]).length === 0 && <p className="p-4 text-[13.5px] text-muted">Nenhum documento registrado.</p>}
            {(r.documentos as any[]).map((d) => (
              <div key={d.tipo} className="flex items-center justify-between px-4 py-2.5 text-[13.5px]">
                <span>{DOC[d.tipo] ?? d.tipo}</span><Badge tone={DOC_STATUS[d.status]?.tone ?? 'gray'}>{DOC_STATUS[d.status]?.label ?? d.status}</Badge>
              </div>
            ))}
            <p className="bg-slate-50 px-4 py-2 text-[12px] text-muted">Só a situação de cada documento — nenhum arquivo é exibido.</p>
          </Card>
        </Section>
      </div>

      <Section title={<span className="inline-flex items-center gap-2"><History className="size-5 text-purple-700" />Linha do tempo do protocolo</span>} subtitle="O que a família também vê" className="mt-0">
        <Card className="divide-y divide-line overflow-hidden">
          {(r.eventos as any[]).length === 0 && <p className="p-4 text-[13.5px] text-muted">Sem movimentações.</p>}
          {(r.eventos as any[]).map((e, i) => (
            <div key={i} className="px-4 py-2.5 text-[13.5px]">
              <span className="text-[12px] text-muted">{fmtDateTime(e.quando)}</span>
              <p>{e.mensagem}</p>
            </div>
          ))}
        </Card>
      </Section>
    </div>
  );
}
