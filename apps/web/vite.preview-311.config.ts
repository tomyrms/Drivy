import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, URL } from 'node:url';

const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: fileURLToPath(new URL('.', import.meta.url)), encoding: 'utf8' }).trim();
export default defineConfig({
  base: './', plugins: [react(), tailwindcss(), {
    name: 'isolated-preview-311',
    generateBundle() {
      const modules = [...this.getModuleIds()].map(id => id.replaceAll('\\', '/'));
      const legacy = modules.filter(id => /\/client\/(?:ui\.tsx|styles\.css|console\/[^?]*\.tsx)|(?:-studio|people-workspace|portal-shell)\.css/.test(id));
      if (legacy.length) this.error(`Legacy presentation imported by preview: ${legacy.join(', ')}`);
      this.emitFile({ type: 'asset', fileName: 'preview-build.json', source: JSON.stringify({ sha, scope: 'access-agenda-learners-pilots', syntheticData: true, legacyPresentationImports: legacy.length }) });
    },
  }],
  resolve: { alias: { '@': fileURLToPath(new URL('./client', import.meta.url)) } },
  define: { __DRIVY_PREVIEW_SHA__: JSON.stringify(sha), __DRIVY_BUILD_SHA__: JSON.stringify(sha) },
  build: { outDir: 'dist/preview-311', emptyOutDir: true, sourcemap: false, rolldownOptions: { input: fileURLToPath(new URL('./preview-311.html', import.meta.url)) } },
  server: { host: '127.0.0.1', port: 5188, strictPort: true },
});
