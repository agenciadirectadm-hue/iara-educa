import { lazy, Suspense } from 'react';
import { useSession } from '@/lib/session';
import { SkeletonList } from '@/components/ui';

const HomePrefeito = lazy(() => import('./home/HomePrefeito'));
const HomeSecretario = lazy(() => import('./home/HomeSecretario'));
const HomeAnalista = lazy(() => import('./home/HomeAnalista'));
const HomeUnidade = lazy(() => import('./home/HomeUnidade'));
const HomeCidadao = lazy(() => import('./home/HomeCidadao'));
const HomeInovacao = lazy(() => import('./home/HomeInovacao'));
const PainelControle = lazy(() => import('./controle/PainelControle'));
const HomeProfessor = lazy(() => import('./home/HomeProfessor'));
const Nutricao = lazy(() => import('./Nutricao'));
const Manutencao = lazy(() => import('./Manutencao'));
const Aee = lazy(() => import('./Aee'));
const Transporte = lazy(() => import('./Transporte'));
const Materiais = lazy(() => import('./Materiais'));

/** A mesma base gera visões diferentes por perfil (spec §6) — cada início responde à pergunta do perfil. */
export default function Home() {
  const { me } = useSession();
  const role = me?.role;
  const el =
    role === 'PREFEITO' ? <HomePrefeito />
      : role === 'SECRETARIO' || role === 'SUPERINTENDENCIA' || role === 'GERENCIA_EI' ? <HomeSecretario />
        : role === 'ANALISTA_CENTRAL' || role === 'ATENDIMENTO' ? <HomeAnalista />
          : role === 'DIRETOR_UNIDADE' || role === 'SECRETARIA_ESCOLAR' ? <HomeUnidade />
            : role === 'CIDADAO' || role === 'CIDADAO_NOVO' ? <HomeCidadao />
              : role === 'INOVACAO' ? <HomeInovacao />
                : role === 'CONTROLE_EXTERNO' ? <PainelControle />
                : role === 'PROFESSOR' ? <HomeProfessor />
                : role === 'NUTRICAO' ? <Nutricao />
                : role === 'MANUTENCAO' ? <Manutencao />
                : role === 'PROFESSOR_AEE' ? <Aee />
                : role === 'TRANSPORTE' ? <Transporte />
                : role === 'ALMOXARIFADO' ? <Materiais />
                : <HomeSecretario />;
  return <Suspense fallback={<SkeletonList rows={5} />}>{el}</Suspense>;
}
