import type { ReactNode } from 'react';
import clsx from 'clsx';
import { ArrowRightLeft, Bus, CalendarCheck, FileText, FolderOpen, HeartPulse, IdCard, ListOrdered, School, Search, Users, type LucideIcon } from 'lucide-react';
import { fmtDate, fmtKm } from '@/lib/format';
import { DOC, QUEUE_CATEGORY, SHIFT, type Tone } from '@/lib/labels';
import { NACIONALIDADE, PARENTESCO, RACA, SEXO, SITUACAO_LEGAL, TRANSPORTE_SITUACAO } from '@/lib/cadastro';
import { SITUACAO_RESTRICAO, pctTone } from '@/lib/escola';
import { Badge, Button, ButtonLink, Card } from '@/components/ui';
import { Foto } from '@/components/arquivos';

const SITUACAO: Record<string, { f: string; m: string; tone: Tone }> = {
  MATRICULADO: { f: 'Matriculada', m: 'Matriculado', tone: 'green' },
  AGUARDANDO_VAGA: { f: 'Aguardando vaga', m: 'Aguardando vaga', tone: 'purple' },
  SEM_VINCULO: { f: 'Sem vaga na rede', m: 'Sem vaga na rede', tone: 'gray' },
  TRANSFERENCIA: { f: 'Em transferência', m: 'Em transferência', tone: 'amber' },
  INATIVO: { f: 'Inativa', m: 'Inativo', tone: 'gray' },
};

function Bloco({ icon: Icon, titulo, acao, children }: { icon: LucideIcon; titulo: string; acao?: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-2xl bg-white p-3.5 ring-1 ring-line/70">
      <div className="mb-1 flex items-center gap-2">
        <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-xl bg-purple-50 text-purple-700"><Icon className="size-4" /></span>
        <h3 className="min-w-0 flex-1 font-display text-[15px] font-extrabold">{titulo}</h3>
        {acao}
      </div>
      <dl className="divide-y divide-line/60">{children}</dl>
    </section>
  );
}

function Linha({ rotulo, children, vazio = 'não informado' }: { rotulo: string; children?: ReactNode; vazio?: string }) {
  const tem = children !== null && children !== undefined && children !== '' && children !== false;
  return (
    <div className="flex items-baseline justify-between gap-3 py-1.5 text-[13.5px]">
      <dt className="shrink-0 text-muted">{rotulo}</dt>
      <dd className={clsx('min-w-0 text-right', tem ? 'font-semibold text-ink' : 'text-subtle')}>{tem ? children : vazio}</dd>
    </div>
  );
}

/**
 * A ficha de um filho, como está na rede: escola (ou fila), dados pessoais, documentos, saúde e alimentação,
 * transporte e quem cuida. Os números de documento vêm mascarados; correções vão por "Documentos e dados".
 */
