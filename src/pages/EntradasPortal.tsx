import { useEffect, useState, type FormEvent } from 'react';
import clsx from 'clsx';
import { Ban, KeyRound, LockKeyhole, LogIn, LogOut, ShieldAlert, ShieldCheck, ShieldX, Sparkles, UserRound } from 'lucide-react';
import { useNow, useRpc, useRpcMutation } from '@/lib/hooks';
import { acessoSituacao } from '@/lib/api';
import { fmtDateTime, fmtInt, fmtTime, timeAgo } from '@/lib/format';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, PageHeader, SkeletonList } from '@/components/ui';

type Evento = 'SENHA_CERTA' | 'SENHA_ERRADA' | 'TENTATIVAS_DEMAIS' | 'BARRADO' | 'PERFIL_ABERTO' | 'ORACULO_MCP';
type Item = {
  id: number; em: string; ultimo_em: string; evento: Evento; n: number; perfil: string | null; detalhe: string | null; ip: string | null;
  pais: string | null; estado: string | null; cidade: string | null; provedor: string | null; aparelho: string | null; perfis: string[] | null;
};
type Dados = {
  dias: number; resumo: Partial<Record<Evento, number>>; itens: Item[]; guardado_desde: string | null;
  base_local: { fonte: string; versao: string; carregada_em: string } | null;
};

const EVENTO: Record<Evento, { label: string; tone: Tone; icon: typeof LogIn }> = {
  SENHA_CERTA: { label: 'Senha certa', tone: 'green', icon: KeyRound },
  SENHA_ERRADA: { label: 'Senha errada', tone: 'red', icon: ShieldX },
  TENTATIVAS_DEMAIS: { label: 'Tentativas demais', tone: 'red', icon: ShieldAlert },
  BARRADO: { label: 'Barrado sem senha', tone: 'amber', icon: Ban },
  PERFIL_ABERTO: { label: 'Perfil aberto', tone: 'blue', icon: UserRound },
  ORACULO_MCP: { label: 'Oráculo pelo Claude', tone: 'purple', icon: Sparkles },
};
const PERIODOS = [{ dias: 1, label: 'Hoje' }, { dias: 7, label: '7 dias' }, { dias: 30, label: '30 dias' }, { dias: 183, label: '6 meses' }];

/** Registro de entradas no portal (099.22): quando, de onde e de que aparelho o portal foi aberto. Só o titular vê. */
export default function EntradasPortal() {
  const [dias, setDias] = useState(7);
  const res = useRpc<Dados>('acesso_entradas', { dias }, { staleTime: 60_000, refetchOnWindowFocus: false, retry: false });
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error?.status === 403) return <Bloqueio onEntrou={() => res.refetch()} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return <Registro d={res.data!} dias={dias} setDias={setDias} atualizar={() => res.refetch()} atualizando={res.isFetching} />;
}

/** Senha do titular. Só recarrega o registro quando a senha confere: recarregar depois de um erro desmontava o formulário e o aviso sumia. */
function Bloqueio({ onEntrou }: { onEntrou: () => void }) {
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const entrar = useRpcMutation<{ senha: string }, { ok: boolean; erro?: string; restantes?: number }>('acesso_entradas_entrar');
  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setErro(null);
    try {
      const r = await entrar.mutateAsync({ senha });
      if (r.ok) { onEntrou(); return; }
      setErro(`${r.erro ?? 'Senha incorreta.'}${r.restantes != null && r.restantes > 0 ? ` Restam ${r.restantes} tentativa(s).` : ''}`);
    } catch (err) {
      setErro(err instanceof Error ? err.message : 'Não foi possível entrar.');
    }
    setSenha('');
  };
  return (
    <div className="mx-auto max-w-md py-10">
      <Card className="p-6">
        <div className="flex items-center gap-3">
          <span className="inline-flex size-12 items-center justify-center rounded-2xl bg-purple-100 text-purple-800"><LockKeyhole className="size-6" /></span>
          <div>
            <h1 className="font-display text-xl font-extrabold">Entradas no portal</h1>
            <p className="text-[13px] text-muted">Só para o titular: entre com a senha do titular.</p>
          </div>
        </div>
        <form onSubmit={enviar} className="mt-5 space-y-3">
          <label className="block">
            <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Senha do titular</span>
            {/* sem preenchimento automático: o navegador punha aqui a senha salva do portal ou do comercial */}
            <input type="password" name="senha-titular" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} autoFocus
              className="h-12 w-full rounded-2xl bg-white px-4 text-[16px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500" />
          </label>
          {erro && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">{erro}</p>}
          <Button type="submit" block loading={entrar.isPending} disabled={!senha}>Entrar</Button>
        </form>
        <p className="mt-4 text-[12px] text-subtle">
          É a senha do <b>titular</b> do simulador de preços (a do “Acesso do titular”). Não é a senha de entrada do portal nem a do comercial.
          Fica liberado nesta sessão por 8 horas.
        </p>
      </Card>
    </div>
  );
}

