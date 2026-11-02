import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MotionConfig } from 'motion/react';
import { RouterProvider } from 'react-router/dom';
import { registerSW } from 'virtual:pwa-register';
import '@fontsource-variable/inter';
import '@fontsource-variable/nunito';
import './styles.css';
import { router } from './router';
import { SessionProvider } from './lib/session';
import { OverlayProvider } from './components/overlays';
import type { ApiError } from './lib/api';

// Versão nova publicada: o navegador só procura ao abrir a página. Com a aba aberta, procura também a cada 30 min e ao
// voltar para a aba; achando, o modo autoUpdate troca e recarrega sozinho.
registerSW({
  immediate: true,
  onRegisteredSW(_url, reg) {
    if (!reg) return;
    const procurar = () => { reg.update().catch(() => {}); };
    setInterval(procurar, 30 * 60_000);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') procurar(); });
  },
});

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (count, error) => ((error as ApiError)?.status ?? 500) >= 500 && count < 2,
      refetchOnWindowFocus: false,
    },
  },
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <MotionConfig reducedMotion="user">
        <OverlayProvider>
          <SessionProvider>
            <RouterProvider router={router} />
          </SessionProvider>
        </OverlayProvider>
      </MotionConfig>
    </QueryClientProvider>
  </StrictMode>,
);
