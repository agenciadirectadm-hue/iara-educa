import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, NavLink, Outlet, useLocation, useMatches, useNavigate } from 'react-router';
import { AnimatePresence, motion } from 'motion/react';
import clsx from 'clsx';
import {
  Building2, ChevronRight, ClipboardList, GraduationCap, LayoutGrid, LogOut, Play, RotateCcw, Search, ShieldCheck, UserRound, Users, X,
} from 'lucide-react';
import { useSession } from '@/lib/session';
import { useDebounced, useRpc } from '@/lib/hooks';
import { rpc } from '@/lib/api';
import { navFor, type NavItem } from './nav';
import { Avatar, Badge, Spinner } from '@/components/ui';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { IaraAvatar } from '@/components/iara';

function isActive(item: NavItem, pathname: string, search: string) {
  const target = item.match ?? item.to.split('?')[0];
  if (target === '/inicio') return pathname === '/inicio';
  if (item.to.includes('?aba=') && pathname === item.to.split('?')[0]) return search.includes(item.to.split('?')[1]);
  return pathname === target || pathname.startsWith(target + '/');
}

export function AppShell() {
  const { me } = useSession();
  const loc = useLocation();
  const matches = useMatches();
  const full = matches.some((m) => (m.handle as { full?: boolean } | undefined)?.full);
  const nav = useMemo(() => navFor(me), [me]);
  const [more, setMore] = useState(false);
  const [account, setAccount] = useState(false);
  const [search, setSearch] = useState(false);

  useEffect(() => {
    setMore(false);
    setSearch(false);
    window.scrollTo({ top: 0 });
  }, [loc.pathname]);

  return (
    <div className="min-h-dvh bg-iara">
      <a href="#conteudo" className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-[100] focus:rounded-xl focus:bg-white focus:px-4 focus:py-2 focus:shadow-lift">
        Pular para o conteúdo
      </a>
      <SideRail nav={nav} onAccount={() => setAccount(true)} />
      <div className="lg:pl-[256px]">
        <TopBar onSearch={() => setSearch(true)} onAccount={() => setAccount(true)} full={full} />
        <main id="conteudo" className={clsx(full ? '' : 'mx-auto w-full max-w-6xl px-4 pb-32 pt-3 sm:px-6 lg:pb-12')}>
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={loc.pathname}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.18, ease: [0.22, 1, 0.36, 1] }}
            >
              <Outlet />
            </motion.div>
          </AnimatePresence>
        </main>
      </div>
      <BottomNav nav={nav} onMore={() => setMore(true)} />
      <MoreSheet open={more} onClose={() => setMore(false)} items={nav.more} />
      <AccountSheet open={account} onClose={() => setAccount(false)} />
      <SearchSheet open={search} onClose={() => setSearch(false)} />
    </div>
  );
}

function Brand({ compact }: { compact?: boolean }) {
  return (
    <Link to="/inicio" className="flex items-center gap-2.5" aria-label="IARA Educa — início">
      <IaraAvatar size={compact ? 36 : 40} />
      <div className="whitespace-nowrap leading-none">
        <div className="font-display text-[19px] font-black tracking-tight">
          <span className="text-purple-700">IARA</span> <span className="text-blue-900">Educa</span>
        </div>
        <div className="mt-0.5 text-[10.5px] font-semibold uppercase tracking-[0.14em] text-muted">SEDUC · Maringá</div>
      </div>
    </Link>
  );
}

