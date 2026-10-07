import { useState } from 'react';
import { BadgeCheck, History, Pencil, Plus } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, Chip, ErrorState, Field, PageHeader, Section, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { useRecarregarBA } from '@/components/busca-ativa';

const SITUACAO: Record<string, { label: string; tone: Tone }> = {
  CONFIRMADO: { label: 'Confirmada', tone: 'green' }, PROPOSTO: { label: 'Proposta', tone: 'amber' }, PENDENTE_VALIDACAO: { label: 'Pendente de validação', tone: 'purple' },
};
const ETAPA: Record<string, string> = { TODAS: 'Todas', CRECHE: 'Creche', PRE: 'Pré-escola', EF: 'Fundamental' };
const TIPO_ORGAO: Record<string, string> = {
  CONSELHO_TUTELAR: 'Conselho Tutelar', CRAS: 'CRAS', CREAS: 'CREAS', SAUDE: 'Saúde', TRANSPORTE_ESCOLAR: 'Transporte escolar', ASSISTENCIA_SOCIAL: 'Assistência social', OUTRO: 'Outro',
};
const CANAL: Record<string, string> = { PROTOCOLO_ELETRONICO: 'Protocolo eletrônico', EMAIL_INSTITUCIONAL: 'E-mail institucional', INTEGRACAO: 'Integração' };

