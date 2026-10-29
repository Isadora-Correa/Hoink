#!/usr/bin/env bash
# Valida a estrutura mínima do repositório (usado no CI).
set -euo pipefail
fail=0
required=(
  README.md .env.example docker-compose.yml .github/workflows/ci.yml .github/workflows/cd.yml
  apps/api/Dockerfile apps/api/package.json apps/api/prisma/schema.prisma
  apps/app/Dockerfile apps/app/pubspec.yaml apps/app/nginx.conf
  e2e/playwright.config.ts perf/load.js docs/ARCHITECTURE.md docs/DEPLOY.md CONTRIBUTING.md
)
for f in "${required[@]}"; do
  if [[ ! -e "$f" ]]; then echo "::error::Arquivo obrigatório ausente: $f"; fail=1; fi
done
# Nenhum .env real pode ser versionado.
if git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v '\.env\.example$'; then
  echo "::error::Arquivo .env versionado — remova e use variáveis de ambiente/secrets."; fail=1
fi
# Migrations devem acompanhar o schema.
if [[ -z "$(ls apps/api/prisma/migrations 2>/dev/null)" ]]; then echo "::error::Sem migrations do Prisma"; fail=1; fi
[[ $fail -eq 0 ]] && echo "Estrutura do projeto válida."
exit $fail