export function FichaFilho({ f, freq, acoes }: { f: any; freq?: any; acoes?: ReactNode }) {
  const m = f.matricula;
  const fem = f.sexo === 'F';
  const sit = SITUACAO[f.situacao];
  const docs = f.documentos ?? {};
  const restricoes = (f.restricoes ?? []) as any[];
  const responsaveis = (f.responsaveis ?? []) as any[];
  const rota = f.transporte?.rota;
  const pct = freq ? Number(freq.percentual) : null;
  return (
    <Card id={`filho-${f.student_id}`} className="scroll-mt-24 overflow-hidden p-0">
      <div className="flex items-start gap-3 p-4">
        <Foto arquivoId={f.foto_arquivo_id} name={f.nome} seed={f.student_id} size={60} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="font-display text-[18px] font-extrabold leading-tight">{f.nome}{f.nome_social && <span className="ml-1.5 text-[14px] font-semibold text-muted">({f.nome_social})</span>}</div>
              <div className="text-[13px] text-muted">{f.idade} · {fem ? 'nascida' : 'nascido'} em {fmtDate(f.nascimento)} · {PARENTESCO[f.parentesco] ?? f.parentesco?.toLowerCase()}</div>
            </div>
            <Badge tone={sit?.tone ?? 'gray'}>{sit ? (fem ? sit.f : sit.m) : f.situacao}</Badge>
          </div>
          <p className="mt-1.5 text-[13.5px] text-ink-2">
            {m ? <>Estuda no <b>{m.unidade}</b> · {m.turma} · {SHIFT[m.turno] ?? m.turno}</>
              : (f.fila as any[]).length ? <>Na fila de {f.fila[0].etapa} · {f.fila[0].unidade}: <b>{f.fila[0].posicao ? `${f.fila[0].posicao}º` : 'oferta em andamento'}</b>{f.fila[0].pontos != null ? ` · ${Number(f.fila[0].pontos)} pontos` : ''}</>
                : f.faixa?.ok ? `Faixa pela data de corte: ${f.faixa.grade_name}.` : f.faixa?.explanation}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 bg-slate-50/70 p-3 md:grid-cols-2 xl:grid-cols-3">
        {m ? (
          <Bloco icon={School} titulo="Escola">
            <Linha rotulo="Unidade">{m.unidade}</Linha>
            <Linha rotulo="Endereço">{[m.unidade_endereco, m.unidade_bairro].filter(Boolean).join(' · ')}</Linha>
            <Linha rotulo="Turma">{m.turma}{m.etapa && m.etapa !== m.turma && !m.turma.startsWith(m.etapa) ? ` · ${m.etapa}` : ''}</Linha>
            <Linha rotulo="Turno">{[SHIFT[m.turno] ?? m.turno, m.sala].filter(Boolean).join(' · ')}</Linha>
            <Linha rotulo="Professora(or) regente">{m.regente}</Linha>
            {m.outros_professores > 0 && <Linha rotulo="Outros professores">{m.outros_professores}</Linha>}
            <Linha rotulo="Direção">{m.direcao}</Linha>
            {m.unidade_telefone && <Linha rotulo="Telefone">{m.unidade_telefone}</Linha>}
            <Linha rotulo={fem ? 'Matriculada desde' : 'Matriculado desde'}>{fmtDate(m.desde)}</Linha>
            <Linha rotulo="Distância de casa">{m.distancia_m != null ? `${fmtKm(m.distancia_m)} (linha reta)` : null}</Linha>
            {freq && <Linha rotulo="Frequência"><Badge tone={pctTone(pct, Number(freq.minimo))}>{String(freq.percentual ?? '—').replace('.', ',')}%</Badge> <span className="font-normal text-muted">· {freq.faltas} falta(s)</span></Linha>}
          </Bloco>
        ) : (
          <Bloco icon={ListOrdered} titulo="Fila por vaga">
            {(f.fila as any[]).length ? (f.fila as any[]).map((q) => (
              <div key={q.id}>
                <Linha rotulo="Unidade">{q.unidade}</Linha>
                <Linha rotulo="Etapa">{q.etapa}</Linha>
                <Linha rotulo="Posição">{q.posicao ? `${q.posicao}º` : q.situacao === 'OFFERED' ? 'oferta aguardando você' : 'aceite registrado'}</Linha>
                <Linha rotulo="Pontos">{q.pontos != null ? Number(q.pontos) : null}</Linha>
                <Linha rotulo="Situação">{QUEUE_CATEGORY[q.categoria]?.label ?? q.categoria}</Linha>
                <Linha rotulo="Inscrição em">{fmtDate(q.desde)}</Linha>
              </div>
            )) : <Linha rotulo="Inscrição" vazio="nenhuma no momento" />}
            <Linha rotulo="Faixa pela data de corte">{f.faixa?.ok ? f.faixa.grade_name : null}</Linha>
          </Bloco>
        )}

        <Bloco icon={IdCard} titulo="Dados pessoais">
          <Linha rotulo="Nascimento">{fmtDate(f.nascimento)}</Linha>
          <Linha rotulo="Sexo">{SEXO[f.sexo]}</Linha>
          <Linha rotulo="Cor/raça">{RACA[f.cor_raca]}</Linha>
          <Linha rotulo="Naturalidade">{f.nacionalidade === 'ESTRANGEIRA' ? f.pais_nascimento : [f.naturalidade_municipio, f.naturalidade_uf].filter(Boolean).join('/')}</Linha>
          <Linha rotulo="Nacionalidade">{NACIONALIDADE[f.nacionalidade] ?? f.nacionalidade}</Linha>
          <Linha rotulo="Filiação">{[f.filiacao_1, f.filiacao_2].filter(Boolean).join(' e ')}</Linha>
          <Linha rotulo="Registro na rede">{f.registro}</Linha>
          {f.codigo_inep && <Linha rotulo="Código INEP">{f.codigo_inep}</Linha>}
          <Linha rotulo="Endereço">{f.mesmo_endereco ? 'o mesmo da família' : f.endereco}</Linha>
        </Bloco>

        <Bloco icon={FileText} titulo="Documentos" acao={<ButtonLink to="/familia/documentos" size="sm" variant="ghost">Enviar</ButtonLink>}>
          <Linha rotulo="CPF">{f.cpf}</Linha>
          <Linha rotulo="Certidão de nascimento">{f.certidao}</Linha>
          <Linha rotulo="NIS">{f.nis}</Linha>
          <Linha rotulo="Cartão SUS">{f.cartao_sus}</Linha>
          <div className="flex flex-wrap justify-end gap-1.5 pt-2">
            {docs.validados > 0 && <Badge tone="green">{docs.validados} conferido(s)</Badge>}
            {docs.em_conferencia > 0 && <Badge tone="amber">{docs.em_conferencia} em conferência</Badge>}
            {docs.recusados > 0 && <Badge tone="red">{docs.recusados} recusado(s)</Badge>}
            {((docs.faltando ?? []) as string[]).length > 0 && <Badge tone="gray">Falta: {(docs.faltando as string[]).map((t) => DOC[t] ?? t).join(', ')}</Badge>}
          </div>
        </Bloco>

        <Bloco icon={HeartPulse} titulo="Saúde e alimentação">
          <Linha rotulo="Restrição alimentar" vazio="nenhuma informada">
            {restricoes.length > 0 && (
              <span className="inline-flex flex-wrap justify-end gap-1">
                {restricoes.map((r, i) => <Badge key={i} tone={SITUACAO_RESTRICAO[r.situacao]?.tone ?? 'gray'}>{String(r.descricao).split(' (')[0]}{r.detalhe ? ` (${r.detalhe})` : ''}</Badge>)}
              </span>
            )}
          </Linha>
          <Linha rotulo="Educação especial (AEE)">{f.aee ? 'Sim' : 'Não'}</Linha>
          <Linha rotulo="Acessibilidade" vazio="nenhuma informada">{f.acessibilidade}</Linha>
          <Linha rotulo="Uso de imagem">{f.uso_imagem ? 'Autorizado' : 'Não autorizado'}</Linha>
        </Bloco>

        {(m || f.transporte?.precisa) && (
          <Bloco icon={Bus} titulo="Transporte escolar">
            {rota ? (
              <>
                <Linha rotulo="Rota">{rota.codigo} · {rota.nome}</Linha>
                <Linha rotulo="Ponto">{rota.ponto}</Linha>
                <Linha rotulo="Horários">{[rota.ida && `ida ${String(rota.ida).slice(0, 5)}`, rota.volta && `volta ${String(rota.volta).slice(0, 5)}`].filter(Boolean).join(' · ')}</Linha>
                <Linha rotulo="Situação">{TRANSPORTE_SITUACAO[f.transporte.situacao] ?? f.transporte.situacao}</Linha>
              </>
            ) : f.transporte?.precisa
              ? <Linha rotulo="Situação">{TRANSPORTE_SITUACAO[f.transporte.situacao] ?? 'Pedido em análise'}</Linha>
              : <Linha rotulo="Usa o transporte" vazio="não usa">{null}</Linha>}
          </Bloco>
        )}

        <Bloco icon={Users} titulo="Quem cuida">
          {responsaveis.map((r, i) => (
            <div key={i} className="py-1.5 text-[13.5px]">
              <div className="flex items-baseline justify-between gap-2">
                <span className="min-w-0 truncate font-semibold">{r.nome}{r.eu && <span className="font-normal text-muted"> (você)</span>}</span>
                <span className="shrink-0 text-muted">{PARENTESCO[r.parentesco] ?? r.parentesco?.toLowerCase()}</span>
              </div>
              <div className="mt-0.5 flex flex-wrap gap-1">
                {r.pode_buscar && <Badge tone="green">pode buscar</Badge>}
                {r.recebe_avisos && <Badge tone="blue">recebe avisos</Badge>}
                {r.situacao_legal && r.situacao_legal !== 'CONFIRMADO' && <Badge tone={SITUACAO_LEGAL[r.situacao_legal]?.tone ?? 'amber'}>guarda {SITUACAO_LEGAL[r.situacao_legal]?.label.toLowerCase() ?? r.situacao_legal}</Badge>}
                {r.telefone && <span className="text-[12px] text-muted">{r.telefone}</span>}
              </div>
            </div>
          ))}
        </Bloco>
      </div>

      {((f.pendencias ?? []) as string[]).length > 0 && (
        <div className="border-t border-amber-200 bg-amber-50 px-4 py-2.5 text-[13px] text-amber-950">
          Para o cadastro ficar completo falta: <b>{(f.pendencias as string[]).join(', ')}</b>. Corrija em Documentos e dados ou leve à secretaria da escola.
        </div>
      )}
      {acoes && <div className="flex flex-wrap gap-2 border-t border-line px-4 py-3">{acoes}</div>}
    </Card>
  );
}

/** Ações de cada ficha: vida escolar, transferência ou fila, e documentos. */
export function AcoesFicha({ f, kid, onDesistir }: { f: any; kid?: any; onDesistir?: (entry: any, kid: any) => void }) {
  const q = (kid?.queue ?? [])[0];
  return (
    <>
      {f.matricula && <ButtonLink to={`/escola?filho=${f.student_id}`} size="sm" variant="purple" icon={CalendarCheck}>Vida escolar de {f.primeiro_nome}</ButtonLink>}
      {!f.matricula && !q && f.faixa?.ok && <ButtonLink to={`/vagas?aluno=${f.student_id}`} size="sm" variant="purple" icon={Search}>Inscrever na fila</ButtonLink>}
      {f.matricula && !q && <ButtonLink to={`/vagas?aluno=${f.student_id}`} size="sm" variant="secondary" icon={ArrowRightLeft}>Pedir transferência</ButtonLink>}
      <ButtonLink to="/familia/documentos" size="sm" variant="secondary" icon={FolderOpen}>Documentos e foto</ButtonLink>
      {q?.status === 'WAITING' && onDesistir && <Button size="sm" variant="ghost" onClick={() => onDesistir(q, kid)}>Desistir da fila</Button>}
    </>
  );
}
