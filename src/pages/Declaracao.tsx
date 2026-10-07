import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';
import { QRCodeSVG } from 'qrcode.react';
import { ArrowLeft, BadgeCheck, CircleAlert, Printer, Search, ShieldCheck } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { SITUACAO_DECLARACAO, TIPO_DECLARACAO, urlVerificacao } from '@/lib/pedagogico';
import { Badge, Button, Card, ErrorState, PageHeader, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { useQuery } from '@tanstack/react-query';

/** Declaração para imprimir (família ou escola): texto emitido, validade e QR code de verificação. */
export default function Declaracao() {
  const { id } = useParams();
  const navigate = useNavigate();
  const res = useRpc<any>('declaracao_ver', { id });
  if (res.isLoading) return <div className="p-6"><SkeletonList rows={6} /></div>;
  if (res.error) return <div className="p-6"><ErrorState error={res.error} onRetry={() => res.refetch()} /></div>;
  const d = res.data;
  const c = d.conteudo;
  const st = SITUACAO_DECLARACAO[d.situacao];
  const url = urlVerificacao(d.codigo);
  return (
    <div className="min-h-dvh bg-slate-100 py-6 print:bg-white print:py-0">
      <div className="mx-auto mb-4 flex max-w-[190mm] flex-wrap items-center justify-between gap-2 px-4 print:hidden">
        <Button variant="secondary" icon={ArrowLeft} onClick={() => navigate(-1)}>Voltar</Button>
        <div className="flex items-center gap-2">
          {d.is_demo && <Simulado detail="Declaração de demonstração." />}
          <Badge tone={st?.tone ?? 'gray'}>{st?.label ?? d.situacao}</Badge>
          <Button icon={Printer} onClick={() => window.print()} disabled={d.situacao !== 'VALIDA'}>Imprimir ou salvar PDF</Button>
        </div>
      </div>
      <article className="relative mx-auto max-w-[190mm] rounded-3xl bg-white px-10 py-10 shadow-lift print:max-w-none print:rounded-none print:px-[18mm] print:py-[16mm] print:shadow-none">
        {d.situacao !== 'VALIDA' && (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <span className="rotate-[-24deg] rounded-2xl border-4 border-red-500/60 px-6 py-2 font-display text-5xl font-black uppercase text-red-500/60">{st?.label}</span>
          </div>
        )}
        <header className="flex items-start justify-between gap-4 border-b border-line pb-5">
          <div>
            <div className="text-[12px] font-bold uppercase tracking-[0.14em] text-purple-700">Prefeitura do Município de Maringá</div>
            <div className="font-display text-xl font-extrabold">{c.orgao}</div>
            {c.unidade && <div className="text-[13.5px] text-muted">{c.unidade}{c.inep ? ` · INEP ${c.inep}` : ''}</div>}
            {c.endereco_unidade && <div className="text-[12.5px] text-muted">{c.endereco_unidade}</div>}
          </div>
          <QRCodeSVG value={url} size={104} level="M" aria-label="QR code de verificação" />
        </header>
        <h1 className="mt-8 text-center font-display text-2xl font-black uppercase tracking-wide">{c.titulo}</h1>
        <p className="mt-8 text-justify text-[16px] leading-[1.9]">{c.texto}</p>
        {c.frequencia && (
          <table className="mt-6 w-full text-[14px]">
            <tbody>
              <tr className="border-b border-line"><td className="py-1.5 text-muted">Dias letivos registrados</td><td className="py-1.5 text-right font-semibold">{c.frequencia.dias}</td></tr>
              <tr className="border-b border-line"><td className="py-1.5 text-muted">Faltas (justificadas)</td><td className="py-1.5 text-right font-semibold">{c.frequencia.faltas} ({c.frequencia.justificadas})</td></tr>
              <tr><td className="py-1.5 text-muted">Frequência</td><td className="py-1.5 text-right font-semibold">{String(c.frequencia.percentual ?? '—').replace('.', ',')}%</td></tr>
            </tbody>
          </table>
        )}
        {c.historico && (
          <table className="mt-6 w-full text-[12.5px]">
            <thead><tr className="border-b border-line text-left text-muted"><th className="py-1">Ano</th><th>Série</th><th>Escola</th><th>CH</th><th>Freq.</th><th>Médias / parecer</th><th>Resultado</th></tr></thead>
            <tbody>
              {(c.historico as any[]).map((a) => (
                <tr key={a.ano} className="border-b border-line/60 align-top">
                  <td className="py-1.5 font-semibold">{a.ano}</td><td>{a.serie}</td><td>{a.unidade}</td><td>{a.carga_horaria}</td><td>{String(a.frequencia ?? '—').replace('.', ',')}%</td>
                  <td>{(a.componentes as any[]).length ? (a.componentes as any[]).map((x) => `${x.nome} ${Number(x.media).toFixed(1).replace('.', ',')}`).join(' · ') : 'Parecer descritivo'}</td>
                  <td>{({ APROVADO: 'Aprovado', APROVADO_CONSELHO: 'Aprovado pelo conselho', PROGRESSAO: 'Progressão', RETIDO: 'Retido', TRANSFERIDO: 'Transferido' } as Record<string, string>)[a.situacao] ?? a.situacao}</td>
                </tr>
              ))}
              {c.em_curso && <tr><td className="py-1.5 font-semibold">{c.em_curso.ano}</td><td>{c.em_curso.serie}</td><td>{c.em_curso.unidade}</td><td colSpan={4}>Cursando</td></tr>}
            </tbody>
          </table>
        )}
        <p className="mt-10 text-[15px]">{c.municipio}, {fmtDate(d.emitida_em)}.</p>
        <footer className="mt-12 rounded-2xl bg-slate-50 p-4 text-[12.5px] leading-relaxed text-ink-2 print:bg-white print:ring-1 print:ring-line">
          <div className="flex items-center gap-2 font-semibold"><ShieldCheck className="size-4 text-green-700" />Documento emitido eletronicamente pelo IARA Educa. A autenticidade se confere pelo código abaixo.</div>
          <div className="mt-1">Confira a autenticidade em <b>{url.replace(/^https?:\/\//, '')}</b> ou pelo QR code, com o código <b className="font-mono text-[13.5px]">{d.codigo}</b>.</div>
          <div className="mt-1">Emitida em {fmtDateTime(d.emitida_em)} · válida até {fmtDate(d.valida_ate)} · resumo de integridade {d.hash}</div>
        </footer>
      </article>
    </div>
  );
}

/** Verificação pública (sem login): a declaração existe, está válida, expirou ou foi revogada. Mostra só o nome abreviado. */
export function Verificar() {
  const { codigo } = useParams();
  const navigate = useNavigate();
  const [texto, setTexto] = useState(codigo ?? '');
  const res = useQuery({
    queryKey: ['declaracao_verificar', codigo],
    queryFn: () => rpc<any>('declaracao_verificar', { codigo }),
    enabled: !!codigo,
    retry: false,
    staleTime: 60_000,
  });
  const d = res.data;
  const st = d?.encontrada ? SITUACAO_DECLARACAO[d.situacao] : null;
  return (
    <div className="mx-auto max-w-xl">
      <PageHeader eyebrow="Secretaria Municipal de Educação de Maringá" title="Verificar declaração ou certificado"
        subtitle="Digite o código impresso no documento (12 letras e números) ou leia o QR code. Não precisa de senha." />
      <Card className="p-4">
        <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); navigate(`/verificar/${texto.trim().toUpperCase()}`); }}>
          <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="ABCD-EFGH-JK23" maxLength={20} autoCapitalize="characters"
            className={`${inputCls} h-12 flex-1 font-mono text-[17px] uppercase tracking-wider`} aria-label="Código da declaração" />
          <Button type="submit" icon={Search} size="lg" disabled={texto.replace(/[^a-z0-9]/gi, '').length !== 12}>Verificar</Button>
        </form>
      </Card>
      {codigo && (
        <div className="mt-4">
          {res.isLoading ? <SkeletonList rows={2} /> : res.error ? <ErrorState error={res.error as any} /> : d?.encontrada ? (
            <Card className={`p-5 ring-2 ${d.situacao === 'VALIDA' ? 'ring-green-300' : 'ring-red-300'}`}>
              <div className="flex items-center gap-3">
                {d.situacao === 'VALIDA' ? <BadgeCheck className="size-9 text-green-700" /> : <CircleAlert className="size-9 text-red-600" />}
                <div>
                  <div className="font-display text-xl font-extrabold">{d.tipo === 'CERTIFICADO' ? 'Certificado autêntico' : d.situacao === 'VALIDA' ? 'Declaração autêntica e válida' : `Declaração ${st?.label.toLowerCase()}`}</div>
                  <div className="text-[13px] text-muted">{d.tipo_rotulo ?? TIPO_DECLARACAO[d.tipo]?.label} · código <span className="font-mono">{d.codigo}</span></div>
                </div>
              </div>
              <dl className="mt-4 grid grid-cols-1 gap-3 text-[14px] sm:grid-cols-2">
                <div><dt className="text-[12px] font-bold uppercase tracking-wide text-subtle">{d.tipo === 'CERTIFICADO' ? 'Participante' : 'Aluno(a)'}</dt><dd className="font-semibold">{d.aluno}{d.nascimento_ano ? ` · nascido(a) em ${d.nascimento_ano}` : ''}</dd></div>
                <div><dt className="text-[12px] font-bold uppercase tracking-wide text-subtle">Unidade</dt><dd>{d.unidade ?? '—'}</dd></div>
                <div className="sm:col-span-2"><dt className="text-[12px] font-bold uppercase tracking-wide text-subtle">Resumo</dt><dd>{d.resumo}</dd></div>
                <div><dt className="text-[12px] font-bold uppercase tracking-wide text-subtle">Emitida em</dt><dd>{fmtDateTime(d.emitida_em)}</dd></div>
                {d.tipo !== 'CERTIFICADO' && <div><dt className="text-[12px] font-bold uppercase tracking-wide text-subtle">Válida até</dt><dd>{fmtDate(d.valida_ate)}</dd></div>}
                <div className="sm:col-span-2"><dt className="text-[12px] font-bold uppercase tracking-wide text-subtle">Resumo de integridade</dt><dd className="font-mono text-[13px]">{d.hash}</dd></div>
              </dl>
              {d.situacao === 'REVOGADA' && <p className="mt-3 rounded-2xl bg-red-50 p-3 text-[13px] text-red-800">A escola revogou esta declaração em {fmtDateTime(d.revogada_em)}. Peça uma nova à família ou à escola.</p>}
              {d.situacao === 'EXPIRADA' && <p className="mt-3 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-900">Passou da validade. A família emite outra na hora, pelo portal ou pela IARA.</p>}
              <p className="mt-3 text-[12px] text-muted">Por privacidade, a verificação mostra o nome abreviado. Confira se os dados batem com o papel apresentado.</p>
            </Card>
          ) : (
            <Card className="p-5 ring-2 ring-red-300">
              <div className="flex items-center gap-3"><CircleAlert className="size-9 text-red-600" /><div className="font-display text-xl font-extrabold">Não encontramos esta declaração</div></div>
              <p className="mt-2 text-[14px]">{d?.mensagem}</p>
            </Card>
          )}
        </div>
      )}
      <p className="mt-4 text-center text-[12.5px] text-muted"><Link to="/ajuda" className="text-blue-700">Dúvidas?</Link> As declarações da rede municipal trazem código e QR code de verificação.</p>
    </div>
  );
}

