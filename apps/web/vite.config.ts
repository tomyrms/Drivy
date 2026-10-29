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
    generateBundle() {
      const modules = [...this.getModuleIds()].map(id => id.replaceAll('\\', '/'));
      const forbidden = modules.filter(id => {
        const path = id.split('/client/')[1]?.split('?')[0];
        if (!path) return false;
        return ['legacy-styles.ts', 'presentation.ts', 'portal/components/not-rebuilt.tsx'].includes(path)
          || path.startsWith('portal/preview/') || path === 'portal/access-preview.tsx'
          || path.endsWith('.css') && !path.startsWith('portal/')
          || path.endsWith('.tsx') && !path.startsWith('portal/') && !path.startsWith('components/ui/') && !['main.tsx', 'BrandSymbol.tsx'].includes(path);
      });
      if (forbidden.length) this.error(`Retired or synthetic presentation in production: ${forbidden.join(', ')}`);
    },
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
