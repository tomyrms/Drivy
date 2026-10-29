import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { fileURLToPath, URL } from 'node:url';
import { execFileSync } from 'node:child_process';

const sha = process.env.DRIVY_BUILD_SHA ?? execFileSync('git', ['rev-parse', 'HEAD'], { cwd: fileURLToPath(new URL('.', import.meta.url)), encoding: 'utf8' }).trim();
if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error('A full commit is required for the web build.');

export default defineConfig({
  base: '/app/',
  plugins: [react(), tailwindcss(), {
    name: 'drivy-build-identity',
    transformIndexHtml: () => [{ tag: 'meta', attrs: { name: 'drivy-build', content: sha }, injectTo: 'head' }],
  }],
  define: { __DRIVY_BUILD_SHA__: JSON.stringify(sha) },
  resolve: { alias: { '@': fileURLToPath(new URL('./client', import.meta.url)) } },
  build: { outDir: 'dist/client', emptyOutDir: true, sourcemap: false },
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: { '/app/bff': { target: 'http://127.0.0.1:3002', changeOrigin: false } },
  },
});
