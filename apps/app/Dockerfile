# syntax=docker/dockerfile:1
# Front-end hoink. (Flutter Web) servido por nginx.
#   docker build -t hoink-web --build-arg API_BASE_URL=https://api.exemplo.com apps/app
# A URL da API é embutida no build (constante de compilação do Flutter).

# SDK do Flutter fixado na mesma versão usada no CI e localmente (build reproduzível).
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.8
RUN apt-get update && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && git clone --depth 1 --branch $FLUTTER_VERSION https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN git config --global --add safe.directory /opt/flutter && flutter config --no-analytics && flutter precache --web
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
ARG API_BASE_URL=http://localhost:3333
ARG APP_VERSION=0.1.0
ARG GIT_SHA=dev
RUN flutter build web --release \
      --dart-define=API_BASE_URL=$API_BASE_URL \
      --dart-define=APP_VERSION=$APP_VERSION \
      --dart-define=GIT_SHA=$GIT_SHA \
  && printf '{"name":"hoink-web","version":"%s","commit":"%s"}\n' "$APP_VERSION" "$GIT_SHA" > build/web/version.json

# Imagem nginx sem privilégios de root (escuta na porta 8080).
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
# Usuário não-root (uid 101 = nginx) explícito.
USER 101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
