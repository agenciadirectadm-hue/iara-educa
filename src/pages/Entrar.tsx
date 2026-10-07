import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router';
import { motion } from 'motion/react';
import clsx from 'clsx';
import { Accessibility, Apple, Baby, BarChart3, BookOpen, Building2, ChevronRight, Crown, Database, Headset, Landmark, MapPin, Plane, Scale, Search, ShieldCheck, Sparkles, UserRound, Users, Wrench } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import type { Bootstrap, Persona, Role } from '@/lib/types';
import { avisoMensagens } from '@/lib/avisos';
import { Sheet, useToast } from '@/components/overlays';
import { IaraBubble, IaraMascot } from '@/components/iara';
import { Badge, Skeleton, inputCls } from '@/components/ui';
import { fmtInt } from '@/lib/format';
import { WhatsAppCard } from '@/components/whatsapp';

const ICON: Record<Role, typeof Crown> = {
  PREFEITO: Landmark, SECRETARIO: Crown, SUPERINTENDENCIA: BarChart3, ANALISTA_CENTRAL: Search, GERENCIA_EI: Baby,
  DIRETOR_UNIDADE: Building2, SECRETARIA_ESCOLAR: Users, ATENDIMENTO: Headset, INOVACAO: Database, CIDADAO: UserRound, CIDADAO_NOVO: Plane,
  CONTROLE_EXTERNO: Scale, PROFESSOR: BookOpen, NUTRICAO: Apple, MANUTENCAO: Wrench, PROFESSOR_AEE: Accessibility,
};
const GRAD: Record<Role, string> = {
  PREFEITO: 'from-blue-700 to-blue-900', SECRETARIO: 'from-purple-500 to-purple-800', SUPERINTENDENCIA: 'from-indigo-500 to-blue-800',
  ANALISTA_CENTRAL: 'from-teal-500 to-green-700', GERENCIA_EI: 'from-fuchsia-500 to-purple-700', DIRETOR_UNIDADE: 'from-orange-400 to-rose-500',
  SECRETARIA_ESCOLAR: 'from-sky-500 to-blue-700', ATENDIMENTO: 'from-emerald-500 to-teal-700', INOVACAO: 'from-slate-500 to-slate-800',
  CIDADAO: 'from-purple-500 to-pink-500', CIDADAO_NOVO: 'from-amber-400 to-pink-500', CONTROLE_EXTERNO: 'from-slate-700 to-indigo-900',
  PROFESSOR: 'from-emerald-500 to-teal-700', NUTRICAO: 'from-lime-500 to-green-700', MANUTENCAO: 'from-amber-500 to-orange-700',
  PROFESSOR_AEE: 'from-violet-500 to-indigo-700',
};
const SCOPE: Record<string, string> = { AGGREGATE: 'Visão agregada', NETWORK: 'Rede inteira', UNIT: 'Uma unidade', GUARDIAN: 'Minha família' };
const FEATURED: Role[] = ['CIDADAO', 'CIDADAO_NOVO', 'PREFEITO', 'SECRETARIO', 'CONTROLE_EXTERNO', 'ANALISTA_CENTRAL', 'DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'PROFESSOR'];

export default function Entrar() {
  const boot = useRpc<Bootstrap>('bootstrap', {}, { staleTime: 5 * 60_000 });
  const { login } = useSession();
  const navigate = useNavigate();
  const toast = useToast();
  const [busy, setBusy] = useState<Role | null>(null);
  const [unitFor, setUnitFor] = useState<Persona | null>(null);
  const personas = boot.data?.personas ?? [];
  const featured = useMemo(() => FEATURED.map((c) => personas.find((p) => p.code === c)).filter(Boolean) as Persona[], [personas]);
  const others = personas.filter((p) => !FEATURED.includes(p.code));

  const enter = async (p: Persona, unitId?: number) => {
    if (p.scope_type === 'UNIT' && unitId == null) {
      setUnitFor(p);
      return;
    }
    setBusy(p.code);
    try {
      await login(p.code, unitId ?? null);
      navigate('/inicio', { replace: true });
    } catch (e) {
      toast({ title: 'Não foi possível entrar', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };

  const k = boot.data?.kpis;
  return (
    <div className="min-h-dvh bg-iara pt-safe pb-safe">
      <div className="mx-auto max-w-5xl px-4 pb-12 pt-6 sm:px-6">
        <div className="grid grid-cols-1 items-center gap-6 md:grid-cols-[1.2fr_1fr]">
          <div>
            <Badge tone="amber">Ambiente de demonstração</Badge>
            <h1 className="mt-3 font-display text-[34px] font-black leading-[1.05] text-ink sm:text-5xl">
              Como você quer <span className="bg-gradient-to-r from-purple-700 to-blue-700 bg-clip-text text-transparent">entrar</span>?
            </h1>
            <p className="mt-3 max-w-xl text-[16px] text-muted">
              A mesma base gera visões diferentes para cada perfil. Escolha quem você é nesta demonstração — o servidor aplica as permissões e o escopo de cada um.
            </p>
            {k && (
              <div className="mt-5 flex flex-wrap gap-2 text-[13px]">
                <span className="rounded-full bg-white px-3 py-1.5 font-semibold shadow-soft ring-1 ring-line"><MapPin className="mr-1 inline size-4 text-purple-700" />{fmtInt(k.official.units)} unidades reais</span>
                <span className="rounded-full bg-white px-3 py-1.5 font-semibold shadow-soft ring-1 ring-line">{fmtInt(k.official.classes)} turmas · {fmtInt(k.official.enrollments)} matrículas</span>
              </div>
            )}
          </div>
          <div className="hidden justify-center md:flex">
            <IaraMascot height={300} mood="wave" />
          </div>
        </div>

        <div className="mt-6 md:hidden">
          <IaraBubble compact>Oi! Eu sou a IARA. Toque em um perfil para ver a plataforma com os olhos de quem a usa.</IaraBubble>
        </div>

        <div className="mt-7 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {boot.isLoading && Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-40" />)}
          {featured.map((p, i) => (
            <PersonaCard key={p.code} p={p} i={i} busy={busy === p.code} onClick={() => enter(p)} />
          ))}
        </div>

        {others.length > 0 && (
          <>
            <h2 className="mt-8 font-display text-lg font-extrabold">Outros perfis da SEDUC</h2>
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {others.map((p, i) => (
                <PersonaCard key={p.code} p={p} i={i} busy={busy === p.code} onClick={() => enter(p)} small />
              ))}
            </div>
          </>
        )}

        <WhatsAppCard
          className="mt-8"
          title="É de uma família? Fale com a IARA pelo WhatsApp"
          subtitle="Responsáveis e outros membros da família podem procurar vaga, acompanhar a fila e avisar mudanças sem abrir o portal."
        />

        <div className="mt-10 flex items-start gap-3 rounded-3xl bg-white/80 p-4 text-[13px] text-muted ring-1 ring-line">
          <ShieldCheck className="mt-0.5 size-5 shrink-0 text-green-700" />
          <p>
            Unidades, endereços, turmas e matrículas agregadas vêm de fontes públicas (Censo Escolar 2025/INEP e Consulta Escolas/SEED-PR).
            Alunos, responsáveis, fila, ofertas, protocolos e conversas são <b className="text-ink">fictícios</b> e marcados com uma bandeirinha.
            {' '}{avisoMensagens(boot.data?.whatsapp?.canal_ativo)}
          </p>
        </div>
      </div>

      <UnitPicker persona={unitFor} onClose={() => setUnitFor(null)} onPick={(id) => unitFor && enter(unitFor, id)} demoUnit={boot.data?.tenant.demo_unit} />
    </div>
  );
}

function PersonaCard({ p, i, busy, onClick, small }: { p: Persona; i: number; busy: boolean; onClick: () => void; small?: boolean }) {
  const I = ICON[p.code] ?? UserRound;
  return (
    <motion.button
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.04 * i, duration: 0.3 }}
      whileTap={{ scale: 0.97 }}
      onClick={onClick}
      disabled={busy}
      className={clsx('group relative flex flex-col overflow-hidden rounded-3xl bg-white text-left shadow-soft ring-1 ring-line/70 transition hover:-translate-y-0.5 hover:shadow-lift', small ? 'p-4' : 'p-5')}
    >
      <div className="flex items-center gap-3">
        <span className={clsx('inline-flex shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br text-white shadow-sm', GRAD[p.code], small ? 'size-10' : 'size-12')}>
          <I className={small ? 'size-5' : 'size-6'} />
        </span>
        <div className="min-w-0">
          <div className={clsx('font-display font-extrabold leading-tight', small ? 'text-[15px]' : 'text-[17px]')}>{p.name}</div>
          <div className="text-[12px] font-semibold text-muted">{SCOPE[p.scope_type]}</div>
        </div>
        <ChevronRight className="ml-auto size-5 shrink-0 text-subtle transition group-hover:translate-x-0.5 group-hover:text-purple-700" />
      </div>
      {!small && <p className="mt-3 text-[13.5px] text-muted">{p.description}</p>}
      <p className={clsx('font-medium italic text-purple-800', small ? 'mt-2 text-[12.5px]' : 'mt-3 text-[14px]')}>“{p.question}”</p>
      {busy && (
        <div className="absolute inset-0 flex items-center justify-center bg-white/70">
          <Sparkles className="size-6 animate-pulse text-purple-700" />
        </div>
      )}
    </motion.button>
  );
}

