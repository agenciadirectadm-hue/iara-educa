import { useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { LockKeyhole } from 'lucide-react';
import { acessoEntrar, acessoSituacao, ApiError, EVENTO_SENHA, guardarPasse, passeDeAcesso } from '@/lib/api';
import { Button, Card } from '@/components/ui';

/** Páginas que continuam abertas sem a senha: a conferência de declaração ou certificado pelo QR code. */
const rotaPublica = () => /^#\/verificar(\/|$|\?)/.test(window.location.hash);

/**
 * Senha de acesso ao portal. Quando o servidor diz que ela está ligada e este aparelho ainda não tem o passe, nada do portal
 * aparece antes da senha. A proteção de verdade está no servidor: sem o passe ele não abre sessão nem responde consultas.
 */
export function PortaoAcesso({ children }: { children: ReactNode }) {
  const [estado, setEstado] = useState<'conferindo' | 'livre' | 'pedir'>(() => (passeDeAcesso() ? 'livre' : 'conferindo'));
  const [publica, setPublica] = useState(rotaPublica);

  useEffect(() => {
    const mudouRota = () => setPublica(rotaPublica());
    const pedir = () => setEstado('pedir');
    window.addEventListener('hashchange', mudouRota);
    window.addEventListener(EVENTO_SENHA, pedir);
    if (!passeDeAcesso()) {
      acessoSituacao()
        .then((r) => setEstado(r.ativo ? 'pedir' : 'livre'))
        .catch(() => setEstado('pedir')); // sem resposta: na dúvida, pede a senha (com ela desligada, qualquer texto passa)
    }
    return () => {
      window.removeEventListener('hashchange', mudouRota);
      window.removeEventListener(EVENTO_SENHA, pedir);
    };
  }, []);

  if (publica) return <>{children}</>;
  if (estado === 'conferindo') return <div className="min-h-dvh bg-iara" aria-busy="true" />;
  if (estado === 'pedir') return <TelaSenha onEntrou={() => setEstado('livre')} />;
  return <>{children}</>;
}

function TelaSenha({ onEntrou }: { onEntrou: () => void }) {
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    if (!senha || enviando) return;
    setEnviando(true);
    setErro(null);
    try {
      const r = await acessoEntrar(senha);
      guardarPasse(r.passe);
      onEntrou();
    } catch (err) {
      const status = (err as ApiError)?.status;
      setErro(status === 401 ? 'Senha incorreta.' : status === 429 ? 'Muitas tentativas. Aguarde alguns minutos e tente de novo.' : (err as Error).message);
      setSenha('');
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-iara px-4 pt-safe pb-safe">
      <Card className="w-full max-w-sm p-6">
        <div className="flex items-center gap-3">
          <span className="inline-flex size-12 items-center justify-center rounded-2xl bg-purple-100 text-purple-800"><LockKeyhole className="size-6" /></span>
          <div>
            <h1 className="font-display text-xl font-extrabold">IARA Educa</h1>
            <p className="text-[13px] text-muted">Acesso restrito. Digite a senha para entrar.</p>
          </div>
        </div>
        <form onSubmit={enviar} className="mt-5 space-y-3">
          <label className="block">
            <span className="mb-1 block text-[12px] font-bold uppercase tracking-wide text-subtle">Senha de acesso</span>
            <input type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} autoFocus
              className="h-12 w-full rounded-2xl bg-white px-4 text-[16px] ring-1 ring-line focus:outline-none focus:ring-2 focus:ring-purple-500" />
          </label>
          {erro && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-[13px] font-semibold text-red-800">{erro}</p>}
          <Button type="submit" block loading={enviando} disabled={!senha}>Entrar</Button>
        </form>
        <p className="mt-4 text-[12px] text-subtle">A senha é pedida sempre que o portal é aberto.</p>
      </Card>
    </div>
  );
}