/** Cadastro versionado das regras da frequência, modelos de mensagem e órgãos destinatários verificados. */
export default function RegrasFrequencia() {
  const res = useRpc<any>('frequencia_regras', {});
  const [aba, setAba] = useState<'regras' | 'modelos' | 'orgaos'>('regras');
  const [hist, setHist] = useState(false);
  const [editar, setEditar] = useState<any | null>(null);
  const [modelo, setModelo] = useState<any | null>(null);
  const [orgao, setOrgao] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const regras = (d.regras as any[]).filter((r) => hist || r.ativo || r.vigencia_fim == null);
  return (
    <div>
      <PageHeader eyebrow="SEDUC · frequência e busca ativa" title="Regras, mensagens e órgãos"
        subtitle="Cada regra tem rede, etapa, gatilho, base normativa, vigência, critério de contagem, aprovador e situação. Proposta não vale como norma municipal confirmada. Toda alteração vira nova versão, com quem, quando e o fundamento." />
      <Tabs value={aba} onChange={setAba} items={[{ value: 'regras', label: 'Regras' }, { value: 'modelos', label: 'Mensagens à família' }, { value: 'orgaos', label: 'Órgãos destinatários' }]} />
      <div className="mt-3">
        {aba === 'regras' && (
          <div className="space-y-2">
            <Chip active={hist} onClick={() => setHist(!hist)} icon={History}>Mostrar versões anteriores</Chip>
            <Card className="overflow-hidden">
              <Tabela colunas="minmax(220px,2fr) 100px 90px 90px minmax(220px,2fr) 170px 60px 50px" largura={1180} rotulo="Regras da frequência">
                <TCabecalho><TCelula fixa>Regra</TCelula><TCelula>Etapa</TCelula><TCelula>Valor</TCelula><TCelula>Ativa</TCelula><TCelula>Base normativa</TCelula><TCelula>Situação</TCelula><TCelula>Versão</TCelula><TCelula /></TCabecalho>
                {regras.map((r) => (
                  <TLinha key={r.id} className={r.ativo ? '' : 'opacity-60'}>
                    <TCelula fixa titulo={`${r.nome} — ${r.gatilho}`} className="font-semibold">{r.nome}</TCelula>
                    <TCelula>{ETAPA[r.etapa]}</TCelula>
                    <TCelula>{r.valor != null ? `${String(r.valor).replace('.', ',')} ${r.unidade ?? ''}` : '—'}</TCelula>
                    <TCelula>{r.ativo ? 'sim' : r.vigencia_fim ? `até ${fmtDate(r.vigencia_fim)}` : 'não'}</TCelula>
                    <TCelula titulo={r.base_normativa} className="text-[12.5px]">{r.base_normativa ?? '—'}</TCelula>
                    <TCelula livre><Badge tone={SITUACAO[r.situacao]?.tone ?? 'gray'}>{SITUACAO[r.situacao]?.label}</Badge></TCelula>
                    <TCelula titulo={r.fundamento_alteracao ? `${r.alterado_por_label}: ${r.fundamento_alteracao}` : undefined}>v{r.versao}</TCelula>
                    <TCelula livre>{d.pode_editar && r.vigencia_fim == null && <button type="button" aria-label={`Alterar ${r.nome}`} onClick={() => setEditar(r)} className="rounded-lg p-1 text-blue-700 hover:bg-blue-50"><Pencil className="size-4" /></button>}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            </Card>
            <p className="text-[12.5px] text-muted">5 faltas seguidas e 7 alternadas em 60 dias existem só como opção de configuração, desligadas e “propostas”: valem para a rede municipal apenas depois da aprovação da SEDUC.</p>
          </div>
        )}
        {aba === 'modelos' && (
          <div className="space-y-2">
            {(d.modelos as any[]).map((m) => (
              <Card key={m.codigo} className="p-4">
                <div className="flex items-center justify-between gap-2"><b>{m.nome}</b><span className="text-[12px] text-muted">v{m.versao}{m.alterado_por_label ? ` · ${m.alterado_por_label}, ${fmtDateTime(m.alterado_em)}` : ''}</span></div>
                <p className="mt-1 text-[14px] text-ink-2">{m.texto}</p>
                {d.pode_editar && <Button size="sm" variant="secondary" icon={Pencil} className="mt-2" onClick={() => setModelo(m)}>Editar</Button>}
              </Card>
            ))}
            <p className="text-[12.5px] text-muted">Mensagens acolhedoras, objetivas e sem ameaça ou presunção de culpa. Variáveis: {'{nome_responsavel} {nome_aluno} {data} {unidade} {servico} {necessidade}'}.</p>
          </div>
        )}
        {aba === 'orgaos' && (
          <Section title="Destinatários institucionais" action={d.pode_editar ? <Button size="sm" icon={Plus} onClick={() => setOrgao({})}>Novo órgão</Button> : undefined}>
            <Card className="overflow-hidden">
              <Tabela colunas="minmax(240px,2fr) 150px 170px minmax(160px,1.2fr) 140px 50px" largura={980} rotulo="Órgãos destinatários">
                <TCabecalho><TCelula fixa>Órgão</TCelula><TCelula>Tipo</TCelula><TCelula>Canal oficial</TCelula><TCelula>Endereço</TCelula><TCelula>Verificação</TCelula><TCelula /></TCabecalho>
                {(d.orgaos as any[]).map((o) => (
                  <TLinha key={o.id} alerta={!o.verificado}>
                    <TCelula fixa titulo={o.nome} className="font-semibold">{o.nome}</TCelula>
                    <TCelula>{TIPO_ORGAO[o.tipo] ?? o.tipo}</TCelula>
                    <TCelula>{CANAL[o.canal]}</TCelula>
                    <TCelula titulo={o.endereco_canal}>{o.endereco_canal ?? '—'}</TCelula>
                    <TCelula livre>{o.verificado ? <Badge tone="green" icon={BadgeCheck}>Verificado</Badge> : <Badge tone="amber">Não verificado</Badge>}</TCelula>
                    <TCelula livre>{d.pode_editar && <button type="button" aria-label={`Editar ${o.nome}`} onClick={() => setOrgao(o)} className="rounded-lg p-1 text-blue-700 hover:bg-blue-50"><Pencil className="size-4" /></button>}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            </Card>
            <p className="mt-1 text-[12.5px] text-muted">Documentos sensíveis só seguem para destinatário verificado, por protocolo eletrônico, integração oficial ou e-mail institucional de domínio público — nunca para número pessoal.</p>
          </Section>
        )}
      </div>
      <RegraSheet r={editar} onClose={() => setEditar(null)} />
      <ModeloSheet m={modelo} onClose={() => setModelo(null)} />
      <OrgaoSheet o={orgao} onClose={() => setOrgao(null)} />
    </div>
  );
}

function RegraSheet({ r, onClose }: { r: any | null; onClose: () => void }) {
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarBA();
  if ((r?.id ?? null) !== chave) {
    setChave(r?.id ?? null);
    setF(r ? { valor: r.valor ?? '', situacao: r.situacao, base_normativa: r.base_normativa ?? '', ativo: r.ativo, aprovador: r.aprovador ?? '', fundamento: '' } : {});
  }
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('frequencia_regra_salvar', { id: r.id, ...f });
      toast({ title: 'Regra alterada', description: 'Nova versão gravada; a anterior fica no histórico.', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não alterada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!r} onClose={onClose} title={r?.nome} subtitle={r ? `${r.gatilho} · ${r.criterio_contagem ?? ''}` : ''}
      footer={<Button block size="lg" loading={busy} disabled={(f.fundamento ?? '').trim().length < 10} onClick={salvar}>Gravar nova versão</Button>}>
      {r && (
        <div className="space-y-3">
          {r.valor != null && <Field label={`Valor (${r.unidade ?? ''})`}><input type="number" step="any" value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} className={`${inputCls} h-11`} /></Field>}
          <Field label="Situação">
            <select value={f.situacao} onChange={(e) => setF({ ...f, situacao: e.target.value })} className={`${inputCls} h-11`}>
              {Object.entries(SITUACAO).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
            </select>
          </Field>
          <Field label="Base normativa"><input value={f.base_normativa} onChange={(e) => setF({ ...f, base_normativa: e.target.value })} className={inputCls} /></Field>
          <Field label="Aprovador"><input value={f.aprovador} onChange={(e) => setF({ ...f, aprovador: e.target.value })} className={inputCls} /></Field>
          <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={!!f.ativo} onChange={(e) => setF({ ...f, ativo: e.target.checked })} />Regra ativa</label>
          <Field label="Fundamento da alteração" hint="Ato, ofício ou decisão que autoriza (fica na trilha)."><textarea value={f.fundamento} onChange={(e) => setF({ ...f, fundamento: e.target.value })} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
        </div>
      )}
    </Sheet>
  );
}

function ModeloSheet({ m, onClose }: { m: any | null; onClose: () => void }) {
  const [texto, setTexto] = useState('');
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarBA();
  if ((m?.codigo ?? null) !== chave) { setChave(m?.codigo ?? null); setTexto(m?.texto ?? ''); }
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('frequencia_modelo_salvar', { codigo: m.codigo, texto });
      toast({ title: 'Mensagem atualizada', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não atualizada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!m} onClose={onClose} title={m?.nome} footer={<Button block size="lg" loading={busy} onClick={salvar}>Salvar</Button>}>
      <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={8} className={`${inputCls} h-auto py-3`} aria-label="Texto da mensagem" />
    </Sheet>
  );
}

function OrgaoSheet({ o, onClose }: { o: any | null; onClose: () => void }) {
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarBA();
  const k = o ? (o.id ?? 'novo') : null;
  if (k !== chave) { setChave(k); setF(o ? { tipo: 'CONSELHO_TUTELAR', canal: 'PROTOCOLO_ELETRONICO', ...o, verificar: false } : {}); }
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('orgao_salvar', f);
      toast({ title: 'Órgão salvo', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!o} onClose={onClose} title={o?.id ? 'Editar órgão' : 'Novo órgão destinatário'} footer={<Button block size="lg" loading={busy} onClick={salvar}>Salvar</Button>}>
      <div className="space-y-3">
        <Field label="Nome"><input value={f.nome ?? ''} onChange={(e) => setF({ ...f, nome: e.target.value })} className={inputCls} /></Field>
        <Field label="Tipo"><select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })} className={`${inputCls} h-11`}>{Object.entries(TIPO_ORGAO).map(([a, b]) => <option key={a} value={a}>{b}</option>)}</select></Field>
        <Field label="Competência"><input value={f.competencia ?? ''} onChange={(e) => setF({ ...f, competencia: e.target.value })} className={inputCls} /></Field>
        <Field label="Canal oficial"><select value={f.canal} onChange={(e) => setF({ ...f, canal: e.target.value })} className={`${inputCls} h-11`}>{Object.entries(CANAL).map(([a, b]) => <option key={a} value={a}>{b}</option>)}</select></Field>
        <Field label="Endereço do canal" hint="E-mail institucional precisa ser de domínio público oficial (.gov.br, .jus.br, .mp.br)."><input value={f.endereco_canal ?? ''} onChange={(e) => setF({ ...f, endereco_canal: e.target.value })} className={inputCls} /></Field>
        <label className="flex items-start gap-2 text-[13.5px]"><input type="checkbox" className="mt-1" checked={!!f.verificar} onChange={(e) => setF({ ...f, verificar: e.target.checked })} />
          <span>Confirmo que o canal foi verificado com o órgão (fica registrado quem verificou e quando).</span></label>
      </div>
    </Sheet>
  );
}
