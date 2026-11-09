import { defineConfig } from 'tsup';

export default defineConfig({
  // app.ts também é gerado separado: a Vercel usa dist/app.js (api/index.mjs) sem subir o servidor.
  entry: ['src/server.ts', 'src/app.ts'],
  format: ['esm'],
  target: 'node20',
  platform: 'node',
  sourcemap: true,
  clean: true,
});
