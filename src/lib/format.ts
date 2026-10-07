const nf = new Intl.NumberFormat('pt-BR');
const nf1 = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });

export const fmtInt = (n: number | null | undefined) => (n == null || Number.isNaN(n) ? '—' : nf.format(Math.round(n)));
export const fmt1 = (n: number | null | undefined) => (n == null || Number.isNaN(n) ? '—' : nf1.format(n));
export const fmtPct = (n: number | null | undefined) => (n == null ? '—' : `${nf1.format(n)}%`);
export const fmtKm = (m: number | null | undefined) =>
  m == null ? '—' : m < 1000 ? `${Math.round(m / 10) * 10} m` : `${nf1.format(m / 1000)} km`;

const TZ = 'America/Sao_Paulo';
export const fmtDate = (iso: string | null | undefined) =>
  iso ? new Date(iso.length === 10 ? iso + 'T12:00:00Z' : iso).toLocaleDateString('pt-BR', { timeZone: TZ }) : '—';
export const fmtDateTime = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('pt-BR', { timeZone: TZ, day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—';
export const fmtTime = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleTimeString('pt-BR', { timeZone: TZ, hour: '2-digit', minute: '2-digit' }) : '';

export function timeAgo(iso: string | null | undefined, now = Date.now()) {
  if (!iso) return '—';
  const s = Math.round((now - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'agora';
  const m = Math.round(s / 60);
  if (m < 60) return `há ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.round(h / 24);
  if (d < 31) return `há ${d} dia${d > 1 ? 's' : ''}`;
  const mo = Math.round(d / 30);
  return `há ${mo} ${mo > 1 ? 'meses' : 'mês'}`;
}

export function timeLeft(iso: string | null | undefined, now = Date.now()) {
  if (!iso) return '—';
  const ms = new Date(iso).getTime() - now;
  if (ms <= 0) return 'prazo encerrado';
  const h = Math.floor(ms / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  return h >= 1 ? `${h} h ${m.toString().padStart(2, '0')} min` : `${m} min`;
}

export function initials(name: string | null | undefined) {
  if (!name) return '?';
  const parts = name.replace(/\(.*?\)/g, '').trim().split(/\s+/).filter((p) => p.length > 2 || /^[A-ZÁÉÍÓÚ]/.test(p));
  return ((parts[0]?.[0] ?? '') + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

const PALETTE = ['#7A24C5', '#086DB6', '#008C72', '#C2410C', '#BE185D', '#4F46E5', '#0E7490', '#A16207', '#15803D', '#9333EA'];
export function colorFor(seed: number | string | null | undefined) {
  const n = typeof seed === 'number' ? seed : [...String(seed ?? '')].reduce((a, c) => a + c.charCodeAt(0), 0);
  return PALETTE[Math.abs(n) % PALETTE.length];
}

export function firstName(name: string | null | undefined) {
  return (name ?? '').split(' ')[0];
}

export function plural(n: number, one: string, many: string) {
  return `${fmtInt(n)} ${n === 1 ? one : many}`;
}

/** "do CMEI X" / "da E.M. Y" */
export function deUnidade(name: string | null | undefined) {
  if (!name) return 'da unidade';
  return name.startsWith('CMEI') ? `do ${name}` : `da ${name}`;
}
export function naUnidade(name: string | null | undefined) {
  if (!name) return 'na unidade';
  return name.startsWith('CMEI') ? `no ${name}` : `na ${name}`;
}

/** Remove o sufixo técnico das sessões de demonstração: "Maria (demo #6C6C)" → "Maria". */
export function cleanLabel(label: string | null | undefined) {
  return (label ?? '').replace(/\s*\(demo #[0-9A-F]+\)/gi, '').trim();
}
const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
export const fmtBRL = (n: number | string | null | undefined) => (n == null || n === '' || Number.isNaN(Number(n)) ? '—' : brl.format(Number(n)));
