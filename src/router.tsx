import { lazy, Suspense, useEffect, type ReactNode } from 'react';
import { createHashRouter, Navigate, useRouteError, useSearchParams } from 'react-router';
import { AppShell } from './app/AppShell';
import Splash, { aberturaJaVistaNaAba } from './pages/Splash';
import AberturaUmuarama from './pages/AberturaUmuarama';
import Entrar from './pages/Entrar';
import { useSession } from './lib/session';
import { erroDeVersao, recarregarNovaVersao } from './lib/novaVersao';
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
const Reunioes = lazy(() => import('./pages/Reunioes'));
const ReunioesControle = lazy(() => import('./pages/controle/ReunioesControle'));
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
const RecusasVaga = lazy(() => import('./pages/RecusasVaga'));
const MinhasOfertas = lazy(() => import('./pages/MinhasOfertas'));
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
const Uniformes = lazy(() => import('./pages/Uniformes'));
const Apoio = lazy(() => import('./pages/Apoio'));
const ApoioCaso = lazy(() => import('./pages/ApoioCaso'));
const PainelOrgao = lazy(() => import('./pages/orgaos/PainelOrgao'));
const Ideb = lazy(() => import('./pages/Ideb'));
const Pendencias = lazy(() => import('./pages/Pendencias'));
const Iaraflix = lazy(() => import('./pages/Iaraflix'));
const IaraflixTrilha = lazy(() => import('./pages/Iaraflix').then((m) => ({ default: m.IaraflixTrilha })));
const IaraflixAula = lazy(() => import('./pages/IaraflixAula'));
const IaraflixGestao = lazy(() => import('./pages/IaraflixGestao'));
const Videos = lazy(() => import('./pages/Videos'));
const VideoFamiliaPagina = lazy(() => import('./pages/Videos').then((m) => ({ default: m.VideoFamiliaPagina })));
const Diario = lazy(() => import('./pages/Diario'));
const Ocorrencias = lazy(() => import('./pages/Ocorrencias'));
const Validacoes = lazy(() => import('./pages/Validacoes'));
const DocumentosFamilia = lazy(() => import('./pages/DocumentosFamilia'));
const Materiais = lazy(() => import('./pages/Materiais'));
const Avaliacao = lazy(() => import('./pages/Avaliacao'));
const Desempenho = lazy(() => import('./pages/Desempenho'));
const Aee = lazy(() => import('./pages/Aee'));
const AeePlano = lazy(() => import('./pages/AeePlano'));
const Declaracao = lazy(() => import('./pages/Declaracao'));
const Verificar = lazy(() => import('./pages/Declaracao').then((m) => ({ default: m.Verificar })));
const Transporte = lazy(() => import('./pages/Transporte'));
const Rota = lazy(() => import('./pages/Rota'));
const SimuladorPrecos = lazy(() => import('./pages/SimuladorPrecos'));
const PublicosPrefeito = lazy(() => import('./pages/PublicosPrefeito'));
const Oraculo = lazy(() => import('./pages/Oraculo'));
const MeuPonto = lazy(() => import('./pages/MeuPonto'));
const PontoEquipe = lazy(() => import('./pages/PontoEquipe'));
const SistemaPresenca = lazy(() => import('./pages/SistemaPresenca'));
const BolsaFamilia = lazy(() => import('./pages/BolsaFamilia'));
const Embarque = lazy(() => import('./pages/Rota').then((m) => ({ default: m.Embarque })));
const BuscaAtiva = lazy(() => import('./pages/BuscaAtiva'));
const GestaoRede = lazy(() => import('./pages/GestaoRede'));
const Guarda = lazy(() => import('./pages/Guarda'));
const Suporte = lazy(() => import('./pages/Suporte'));
const Biblioteca = lazy(() => import('./pages/Biblioteca'));
const RegrasFrequencia = lazy(() => import('./pages/RegrasFrequencia'));
const Rematricula = lazy(() => import('./pages/Rematricula'));
const Ensalamento = lazy(() => import('./pages/Ensalamento'));
const Eventos = lazy(() => import('./pages/Eventos'));
const Certificado = lazy(() => import('./pages/Declaracao').then((m) => ({ default: m.Certificado })));

function Loader() {
  return (
    <div className="flex min-h-[50vh] items-center justify-center">
      <Spinner className="size-7" />
    </div>
  );
}

const S = (el: ReactNode) => <Suspense fallback={<Loader />}>{el}</Suspense>;

/** O endereço do site é sempre a abertura: ela é a tela principal. */
function RootGate() {
  return <Navigate to="/abertura" replace />;
}

/** Quem chega direto numa tela do sistema (aba nova, endereço salvo) também passa antes pela abertura e pela escolha de perfis.
 * O QR code do WhatsApp e os documentos para imprimir ficam de fora, e o que já está aberto nesta aba não repete a abertura. */
function ChegadaPelaAbertura({ children }: { children: ReactNode }) {
  if (!aberturaJaVistaNaAba()) return <Navigate to="/abertura" replace />;
  return <>{children}</>;
}