function TopBar({ onSearch, onAccount, full }: { onSearch: () => void; onAccount: () => void; full: boolean }) {
  const { me } = useSession();
  return (
    <div className={clsx('sticky top-0 z-40 pt-safe', full ? 'glass border-b border-white/60' : 'glass border-b border-line/60')}>
      <div className="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4 sm:px-6">
        <div className="lg:hidden">
          <Brand compact />
        </div>
        <button
          onClick={onSearch}
          className="ml-auto hidden h-11 flex-1 items-center gap-2 rounded-2xl bg-white/90 px-4 text-left text-[14px] text-subtle ring-1 ring-line transition hover:ring-purple-300 md:flex lg:ml-0 lg:max-w-xl"
        >
          <Search className="size-[18px]" aria-hidden />
          Buscar aluno, unidade, protocolo, responsável…
        </button>
        <div className="ml-auto flex items-center gap-2 md:ml-0">
          <span className="hidden sm:block"><Badge tone="amber">Demonstração</Badge></span>
          <button onClick={onSearch} className="inline-flex size-11 items-center justify-center rounded-2xl bg-white/90 ring-1 ring-line md:hidden" aria-label="Buscar">
            <Search className="size-5" aria-hidden />
          </button>
          <button onClick={onAccount} className="flex items-center gap-2 rounded-2xl bg-white/90 py-1 pl-1 pr-3 ring-1 ring-line transition hover:ring-purple-300" aria-label="Perfil e opções">
            {me ? <Avatar name={me.display_name} seed={me.role} size={36} /> : <span className="inline-flex size-9 items-center justify-center rounded-full bg-slate-100"><UserRound className="size-5" /></span>}
            <span className="hidden max-w-[150px] truncate text-[13px] font-semibold sm:block">{me?.role_short ?? 'Visitante'}</span>
          </button>
        </div>
      </div>
    </div>
  );
}

function SideRail({ nav, onAccount }: { nav: { primary: NavItem[]; more: NavItem[] }; onAccount: () => void }) {
  const { me } = useSession();
  const loc = useLocation();
  return (
    <aside className="fixed inset-y-0 left-0 z-50 hidden w-[256px] flex-col border-r border-line/70 bg-white/80 backdrop-blur-xl lg:flex">
      <div className="px-5 pb-4 pt-5">
        <Brand />
      </div>
      <nav className="flex-1 space-y-0.5 overflow-y-auto px-3" aria-label="Navegação principal">
        {[...nav.primary, ...nav.more].map((item) => {
          const active = isActive(item, loc.pathname, loc.search);
          return (
            <NavLink
              key={item.to + item.label}
              to={item.to}
              className={clsx('relative flex h-11 items-center gap-3 rounded-2xl px-3 text-[14.5px] font-semibold transition', active ? 'text-purple-800' : 'text-ink-2 hover:bg-slate-100')}
            >
              {active && <motion.span layoutId="rail-active" className="absolute inset-0 rounded-2xl bg-purple-100" transition={{ type: 'spring', stiffness: 420, damping: 36 }} />}
              <item.icon className="relative size-5" />
              <span className="relative">{item.label}</span>
            </NavLink>
          );
        })}
      </nav>
      <button onClick={onAccount} className="m-3 flex items-center gap-3 rounded-2xl bg-slate-50 p-3 text-left ring-1 ring-line hover:bg-purple-50">
        {me && <Avatar name={me.display_name} seed={me.role} size={38} />}
        <div className="min-w-0">
          <div className="truncate text-[13px] font-bold">{me?.role_name ?? 'Visitante'}</div>
          <div className="truncate text-[11.5px] text-muted">{me?.unit?.name ?? me?.org_unit ?? 'Escolha um perfil'}</div>
        </div>
      </button>
    </aside>
  );
}

function BottomNav({ nav, onMore }: { nav: { primary: NavItem[]; more: NavItem[] }; onMore: () => void }) {
  const loc = useLocation();
  return (
    <nav className="glass fixed inset-x-0 bottom-0 z-40 border-t border-line/70 pb-safe lg:hidden" aria-label="Navegação principal">
      <div className="mx-auto grid h-[66px] max-w-xl grid-cols-5">
        {nav.primary.map((item) => {
          const active = isActive(item, loc.pathname, loc.search);
          return (
            <NavLink key={item.to + item.label} to={item.to} className="relative flex flex-col items-center justify-center gap-1" aria-current={active ? 'page' : undefined}>
              {active && <motion.span layoutId="bottom-active" className="absolute top-1.5 h-8 w-14 rounded-full bg-purple-100" transition={{ type: 'spring', stiffness: 420, damping: 34 }} />}
              <item.icon className={clsx('relative size-[22px]', active ? 'text-purple-800' : 'text-ink-2')} />
              <span className={clsx('relative text-[11px] font-semibold leading-none', active ? 'text-purple-800' : 'text-muted')}>{item.label}</span>
            </NavLink>
          );
        })}
        <button onClick={onMore} className="flex flex-col items-center justify-center gap-1" aria-label="Mais opções">
          <LayoutGrid className="size-[22px] text-ink-2" />
          <span className="text-[11px] font-semibold leading-none text-muted">Mais</span>
        </button>
      </div>
    </nav>
  );
}

