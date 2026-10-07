import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { BookOpen, Clock, GraduationCap, Pencil, School } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { FUNCAO_SERVIDOR } from '@/lib/escola';
import { Badge, Button, Card, DataPair, EmptyState, ErrorState, PageHeader, Section, Simulado, SkeletonList } from '@/components/ui';
import { Foto, TrocarFoto } from '@/components/arquivos';
import { ExcluirCadastro } from '@/components/documentos';
import { ServidorForm } from '@/components/servidor-form';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { GradeHorario } from '@/components/escola';
import { CargaBarra } from './Pessoal';

/** Ficha funcional: dados do vínculo, carga horária, turmas, horário semanal, formação e lotações. */
export default function Servidor() {
  const { id } = useParams();
  const res = useRpc<any>('pessoal_ficha', { id });
  const [editar, setEditar] = useState(false);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const s = res.data;
  return (
    <div>
      <PageHeader eyebrow={s.unidade?.name} title={<span className="inline-flex items-center gap-2">{s.nome}{s.is_demo && <Simulado detail="Servidor fictício: nome, matrícula, jornada e formação são de demonstração." />}</span>}
        subtitle={`${s.cargo ?? FUNCAO_SERVIDOR[s.funcao] ?? s.funcao} · ${s.vinculo ?? ''}${s.area ? ' · ' + s.area : ''}`}
        actions={s.pode_editar ? <>
          <Button variant="secondary" icon={Pencil} onClick={() => setEditar(true)}>Alterar cadastro</Button>
          <ExcluirCadastro fn="pessoal_excluir" id={s.id} nome={s.nome} voltarPara="/pessoal" rotulo="Desligar ou excluir" />
        </> : undefined} />
      <ServidorForm open={editar} onClose={() => setEditar(false)} servidor={s} />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1.4fr]">
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="flex shrink-0 flex-col items-center gap-1">
              <Foto arquivoId={s.foto_arquivo_id} name={s.nome} seed={s.id} size={64} />
              {(s.pode_editar || s.proprio) && <TrocarFoto finalidade="FOTO_SERVIDOR" alvo={s.id} rotulo="Foto" variant="ghost" />}
            </div>
            <div className="min-w-0">
              <div className="font-display text-lg font-extrabold">{s.nome}</div>
              <div className="flex flex-wrap gap-1.5">
                <Badge tone={s.situacao === 'ATIVO' ? 'green' : s.situacao === 'DESLIGADO' ? 'gray' : 'amber'}>{s.situacao === 'ATIVO' ? 'Em exercício' : s.situacao === 'LICENCA' ? 'Licença' : s.situacao === 'DESLIGADO' ? 'Desligado' : 'Afastado'}</Badge>
                <Badge tone="blue">{FUNCAO_SERVIDOR[s.funcao] ?? s.funcao}</Badge>
              </div>
            </div>
          </div>
          <div className="mt-4 grid grid-cols-2 gap-3">
            <DataPair label="Matrícula funcional" value={s.matricula ?? '—'} />
            <DataPair label="Admissão" value={fmtDate(s.admissao)} />
            <DataPair label="Jornada semanal" value={s.ch ? `${s.ch} horas` : '—'} />
            <DataPair label="Escolaridade" value={s.escolaridade ?? '—'} />
            <DataPair label="Formação" value={s.formacao ?? '—'} className="col-span-2" />
          </div>
          <div className="mt-4 rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
            <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Carga em sala (2/3 da jornada · Lei 11.738/2008)</div>
            <div className="mt-1.5"><CargaBarra atribuidas={s.carga?.atribuidas ?? 0} capacidade={s.carga?.capacidade ?? null} /></div>
            <p className="mt-1 text-[12.5px] text-muted">
              {s.carga?.capacidade ? (s.carga.disponivel < 0 ? `${-s.carga.disponivel} aula(s) acima da capacidade.` : `${s.carga.disponivel} aula(s) livres para atribuir.`) : 'Sem regência de turma.'}
            </p>
          </div>
        </Card>

        <Section title={`Turmas (${fmtInt(s.turmas.length)})`} className="mt-0">
          <Card className="overflow-hidden">
            {s.turmas.length ? (
              <Tabela colunas="minmax(140px,1fr) 110px 90px 110px 80px" largura={540} rotulo="Turmas do servidor">
                <TCabecalho><TCelula>Turma</TCelula><TCelula>Série</TCelula><TCelula>Turno</TCelula><TCelula>Papel</TCelula><TCelula>Aulas</TCelula></TCabecalho>
                {(s.turmas as any[]).map((t) => (
                  <TLinha key={t.id + t.papel} to={`/turmas/${t.id}`}>
                    <TCelula fixa><span className="font-semibold">{t.nome}</span></TCelula><TCelula>{t.serie}</TCelula><TCelula>{SHIFT[t.turno] ?? t.turno}</TCelula>
                    <TCelula>{t.papel === 'REGENTE' ? 'Regente' : t.papel === 'ESPECIALISTA' ? 'Especialista' : t.papel === 'AUXILIAR' ? 'Auxiliar' : t.papel}</TCelula>
                    <TCelula>{t.aulas ?? '—'}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : <EmptyState compact title="Sem turma atribuída" />}
          </Card>
          {s.mediacoes?.length > 0 && (
            <Card className="mt-3 p-3 text-[13.5px]">
              <b>Mediação escolar:</b> {(s.mediacoes as any[]).map((m) => `${m.aluno} (${m.turma})`).join(', ')}
            </Card>
          )}
        </Section>
      </div>

      <Section title="Horário semanal" subtitle="As aulas de cada turma, de segunda a sexta">
        <Card className="p-3">
          <GradeHorario aulas={s.horario} rotulo="Horário do servidor" celula={(a) => ({ titulo: a.turma, sub: a.componente })} />
        </Card>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Formação continuada">
          <Card className="divide-y divide-line overflow-hidden">
            {(s.formacoes as any[]).length ? (s.formacoes as any[]).map((f, i) => (
              <div key={i} className="flex items-center gap-3 px-4 py-2.5">
                <GraduationCap className="size-4 shrink-0 text-purple-700" />
                <span className="min-w-0 flex-1 truncate text-[13.5px] font-semibold" title={`${f.titulo} · ${f.instituicao ?? ''}`}>{f.titulo}</span>
                <span className="shrink-0 text-[12px] text-muted">{f.carga_horaria ? `${f.carga_horaria} h · ` : ''}{fmtDate(f.concluido_em)}</span>
              </div>
            )) : <p className="p-4 text-sm text-muted">Nenhum curso registrado.</p>}
          </Card>
        </Section>
        <Section title="Lotações">
          <Card className="divide-y divide-line overflow-hidden">
            {(s.lotacoes as any[]).length ? (s.lotacoes as any[]).map((l, i) => (
              <div key={i} className="flex items-center gap-3 px-4 py-2.5">
                {l.fim ? <Clock className="size-4 shrink-0 text-slate-500" /> : <School className="size-4 shrink-0 text-green-700" />}
                <span className="min-w-0 flex-1 truncate text-[13.5px] font-semibold" title={l.motivo ?? ''}>{l.unidade}</span>
                <span className="shrink-0 text-[12px] text-muted">{fmtDate(l.inicio)} — {l.fim ? fmtDate(l.fim) : 'atual'}</span>
              </div>
            )) : <p className="p-4 text-sm text-muted">Sem histórico de lotação.</p>}
          </Card>
        </Section>
      </div>
      <p className="mt-6 text-center text-[12px] text-muted"><BookOpen className="mr-1 inline size-3.5" />Dados funcionais visíveis ao próprio servidor e à gestão com permissão de pessoal. <Link to="/pessoal" className="font-semibold text-blue-700">Voltar ao pessoal</Link></p>
    </div>
  );
}
