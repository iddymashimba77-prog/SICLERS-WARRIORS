import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Admin Web — dev server.
// Middleware proxies every `/api` call to the Django backend so the panel is
// origin-clean: no CORS needed during development, and the deployed build uses
// the same relative `/api` base against the production origin.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    host: true,
    hmr: { overlay: false }, // never splash the dev source-code overlay — show app messages only
    proxy: {
      '/api': {
        target: process.env.VITE_BACKEND ?? 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
  build: { outDir: 'dist', sourcemap: true },
});