import { useEffect, useState } from 'react';
import clsx from 'clsx';
import { Fingerprint, MapPin, ShieldCheck, Smartphone, Trash2 } from 'lucide-react';
import { useNow, useRpc, useRpcMutation } from '@/lib/hooks';
import { pontoCadastrar, pontoMarcar, pontoOpcoes } from '@/lib/api';
import { biometriaDisponivel, criarCredencial, usarCredencial } from '@/lib/webauthn';
import { fmtDate, fmtDateTime } from '@/lib/format';
import { FUNCAO_SERVIDOR } from '@/lib/escola';
import { Badge, Button, Card, ErrorState, Field, PageHeader, Section, SkeletonList, inputCls } from '@/components/ui';
import { Sheet } from '@/components/overlays';

export type DiaPonto = {
  data: string; util: boolean; minutos: number; previstos: number; atraso_min: number | null; fora: boolean;
  situacao: 'OK' | 'ATRASO' | 'FALTA' | 'INCOMPLETO' | 'TRABALHANDO' | 'AGUARDANDO' | 'ABONADO' | 'NAO_UTIL';
  marcacoes: { id: string; hora: string; tipo: 'ENTRADA' | 'SAIDA'; metodo: string; fora: boolean; distancia_m: number | null; motivo: string | null }[];
  justificativa: { id: string; tipo: string; descricao: string; situacao: 'PENDENTE' | 'ABONADA' | 'RECUSADA'; observacao: string | null } | null;
};
export type Espelho = {
  profissional: { id: string; nome: string; funcao: string; carga: number | null }; unidade: string; mes: string; fechado: boolean;
  jornada: { periodos: [string, string][]; minutos: number }; dias: DiaPonto[];
  totais: { minutos: number; previstos: number; saldo: number; dias_trabalhados: number; faltas: number; atrasos: number; incompletos: number; abonados: number };
};
type Eu = {
  profissional: { nome: string; funcao: string; cargo: string | null; carga: number | null };
  unidade: { id: number; nome: string; lat: number; lng: number }; jornada: Espelho['jornada']; raio_m: number;
  hoje: DiaPonto; proxima: 'ENTRADA' | 'SAIDA';
  credenciais: { id: string; aparelho: string | null; rp_id: string; criada_em: string; ultimo_uso_em: string | null }[];
};

export const SITUACAO_PONTO: Record<DiaPonto['situacao'], { rotulo: string; tom: 'green' | 'amber' | 'red' | 'gray' | 'blue' | 'purple' }> = {
  OK: { rotulo: 'Completo', tom: 'green' }, ATRASO: { rotulo: 'Atraso', tom: 'amber' }, FALTA: { rotulo: 'Falta', tom: 'red' },
  INCOMPLETO: { rotulo: 'Sem saída', tom: 'amber' }, TRABALHANDO: { rotulo: 'Em jornada', tom: 'blue' }, AGUARDANDO: { rotulo: 'Sem marcação', tom: 'gray' },
  ABONADO: { rotulo: 'Abonado', tom: 'purple' }, NAO_UTIL: { rotulo: '—', tom: 'gray' },
};
const MOTIVOS: Record<string, string> = {
  ESQUECIMENTO: 'Esqueci de marcar', ATESTADO: 'Atestado médico', SERVICO_EXTERNO: 'Serviço externo', FORMACAO: 'Formação', OUTRO: 'Outro motivo',
};
export const horas = (min: number) => `${min < 0 ? '−' : ''}${Math.floor(Math.abs(min) / 60)}h${String(Math.abs(min) % 60).padStart(2, '0')}`;
const mesDe = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;

function local(): Promise<{ lat: number; lng: number; precisao: number } | null> {
  if (!navigator.geolocation) return Promise.resolve(null);
  return new Promise((ok) => navigator.geolocation.getCurrentPosition(
    (p) => ok({ lat: p.coords.latitude, lng: p.coords.longitude, precisao: Math.round(p.coords.accuracy) }),
    () => ok(null), { enableHighAccuracy: true, timeout: 8000, maximumAge: 60_000 }));
}

