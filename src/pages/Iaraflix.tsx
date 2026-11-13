import { useEffect, useState } from 'react';
import { Link, useLocation, useParams } from 'react-router';
import clsx from 'clsx';
import { ArrowLeft, Award, BadgeCheck, CheckCircle2, ClipboardCheck, Clapperboard, Film, Lock, MonitorPlay, Play, Settings2, ShieldCheck, Users, XCircle } from 'lucide-react';
import { useMediaQuery, useRpc, useRpcMutation } from '@/lib/hooks';
import { fmtDate } from '@/lib/format';
import { fmtDuracao, fmtMinutos } from '@/lib/iaraflix';
import { Button, ButtonLink, Card, EmptyState, ErrorState, Section, SkeletonList } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { useToast } from '@/components/overlays';
import { IaraflixMarca, IpeAssistindo, PosterTrilha, SituacaoAula, capaDaTrilha, type TrilhaResumo } from '@/components/iaraflix';

type Inicio = {
  eu: { nome: string; perfil: string; unidade: string | null };
  gestao: boolean; equipe: boolean;
  trilhas: TrilhaResumo[];
  continuar: { id: string; titulo: string; ordem: number; trilha_id: string; trilha: string; posicao_s: number; duracao_s: number | null; tem_video: boolean }[];
};

/** Para onde vai o botão principal de uma trilha, e com que texto. */
function proximoPasso(t: TrilhaResumo, continuar?: Inicio['continuar'][number]) {
  if (continuar && continuar.trilha_id === t.id) return { to: `/iaraflix/aula/${continuar.id}`, label: `Continuar: ${continuar.titulo}` };
  if (t.concluida_em) return { to: `/iaraflix/trilha/${t.id}#certificado`, label: 'Ver o certificado' };
  if (t.proxima) return { to: `/iaraflix/aula/${t.proxima.id}`, label: `${t.concluidas ? 'Próxima aula' : 'Começar'}: ${t.proxima.titulo}` };
  return { to: `/iaraflix/trilha/${t.id}#perguntas`, label: 'Responder as perguntas' };
}

