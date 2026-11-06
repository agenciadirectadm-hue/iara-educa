import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router';
import { useRpc } from '@/lib/hooks';
import { fmtInt } from '@/lib/format';
import { Card, Chip, ErrorState, PageHeader, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { ReuniaoSheet, ReunioesTabela } from '@/components/reunioes';

/** Reuniões com responsáveis: da turma (professor), da unidade (direção e secretaria) ou da rede (Secretaria e Prefeito). */
export default function Reunioes() {
  const [sp, setSp] = useSearchParams();
  const situacao = sp.get('situacao') ?? '';
  const codigo = sp.get('codigo') ?? '';
  const res = useRpc<any>('reunioes_lista', { situacao: situacao || null });
  const [aberta, setAberta] = useState<string | null>(null);
  const [busca, setBusca] = useState('');
  const itens = (res.data?.itens ?? []) as any[];
  useEffect(() => {
    if (!codigo || !itens.length) return;
    const r = itens.find((x) => x.codigo === codigo);
    if (r) setAberta(r.id);
  }, [codigo, itens.length]); // eslint-disable-line react-hooks/exhaustive-deps
  const c = res.data?.contagem;
  const filtros: { value: string; label: string; n?: number }[] = [
    { value: '', label: 'Todas', n: c?.total },
    { value: 'ENVIO_PENDENTE', label: 'Envio pendente', n: c?.envios_pendentes },
    { value: 'PRAZO_VENCIDO', label: 'Sem validação', n: c?.prazo_vencido },
    { value: 'AGUARDANDO', label: 'Aguardando o responsável', n: c?.aguardando },
    { value: 'RESPONDIDAS', label: 'Respondidas', n: c?.respondidas },
    { value: 'SEM_ENVIO', label: 'Sem envio, por proteção', n: c?.sem_envio },
  ];
  const q = busca.trim().toLowerCase();
  const visiveis = q ? itens.filter((r) => `${r.aluno} ${r.unidade} ${r.tema_rotulo} ${r.codigo}`.toLowerCase().includes(q)) : itens;
  return (
    <div>
      <PageHeader eyebrow="Vida escolar" title={<span className="inline-flex items-center gap-2">Reuniões com responsáveis<Simulado detail="Registros fictícios, para a apresentação." /></span>}
        subtitle={`Assuntos que podem ser pauta do Conselho Tutelar, da Defensoria Pública e do Ministério Público.${res.data?.pode_registrar ? ' Para registrar uma reunião, abra a ficha do aluno, aba Reuniões.' : ''}`} />
      <div className="mb-3 flex gap-2 overflow-x-auto pb-1">
        {filtros.map((f) => (
          <Chip key={f.value} active={situacao === f.value} onClick={() => setSp(f.value ? { situacao: f.value } : {}, { replace: true })}>
            {f.label}{situacao === '' && f.n != null ? ` · ${fmtInt(f.n)}` : ''}
          </Chip>
        ))}
      </div>
      <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar aluno, unidade, assunto ou código" aria-label="Buscar" className={`${inputCls} mb-3 max-w-md`} />
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden"><ReunioesTabela itens={visiveis} onAbrir={setAberta} /></Card>
      )}
      <ReuniaoSheet id={aberta} onClose={() => { setAberta(null); if (codigo) { const n = new URLSearchParams(sp); n.delete('codigo'); setSp(n, { replace: true }); } }} />
    </div>
  );
}
