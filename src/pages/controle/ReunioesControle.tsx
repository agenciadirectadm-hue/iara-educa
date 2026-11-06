import { useState } from 'react';
import { Lock, Search } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, MarcaSimulado, PageHeader, SkeletonList, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';
import { ORGAOS, ReuniaoConteudo, SITUACAO_REUNIAO, etapaAviso } from '@/components/reunioes';

const CURTO = Object.fromEntries(ORGAOS.map((o) => [o.value, o.curto]));

/** Controle externo: a lista não identifica a criança. Para abrir, o motivo da consulta é obrigatório e fica na auditoria. */
export default function ReunioesControle() {
  const [orgao, setOrgao] = useState('');
  const [situacao, setSituacao] = useState('');
  const res = useRpc<any>('controle_reunioes', { orgao: orgao || null, situacao: situacao || null });
  const [item, setItem] = useState<any | null>(null);
  const c = res.data?.contagem;
  const itens = (res.data?.itens ?? []) as any[];
  return (
    <div>
      <PageHeader eyebrow="Controle externo" title="Registros de reunião"
        subtitle="Reuniões da escola com responsáveis, à disposição para verificação. A lista não identifica a criança; para abrir um registro, informe o motivo da consulta, que fica registrado." />
      <div className="mb-2 flex gap-2 overflow-x-auto pb-1">
        <Chip active={orgao === ''} onClick={() => setOrgao('')}>Todos os órgãos</Chip>
        {ORGAOS.map((o) => <Chip key={o.value} active={orgao === o.value} onClick={() => setOrgao(o.value)}>{o.label}</Chip>)}
      </div>
      <div className="mb-3 flex gap-2 overflow-x-auto pb-1">
        {[{ v: '', l: `Todas${c ? ` · ${fmtInt(c.total)}` : ''}` }, { v: 'PRAZO_VENCIDO', l: `Sem validação${c ? ` · ${fmtInt(c.prazo_vencido)}` : ''}` }, { v: 'AGUARDANDO', l: `Aguardando o responsável${c ? ` · ${fmtInt(c.aguardando)}` : ''}` },
          { v: 'RESPONDIDAS', l: `Respondidas${c ? ` · ${fmtInt(c.respondidas)}` : ''}` }, { v: 'SEM_ENVIO', l: `Sem envio, por proteção${c ? ` · ${fmtInt(c.sem_envio)}` : ''}` }].map((f) => (
          <Chip key={f.v} active={situacao === f.v} onClick={() => setSituacao(f.v)}>{f.l}</Chip>
        ))}
      </div>
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden">
          {!itens.length ? <EmptyState compact title="Nenhum registro" /> : (
            <Tabela colunas="104px 136px minmax(150px,1fr) minmax(200px,1.2fr) minmax(220px,1.2fr) minmax(170px,1fr)" largura={1040} rotulo="Registros de reunião">
              <TCabecalho><TCelula>Código</TCelula><TCelula>Reunião</TCelula><TCelula>Unidade</TCelula><TCelula>Assunto</TCelula><TCelula>Situação</TCelula><TCelula>Órgãos</TCelula></TCabecalho>
              {itens.map((r) => (
                <TLinha key={r.id} onClick={() => setItem(r)} alerta={r.situacao === 'PRAZO_VENCIDO'} rotulo={`${r.codigo}: ${r.tema_rotulo}`}>
                  <TCelula fixa><span className="font-mono text-[12.5px] font-semibold">{r.codigo}</span>{r.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>
                  <TCelula>{fmtDateTime(r.realizada_em)}</TCelula>
                  <TCelula titulo={r.unidade}>{r.unidade}</TCelula>
                  <TCelula titulo={r.tema_rotulo}>{r.tema_rotulo}</TCelula>
                  <TCelula livre>
                    <Badge tone={SITUACAO_REUNIAO[r.situacao]?.tone}>{SITUACAO_REUNIAO[r.situacao]?.label}</Badge>
                    {r.situacao === 'AGUARDANDO' && etapaAviso(r.ultimo_aviso) && <Badge tone={r.ultimo_aviso >= 2 ? 'red' : 'gray'} className="ml-1">{etapaAviso(r.ultimo_aviso)}</Badge>}
                  </TCelula>
                  <TCelula titulo={(r.envios as any[]).map((e) => `${CURTO[e.orgao]}: ${e.situacao === 'ENVIADO' ? 'enviado' : 'aguarda envio'}`).join(' · ')}>
                    {(r.envios as any[]).length
                      ? (r.envios as any[]).map((e) => `${CURTO[e.orgao]}${e.situacao === 'ENVIADO' ? ' ✓' : ''}`).join(', ')
                      : <span className="text-subtle">—</span>}
                  </TCelula>
                </TLinha>
              ))}
            </Tabela>
          )}
        </Card>
      )}
      <ConsultaSheet item={item} onClose={() => setItem(null)} />
    </div>
  );
}

function ConsultaSheet({ item, onClose }: { item: any | null; onClose: () => void }) {
  const toast = useToast();
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const [r, setR] = useState<any | null>(null);
  const fechar = () => { setMotivo(''); setR(null); onClose(); };
  const abrir = async () => {
    setBusy(true);
    try {
      setR(await rpc<any>('controle_reuniao', { id: item.id, motivo }));
    } catch (e) {
      toast({ title: 'Não foi possível abrir', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!item} onClose={fechar} title={item ? `Registro ${item.codigo}` : ''} subtitle={item ? `${item.tema_rotulo} · ${item.unidade}` : ''} size="lg"
      footer={!r ? <Button block size="lg" icon={Search} loading={busy} disabled={motivo.trim().length < 10} onClick={abrir}>Abrir o registro</Button> : undefined}>
      {!r ? (
        <div className="space-y-3 pt-1">
          <div className="flex items-start gap-2 rounded-2xl bg-slate-50 p-3 text-[13px] ring-1 ring-line">
            <Lock className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
            <span>O registro identifica a criança e a família. A consulta fica registrada na auditoria e na linha do tempo do registro, com o motivo informado.</span>
          </div>
          <Field label="Motivo da consulta" hint="Ex.: atendimento da Defensoria nº …, procedimento do MP nº …">
            <input autoFocus value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} className={inputCls} />
          </Field>
        </div>
      ) : <ReuniaoConteudo r={r} />}
    </Sheet>
  );
}