export default function Iaraflix() {
  const q = useRpc<Inicio>('iaraflix_inicio', {}, { staleTime: 0 });
  const largo = useMediaQuery('(min-width: 768px)');
  if (q.isLoading) return <SkeletonList rows={5} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const d = q.data!;
  const minhas = d.trilhas.filter((t) => t.obrigatoria);
  const tambem = d.trilhas.filter((t) => t.minha && !t.obrigatoria);
  const outras = d.trilhas.filter((t) => !t.minha);
  const principal = minhas.find((t) => !t.concluida_em) ?? minhas[0] ?? d.trilhas[0];
  const passo = principal ? proximoPasso(principal, d.continuar.find((c) => c.trilha_id === principal.id)) : null;
  const feitas = minhas.filter((t) => t.concluida_em).length;

  return (
    <div>
      <section className="relative overflow-hidden rounded-[28px] bg-[#16072a] text-white shadow-[0_30px_60px_-30px_rgb(22_7_42/0.9)]">
        <div aria-hidden className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_80%_at_85%_30%,rgb(168_70_232/0.45),transparent_70%),radial-gradient(50%_60%_at_10%_100%,rgb(8_109_182/0.35),transparent_70%)]" />
        <div className="relative grid grid-cols-[minmax(0,1fr)] items-end gap-2 px-5 pt-6 sm:px-8 sm:pt-8 md:grid-cols-[minmax(0,1fr)_auto]">
          <div className="min-w-0 pb-6 sm:pb-8">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <IaraflixMarca className="text-[46px] leading-none sm:text-6xl" />
              <div className="flex gap-2">
                {d.gestao && <ButtonLink to="/iaraflix/gestao" size="sm" variant="secondary" icon={Settings2}>Gestão</ButtonLink>}
                {!d.gestao && d.equipe && <ButtonLink to="/iaraflix/gestao?aba=adesao" size="sm" variant="secondary" icon={Users}>Adesão da equipe</ButtonLink>}
              </div>
            </div>
            <p className="mt-3 max-w-xl text-[15px] text-white/80 text-pretty">
              O treinamento do IARA Educa no seu tempo, no celular ou no computador: aulas curtas, prática no ambiente de treinamento e certificado
              com código de verificação.
            </p>
            {principal && passo && (
              <div className="mt-5 max-w-xl rounded-2xl bg-white/10 p-4 ring-1 ring-white/15 backdrop-blur-sm">
                <div className="text-[11px] font-bold uppercase tracking-[0.12em] text-purple-200">
                  {principal.concluida_em ? 'Trilha concluída' : principal.obrigatoria ? 'Sua trilha agora' : 'Trilha'}
                </div>
                <div className="font-display text-xl font-extrabold leading-tight">{principal.titulo}</div>
                <div className="mt-2 flex items-center gap-3 text-[13px] text-white/80">
                  <span className="shrink-0">{principal.concluidas} de {principal.aulas} aulas</span>
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/20">
                    <div className="h-full rounded-full bg-gradient-to-r from-purple-300 to-fuchsia-300" style={{ width: `${principal.aulas ? (principal.concluidas / principal.aulas) * 100 : 0}%` }} />
                  </div>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  <ButtonLink to={passo.to} variant="purple" icon={principal.concluida_em ? Award : Play} className="max-w-full">
                    <span className="truncate">{passo.label}</span>
                  </ButtonLink>
                  <ButtonLink to={`/iaraflix/trilha/${principal.id}`} variant="secondary">Ver a trilha</ButtonLink>
                </div>
              </div>
            )}
          </div>
          <IpeAssistindo height={largo ? 330 : 220} className="mx-auto -mb-1" />
        </div>
      </section>

      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
        {[
          { i: MonitorPlay, t: 'Assista', s: 'Aulas de 3 a 5 minutos' },
          { i: ClipboardCheck, t: 'Pratique', s: 'No ambiente de treinamento' },
          { i: CheckCircle2, t: 'Responda', s: 'Perguntas rápidas no fim' },
          { i: Award, t: 'Certificado', s: 'Com código de verificação' },
        ].map(({ i: I, t, s }) => (
          <div key={t} className="flex items-center gap-2.5 rounded-2xl bg-white px-3 py-2.5 ring-1 ring-line">
            <span className="inline-flex size-9 shrink-0 items-center justify-center rounded-xl bg-purple-100 text-purple-700"><I className="size-[18px]" aria-hidden /></span>
            <div className="min-w-0"><div className="text-[13.5px] font-bold text-ink">{t}</div><div className="truncate text-xs text-muted">{s}</div></div>
          </div>
        ))}
      </div>

      {d.continuar.length > 0 && (
        <Section title="Continue de onde parou">
          <div className="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-1">
            {d.continuar.map((c) => (
              <Link key={c.id} to={`/iaraflix/aula/${c.id}`}
                className={clsx('group relative flex w-64 shrink-0 flex-col overflow-hidden rounded-2xl bg-gradient-to-br p-3.5 text-white ring-1 ring-white/10', capaDaTrilha(c.trilha_id))}>
                <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-white/75"><Film className="size-3.5" aria-hidden />{c.trilha}</div>
                <div className="mt-1 line-clamp-2 font-display text-[16px] font-extrabold leading-snug">{c.ordem}. {c.titulo}</div>
                <div className="mt-3 flex items-center gap-2 text-xs text-white/80">
                  <Play className="size-3.5" aria-hidden />parou em {fmtDuracao(c.posicao_s)}{c.duracao_s ? ` de ${fmtDuracao(c.duracao_s)}` : ''}
                </div>
                <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-white/20">
                  <div className="h-full bg-white" style={{ width: `${c.duracao_s ? Math.min(100, (c.posicao_s / c.duracao_s) * 100) : 10}%` }} />
                </div>
              </Link>
            ))}
          </div>
        </Section>
      )}

      {minhas.length > 0 && (
        <Section title="Suas trilhas" subtitle={`${feitas} de ${minhas.length} concluída${minhas.length > 1 ? 's' : ''}. Comece por "Primeiros passos" e siga com a trilha do seu perfil.`}>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{minhas.map((t) => <PosterTrilha key={t.id} t={t} />)}</div>
        </Section>
      )}
      {tambem.length > 0 && (
        <Section title="Também para você" subtitle="Trilhas opcionais para o seu perfil.">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{tambem.map((t) => <PosterTrilha key={t.id} t={t} />)}</div>
        </Section>
      )}
      {outras.length > 0 && (
        <Section title="Todas as trilhas da rede" subtitle="Você vê as trilhas de todos os perfis porque acompanha o treinamento da rede.">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{outras.map((t) => <PosterTrilha key={t.id} t={t} />)}</div>
        </Section>
      )}
      {d.trilhas.length === 0 && <EmptyState title="Nenhuma trilha para o seu perfil ainda" body="Quando a gestão publicar, ela aparece aqui." />}

      <p className="mt-6 flex items-start gap-2 text-xs text-muted">
        <ShieldCheck className="mt-0.5 size-4 shrink-0 text-green-700" aria-hidden />
        Os vídeos foram gravados no ambiente de treinamento, só com dados fictícios. Eles abrem só para quem tem acesso à trilha, com o seu nome
        marcado na tela, e não podem ser baixados. Não grave nem compartilhe as aulas.
      </p>
    </div>
  );
}

