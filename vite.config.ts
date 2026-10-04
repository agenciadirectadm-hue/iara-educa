import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { VitePWA } from 'vite-plugin-pwa';
import { fileURLToPath, URL } from 'node:url';

// Base relativa + HashRouter: o build funciona em qualquer subcaminho (GitHub Pages, CDN, servidor da Prefeitura).
export default defineConfig({
  base: './',
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/*.png', 'iara/*.webp', 'geo/*.geojson', 'favicon.svg'],
      manifest: {
        name: 'IARA Educa — SEDUC Maringá',
        short_name: 'IARA Educa',
        description: 'Plataforma municipal de gestão educacional: vagas, fila, turmas, atendimento e território.',
        lang: 'pt-BR',
        theme_color: '#7A24C5',
        background_color: '#F5F7FB',
        display: 'standalone',
        orientation: 'any',
        start_url: './',
        scope: './',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // Somente interface e ativos públicos; respostas da API nunca são guardadas no aparelho.
        globPatterns: ['**/*.{js,css,html,webp,png,svg,woff2,geojson}'],
        maximumFileSizeToCacheInBytes: 5_000_000,
        navigateFallback: 'index.html',
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/tiles\.openfreemap\.org\//,
            handler: 'CacheFirst',
            options: { cacheName: 'mapa-base', expiration: { maxEntries: 600, maxAgeSeconds: 14 * 24 * 3600 } },
          },
        ],
      },
    }),
  ],
  worker: { format: 'es' },
  build: { target: 'es2022', chunkSizeWarningLimit: 1800, sourcemap: false },
  server: { host: true, port: 5173 },
  preview: { host: true, port: 4173 },
});