/** Meu ponto: o(a) profissional bate o ponto com a biometria do próprio aparelho, vê o espelho do mês e justifica um dia. */
export default function MeuPonto() {
  const eu = useRpc<Eu>('ponto_eu', {});
  const agora = useNow(1000);
  const [temBio, setTemBio] = useState<boolean | null>(null);
  const [ocupado, setOcupado] = useState<'cadastro' | 'marcacao' | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [feito, setFeito] = useState<string | null>(null);
  const [mes, setMes] = useState(mesDe(new Date()));
  const esp = useRpc<Espelho>('ponto_espelho', { mes });
  const revogar = useRpcMutation('ponto_revogar', ['ponto_eu']);
  const [justificar, setJustificar] = useState<DiaPonto | null>(null);

  useEffect(() => { biometriaDisponivel().then(setTemBio); }, []);

  if (eu.isLoading) return <SkeletonList rows={5} />;
  if (eu.error) return <ErrorState error={eu.error} onRetry={() => eu.refetch()} />;
  const e = eu.data!;
  const aqui = e.credenciais.filter((c) => c.rp_id === location.hostname);

  async function cadastrar() {
    setErro(null); setFeito(null); setOcupado('cadastro');
    try {
      const op = await pontoOpcoes('CADASTRO');
      await pontoCadastrar(await criarCredencial(op));
      setFeito('Biometria deste aparelho cadastrada. Agora é só bater o ponto.');
      await eu.refetch();
    } catch (x) { setErro((x as Error).message); } finally { setOcupado(null); }
  }

  async function bater() {
    setErro(null); setFeito(null); setOcupado('marcacao');
    try {
      const [op, pos] = await Promise.all([pontoOpcoes('MARCACAO'), local()]);
      const r = await pontoMarcar({ resposta: await usarCredencial(op), lat: pos?.lat, lng: pos?.lng, precisao: pos?.precisao });
      if (r.repetida) setFeito(r.aviso ?? 'Marcação já registrada.');
      else setFeito(`${r.tipo === 'ENTRADA' ? 'Entrada' : 'Saída'} registrada às ${r.hora}.` +
        (r.sem_local ? ' Sem localização do aparelho.' : r.fora ? ` Atenção: ${r.distancia_m} m da unidade (fica sinalizado para a direção).` : ' Na unidade.'));
      await Promise.all([eu.refetch(), esp.refetch()]);
    } catch (x) { setErro((x as Error).message); } finally { setOcupado(null); }
  }

  const hoje = e.hoje;
  return (
    <div>
      <PageHeader eyebrow={e.unidade.nome} title="Meu ponto"
        subtitle="Bata o ponto com a biometria do seu aparelho (digital, rosto ou bloqueio de tela). A biometria não sai do aparelho: o IARA só confere a assinatura." />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1.3fr]">
        <div className="space-y-3">
          <Card className="p-4 text-center">
            <div className="font-display text-[44px] font-black leading-none tabular text-ink">
              {new Date(agora).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
            </div>
            <div className="mt-1 text-[13px] text-muted">{new Date(agora).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
            {temBio === false ? (
              <p className="mt-4 rounded-xl bg-amber-50 p-3 text-left text-[13px] text-amber-900">
                Este aparelho não tem biometria nem bloqueio de tela disponível para o navegador. Configure o bloqueio de tela (ou use o celular) — se não
                for possível, a direção lança a marcação com o motivo.
              </p>
            ) : aqui.length === 0 ? (
              <Button block className="mt-4" icon={Fingerprint} loading={ocupado === 'cadastro'} onClick={cadastrar}>Cadastrar a biometria deste aparelho</Button>
            ) : (
              <Button block size="lg" className="mt-4" icon={Fingerprint} loading={ocupado === 'marcacao'} onClick={bater}>
                Bater ponto · {e.proxima === 'ENTRADA' ? 'entrada' : 'saída'}
              </Button>
            )}
            {feito && <p role="status" className="mt-3 rounded-xl bg-green-50 p-2.5 text-[13px] font-semibold text-green-800">{feito}</p>}
            {erro && <p role="alert" className="mt-3 rounded-xl bg-red-50 p-2.5 text-[13px] font-semibold text-red-800">{erro}</p>}
            <p className="mt-3 flex items-start gap-1.5 text-left text-[12px] text-muted">
              <MapPin className="mt-0.5 size-3.5 shrink-0" />O local do aparelho é usado só para a distância até a unidade (até {e.raio_m} m conta como na unidade).
            </p>
          </Card>

          <Card className="p-4">
            <div className="flex items-center justify-between">
              <h2 className="font-display text-[16px] font-extrabold">Hoje</h2>
              <Badge tone={SITUACAO_PONTO[hoje.situacao].tom}>{SITUACAO_PONTO[hoje.situacao].rotulo}</Badge>
            </div>
            <p className="mt-1 text-[13px] text-muted">
              Jornada prevista: {e.jornada.periodos.map(([a, b]) => `${a}–${b}`).join(' e ')} ({horas(e.jornada.minutos)}) · {FUNCAO_SERVIDOR[e.profissional.funcao] ?? e.profissional.funcao}
            </p>
            <Marcas dia={hoje} />
            {hoje.minutos > 0 && <p className="mt-2 text-[13px] text-ink-2">Trabalhado até agora: <b>{horas(hoje.minutos)}</b></p>}
          </Card>

          <Section title="Biometrias cadastradas">
            {e.credenciais.length === 0 ? (
              <p className="text-[13px] text-muted">Nenhum aparelho cadastrado ainda.</p>
            ) : (
              <Card className="divide-y divide-line">
                {e.credenciais.map((c) => (
                  <div key={c.id} className="flex items-center gap-2 px-3 py-2.5">
                    <Smartphone className="size-4 shrink-0 text-purple-700" />
                    <div className="min-w-0 flex-1 text-[13px]">
                      <div className="font-semibold">{c.aparelho || 'Aparelho'}{c.rp_id !== location.hostname && <span className="font-normal text-muted"> · {c.rp_id}</span>}</div>
                      <div className="text-[12px] text-muted">Cadastrada em {fmtDate(c.criada_em)}{c.ultimo_uso_em ? ` · último uso ${fmtDateTime(c.ultimo_uso_em)}` : ''}</div>
                    </div>
                    <Button size="sm" variant="ghost" icon={Trash2} loading={revogar.isPending} aria-label="Remover esta biometria"
                      onClick={() => { if (confirm('Remover a biometria deste aparelho do seu ponto?')) revogar.mutate({ id: c.id }); }}>
                      <span className="sr-only">Remover</span>
                    </Button>
                  </div>
                ))}
              </Card>
            )}
            <p className="mt-2 flex items-start gap-1.5 text-[12px] text-muted"><ShieldCheck className="mt-0.5 size-3.5 shrink-0" />Trocou ou perdeu o aparelho? Remova a biometria dele aqui ou peça à direção.</p>
          </Section>
        </div>

        <EspelhoMes esp={esp} mes={mes} setMes={setMes} onJustificar={setJustificar} />
      </div>

      <Justificar dia={justificar} onClose={() => setJustificar(null)} />
    </div>
  );
}

export function Marcas({ dia }: { dia: DiaPonto }) {
  if (!dia.marcacoes.length) return <p className="mt-2 text-[13px] text-muted">Nenhuma marcação.</p>;
  return (
    <div className="mt-2 flex flex-wrap gap-1.5">
      {dia.marcacoes.map((m) => (
        <span key={m.id} title={m.motivo ?? undefined}
          className={clsx('rounded-lg px-2 py-1 text-[12px] ring-1', m.fora ? 'bg-amber-50 ring-amber-200' : 'bg-white ring-line')}>
          <b className="tabular">{m.hora}</b> {m.tipo === 'ENTRADA' ? 'entrada' : 'saída'}
          {m.metodo === 'AJUSTE_DIRECAO' && <span className="text-purple-700"> · ajuste</span>}
          {m.fora && <span className="text-amber-800"> · {m.distancia_m} m</span>}
        </span>
      ))}
    </div>
  );
}

export function EspelhoMes({ esp, mes, setMes, onJustificar }: {
  esp: { data?: Espelho; isLoading: boolean; error: any; refetch: () => unknown }; mes: string; setMes: (m: string) => void; onJustificar?: (d: DiaPonto) => void;
}) {
  const atual = mesDe(new Date());
  const anterior = mesDe(new Date(new Date().getFullYear(), new Date().getMonth() - 1, 1));
  const t = esp.data?.totais;
  return (
    <Section title="Espelho do mês" action={
      <select value={mes} onChange={(e) => setMes(e.target.value)} aria-label="Mês" className={clsx(inputCls, 'h-9 w-auto py-1 text-[13px]')}>
        <option value={atual}>Este mês</option>
        <option value={anterior}>Mês passado</option>
      </select>
    }>
      {esp.isLoading ? <SkeletonList rows={6} /> : esp.error ? <ErrorState error={esp.error} onRetry={() => esp.refetch()} /> : (
        <Card className="p-0">
          {t && (
            <div className="grid grid-cols-2 gap-2 border-b border-line p-3 text-[13px] sm:grid-cols-4">
              <div><div className="text-[18px] font-extrabold tabular">{horas(t.minutos)}</div><div className="text-muted">trabalhadas</div></div>
              <div><div className={clsx('text-[18px] font-extrabold tabular', t.saldo < 0 ? 'text-red-700' : 'text-green-700')}>{horas(t.saldo)}</div><div className="text-muted">saldo ({horas(t.previstos)} previstas)</div></div>
              <div><div className="text-[18px] font-extrabold tabular">{t.faltas}</div><div className="text-muted">faltas</div></div>
              <div><div className="text-[18px] font-extrabold tabular">{t.atrasos}</div><div className="text-muted">atrasos</div></div>
            </div>
          )}
          {esp.data?.fechado && <p className="border-b border-line bg-slate-50 px-3 py-2 text-[12px] font-semibold text-ink-2">Mês fechado pela direção.</p>}
          <ul className="divide-y divide-line">
            {[...(esp.data?.dias ?? [])].reverse().filter((d) => d.util || d.marcacoes.length).map((d) => (
              <li key={d.data} className="flex flex-wrap items-start gap-x-3 gap-y-1 px-3 py-2.5">
                <div className="w-20 shrink-0 text-[13px] font-semibold capitalize">
                  {new Date(d.data + 'T12:00:00').toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit' })}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge tone={SITUACAO_PONTO[d.situacao].tom}>{SITUACAO_PONTO[d.situacao].rotulo}{d.atraso_min ? ` ${d.atraso_min} min` : ''}</Badge>
                    {d.minutos > 0 && <span className="text-[12px] text-muted tabular">{horas(d.minutos)}</span>}
                    {d.justificativa && <span className="text-[12px] text-muted">· {MOTIVOS[d.justificativa.tipo] ?? d.justificativa.tipo}: {d.justificativa.situacao === 'PENDENTE' ? 'aguardando a direção' : d.justificativa.situacao === 'ABONADA' ? 'abonado' : 'recusado'}</span>}
                  </div>
                  {d.marcacoes.length > 0 && <Marcas dia={d} />}
                </div>
                {onJustificar && !esp.data?.fechado && ['FALTA', 'INCOMPLETO', 'ATRASO'].includes(d.situacao) && d.justificativa?.situacao !== 'PENDENTE' && (
                  <Button size="sm" variant="secondary" onClick={() => onJustificar(d)}>Justificar</Button>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </Section>
  );
}

function Justificar({ dia, onClose }: { dia: DiaPonto | null; onClose: () => void }) {
  const [tipo, setTipo] = useState('ESQUECIMENTO');
  const [texto, setTexto] = useState('');
  const m = useRpcMutation('ponto_justificar', ['ponto_espelho', 'ponto_eu']);
  useEffect(() => { setTexto(''); setTipo(dia?.situacao === 'FALTA' ? 'ATESTADO' : 'ESQUECIMENTO'); m.reset(); }, [dia?.data]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Sheet open={!!dia} onClose={onClose} title="Justificar o dia" subtitle={dia ? fmtDate(dia.data) : undefined} size="sm"
      footer={<Button block loading={m.isPending} disabled={texto.trim().length < 5}
        onClick={() => m.mutate({ data: dia!.data, tipo, descricao: texto }, { onSuccess: onClose })}>Enviar para a direção</Button>}>
      <div className="space-y-3">
        <Field label="Motivo">
          <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={inputCls}>
            {Object.entries(MOTIVOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
        <Field label="O que houve" hint="A direção da unidade vê e decide se abona.">
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={500} className={inputCls} />
        </Field>
        {m.error && <p role="alert" className="text-[13px] font-semibold text-red-700">{m.error.message}</p>}
      </div>
    </Sheet>
  );
}
