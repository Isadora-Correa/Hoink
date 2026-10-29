import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'tests/**/*.test.ts'],
    setupFiles: ['tests/setup.ts'],
    globalSetup: ['tests/globalSetup.ts'],
    // Testes de integração compartilham o mesmo banco; executar arquivos em série evita interferência.
    fileParallelism: false,
    testTimeout: 20000,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/server.ts', 'src/types.d.ts'],
      reporter: ['text-summary', 'html', 'lcov', 'json-summary'],
      thresholds: { lines: 75, functions: 75, branches: 65, statements: 75 },
    },
    hookTimeout: 30000,
  },
});