function UnitPicker({ persona, onClose, onPick, demoUnit }: { persona: Persona | null; onClose: () => void; onPick: (id: number) => void; demoUnit?: number }) {
  const [q, setQ] = useState('');
  const units = useRpc<{ items: { id: number; name: string; type: string; neighborhood: string }[] }>('persona_units', { q }, { enabled: !!persona });
  return (
    <Sheet open={!!persona} onClose={onClose} title="Qual unidade?" subtitle={`${persona?.name ?? ''}: o acesso fica restrito à unidade escolhida.`}>
      <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar escola ou CMEI…" className={inputCls} aria-label="Buscar unidade" />
      <div className="mt-3 space-y-2">
        {units.isLoading && <Skeleton className="h-16" />}
        {(units.data?.items ?? []).slice(0, 40).map((u) => (
          <button key={u.id} onClick={() => onPick(u.id)} className="flex w-full items-center gap-3 rounded-2xl bg-slate-50 p-3 text-left ring-1 ring-line hover:bg-purple-50">
            <Building2 className="size-5 text-purple-700" />
            <div className="min-w-0 flex-1">
              <div className="truncate font-semibold">{u.name}</div>
              <div className="truncate text-[12.5px] text-muted">{u.neighborhood}</div>
            </div>
            {u.id === demoUnit && <Badge tone="purple">Cenário da demo</Badge>}
          </button>
        ))}
      </div>
    </Sheet>
  );
}
