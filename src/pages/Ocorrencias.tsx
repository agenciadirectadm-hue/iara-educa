import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { BellRing, CheckCheck, GitBranch, Hourglass, MessageCircleWarning, ShieldAlert } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt } from '@/lib/format';
import { TIPO_OCORRENCIA, VIOLENCIA } from '@/lib/escola';
import { Card, Chip, ErrorState, Kpi, PageHeader, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { OcorrenciaSheet, OcorrenciasTabela } from '@/components/vida-escolar';
import { ModelosResposta, OcorrenciasIndicadores } from '@/components/ocorrencias-gestao';
import { UnitSelect } from '@/components/escola';

const SITUACOES = [{ value: 'PENDENTES', label: 'Em aberto' }, { value: 'ABERTA', label: 'Abertas' }, { value: 'EM_ACOMPANHAMENTO', label: 'Em acompanhamento' },
  { value: 'ENCERRADA', label: 'Encerradas' }, { value: 'TODAS', label: 'Todas' }];
type Aba = 'registros' | 'indicadores' | 'modelos';
const sel = 'h-10 rounded-2xl bg-white px-3 text-[14px] ring-1 ring-line';

/** Ocorrências da unidade (1ª instância) ou da rede (2ª instância e acompanhamento pela Secretaria). */
export default function Ocorrencias() {
  const { me } = useSession();
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'registros') as Aba;
  const sit = sp.get('s') ?? 'PENDENTES';
  const origem = sp.get('origem') ?? '';
  const tipo = sp.get('tipo') ?? '';
  const instancia = sp.get('instancia') ?? '';
  const violencia = sp.get('violencia') ?? '';
  const vencidas = sp.get('vencidas') === '1';
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const [busca, setBusca] = useState('');
  const db = useDebounced(busca, 300);
  const [aberta, setAberta] = useState<string | null>(null);
  const res = useRpc<any>('ocorrencias_lista', { unit_id: unit, situacao: sit === 'TODAS' ? null : sit, origem: origem || null, tipo: tipo || null,
    instancia: instancia || null, violencia: violencia || null, vencidas, busca: db });
  const c = res.data?.contagem;
  const set = (k: string, v: string) => {
    const p = new URLSearchParams(sp);
    if (v) p.set(k, v); else p.delete(k);
    setSp(p, { replace: true });
  };
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Ocorrências<Simulado detail="Ocorrências fictícias." /></span>}
        subtitle="Professores e famílias registram. A unidade trata em 1ª instância e a Secretaria em 2ª instância; a família vê o registro, as mensagens e a solução — nunca as tratativas internas."
        actions={rede ? <UnitSelect value={unit} onChange={setUnit} /> : undefined} />
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-6">
        <Kpi compact icon={ShieldAlert} tone="red" label="Abertas" value={fmtInt(c?.ABERTA)} onClick={() => set('s', 'ABERTA')} />
        <Kpi compact icon={BellRing} tone="amber" label="Em acompanhamento" value={fmtInt(c?.EM_ACOMPANHAMENTO)} onClick={() => set('s', 'EM_ACOMPANHAMENTO')} />
        <Kpi compact icon={MessageCircleWarning} tone="purple" label="Relatadas pela família (em aberto)" value={fmtInt(c?.FAMILIA)} onClick={() => set('origem', 'FAMILIA')} />
        <Kpi compact icon={GitBranch} tone="purple" label="Na Secretaria (2ª instância)" value={fmtInt(c?.SECRETARIA)} onClick={() => set('instancia', 'SECRETARIA')} />
        <Kpi compact icon={Hourglass} tone="red" label="Prazo de resposta vencido" value={fmtInt(c?.vencidas)} onClick={() => set('vencidas', '1')} />
        <Kpi compact icon={CheckCheck} tone="blue" label="Sem ciência da família" value={fmtInt(c?.sem_ciencia)} />
      </div>
      <Tabs className="mt-4" value={aba} onChange={(v) => set('aba', v === 'registros' ? '' : v)} items={[
        { value: 'registros', label: 'Registros' }, { value: 'indicadores', label: 'Indicadores' }, { value: 'modelos', label: 'Modelos de resposta' },
      ]} />
      {aba === 'indicadores' ? <div className="mt-3"><OcorrenciasIndicadores unitId={unit} /></div>
        : aba === 'modelos' ? <div className="mt-3"><ModelosResposta /></div> : (
        <>
          <Card className="mt-3 space-y-2 p-3">
            <div className="flex flex-wrap gap-2">
              {SITUACOES.map((s) => <Chip key={s.value} active={sit === s.value} onClick={() => set('s', s.value === 'PENDENTES' ? '' : s.value)}>{s.label}</Chip>)}
              <Chip active={vencidas} onClick={() => set('vencidas', vencidas ? '' : '1')}>Prazo vencido</Chip>
            </div>
            <div className="flex flex-wrap gap-2">
              <select value={origem} onChange={(e) => set('origem', e.target.value)} className={sel} aria-label="Quem registrou">
                <option value="">Escola e família</option><option value="ESCOLA">Registradas pela escola</option><option value="FAMILIA">Relatadas pela família</option>
              </select>
              <select value={instancia} onChange={(e) => set('instancia', e.target.value)} className={sel} aria-label="Instância">
                <option value="">1ª e 2ª instância</option><option value="UNIDADE">Na unidade (1ª instância)</option><option value="SECRETARIA">Na Secretaria (2ª instância)</option>
              </select>
              <select value={tipo} onChange={(e) => set('tipo', e.target.value)} className={sel} aria-label="Assunto">
                <option value="">Todos os assuntos</option>
                {Object.entries(TIPO_OCORRENCIA).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
              </select>
              <select value={violencia} onChange={(e) => set('violencia', e.target.value)} className={sel} aria-label="Violência">
                <option value="">Com ou sem violência</option><option value="QUALQUER">Qualquer violência</option>
                {Object.entries(VIOLENCIA).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
              </select>
              <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome do aluno (parte do nome)…" className={`${inputCls} h-10 max-w-xs`} aria-label="Buscar aluno" />
            </div>
          </Card>
          <div className="mt-3">
            {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
              <Card className="overflow-hidden"><OcorrenciasTabela itens={res.data.itens} onAbrir={setAberta} /></Card>
            )}
          </div>
        </>
      )}
      <OcorrenciaSheet id={aberta} onClose={() => setAberta(null)} />
    </div>
  );
}