const FUNCAO_CERT: Record<string, string> = { PARTICIPANTE: 'participou', PALESTRANTE: 'atuou como palestrante', ORGANIZACAO: 'atuou na organização', PREMIADO: 'foi premiado(a)' };

/** Certificado de participação em evento (formação, feira, mostra, olimpíada), com código e QR code de verificação. */
export function Certificado() {
  const { codigo } = useParams();
  const navigate = useNavigate();
  const res = useRpc<any>('certificado_ver', { codigo });
  if (res.isLoading) return <div className="p-6"><SkeletonList rows={6} /></div>;
  if (res.error) return <div className="p-6"><ErrorState error={res.error} onRetry={() => res.refetch()} /></div>;
  const d = res.data;
  const url = urlVerificacao(d.codigo);
  const periodo = d.inicio === d.fim ? `em ${fmtDate(d.inicio)}` : `de ${fmtDate(d.inicio)} a ${fmtDate(d.fim)}`;
  return (
    <div className="min-h-dvh bg-slate-100 py-6 print:bg-white print:py-0">
      <div className="mx-auto mb-4 flex max-w-[277mm] flex-wrap items-center justify-between gap-2 px-4 print:hidden">
        <Button variant="secondary" icon={ArrowLeft} onClick={() => navigate(-1)}>Voltar</Button>
        <div className="flex items-center gap-2">
          {d.is_demo && <Simulado detail="Certificado de demonstração." />}
          <Button icon={Printer} onClick={() => window.print()}>Imprimir ou salvar PDF</Button>
        </div>
      </div>
      <style>{'@media print { @page { size: A4 landscape; margin: 0; } }'}</style>
      <article className="relative mx-auto max-w-[277mm] rounded-3xl bg-white px-14 py-12 shadow-lift ring-[10px] ring-inset ring-purple-100 print:max-w-none print:rounded-none print:px-[22mm] print:py-[16mm] print:shadow-none">
        <header className="flex items-start justify-between gap-4">
          <div>
            <div className="text-[12px] font-bold uppercase tracking-[0.14em] text-purple-700">Prefeitura do Município de Maringá</div>
            <div className="font-display text-lg font-extrabold">Secretaria Municipal de Educação</div>
            <div className="text-[13.5px] text-muted">{d.unidade}</div>
          </div>
          <QRCodeSVG value={url} size={96} level="M" aria-label="QR code de verificação" />
        </header>
        <h1 className="mt-8 text-center font-display text-4xl font-black uppercase tracking-[0.12em] text-purple-800">Certificado</h1>
        <p className="mx-auto mt-8 max-w-[220mm] text-center text-[18px] leading-[1.9]">
          Certificamos que <b className="text-[21px]">{d.nome}</b> {FUNCAO_CERT[d.funcao] ?? 'participou'} {d.funcao === 'PREMIADO' ? 'em' : 'de'} <b>{d.evento}</b>,
          realizado {periodo}{d.local ? `, em ${d.local}` : ''}, com carga horária de <b>{String(d.carga_horaria).replace('.', ',')} hora(s)</b>
          {d.presenca != null && d.funcao === 'PARTICIPANTE' ? ` e frequência de ${String(d.presenca).replace('.', ',')}%` : ''}.
        </p>
        <p className="mt-10 text-center text-[15px]">Maringá, {fmtDate(d.emitido_em)}.</p>
        <footer className="mt-10 rounded-2xl bg-slate-50 p-4 text-[12.5px] leading-relaxed text-ink-2 print:bg-white print:ring-1 print:ring-line">
          <div className="flex items-center gap-2 font-semibold"><ShieldCheck className="size-4 text-green-700" />Certificado emitido eletronicamente pelo IARA Educa.</div>
          <div className="mt-1">Confira a autenticidade em <b>{url.replace(/^https?:\/\//, '')}</b> ou pelo QR code, com o código <b className="font-mono text-[13.5px]">{d.codigo}</b> · resumo de integridade {d.hash}</div>
        </footer>
      </article>
    </div>
  );
}