function MoreSheet({ open, onClose, items }: { open: boolean; onClose: () => void; items: NavItem[] }) {
  return (
    <Sheet open={open} onClose={onClose} title="Mais opções">
      <div className="grid grid-cols-3 gap-3 pt-1">
        {items.map((it) => (
          <Link key={it.to + it.label} to={it.to} onClick={onClose} className="flex flex-col items-center gap-2 rounded-3xl bg-slate-50 p-3 text-center ring-1 ring-line transition active:scale-95 hover:bg-purple-50">
            <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-white text-purple-700 shadow-soft">
              <it.icon className="size-5" />
            </span>
            <span className="text-[12.5px] font-semibold leading-tight">{it.label}</span>
          </Link>
        ))}
      </div>
    </Sheet>
  );
}

function AccountSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { me, logout } = useSession();
  const navigate = useNavigate();
  const toast = useToast();
  const confirm = useConfirm();
  const [busy, setBusy] = useState(false);
  return (
    <Sheet open={open} onClose={onClose} title="Seu perfil" subtitle="Ambiente de demonstração — dados pessoais fictícios">
      {me ? (
        <div className="space-y-4">
          <div className="flex items-center gap-3 rounded-3xl bg-gradient-to-br from-purple-50 to-blue-50 p-4 ring-1 ring-purple-100">
            <Avatar name={me.display_name} seed={me.role} size={52} />
            <div className="min-w-0">
              <div className="font-display text-lg font-extrabold leading-tight">{me.role_name}</div>
              <div className="truncate text-[13px] text-muted">{me.display_name}</div>
              <div className="mt-1 text-[13px] italic text-purple-800">“{me.question}”</div>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-2 text-[13px]">
            <div className="rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
              <div className="text-[11px] font-bold uppercase tracking-wide text-subtle">Escopo</div>
              <div className="font-semibold">{{ AGGREGATE: 'Cidade (agregado)', NETWORK: 'Rede inteira', UNIT: 'Somente a unidade', GUARDIAN: 'Minhas crianças' }[me.scope]}</div>
            </div>
            <div className="rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
              <div className="text-[11px] font-bold uppercase tracking-wide text-subtle">Permissões</div>
              <div className="font-semibold">{me.permissions.length} ações autorizadas</div>
            </div>
          </div>
          <div className="divide-y divide-line overflow-hidden rounded-3xl bg-white ring-1 ring-line">
            <AccountRow icon={Users} label="Trocar de perfil" onClick={() => { onClose(); navigate('/entrar'); }} />
            <AccountRow icon={Play} label="Rever a abertura animada" onClick={() => { onClose(); navigate('/abertura'); }} />
            <AccountRow icon={ShieldCheck} label="Sobre os dados e as fontes" onClick={() => { onClose(); navigate('/ajuda'); }} />
            <AccountRow
              icon={RotateCcw}
              label={busy ? 'Reiniciando…' : 'Reiniciar cenário do cidadão (Maria · Davi)'}
              onClick={async () => {
                const ok = await confirm({ title: 'Reiniciar cenário?', body: 'Devolve a família fictícia da Maria ao estado original (membros, endereço, declarações) e o Davi à fila em 1º lugar. Tudo fica registrado na auditoria.', confirm: 'Reiniciar', tone: 'purple' });
                if (!ok) return;
                setBusy(true);
                try {
                  const r = await rpc<{ posicao_davi: number }>('demo_reset_citizen');
                  toast({ title: 'Cenário reiniciado', description: `Davi está na posição ${r.posicao_davi} da fila.`, tone: 'success' });
                } catch (e) {
                  toast({ title: 'Não foi possível reiniciar', description: (e as Error).message, tone: 'error' });
                } finally {
                  setBusy(false);
                }
              }}
            />
            <AccountRow icon={LogOut} label="Sair" danger onClick={async () => { await logout(); onClose(); navigate('/entrar'); }} />
          </div>
        </div>
      ) : (
        <Link to="/entrar" onClick={onClose} className="flex h-14 items-center justify-center rounded-2xl bg-purple-700 font-semibold text-white">
          Escolher um perfil
        </Link>
      )}
    </Sheet>
  );
}

