#!/usr/bin/env bash
# Build do front (Flutter Web) na Vercel. A Vercel não tem Flutter: baixamos a mesma versão do Dockerfile/CI.
# A URL da API vem da variável de ambiente API_BASE_URL do projeto na Vercel (sem barra no final).
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.8}"
FLUTTER_DIR="${HOME}/flutter-${FLUTTER_VERSION}"

if [ -z "${API_BASE_URL:-}" ]; then
  echo "Defina API_BASE_URL nas variáveis de ambiente do projeto na Vercel (ex.: https://hoink-api.vercel.app)." >&2
  exit 1
fi
API_BASE_URL="${API_BASE_URL%/}"

# O SDK do Flutter usa unzip para baixar as ferramentas do Dart.
if ! command -v unzip >/dev/null 2>&1; then
  dnf install -y unzip >/dev/null
fi

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"
git config --global --add safe.directory "${FLUTTER_DIR}"

flutter config --no-analytics >/dev/null
flutter pub get
GIT_SHA="${VERCEL_GIT_COMMIT_SHA:-dev}"
flutter build web --release \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=GIT_SHA="${GIT_SHA}"
printf '{"name":"hoink-web","commit":"%s"}\n' "${GIT_SHA}" > build/web/version.json
echo "Front gerado apontando para ${API_BASE_URL}"
