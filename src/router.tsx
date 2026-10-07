import { lazy, Suspense, type ReactNode } from 'react';
import { createHashRouter, Navigate, useRouteError } from 'react-router';
import { AppShell } from './app/AppShell';
import Splash, { SPLASH_KEY } from './pages/Splash';
import Entrar from './pages/Entrar';
import { useSession } from './lib/session';
import { Button, Spinner } from './components/ui';
import { IaraMascot } from './components/iara';

const Home = lazy(() => import('./pages/Home'));
const MapPage = lazy(() => import('./pages/MapPage'));
const Units = lazy(() => import('./pages/Units'));
const UnitPage = lazy(() => import('./pages/UnitPage'));
const ClassPage = lazy(() => import('./pages/ClassPage'));
const TerritoryPage = lazy(() => import('./pages/TerritoryPage'));
const StudentPage = lazy(() => import('./pages/StudentPage'));
const GuardianPage = lazy(() => import('./pages/GuardianPage'));
const Alunos = lazy(() => import('./pages/Alunos'));
const Responsaveis = lazy(() => import('./pages/Responsaveis'));
const CadastroAluno = lazy(() => import('./pages/CadastroAluno'));
const CadastroResponsavel = lazy(() => import('./pages/CadastroResponsavel'));
const Cases = lazy(() => import('./pages/Cases'));
const CaseNew = lazy(() => import('./pages/CaseNew'));
const CasePage = lazy(() => import('./pages/CasePage'));
const VacancySearch = lazy(() => import('./pages/VacancySearch'));
const Queue = lazy(() => import('./pages/Queue'));
const QueueEntry = lazy(() => import('./pages/QueueEntry'));
const Offers = lazy(() => import('./pages/Offers'));
const IaraHub = lazy(() => import('./pages/IaraHub'));
const Conversation = lazy(() => import('./pages/Conversation'));
const CitizenCases = lazy(() => import('./pages/CitizenCases'));
const Family = lazy(() => import('./pages/Family'));
const Indicators = lazy(() => import('./pages/Indicators'));
const Audit = lazy(() => import('./pages/Audit'));
const Quality = lazy(() => import('./pages/Quality'));
const Rules = lazy(() => import('./pages/Rules'));
const Help = lazy(() => import('./pages/Help'));
const CanalWhatsApp = lazy(() => import('./pages/CanalWhatsApp'));
const WhatsAppEntry = lazy(() => import('./pages/WhatsApp'));
const WhatsAppPoster = lazy(() => import('./pages/WhatsApp').then((m) => ({ default: m.WhatsAppPoster })));
const PainelControle = lazy(() => import('./pages/controle/PainelControle'));
const FilaPublica = lazy(() => import('./pages/controle/FilaPublica'));
const ConsultaCaso = lazy(() => import('./pages/controle/ConsultaCaso'));
const Chamada = lazy(() => import('./pages/Chamada'));
const Pessoal = lazy(() => import('./pages/Pessoal'));
const Servidor = lazy(() => import('./pages/Servidor'));
const Frequencia = lazy(() => import('./pages/Frequencia'));
const Nutricao = lazy(() => import('./pages/Nutricao'));
const Cozinha = lazy(() => import('./pages/Cozinha'));
const Manutencao = lazy(() => import('./pages/Manutencao'));
const Chamado = lazy(() => import('./pages/Chamado'));
const Mural = lazy(() => import('./pages/Mural'));
const Calendario = lazy(() => import('./pages/Calendario'));
const Escola = lazy(() => import('./pages/Escola'));

function Loader() {
  return (
    <div className="flex min-h-[50vh] items-center justify-center">
      <Spinner className="size-7" />
    </div>
  );
}

const S = (el: ReactNode) => <Suspense fallback={<Loader />}>{el}</Suspense>;

function RootGate() {
  const { session, ready } = useSession();
  let seen = false;
  try {
    seen = localStorage.getItem(SPLASH_KEY) === 'true';
  } catch {
    seen = false;
  }
  if (!seen) return <Navigate to="/abertura" replace />;
  if (!ready) return <Loader />;
  return <Navigate to={session ? '/inicio' : '/entrar'} replace />;
}

function RequireSession({ children }: { children: ReactNode }) {
  const { session, ready } = useSession();
  if (!ready) return <Loader />;
  if (!session) return <Navigate to="/entrar" replace />;
  return <>{children}</>;
}

function RouteError() {
  const err = useRouteError() as Error | undefined;
  return (
    <div className="mx-auto flex max-w-md flex-col items-center px-6 py-16 text-center">
      <IaraMascot height={220} mood="attention" />
      <h1 className="mt-4 font-display text-2xl font-extrabold">Algo saiu do lugar</h1>
      <p className="mt-2 text-muted">{err?.message ?? 'Erro inesperado nesta tela.'}</p>
      <Button className="mt-5" onClick={() => (window.location.hash = '#/inicio')}>Voltar ao início</Button>
    </div>
  );
}

function NotFound() {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center px-6 py-16 text-center">
      <IaraMascot height={220} mood="thinking" />
      <h1 className="mt-4 font-display text-2xl font-extrabold">Página não encontrada</h1>
      <p className="mt-2 text-muted">O endereço pode ter mudado. Use o menu para continuar.</p>
    </div>
  );
}

