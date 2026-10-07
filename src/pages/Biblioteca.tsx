import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { AlarmClock, BookMarked, BookOpen, BookPlus, BookUp, Library, RotateCcw, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt } from '@/lib/format';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, PageHeader, Section, Segmented, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { BuscarPessoaSheet } from '@/components/Vinculos';
import { BarList } from '@/components/charts';

export const GENERO_LIVRO: Record<string, string> = {
  LITERATURA_INFANTIL: 'Literatura infantil', INFANTOJUVENIL: 'Infantojuvenil', POESIA: 'Poesia', CONTOS_FABULAS: 'Contos e fábulas', HISTORIA_EM_QUADRINHOS: 'Quadrinhos',
  INFORMATIVO: 'Informativo', DIDATICO: 'Didático', REFERENCIA: 'Referência', OUTRO: 'Outro',
};
type Aba = 'emprestimos' | 'acervo' | 'leitura';

function useRecarregar() {
  const qc = useQueryClient();
  return () => ['biblioteca_painel', 'biblioteca_acervo', 'biblioteca_titulo', 'familia_biblioteca'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Biblioteca escolar: empréstimos em aberto e atrasados, acervo com disponibilidade, reservas e leitura por turma. */
export default function Biblioteca() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? (rede ? 'leitura' : 'emprestimos')) as Aba;
  const [unit, setUnit] = useState<number | null>(null);
  const [emprestar, setEmprestar] = useState(false);
  const res = useRpc<any>('biblioteca_painel', { unit_id: unit });
  const d = res.data;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Biblioteca escolar<Simulado detail="Acervo, empréstimos e reservas de demonstração." /></span>}
        subtitle="Empréstimo e devolução pelo tombo, renovação, reservas e a sacola literária da educação infantil. A família acompanha pelo portal e pela IARA."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{d?.pode_emprestar && <Button icon={BookUp} onClick={() => setEmprestar(true)}>Emprestar</Button>}</>} />
      {res.isLoading ? <SkeletonList rows={3} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
            <Kpi compact icon={Library} tone="blue" label="Exemplares no acervo" value={fmtInt(d.acervo.exemplares)} sub={`${fmtInt(d.acervo.titulos)} títulos`} onClick={() => setSp({ aba: 'acervo' }, { replace: true })} />
            <Kpi compact icon={BookOpen} tone="purple" label="Emprestados agora" value={fmtInt(d.emprestados)} onClick={() => setSp({ aba: 'emprestimos' }, { replace: true })} />
            <Kpi compact icon={AlarmClock} tone="red" label="Atrasados" value={fmtInt(d.atrasados)} />
            <Kpi compact icon={Users} tone="green" label="Leitores nos últimos 30 dias" value={fmtInt(d.leitores_mes)} sub={`${fmtInt(d.leituras_ano)} leituras no ano`} />
            <Kpi compact icon={BookMarked} tone="amber" label="Reservas na fila" value={fmtInt(d.reservas)} />
          </div>
          <p className="mt-2 text-[12px] text-muted">{d.regras}</p>
          <Tabs className="mt-3" value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })}
            items={[...(d.unit_id ? [{ value: 'emprestimos' as Aba, label: 'Empréstimos em aberto' }] : []), { value: 'acervo', label: 'Acervo' }, { value: 'leitura', label: d.unit_id ? 'Leitura por turma' : 'Leitura na rede' }]} />
          <div className="mt-3">
            {aba === 'emprestimos' && d.unit_id && <Emprestimos d={d} />}
            {aba === 'acervo' && <Acervo unitId={d.unit_id} podeAcervo={d.pode_acervo} podeEmprestar={d.pode_emprestar} />}
            {aba === 'leitura' && <Leitura d={d} />}
          </div>
        </>
      )}
      <EmprestarSheet open={emprestar} onClose={() => setEmprestar(false)} />
    </div>
  );
}