function Registro({ d, dias, setDias, atualizar, atualizando }: { d: Dados; dias: number; setDias: (n: number) => void; atualizar: () => void; atualizando: boolean }) {
  const now = useNow(60_000);
  const [ligada, setLigada] = useState<boolean | null>(null);
  const [filtro, setFiltro] = useState<Evento | 'TODOS'>('TODOS');
  const sair = useRpcMutation('acesso_entradas_sair', ['acesso_entradas']);
  useEffect(() => { acessoSituacao().then((r) => setLigada(r.ativo)).catch(() => setLigada(null)); }, []);
  const itens = filtro === 'TODOS' ? d.itens : d.itens.filter((i) => i.evento === filtro);
  const r = d.resumo ?? {};
  return (
    <div>
      <PageHeader
        eyebrow="Controle e transparência"
        title="Entradas no portal"
        subtitle="Quando, de onde e de que aparelho o portal foi aberto. A senha de acesso é a mesma para todos: o registro mostra quando e de onde, não quem."
        actions={<Button variant="secondary" size="sm" icon={LogOut} onClick={() => sair.mutate({})} loading={sair.isPending}>Fechar</Button>}
      />
      <div className={clsx('mb-3 flex items-start gap-2 rounded-2xl px-3 py-2 text-[13px] ring-1',
        ligada === false ? 'bg-amber-50 text-amber-900 ring-amber-100' : 'bg-green-50 text-green-900 ring-green-100')}>
        {ligada === false ? <ShieldAlert className="mt-0.5 size-4 shrink-0" /> : <ShieldCheck className="mt-0.5 size-4 shrink-0" />}
        <span>{ligada === false ? 'A senha de acesso está desligada: o portal abre sem senha.' : ligada ? 'A senha de acesso está ligada: o portal pede a senha a cada abertura.' : 'Conferindo a senha de acesso…'}</span>
      </div>

      <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 pb-1">
        {PERIODOS.map((p) => <Chip key={p.dias} active={dias === p.dias} onClick={() => setDias(p.dias)}>{p.label}</Chip>)}
        <button type="button" onClick={atualizar} disabled={atualizando} className="ml-auto shrink-0 text-[13px] font-semibold text-purple-700 disabled:opacity-50">Atualizar</button>
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        {(Object.keys(EVENTO) as Evento[]).map((k) => {
          const e = EVENTO[k];
          const ativo = filtro === k;
          return (
            <button key={k} type="button" onClick={() => setFiltro(ativo ? 'TODOS' : k)} aria-pressed={ativo}
              className={clsx('rounded-2xl bg-white px-3 py-2 text-left ring-1 transition hover:shadow-soft', ativo ? 'ring-2 ring-purple-500' : 'ring-line')}>
              <div className="flex items-center gap-1.5 text-[12px] text-muted"><e.icon className="size-3.5" />{e.label}</div>
              <div className={clsx('font-display text-xl font-extrabold tabular', (k === 'SENHA_ERRADA' || k === 'TENTATIVAS_DEMAIS') && (r[k] ?? 0) > 0 && 'text-red-700')}>{fmtInt(r[k] ?? 0)}</div>
            </button>
          );
        })}
      </div>

      <div className="mt-3 text-[13px] text-muted">
        {itens.length ? `${fmtInt(itens.length)} registro(s)${d.itens.length >= 500 ? ' (os 500 mais recentes)' : ''}` : ''}
        {filtro !== 'TODOS' && <button type="button" onClick={() => setFiltro('TODOS')} className="ml-2 font-semibold text-purple-700">Ver todos</button>}
      </div>
      <Card className="mt-2 overflow-hidden">
        {!itens.length ? (
          <EmptyState compact title="Nenhuma entrada neste período" body={filtro === 'TODOS' ? 'Ninguém abriu o portal nem usou o Oráculo pela conexão permanente.' : 'Nada deste tipo no período.'} />
        ) : (
          <ul className="divide-y divide-line">{itens.map((i) => <Linha key={i.id} i={i} now={now} />)}</ul>
        )}
      </Card>

      <p className="mt-3 text-[12px] text-subtle">
        Localização aproximada pelo endereço de internet (IP): é a do provedor, e no celular pode aparecer outra cidade. No Oráculo pelo Claude, o lugar é o do servidor do Claude, não o de quem pergunta.
        {' '}Guardado por 6 meses{d.guardado_desde ? `, desde ${fmtDateTime(d.guardado_desde)}` : ''}.
        {' '}<a href="https://db-ip.com" target="_blank" rel="noopener noreferrer" className="underline">IP Geolocation by DB-IP</a>{d.base_local ? ` (base de ${d.base_local.versao})` : ''}.
      </p>
    </div>
  );
}