function RequireSession({ children }: { children: ReactNode }) {
  const { session, ready } = useSession();
  if (!ready) return <Loader />;
  if (!session) return <Navigate to="/entrar" replace />;
  return <>{children}</>;
}

/** Mapas de calor viraram temas do mapa unificado: o endereço antigo leva ao mesmo quesito, em pontos. */
function RedirecionaCalor() {
  const [sp] = useSearchParams();
  const camada = sp.get('camada') ?? 'transporte_necessidade';
  return <Navigate to={`/mapa?q=${encodeURIComponent(camada)}&recorte=pontos`} replace />;
}

function RouteError() {
  const err = useRouteError() as Error | undefined;
  const versaoNova = erroDeVersao(err);
  useEffect(() => {
    if (versaoNova) void recarregarNovaVersao();
  }, [versaoNova]);
  if (versaoNova) {
    return (
      <div className="mx-auto flex max-w-md flex-col items-center px-6 py-16 text-center">
        <IaraMascot height={220} mood="wave" />
        <h1 className="mt-4 font-display text-2xl font-extrabold">Atualizando o site</h1>
        <p className="mt-2 text-muted">Saiu uma versão nova. A página recarrega sozinha; se não recarregar, toque no botão.</p>
        <Button className="mt-5" onClick={() => window.location.reload()}>Recarregar agora</Button>
      </div>
    );
  }
  return (
    <div className="mx-auto flex max-w-md flex-col items-center px-6 py-16 text-center">
      <IaraMascot height={220} mood="attention" />
      <h1 className="mt-4 font-display text-2xl font-extrabold">Algo saiu do lugar</h1>
      <p className="mt-2 text-muted">{err?.message ?? 'Erro inesperado nesta tela.'}</p>
      {/* o erro fica preso à tela: sem recarregar, "voltar" a partir do próprio início não sairia dele */}
      <Button className="mt-5" onClick={() => { window.location.hash = '#/inicio'; window.location.reload(); }}>Voltar ao início</Button>
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
  // abertura com a Ipê e o Umuaraminha, só por este endereço (foi a tela principal durante a apresentação em Umuarama)
  { path: '/umuarama', element: <AberturaUmuarama /> },
  { path: '/entrar', element: <ChegadaPelaAbertura><Entrar /></ChegadaPelaAbertura> },
  // início da conversa pelo WhatsApp (destino do QR code) e cartaz para imprimir — públicos
  { path: '/whatsapp', element: S(<WhatsAppEntry />) },
  { path: '/whatsapp/cartaz', element: S(<WhatsAppPoster />) },
  // declaração para imprimir (com QR code de verificação)
  { path: '/declaracao/:id', element: <RequireSession>{S(<Declaracao />)}</RequireSession> },
  { path: '/certificado/:codigo', element: <RequireSession>{S(<Certificado />)}</RequireSession> },
  {
    element: <ChegadaPelaAbertura><AppShell /></ChegadaPelaAbertura>,
    errorElement: <RouteError />,
    children: [
      { path: '/inicio', element: <RequireSession>{S(<Home />)}</RequireSession> },
      { path: '/mapa', element: S(<MapPage />), handle: { full: true } },
      { path: '/unidades', element: S(<Units />) },
      { path: '/unidades/:id', element: S(<UnitPage />) },
      { path: '/turmas/:id', element: <RequireSession>{S(<ClassPage />)}</RequireSession> },
      { path: '/turmas/:id/chamada', element: <RequireSession>{S(<Chamada />)}</RequireSession> },
      { path: '/turmas/:id/diario', element: <RequireSession>{S(<Diario />)}</RequireSession>, handle: { wide: true } },
      { path: '/turmas/:id/avaliacao', element: <RequireSession>{S(<Avaliacao />)}</RequireSession>, handle: { wide: true } },
      { path: '/desempenho', element: <RequireSession>{S(<Desempenho />)}</RequireSession>, handle: { wide: true } },
      { path: '/aee', element: <RequireSession>{S(<Aee />)}</RequireSession>, handle: { wide: true } },
      { path: '/aee/:id', element: <RequireSession>{S(<AeePlano />)}</RequireSession>, handle: { wide: true } },
      { path: '/transporte', element: <RequireSession>{S(<Transporte />)}</RequireSession>, handle: { wide: true } },
      { path: '/gestao', element: <RequireSession>{S(<GestaoRede />)}</RequireSession>, handle: { wide: true } },
      { path: '/guarda', element: <RequireSession>{S(<Guarda />)}</RequireSession>, handle: { wide: true } },
      { path: '/biblioteca', element: <RequireSession>{S(<Biblioteca />)}</RequireSession>, handle: { wide: true } },
      { path: '/rematricula', element: <RequireSession>{S(<Rematricula />)}</RequireSession>, handle: { wide: true } },
      { path: '/ensalamento', element: <RequireSession>{S(<Ensalamento />)}</RequireSession>, handle: { wide: true } },
      { path: '/eventos', element: <RequireSession>{S(<Eventos />)}</RequireSession>, handle: { wide: true } },
      { path: '/mapas-de-calor', element: <RedirecionaCalor /> },
      { path: '/suporte', element: <RequireSession>{S(<Suporte />)}</RequireSession>, handle: { wide: true } },
      { path: '/busca-ativa', element: <RequireSession>{S(<BuscaAtiva />)}</RequireSession>, handle: { wide: true } },
      { path: '/busca-ativa/regras', element: <RequireSession>{S(<RegrasFrequencia />)}</RequireSession>, handle: { wide: true } },
      { path: '/transporte/rotas/:id', element: <RequireSession>{S(<Rota />)}</RequireSession>, handle: { wide: true } },
      { path: '/transporte/rotas/:id/embarque', element: <RequireSession>{S(<Embarque />)}</RequireSession> },
      // verificação pública de declaração (sem login)
      { path: '/verificar', element: S(<Verificar />) },
      { path: '/verificar/:codigo', element: S(<Verificar />) },
      { path: '/ocorrencias', element: <RequireSession>{S(<Ocorrencias />)}</RequireSession>, handle: { wide: true } },
      { path: '/validacoes', element: <RequireSession>{S(<Validacoes />)}</RequireSession>, handle: { wide: true } },
      { path: '/familia/documentos', element: <RequireSession>{S(<DocumentosFamilia />)}</RequireSession> },
      { path: '/materiais', element: <RequireSession>{S(<Materiais />)}</RequireSession>, handle: { wide: true } },
      { path: '/uniformes', element: <RequireSession>{S(<Uniformes />)}</RequireSession>, handle: { wide: true } },
      { path: '/apoio', element: <RequireSession>{S(<Apoio />)}</RequireSession>, handle: { wide: true } },
      { path: '/apoio/:id', element: <RequireSession>{S(<ApoioCaso />)}</RequireSession>, handle: { wide: true } },
      { path: '/orgaos', element: <RequireSession>{S(<PainelOrgao />)}</RequireSession>, handle: { wide: true } },
      { path: '/ideb', element: S(<Ideb />), handle: { wide: true } },
      { path: '/pendencias', element: <RequireSession>{S(<Pendencias />)}</RequireSession>, handle: { wide: true } },
      // IARAFLIX: treinamento em vídeo (trilha por perfil, player, gestão e adesão)
      { path: '/iaraflix', element: <RequireSession>{S(<Iaraflix />)}</RequireSession>, handle: { wide: true } },
      { path: '/iaraflix/trilha/:id', element: <RequireSession>{S(<IaraflixTrilha />)}</RequireSession>, handle: { wide: true } },
      { path: '/iaraflix/aula/:id', element: <RequireSession>{S(<IaraflixAula />)}</RequireSession>, handle: { wide: true } },
      { path: '/iaraflix/gestao', element: <RequireSession>{S(<IaraflixGestao />)}</RequireSession>, handle: { wide: true } },
      // vídeos da SEDUC para as famílias: públicos (sem login), no portal e pela IARA
      { path: '/videos', element: S(<Videos />), handle: { wide: true } },
      { path: '/videos/:id', element: S(<VideoFamiliaPagina />), handle: { wide: true } },
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
      { path: '/simulador', element: <RequireSession>{S(<SimuladorPrecos />)}</RequireSession>, handle: { wide: true } },
      { path: '/publicos', element: <RequireSession>{S(<PublicosPrefeito />)}</RequireSession>, handle: { wide: true } },
      { path: '/oraculo', element: <RequireSession>{S(<Oraculo />)}</RequireSession>, handle: { wide: true } },
      { path: '/ponto', element: <RequireSession>{S(<MeuPonto />)}</RequireSession>, handle: { wide: true } },
      { path: '/ponto/equipe', element: <RequireSession>{S(<PontoEquipe />)}</RequireSession>, handle: { wide: true } },
      { path: '/presenca', element: <RequireSession>{S(<SistemaPresenca />)}</RequireSession>, handle: { wide: true } },
      { path: '/bolsa-familia', element: <RequireSession>{S(<BolsaFamilia />)}</RequireSession>, handle: { wide: true } },
      { path: '/fila', element: <RequireSession>{S(<Queue />)}</RequireSession>, handle: { wide: true } },
      { path: '/fila/:id', element: <RequireSession>{S(<QueueEntry />)}</RequireSession> },
      { path: '/ofertas', element: <RequireSession>{S(<Offers />)}</RequireSession> },
      { path: '/recusas', element: <RequireSession>{S(<RecusasVaga />)}</RequireSession>, handle: { wide: true } },
      { path: '/minhas-ofertas', element: <RequireSession>{S(<MinhasOfertas />)}</RequireSession>, handle: { wide: true } },
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
      { path: '/controle/reunioes', element: <RequireSession>{S(<ReunioesControle />)}</RequireSession>, handle: { wide: true } },
      { path: '/reunioes', element: <RequireSession>{S(<Reunioes />)}</RequireSession>, handle: { wide: true } },
      { path: '/ajuda', element: S(<Help />) },
      { path: '*', element: <NotFound /> },
    ],
  },
]);
