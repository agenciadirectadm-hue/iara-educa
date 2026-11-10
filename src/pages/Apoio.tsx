// Apoio pedagógico interdisciplinar — fila por área (gerência), meus casos (profissional), casos da unidade (escola e AEE).
import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { Clock, HeartHandshake, Inbox, Phone, Search, Send, UserCheck, Users } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt } from '@/lib/format';
import { Badge, Button, Card, EmptyState, ErrorState, Kpi, PageHeader, Section, Segmented, SkeletonList, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { EncaminharSheet, SituacaoApoio } from '@/components/apoio';

export default function Apoio() {
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const area = sp.get('area') ?? '';
  const sit = sp.get('situacao') ?? 'ABERTOS';
  const [busca, setBusca] = useState('');
  const termo = useDebounced(busca, 300);
  const profissional = can('apoio.atender') && !can('apoio.gerir');
  const [meus, setMeus] = useState(profissional);
  const res = useRpc<any>('apoio_lista', { area, situacao: sit === 'TODOS' ? '' : sit, busca: termo, meus });
  const areasRes = useRpc<any>('apoio_areas', {}, { staleTime: 60 * 60_000 });
  const [enc, setEnc] = useState(false);
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); if (v) n.set(k, v); else n.delete(k); setSp(n, { replace: true }); };
  const d = res.data;
  return (
    <div>
      <PageHeader eyebrow="AEE · Educação especial" title="Apoio interdisciplinar"
        subtitle="Orientação educacional, acompanhamento pedagógico, educação especial, psicologia, fonoaudiologia, deficiência visual e altas habilidades. O registro técnico é sigiloso: só o profissional e a chefia veem."
        actions={d?.pode_encaminhar && <Button icon={Send} onClick={() => setEnc(true)}>Encaminhar aluno</Button>} />
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <div className="space-y-5">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
            {profissional ? (
              <Kpi compact icon={UserCheck} tone="purple" label={d.eu ? `Meus casos · ${d.eu.split(' ')[0]}` : 'Meus casos'} value={fmtInt(d.meus_abertos)} sub="em triagem ou atendimento" />
            ) : (
              <Kpi compact icon={Inbox} tone="amber" label="Pedidos das famílias" value={fmtInt(d.pedidos_familia)} sub="a escola analisa" />
            )}
            <Kpi compact icon={Users} tone="blue" label="Encaminhados sem profissional" value={fmtInt(d.contagem.ENCAMINHADO ?? 0)} />
            <Kpi compact icon={Clock} tone="red" label="Esperando há mais de 30 dias" value={fmtInt(d.atrasados)} />
            <Kpi compact icon={HeartHandshake} tone="purple" label="Em atendimento" value={fmtInt((d.contagem.EM_TRIAGEM ?? 0) + (d.contagem.EM_ATENDIMENTO ?? 0) + (d.contagem.AGUARDANDO_REDE ?? 0))} />
            <Kpi compact icon={UserCheck} tone="green" label="Concluídos" value={fmtInt(d.contagem.CONCLUIDO ?? 0)} />
          </div>
          {!profissional && (
            <Section title="Por área" subtitle="Casos abertos, quem espera profissional e há quantos dias.">
              <Card className="overflow-hidden">
                <Tabela colunas="minmax(240px,1.6fr) 100px 140px 130px 130px 140px" largura={900} rotulo="Por área">
                  <TCabecalho><TCelula fixa>Área</TCelula><TCelula>Abertos</TCelula><TCelula>Sem profissional</TCelula><TCelula>Espera média</TCelula><TCelula>Maior espera</TCelula><TCelula>Concluídos (90 d)</TCelula></TCabecalho>
                  {(d.por_area as any[]).map((a) => (
                    <TLinha key={a.area} onClick={() => set('area', area === a.area ? '' : a.area)} ativo={area === a.area} alerta={(a.espera_maxima ?? 0) > 30}>
                      <TCelula fixa>{a.nome}</TCelula><TCelula>{fmtInt(a.abertos)}</TCelula><TCelula>{fmtInt(a.sem_profissional)}</TCelula>
                      <TCelula>{a.espera_media == null ? '—' : `${a.espera_media} dias`}</TCelula><TCelula>{a.espera_maxima == null ? '—' : `${a.espera_maxima} dias`}</TCelula><TCelula>{fmtInt(a.concluidos_90)}</TCelula>
                    </TLinha>
                  ))}
                </Tabela>
              </Card>
            </Section>
          )}
          <div className="flex flex-wrap items-center gap-2">
            <Segmented value={sit} onChange={(v) => set('situacao', v)} items={[
              { value: 'ABERTOS', label: 'Em aberto' }, { value: 'PEDIDO_FAMILIA', label: 'Pedidos da família' }, { value: 'ENCAMINHADO', label: 'Sem profissional' },
              { value: 'CONCLUIDO', label: 'Concluídos' }, { value: 'TODOS', label: 'Todos' }]} />
            {profissional && <Segmented value={meus ? 'meus' : 'area'} onChange={(v) => setMeus(v === 'meus')} items={[{ value: 'meus', label: 'Meus casos' }, { value: 'area', label: 'Fila da minha área' }]} />}
            <select className={inputCls + ' w-auto'} value={area} onChange={(e) => set('area', e.target.value)} aria-label="Área">
              <option value="">Todas as áreas</option>{((areasRes.data?.areas ?? []) as any[]).filter((a) => a.codigo !== 'FORMACAO').map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
            </select>
            <div className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" /><input className={inputCls + ' w-56 pl-9'} value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Aluno ou protocolo" /></div>
          </div>
          <Card className="overflow-hidden">
            {(d.itens as any[]).length ? (
              <Tabela colunas="110px minmax(200px,1.4fr) minmax(150px,1fr) minmax(170px,1fr) 160px minmax(160px,1fr) 100px 90px" largura={1240} rotulo="Casos">
                <TCabecalho><TCelula fixa>Protocolo</TCelula><TCelula>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Área</TCelula><TCelula>Situação</TCelula><TCelula>Profissional</TCelula><TCelula>Desde</TCelula><TCelula>Espera</TCelula></TCabecalho>
                {(d.itens as any[]).map((c) => (
                  <TLinha key={c.id} to={`/apoio/${c.id}`} rotulo={`${c.numero} ${c.aluno}`} alerta={(c.dias_espera ?? 0) > 30}>
                    <TCelula fixa>{c.numero}</TCelula>
                    <TCelula titulo={c.aluno}><span className="inline-flex items-center gap-1.5">{c.prioridade === 'ALTA' && <Badge tone="red">alta</Badge>}{c.aluno}</span></TCelula>
                    <TCelula>{c.unidade}</TCelula><TCelula>{c.area_nome}</TCelula><TCelula livre><SituacaoApoio s={c.situacao} /></TCelula>
                    <TCelula>{c.profissional ?? '—'}</TCelula><TCelula>{fmtDate(c.created_at)}</TCelula><TCelula>{c.dias_espera == null ? '—' : `${c.dias_espera} d`}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : <EmptyState compact title="Nenhum caso neste filtro" />}
          </Card>
          <p className="flex items-center gap-1.5 text-[12.5px] text-muted"><Phone className="size-3.5" />Gerência: {d.contato.telefone} · {d.contato.email} (portal da Prefeitura, Educação → Apoio Pedagógico Interdisciplinar).</p>
        </div>
      )}
      <EncaminharSheet open={enc} onClose={() => setEnc(false)} areas={((areasRes.data?.areas ?? []) as any[]).filter((a) => a.codigo !== 'FORMACAO')} onFeito={() => res.refetch()} />
    </div>
  );
}
