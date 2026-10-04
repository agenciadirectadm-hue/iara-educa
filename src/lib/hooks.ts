import { useMutation, useQuery, useQueryClient, type UseQueryOptions } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { rpc, ApiError } from './api';
import { useSession } from './session';

export function useRpc<T = any>(fn: string, args: object = {}, opts: Partial<UseQueryOptions<T, ApiError>> = {}) {
  const { me } = useSession();
  return useQuery<T, ApiError>({
    queryKey: [fn, args, me?.user_id ?? 'anon'],
    queryFn: () => rpc<T>(fn, args),
    staleTime: 30_000,
    ...opts,
  });
}

/** Mutação transacional: sem sucesso otimista — a UI só confirma após a resposta do servidor. */
export function useRpcMutation<TArgs extends object = any, TRes = any>(fn: string, invalidate: string[] = []) {
  const qc = useQueryClient();
  return useMutation<TRes, ApiError, TArgs>({
    mutationFn: (args: TArgs) => rpc<TRes>(fn, args),
    onSuccess: () => {
      for (const key of invalidate) qc.invalidateQueries({ queryKey: [key] });
    },
  });
}

export function useMediaQuery(q: string) {
  const [match, setMatch] = useState(() => (typeof window !== 'undefined' ? window.matchMedia(q).matches : false));
  useEffect(() => {
    const m = window.matchMedia(q);
    const on = () => setMatch(m.matches);
    m.addEventListener('change', on);
    return () => m.removeEventListener('change', on);
  }, [q]);
  return match;
}

export const useIsDesktop = () => useMediaQuery('(min-width: 1024px)');

export function useDebounced<T>(value: T, ms = 300) {
  const [v, setV] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

export function useNow(intervalMs = 60_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(t);
  }, [intervalMs]);
  return now;
}

/** Persistência leve por aparelho (preferências de interface), tolerante a armazenamento bloqueado. */
export function useLocal<T>(key: string, initial: T): [T, (v: T) => void] {
  const [v, setV] = useState<T>(() => {
    try {
      const raw = localStorage.getItem(key);
      return raw != null ? (JSON.parse(raw) as T) : initial;
    } catch {
      return initial;
    }
  });
  const set = (nv: T) => {
    setV(nv);
    try {
      localStorage.setItem(key, JSON.stringify(nv));
    } catch {
      /* ignorado */
    }
  };
  return [v, set];
}
