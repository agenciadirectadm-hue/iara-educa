import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { createSession, endSession, onSessionExpired, rpc, setApiToken } from './api';
import type { Me } from './types';

type Session = { token: string; me: Me };
type Ctx = {
  session: Session | null;
  me: Me | null;
  ready: boolean;
  expired: boolean;
  login: (persona: string, unitId?: number | null) => Promise<Me>;
  logout: () => Promise<void>;
  refreshMe: () => Promise<void>;
  can: (perm: string) => boolean;
};

const KEY = 'iara.sessao.v1';
const SessionCtx = createContext<Ctx | null>(null);

function load(): Session | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}
function save(s: Session | null) {
  try {
    if (s) localStorage.setItem(KEY, JSON.stringify(s));
    else localStorage.removeItem(KEY);
  } catch {
    /* armazenamento indisponível: sessão vale só nesta aba */
  }
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient();
  const [session, setSession] = useState<Session | null>(() => {
    const s = load();
    if (s) setApiToken(s.token);
    return s;
  });
  const [ready, setReady] = useState(false);
  const [expired, setExpired] = useState(false);

  useEffect(() => {
    onSessionExpired(() => {
      setApiToken(null);
      save(null);
      setSession(null);
      setExpired(true);
      qc.clear();
    });
  }, [qc]);

  // Revalida a sessão salva ao abrir o app
  useEffect(() => {
    let alive = true;
    (async () => {
      if (session) {
        try {
          const me = await rpc<Me>('me');
          if (alive) {
            const s = { token: session.token, me };
            setSession(s);
            save(s);
          }
        } catch {
          if (alive) {
            setApiToken(null);
            save(null);
            setSession(null);
          }
        }
      }
      if (alive) setReady(true);
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const login = useCallback(
    async (persona: string, unitId?: number | null) => {
      const { token, me } = await createSession(persona, unitId);
      setApiToken(token);
      const s = { token, me: me as Me };
      save(s);
      qc.clear();
      setExpired(false);
      setSession(s);
      return s.me;
    },
    [qc],
  );

  const logout = useCallback(async () => {
    await endSession();
    setApiToken(null);
    save(null);
    setSession(null);
    qc.clear();
  }, [qc]);

  const refreshMe = useCallback(async () => {
    if (!session) return;
    const me = await rpc<Me>('me');
    const s = { token: session.token, me };
    setSession(s);
    save(s);
  }, [session]);

  const value = useMemo<Ctx>(
    () => ({
      session,
      me: session?.me ?? null,
      ready,
      expired,
      login,
      logout,
      refreshMe,
      can: (perm: string) => !!session?.me.permissions?.includes(perm),
    }),
    [session, ready, expired, login, logout, refreshMe],
  );
  return <SessionCtx.Provider value={value}>{children}</SessionCtx.Provider>;
}

export function useSession() {
  const ctx = useContext(SessionCtx);
  if (!ctx) throw new Error('useSession fora do SessionProvider');
  return ctx;
}