type Trilha = TrilhaResumo & {
  lista: { id: string; ordem: number; titulo: string; resumo: string | null; pratica: string | null; duracao_s: number | null; tem_video: boolean; tem_legenda: boolean; posicao_s: number; concluida: boolean }[];
  perguntas: { id: string; enunciado: string; opcoes: string[] }[];
  pode_avaliar: boolean;
  participacao: { nome: string; aulas_concluidas: number; concluida_em: string | null; tentativas: number; acertos: number | null; perguntas: number | null; certificado: string | null; hash: string | null } | null;
};

export function IaraflixTrilha() {
  const { id } = useParams();
  const { hash } = useLocation();
  const q = useRpc<Trilha>('iaraflix_trilha', { id }, { staleTime: 0 });
  const pronta = !!q.data;
  // "#perguntas" e "#certificado" levam direto à seção (o roteador por hash não rola sozinho até a âncora)
  useEffect(() => {
    if (!pronta || !hash) return;
    const t = setTimeout(() => document.getElementById(hash.slice(1))?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 150);
    return () => clearTimeout(t);
  }, [pronta, hash]);
  if (q.isLoading) return <SkeletonList rows={6} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const t = q.data!;
  const passo = proximoPasso(t);
  const pct = t.aulas ? Math.round((t.concluidas / t.aulas) * 100) : 0;

  return (
    <div>
      <Link to="/iaraflix" className="mb-3 inline-flex items-center gap-1.5 text-sm font-semibold text-purple-700 hover:text-purple-900">
        <ArrowLeft className="size-4" aria-hidden /><IaraflixMarca claro className="text-[15px]" />
      </Link>
      <section className={clsx('relative overflow-hidden rounded-[26px] bg-gradient-to-br p-5 text-white sm:p-7', capaDaTrilha(t.id))}>
        <div aria-hidden className="pointer-events-none absolute -right-10 -top-16 size-56 rounded-full bg-white/10 blur-2xl" />
        <div className="relative">
          <div className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.12em] text-white/75">
            <Clapperboard className="size-3.5" aria-hidden />{t.obrigatoria ? 'Sua trilha' : t.minha ? 'Também para você' : 'Trilha da rede'} · {t.aulas} aulas · {fmtMinutos(t.duracao_s)} · certificado de {String(t.carga_horaria).replace('.', ',')} h
          </div>
          <h1 className="mt-2 font-display text-[28px] font-extrabold leading-tight text-balance sm:text-4xl">{t.titulo}</h1>
          <p className="mt-1 text-[15px] text-white/85">{t.publico}</p>
          <p className="mt-3 max-w-2xl text-[14.5px] text-white/90 text-pretty">{t.objetivo}</p>
          <div className="mt-4 flex max-w-md items-center gap-3 text-[13px] text-white/85">
            <span className="shrink-0">{t.concluidas} de {t.aulas} aulas</span>
            <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/25"><div className="h-full rounded-full bg-white" style={{ width: `${pct}%` }} /></div>
          </div>
          <div className="mt-4 flex flex-wrap gap-2">
            <ButtonLink to={passo.to} variant="secondary" icon={t.concluida_em ? Award : Play} className="max-w-full"><span className="truncate">{passo.label}</span></ButtonLink>
          </div>
        </div>
      </section>

      {(t.saber?.length ?? 0) > 0 && (
        <Section title="Ao final, você consegue">
          <ul className="grid gap-2 sm:grid-cols-2">
            {t.saber!.map((s) => (
              <li key={s} className="flex items-start gap-2 rounded-2xl bg-white px-3 py-2.5 text-[14px] text-ink ring-1 ring-line">
                <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" aria-hidden />{s}
              </li>
            ))}
          </ul>
        </Section>
      )}

      <Section title="Aulas" subtitle="Assista em ordem. Cada aula tem uma prática para fazer no ambiente de treinamento.">
        <Card className="overflow-hidden">
          <Tabela colunas="2.25rem minmax(0,1fr) 4rem 9.5rem" largura={560} rotulo="Aulas da trilha">
            <TCabecalho><span>Nº</span><span>Aula</span><span>Duração</span><span>Situação</span></TCabecalho>
            {t.lista.map((a) => (
              <TLinha key={a.id} to={`/iaraflix/aula/${a.id}`} rotulo={`Aula ${a.ordem}: ${a.titulo}`}>
                <TCelula className="font-display font-extrabold text-purple-700">{a.ordem}</TCelula>
                <TCelula titulo={a.titulo}>
                  <span className="font-semibold text-ink">{a.titulo}</span>
                  {!a.tem_video && <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-800">vídeo em produção</span>}
                </TCelula>
                <TCelula className="tabular text-muted">{a.tem_video ? fmtDuracao(a.duracao_s) : '—'}</TCelula>
                <TCelula livre><SituacaoAula concluida={a.concluida} posicao_s={a.posicao_s} duracao_s={a.duracao_s} tem_video={a.tem_video} /></TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>

      <Perguntas t={t} />
    </div>
  );
}

function Perguntas({ t }: { t: Trilha }) {
  const toast = useToast();
  const [resp, setResp] = useState<(number | null)[]>(() => t.perguntas.map(() => null));
  const [res, setRes] = useState<{ aprovado: boolean; acertos: number; perguntas: number; resultado: { id: string; certa: boolean; explicacao: string | null }[] } | null>(null);
  const avaliar = useRpcMutation('iaraflix_avaliar', ['iaraflix_trilha', 'iaraflix_inicio']);
  const p = t.participacao;

  if (p?.concluida_em && p.certificado) {
    return (
      <Section title="Certificado" id="certificado">
        <Card className="relative overflow-hidden p-5 sm:p-6">
          <div aria-hidden className="pointer-events-none absolute -right-10 -top-10 size-40 rounded-full bg-purple-100" />
          <div className="relative flex flex-col gap-4 sm:flex-row sm:items-center">
            <span className="inline-flex size-14 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-purple-700 to-fuchsia-600 text-white"><Award className="size-7" aria-hidden /></span>
            <div className="min-w-0 flex-1">
              <div className="text-[11px] font-bold uppercase tracking-[0.12em] text-purple-700">Certificado de formação · IARAFLIX</div>
              <p className="mt-1 text-[15px] text-ink text-pretty">
                <b>{p.nome}</b> concluiu a trilha <b>{t.titulo}</b>, com carga de {String(t.carga_horaria).replace('.', ',')} h, a distância e com avaliação,
                em {fmtDate(p.concluida_em)}.
              </p>
              <div className="mt-2 font-mono text-[15px] font-bold tracking-wider text-ink">{p.certificado}</div>
            </div>
            <ButtonLink to={`/verificar/${p.certificado}`} variant="secondary" icon={BadgeCheck}>Conferir autenticidade</ButtonLink>
          </div>
        </Card>
      </Section>
    );
  }

  if (!t.pode_avaliar) {
    return (
      <Section title="Perguntas e certificado" id="perguntas">
        <Card className="flex items-center gap-3 p-4">
          <Lock className="size-5 shrink-0 text-subtle" aria-hidden />
          <p className="text-[14px] text-muted">
            Conclua as {t.aulas} aulas para liberar as {t.perguntas.length} perguntas do fim. Faltam {t.aulas - t.concluidas}.
            Acertando todas, o certificado sai na hora, com código de verificação.
          </p>
        </Card>
      </Section>
    );
  }

  const enviar = async () => {
    try {
      const r = await avaliar.mutateAsync({ trilha_id: t.id, respostas: resp });
      setRes(r);
      if (r.aprovado) toast({ title: 'Trilha concluída!', description: 'O seu certificado já está disponível.', tone: 'success' });
    } catch (e) {
      toast({ title: 'Não foi possível enviar', description: (e as Error).message, tone: 'error' });
    }
  };
  const porId = new Map((res?.resultado ?? []).map((x) => [x.id, x]));

  return (
    <Section title="Perguntas do fim da trilha" id="perguntas"
      subtitle={res && !res.aprovado ? `Você acertou ${res.acertos} de ${res.perguntas}. Veja a explicação e tente de novo.` : 'Acertando todas, o certificado sai na hora. Pode tentar quantas vezes precisar.'}>
      <div className="space-y-3">
        {t.perguntas.map((q, i) => {
          const r = porId.get(q.id);
          return (
            <Card key={q.id} className={clsx('p-4', r && (r.certa ? 'ring-2 ring-green-200' : 'ring-2 ring-red-200'))}>
              <div className="flex items-start gap-2">
                <span className="font-display text-lg font-extrabold text-purple-700">{i + 1}.</span>
                <p className="pt-0.5 text-[15px] font-semibold text-ink">{q.enunciado}</p>
              </div>
              <div className="mt-3 grid gap-2" role="radiogroup" aria-label={`Pergunta ${i + 1}`}>
                {q.opcoes.map((o, k) => (
                  <label key={k} className={clsx('flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2.5 text-[14px] ring-1 transition',
                    resp[i] === k ? 'bg-purple-50 text-ink ring-purple-400' : 'bg-white text-ink-2 ring-line hover:bg-slate-50')}>
                    <input type="radio" name={`q-${q.id}`} className="size-4 accent-purple-700" checked={resp[i] === k}
                      onChange={() => { setResp((x) => x.map((v, j) => (j === i ? k : v))); setRes(null); }} />
                    {o}
                  </label>
                ))}
              </div>
              {r && (
                <p className={clsx('mt-3 flex items-start gap-2 text-[13.5px]', r.certa ? 'text-green-800' : 'text-red-800')}>
                  {r.certa ? <CheckCircle2 className="mt-0.5 size-4 shrink-0" aria-hidden /> : <XCircle className="mt-0.5 size-4 shrink-0" aria-hidden />}
                  {r.certa ? 'Certo.' : 'Ainda não.'} {r.explicacao}
                </p>
              )}
            </Card>
          );
        })}
      </div>
      <div className="mt-4">
        <Button variant="purple" icon={Award} loading={avaliar.isPending} disabled={resp.some((x) => x == null)} onClick={enviar}>
          {res && !res.aprovado ? 'Tentar de novo' : 'Enviar respostas'}
        </Button>
      </div>
    </Section>
  );
}
