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

registerSW({ immediate: true });

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
