import { useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import { CalendarCheck, ClipboardPlus, MessageSquare } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { SHIFT } from '@/lib/labels';
import { Button, Card, ErrorState, PageHeader, Simulado, SkeletonList, Tabs } from '@/components/ui';
import { AgendaLista, NovaOcorrenciaSheet, NovoRecadoSheet, OcorrenciaSheet, OcorrenciasTabela } from '@/components/vida-escolar';

/** Diário da turma: a agenda (recados, tarefas, bilhetes e o que as famílias escreveram) e as ocorrências dos alunos. */
export default function Diario() {
  const { id } = useParams();
  const [sp, setSp] = useSearchParams();
  const aba = sp.get('aba') ?? 'agenda';
  const ag = useRpc<any>('agenda_turma', { class_id: id });
  const oc = useRpc<any>('ocorrencias_lista', { class_id: id }, { enabled: aba === 'ocorrencias', retry: false });
  const [novoRecado, setNovoRecado] = useState(false);
  const [novaOc, setNovaOc] = useState(false);
  const [aberta, setAberta] = useState<string | null>(null);
  if (ag.isLoading) return <SkeletonList rows={5} />;
  if (ag.error) return <ErrorState error={ag.error} onRetry={() => ag.refetch()} />;
  const d = ag.data;
  const familia = (d.itens as any[]).filter((a) => a.origem === 'FAMILIA' && a.data >= new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10)).length;
  return (
    <div>
      <PageHeader eyebrow={<span className="inline-flex items-center gap-1">{d.turma.unidade}<Simulado detail="Recados, bilhetes e ocorrências fictícios." /></span>}
        title={`Diário · ${d.turma.nome}`} subtitle={`Turno ${SHIFT[d.turma.turno]?.toLowerCase() ?? ''} · agenda escolar e ocorrências`}
        actions={<>
          <Link to={`/turmas/${id}/chamada`} className="inline-flex h-11 items-center gap-1.5 rounded-2xl bg-white px-4 text-[15px] font-semibold ring-1 ring-line hover:bg-blue-50"><CalendarCheck className="size-4" />Chamada</Link>
          {aba === 'agenda' && d.pode_publicar && <Button icon={MessageSquare} onClick={() => setNovoRecado(true)}>Escrever na agenda</Button>}
          {aba === 'ocorrencias' && d.pode_ocorrencia && <Button icon={ClipboardPlus} onClick={() => setNovaOc(true)}>Nova ocorrência</Button>}
        </>} />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })}
        items={[{ value: 'agenda', label: 'Agenda', count: familia || null }, { value: 'ocorrencias', label: 'Ocorrências', count: oc.data ? (oc.data.contagem.ABERTA + oc.data.contagem.EM_ACOMPANHAMENTO) || null : null }]} />
      <div className="mt-3">
        {aba === 'agenda' && <Card className="overflow-hidden"><AgendaLista itens={d.itens} /></Card>}
        {aba === 'ocorrencias' && (oc.isLoading ? <SkeletonList rows={4} /> : oc.error ? <ErrorState error={oc.error} /> : (
          <Card className="overflow-hidden"><OcorrenciasTabela itens={oc.data.itens} onAbrir={setAberta} /></Card>
        ))}
      </div>
      <NovoRecadoSheet open={novoRecado} onClose={() => setNovoRecado(false)} classId={d.turma.id} alunos={d.alunos} />
      <NovaOcorrenciaSheet open={novaOc} onClose={() => setNovaOc(false)} alunos={d.alunos} />
      <OcorrenciaSheet id={aberta} onClose={() => setAberta(null)} />
    </div>
  );
}