function AccountRow({ icon: I, label, onClick, danger }: { icon: typeof Users; label: string; onClick: () => void; danger?: boolean }) {
  return (
    <button onClick={onClick} className={clsx('flex h-14 w-full items-center gap-3 px-4 text-left text-[15px] font-semibold hover:bg-slate-50', danger && 'text-red-700')}>
      <I className="size-5" />
      <span className="flex-1">{label}</span>
      <ChevronRight className="size-4 text-subtle" />
    </button>
  );
}

const GROUPS: { key: string; label: string; icon: typeof Users; path: (id: string) => string }[] = [
  { key: 'students', label: 'Alunos', icon: GraduationCap, path: (id) => `/alunos/${id}` },
  { key: 'guardians', label: 'Responsáveis', icon: Users, path: (id) => `/responsaveis/${id}` },
  { key: 'units', label: 'Unidades', icon: Building2, path: (id) => `/unidades/${id}` },
  { key: 'classes', label: 'Turmas', icon: LayoutGrid, path: (id) => `/turmas/${id}` },
  { key: 'cases', label: 'Protocolos', icon: ClipboardList, path: (id) => `/atendimentos/${id}` },
];

function SearchSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { me } = useSession();
  const [q, setQ] = useState('');
  const dq = useDebounced(q.trim(), 280);
  const navigate = useNavigate();
  const inputRef = useRef<HTMLInputElement>(null);
  const authed = !!me && me.scope !== 'GUARDIAN';
  const res = useRpc<any>(authed ? 'global_search' : 'units_list', authed ? { q: dq } : { q: dq }, { enabled: open && dq.length >= 2 });
  useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 80);
    else setQ('');
  }, [open]);
  const data = res.data;
  const groups = authed ? data : data ? { units: (data.items ?? []).slice(0, 10).map((u: any) => ({ id: u.id, name: u.name, sub: u.neighborhood })) } : null;
  const total = groups ? GROUPS.reduce((a, g) => a + ((groups as any)[g.key]?.length ?? 0), 0) : 0;
  return (
    <Sheet open={open} onClose={onClose} title="Busca global" subtitle="Os resultados respeitam as permissões do seu perfil">
      <div className="sticky top-0 z-10 -mx-5 bg-white px-5 pb-3">
        <div className="flex h-12 items-center gap-2 rounded-2xl bg-slate-50 px-4 ring-1 ring-line focus-within:ring-2 focus-within:ring-purple-500">
          <Search className="size-5 text-subtle" />
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={authed ? 'Nome, matrícula, protocolo, CPF, telefone…' : 'Nome da unidade ou bairro…'}
            className="h-full flex-1 bg-transparent text-[15px] outline-none"
            aria-label="Termo de busca"
          />
          {q && (
            <button onClick={() => setQ('')} aria-label="Limpar busca">
              <X className="size-5 text-subtle" />
            </button>
          )}
        </div>
      </div>
      {dq.length < 2 ? (
        <p className="py-6 text-center text-sm text-muted">Digite pelo menos 2 letras.</p>
      ) : res.isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : total === 0 ? (
        <p className="py-6 text-center text-sm text-muted">Nada encontrado para “{dq}” no seu escopo.</p>
      ) : (
        <div className="space-y-4">
          {GROUPS.map((g) => {
            const items = (groups as any)?.[g.key] as any[] | undefined;
            if (!items?.length) return null;
            return (
              <div key={g.key}>
                <div className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wide text-subtle">
                  <g.icon className="size-4" /> {g.label}
                </div>
                <div className="overflow-hidden rounded-2xl ring-1 ring-line">
                  {items.map((it) => (
                    <button key={it.id} onClick={() => { onClose(); navigate(g.path(it.id)); }} className="flex w-full items-center gap-3 border-b border-line px-4 py-3 text-left last:border-0 hover:bg-purple-50">
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[15px] font-semibold">{it.name}</div>
                        {it.sub && <div className="truncate text-[12.5px] text-muted">{it.sub}</div>}
                      </div>
                      <ChevronRight className="size-4 text-subtle" />
                    </button>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Sheet>
  );
}