const regiao = (() => {
  try { return new Intl.DisplayNames(['pt-BR'], { type: 'region' }); } catch { return null; }
})();
function lugar(i: Item): string {
  if (i.pais === 'BR' || (!i.pais && i.cidade)) return [i.cidade, i.estado].filter(Boolean).join('-') || 'Brasil';
  if (i.pais) return regiao?.of(i.pais) ?? i.pais;
  return 'Local desconhecido';
}

/** Sistema e navegador a partir do aparelho informado pelo navegador (user-agent). */
function aparelho(ua: string | null): string {
  if (!ua) return 'Aparelho desconhecido';
  if (/^Claude-User/i.test(ua)) return 'Claude';
  if (/WindowsPowerShell/i.test(ua)) return 'PowerShell';
  if (/^curl\//i.test(ua)) return 'curl';
  if (/^node$/i.test(ua)) return 'Script (node)';
  const so = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android' : /CrOS/.test(ua) ? 'Chromebook'
    : /Windows/.test(ua) ? 'Windows' : /Macintosh|Mac OS X/.test(ua) ? 'Mac' : /Linux/.test(ua) ? 'Linux' : null;
  const nav = /Edg\//.test(ua) ? 'Edge' : /OPR\/|Opera/.test(ua) ? 'Opera' : /SamsungBrowser/.test(ua) ? 'Samsung Internet' : /Firefox\//.test(ua) ? 'Firefox'
    : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : null;
  return [so, nav].filter(Boolean).join(' · ') || ua.slice(0, 40);
}

function Linha({ i, now }: { i: Item; now: number }) {
  const e = EVENTO[i.evento] ?? EVENTO.PERFIL_ABERTO;
  const oque = i.evento === 'PERFIL_ABERTO' ? `${i.perfil ?? 'Perfil'}${i.detalhe ? ` · ${i.detalhe}` : ''}`
    : i.evento === 'ORACULO_MCP' ? `${i.detalhe ?? 'Conexão'} · ${fmtInt(i.n)} consulta(s)${i.n > 1 ? ` até ${fmtTime(i.ultimo_em)}` : ''}`
    : i.evento === 'SENHA_CERTA' ? (i.perfis?.length ? `Abriu: ${i.perfis.join(', ')}` : 'Não abriu perfil')
    : i.n > 1 ? `${fmtInt(i.n)} vezes até ${fmtTime(i.ultimo_em)}` : null;
  return (
    // uma linha por registro na tela larga; abaixo disso, quebra e o "o que houve" ganha a linha inteira
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5 text-[13.5px] xl:flex-nowrap">
      <span className="w-[7.5rem] shrink-0 tabular text-ink-2" title={timeAgo(i.em, now)}>{fmtDateTime(i.em)}</span>
      <Badge tone={e.tone} icon={e.icon} className="shrink-0">{e.label}</Badge>
      <span className="min-w-0 shrink-0 font-semibold xl:w-40 xl:truncate">{lugar(i)}</span>
      <span className="min-w-0 truncate text-muted xl:w-44" title={i.provedor ?? undefined}>{i.provedor ?? '—'}</span>
      <span className="shrink-0 text-muted xl:w-32">{aparelho(i.aparelho)}</span>
      {oque && <span className="min-w-0 basis-full truncate text-ink-2 xl:basis-auto xl:flex-1" title={oque}>{oque}</span>}
      <span className="ml-auto shrink-0 font-mono text-[11.5px] text-subtle">{i.ip ?? ''}</span>
    </li>
  );
}