export const router = createHashRouter([
  { path: '/', element: <RootGate /> },
  { path: '/abertura', element: <Splash /> },
  { path: '/entrar', element: <Entrar /> },
  // início da conversa pelo WhatsApp (destino do QR code) e cartaz para imprimir — públicos
  { path: '/whatsapp', element: S(<WhatsAppEntry />) },
  { path: '/whatsapp/cartaz', element: S(<WhatsAppPoster />) },
  {
    element: <AppShell />,
    errorElement: <RouteError />,
    children: [
      { path: '/inicio', element: <RequireSession>{S(<Home />)}</RequireSession> },
      { path: '/mapa', element: S(<MapPage />), handle: { full: true } },
      { path: '/unidades', element: S(<Units />) },
      { path: '/unidades/:id', element: S(<UnitPage />) },
      { path: '/turmas/:id', element: <RequireSession>{S(<ClassPage />)}</RequireSession> },
      { path: '/turmas/:id/chamada', element: <RequireSession>{S(<Chamada />)}</RequireSession> },
      { path: '/pessoal', element: <RequireSession>{S(<Pessoal />)}</RequireSession>, handle: { wide: true } },
      { path: '/pessoal/:id', element: <RequireSession>{S(<Servidor />)}</RequireSession>, handle: { wide: true } },
      { path: '/frequencia', element: <RequireSession>{S(<Frequencia />)}</RequireSession>, handle: { wide: true } },
      { path: '/nutricao', element: <RequireSession>{S(<Nutricao />)}</RequireSession>, handle: { wide: true } },
      { path: '/cozinha', element: <RequireSession>{S(<Cozinha />)}</RequireSession> },
      { path: '/manutencao', element: <RequireSession>{S(<Manutencao />)}</RequireSession>, handle: { wide: true } },
      { path: '/manutencao/:id', element: <RequireSession>{S(<Chamado />)}</RequireSession> },
      { path: '/mural', element: <RequireSession>{S(<Mural />)}</RequireSession> },
      { path: '/calendario', element: S(<Calendario />) },
      { path: '/escola', element: <RequireSession>{S(<Escola />)}</RequireSession> },
      { path: '/territorios/:id', element: S(<TerritoryPage />) },
      { path: '/alunos', element: <RequireSession>{S(<Alunos />)}</RequireSession>, handle: { wide: true } },
      { path: '/alunos/novo', element: <RequireSession>{S(<CadastroAluno />)}</RequireSession> },
      { path: '/alunos/:id', element: <RequireSession>{S(<StudentPage />)}</RequireSession> },
      { path: '/alunos/:id/cadastro', element: <RequireSession>{S(<CadastroAluno />)}</RequireSession> },
      { path: '/responsaveis', element: <RequireSession>{S(<Responsaveis />)}</RequireSession>, handle: { wide: true } },
      { path: '/responsaveis/novo', element: <RequireSession>{S(<CadastroResponsavel />)}</RequireSession> },
      { path: '/responsaveis/:id', element: <RequireSession>{S(<GuardianPage />)}</RequireSession> },
      { path: '/responsaveis/:id/cadastro', element: <RequireSession>{S(<CadastroResponsavel />)}</RequireSession> },
      { path: '/atendimentos', element: <RequireSession>{S(<Cases />)}</RequireSession> },
      { path: '/atendimentos/novo', element: <RequireSession>{S(<CaseNew />)}</RequireSession> },
      { path: '/atendimentos/:id', element: <RequireSession>{S(<CasePage />)}</RequireSession> },
      { path: '/vagas', element: S(<VacancySearch />) },
      { path: '/fila', element: <RequireSession>{S(<Queue />)}</RequireSession>, handle: { wide: true } },
      { path: '/fila/:id', element: <RequireSession>{S(<QueueEntry />)}</RequireSession> },
      { path: '/ofertas', element: <RequireSession>{S(<Offers />)}</RequireSession> },
      { path: '/iara', element: <RequireSession>{S(<IaraHub />)}</RequireSession>, handle: { full: true } },
      { path: '/conversas/:id', element: <RequireSession>{S(<Conversation />)}</RequireSession> },
      { path: '/protocolos', element: <RequireSession>{S(<CitizenCases />)}</RequireSession> },
      { path: '/familia', element: <RequireSession>{S(<Family />)}</RequireSession> },
      { path: '/canal-whatsapp', element: <RequireSession>{S(<CanalWhatsApp />)}</RequireSession> },
      { path: '/indicadores', element: <RequireSession>{S(<Indicators />)}</RequireSession> },
      { path: '/auditoria', element: <RequireSession>{S(<Audit />)}</RequireSession> },
      { path: '/qualidade', element: S(<Quality />) },
      { path: '/regras', element: S(<Rules />) },
      { path: '/controle', element: <RequireSession>{S(<PainelControle />)}</RequireSession>, handle: { wide: true } },
      { path: '/controle/fila', element: <RequireSession>{S(<FilaPublica />)}</RequireSession>, handle: { wide: true } },
      { path: '/controle/caso', element: <RequireSession>{S(<ConsultaCaso />)}</RequireSession> },
      { path: '/ajuda', element: S(<Help />) },
      { path: '*', element: <NotFound /> },
    ],
  },
]);