function Emprestimos({ d }: { d: any }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [filtro, setFiltro] = useState<'todos' | 'atrasados'>('todos');
  const [busy, setBusy] = useState<string | null>(null);
  const acao = async (fn: string, args: object, msg: string, id: string) => {
    setBusy(id);
    try {
      const r = await rpc<any>(fn, args);
      toast({ title: msg, description: r?.reserva_avisada ? 'Havia reserva: a família foi avisada que o livro chegou.' : undefined, tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };
  const itens = ((d.ativos ?? []) as any[]).filter((x) => filtro === 'todos' || x.atrasado);
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <Chip active={filtro === 'todos'} onClick={() => setFiltro('todos')}>Todos ({(d.ativos ?? []).length})</Chip>
        <Chip active={filtro === 'atrasados'} onClick={() => setFiltro('atrasados')}>Atrasados ({fmtInt(d.atrasados)})</Chip>
      </div>
      <Card className="overflow-hidden">
        {!itens.length ? <EmptyState compact title="Nenhum empréstimo nesta lista" /> : (
          <Tabela colunas="110px minmax(200px,1.6fr) minmax(180px,1.2fr) 120px 110px 230px" largura={1000} rotulo="Empréstimos em aberto">
            <TCabecalho><TCelula fixa>Tombo</TCelula><TCelula>Livro</TCelula><TCelula>Leitor</TCelula><TCelula>Devolver até</TCelula><TCelula>Renovações</TCelula><TCelula>Ações</TCelula></TCabecalho>
            {itens.map((x) => (
              <TLinha key={x.id} alerta={x.atrasado} rotulo={x.titulo}>
                <TCelula fixa className="font-mono text-[12.5px]">{x.tombo}{x.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>
                <TCelula titulo={`${x.titulo} — ${x.autor}`}><span className="font-semibold">{x.titulo}</span> <span className="text-[12px] text-muted">{x.autor}</span></TCelula>
                <TCelula titulo={x.leitor}>{x.leitor}</TCelula>
                <TCelula className={x.atrasado ? 'font-semibold text-red-700' : ''}>{fmtDate(x.prevista)}{x.atrasado ? ` (${x.dias_atraso} d)` : ''}</TCelula>
                <TCelula>{x.renovacoes}</TCelula>
                <TCelula livre>
                  <span className="inline-flex gap-1">
                    <Button size="sm" loading={busy === x.id} onClick={() => acao('biblioteca_devolver', { emprestimo_id: x.id, estado: 'BOM' }, 'Devolução registrada', x.id)}>Devolver</Button>
                    {x.pode_renovar && <Button size="sm" variant="secondary" icon={RotateCcw} loading={busy === x.id} onClick={() => acao('biblioteca_renovar', { id: x.id }, 'Renovado', x.id)}>Renovar</Button>}
                  </span>
                </TCelula>
              </TLinha>
            ))}
          </Tabela>
        )}
      </Card>
      {(d.reservas_lista ?? []).length > 0 && (
        <Section title="Reservas" subtitle="Quem está na frente da fila leva o próximo exemplar devolvido.">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(200px,1.5fr) minmax(180px,1.2fr) 130px 120px" largura={680} rotulo="Reservas">
              <TCabecalho><TCelula fixa>Livro</TCelula><TCelula>Aluno</TCelula><TCelula>Situação</TCelula><TCelula>Desde</TCelula></TCabecalho>
              {(d.reservas_lista as any[]).map((r) => (
                <TLinha key={r.id} rotulo={r.titulo}>
                  <TCelula fixa>{r.titulo}</TCelula><TCelula>{r.aluno}</TCelula>
                  <TCelula livre><Badge tone={r.situacao === 'DISPONIVEL' ? 'green' : 'amber'}>{r.situacao === 'DISPONIVEL' ? 'livro separado' : 'na fila'}</Badge></TCelula><TCelula>{fmtDate(r.criada_em)}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      )}
    </div>
  );
}

function Acervo({ unitId, podeAcervo, podeEmprestar }: { unitId: number | null; podeAcervo: boolean; podeEmprestar: boolean }) {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const [genero, setGenero] = useState('');
  const [disp, setDisp] = useState(false);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  const res = useRpc<any[]>('biblioteca_acervo', { unit_id: unitId, q: dq || null, genero: genero || null, disponivel: disp });
  return (
    <div className="space-y-3">
      <Card className="flex flex-wrap items-center gap-2 p-3">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Título, autor ou ISBN…" className={`${inputCls} h-10 max-w-xs`} aria-label="Buscar no acervo" />
        <select value={genero} onChange={(e) => setGenero(e.target.value)} className="h-10 rounded-2xl bg-white px-3 text-[14px] ring-1 ring-line" aria-label="Gênero">
          <option value="">Todos os gêneros</option>{Object.entries(GENERO_LIVRO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <Chip active={disp} onClick={() => setDisp(!disp)}>Só disponíveis</Chip>
        {podeAcervo && <Button icon={BookPlus} onClick={() => setNovo(true)}>Novo título</Button>}
      </Card>
      <Card className="overflow-hidden">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : !res.data?.length ? <EmptyState compact title="Nada encontrado" /> : (
          <Tabela colunas="minmax(220px,1.8fr) minmax(160px,1fr) 150px 100px 110px 90px" largura={900} rotulo="Acervo">
            <TCabecalho><TCelula fixa>Título</TCelula><TCelula>Autor</TCelula><TCelula>Gênero</TCelula><TCelula>Exemplares</TCelula><TCelula>Disponíveis</TCelula><TCelula>Reservas</TCelula></TCabecalho>
            {res.data.map((t) => (
              <TLinha key={t.id} onClick={() => setAberto(t.id)} rotulo={t.titulo}>
                <TCelula fixa><span className="font-semibold">{t.titulo}</span>{t.pnld && <Badge tone="blue" className="ml-1">PNLD</Badge>}</TCelula>
                <TCelula>{t.autor}</TCelula><TCelula>{GENERO_LIVRO[t.genero]}</TCelula><TCelula>{fmtInt(t.exemplares)}</TCelula>
                <TCelula>{t.disponiveis ? <Badge tone="green">{t.disponiveis}</Badge> : <Badge tone="gray">0</Badge>}</TCelula><TCelula>{t.reservas || '—'}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        )}
      </Card>
      <TituloSheet id={aberto} unitId={unitId} podeAcervo={podeAcervo} podeEmprestar={podeEmprestar} onClose={() => setAberto(null)} />
      <NovoTituloSheet open={novo} onClose={() => setNovo(false)} />
    </div>
  );
}

function TituloSheet({ id, unitId, podeAcervo, podeEmprestar, onClose }: { id: string | null; unitId: number | null; podeAcervo: boolean; podeEmprestar: boolean; onClose: () => void }) {
  const res = useRpc<any>('biblioteca_titulo', { id, unit_id: unitId }, { enabled: !!id });
  const toast = useToast();
  const recarregar = useRecarregar();
  const [aluno, setAluno] = useState<string | null>(null);
  const [mais, setMais] = useState(1);
  const t = res.data;
  const fazer = async (fn: string, args: object, msg: string) => {
    try {
      await rpc(fn, args);
      toast({ title: msg, tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  return (
    <Sheet open={!!id} onClose={onClose} size="lg" title={t?.titulo ?? 'Título'} subtitle={t ? `${t.autor}${t.editora ? ` · ${t.editora}` : ''} · ${GENERO_LIVRO[t.genero]} · ${fmtInt(t.leituras)} leitura(s)` : ''}>
      {!t ? <SkeletonList rows={3} /> : (
        <div className="space-y-3 pt-1">
          <Tabela colunas="110px 110px minmax(140px,1fr) minmax(200px,1.5fr)" largura={620} rotulo="Exemplares">
            <TCabecalho><TCelula fixa>Tombo</TCelula><TCelula>Estado</TCelula><TCelula>Local</TCelula><TCelula>Situação</TCelula></TCabecalho>
            {(t.exemplares as any[]).map((x) => (
              <TLinha key={x.id} rotulo={x.tombo} alerta={x.emprestimo?.atrasado}>
                <TCelula fixa className="font-mono text-[12.5px]">{x.tombo}</TCelula><TCelula>{x.estado.toLowerCase()}</TCelula><TCelula>{x.localizacao ?? x.unidade}</TCelula>
                <TCelula livre>{x.emprestimo ? <span>com {x.emprestimo.leitor} até {fmtDate(x.emprestimo.prevista)}</span>
                  : podeEmprestar && ['BOM', 'REGULAR'].includes(x.estado) ? <Button size="sm" onClick={() => setAluno(x.id)}>Emprestar</Button> : <span className="text-muted">disponível</span>}</TCelula>
              </TLinha>
            ))}
          </Tabela>
          {(t.reservas as any[]).length > 0 && <p className="text-[13px]">Fila de reservas: {(t.reservas as any[]).map((r) => r.aluno.split(' ')[0]).join(', ')}</p>}
          {podeAcervo && (
            <div className="flex items-center gap-2">
              <input type="number" min={1} max={50} value={mais} onChange={(e) => setMais(Number(e.target.value))} className={`${inputCls} h-10 w-24`} aria-label="Quantidade de exemplares" />
              <Button variant="secondary" icon={BookPlus} onClick={() => fazer('biblioteca_titulo_salvar', { id: t.id, titulo: t.titulo, autor: t.autor, exemplares: mais }, `${mais} exemplar(es) incluído(s)`)}>Incluir exemplares</Button>
            </div>
          )}
        </div>
      )}
      <BuscarPessoaSheet open={!!aluno} onClose={() => setAluno(null)} tipo="aluno"
        onEscolher={(p) => { const ex = aluno; setAluno(null); fazer('biblioteca_emprestar', { exemplar_id: ex, student_id: p.id }, `Emprestado para ${p.nome.split(' ')[0]}`); }} />
    </Sheet>
  );
}

function NovoTituloSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [f, setF] = useState({ titulo: '', autor: '', editora: '', isbn: '', genero: 'LITERATURA_INFANTIL', faixa: 'TODAS', origem: 'PNLD', exemplares: 1 });
  const [busy, setBusy] = useState(false);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('biblioteca_titulo_salvar', f);
      toast({ title: 'Título incluído no acervo', tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não incluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Novo título" subtitle="Os exemplares recebem tombo automático da unidade."
      footer={<Button block loading={busy} disabled={f.titulo.trim().length < 2 || f.autor.trim().length < 2} onClick={salvar}>Incluir</Button>}>
      <div className="space-y-3 pt-1">
        <Field label="Título"><input value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} className={inputCls} /></Field>
        <Field label="Autor"><input value={f.autor} onChange={(e) => setF({ ...f, autor: e.target.value })} className={inputCls} /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Editora"><input value={f.editora} onChange={(e) => setF({ ...f, editora: e.target.value })} className={inputCls} /></Field>
          <Field label="ISBN (opcional)"><input value={f.isbn} onChange={(e) => setF({ ...f, isbn: e.target.value })} className={inputCls} /></Field>
          <Field label="Gênero"><select value={f.genero} onChange={(e) => setF({ ...f, genero: e.target.value })} className={inputCls}>{Object.entries(GENERO_LIVRO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          <Field label="Origem"><select value={f.origem} onChange={(e) => setF({ ...f, origem: e.target.value })} className={inputCls}>{['PNLD', 'DOACAO', 'COMPRA', 'OUTRO'].map((o) => <option key={o} value={o}>{o === 'DOACAO' ? 'Doação' : o === 'COMPRA' ? 'Compra' : o === 'OUTRO' ? 'Outra' : 'PNLD'}</option>)}</select></Field>
          <Field label="Exemplares"><input type="number" min={1} max={50} value={f.exemplares} onChange={(e) => setF({ ...f, exemplares: Number(e.target.value) })} className={inputCls} /></Field>
        </div>
      </div>
    </Sheet>
  );
}

/** Empréstimo rápido: tombo do exemplar e o aluno (a busca respeita a unidade). */
function EmprestarSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [tombo, setTombo] = useState('');
  const [aluno, setAluno] = useState<{ id: string; nome: string } | null>(null);
  const [busca, setBusca] = useState(false);
  const [busy, setBusy] = useState(false);
  const salvar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('biblioteca_emprestar', { tombo, student_id: aluno?.id });
      toast({ title: `“${r.titulo}” emprestado`, description: `Devolver até ${fmtDate(r.prevista)}.`, tone: 'success' });
      setTombo(''); setAluno(null);
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não emprestado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Emprestar livro" subtitle="Digite o tombo da etiqueta e escolha o aluno."
      footer={<Button block loading={busy} disabled={!tombo.trim() || !aluno} onClick={salvar}>Registrar empréstimo</Button>}>
      <div className="space-y-3 pt-1">
        <Field label="Tombo do exemplar"><input value={tombo} onChange={(e) => setTombo(e.target.value.toUpperCase())} placeholder="Ex.: 76-00012" className={`${inputCls} font-mono`} /></Field>
        <Field label="Aluno">
          <button type="button" onClick={() => setBusca(true)} className={`${inputCls} text-left`}>{aluno?.nome ?? 'Buscar aluno…'}</button>
        </Field>
      </div>
      <BuscarPessoaSheet open={busca} onClose={() => setBusca(false)} tipo="aluno" onEscolher={(p) => { setAluno(p); setBusca(false); }} />
    </Sheet>
  );
}

function Leitura({ d }: { d: any }) {
  const [modo, setModo] = useState<'mes' | 'titulos'>('mes');
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Section title={d.unit_id ? 'Leitura por turma' : 'Unidades'} subtitle={d.unit_id ? 'Livros emprestados no ano por aluno' : 'Leituras no ano e atrasos'}>
        <Card className="overflow-hidden">
          {d.unit_id ? (
            <Tabela colunas="minmax(140px,1fr) 80px 90px 100px" largura={420} rotulo="Leitura por turma">
              <TCabecalho><TCelula fixa>Turma</TCelula><TCelula>Alunos</TCelula><TCelula>Leituras</TCelula><TCelula>Por aluno</TCelula></TCabecalho>
              {((d.turmas ?? []) as any[]).map((t) => (
                <TLinha key={t.class_id} rotulo={t.turma}><TCelula fixa>{t.turma}</TCelula><TCelula>{t.alunos}</TCelula><TCelula>{fmtInt(t.leituras)}</TCelula><TCelula>{String(t.por_aluno ?? '—').replace('.', ',')}</TCelula></TLinha>
              ))}
            </Tabela>
          ) : (
            <Tabela colunas="minmax(180px,1.4fr) 100px 90px 90px" largura={480} rotulo="Unidades">
              <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Exemplares</TCelula><TCelula>Leituras</TCelula><TCelula>Atrasos</TCelula></TCabecalho>
              {((d.unidades ?? []) as any[]).map((u) => (
                <TLinha key={u.unit_id} rotulo={u.unidade} alerta={u.atrasados > 20}><TCelula fixa>{u.unidade}</TCelula><TCelula>{fmtInt(u.exemplares)}</TCelula><TCelula>{fmtInt(u.leituras)}</TCelula><TCelula>{fmtInt(u.atrasados)}</TCelula></TLinha>
              ))}
            </Tabela>
          )}
        </Card>
      </Section>
      <Section title="Movimento" action={<Segmented value={modo} onChange={setModo} items={[{ value: 'mes', label: 'Por mês' }, { value: 'titulos', label: 'Mais lidos' }]} />}>
        <Card className="p-4">
          {modo === 'mes'
            ? <BarList items={((d.por_mes ?? []) as any[]).map((m) => ({ key: m.mes, label: new Date(`${m.mes}T12:00:00`).toLocaleDateString('pt-BR', { month: 'short' }), value: m.n }))} />
            : <BarList items={((d.mais_lidos ?? []) as any[]).map((t) => ({ key: t.titulo_id, label: t.titulo, value: t.n }))} />}
        </Card>
      </Section>
    </div>
  );
}
