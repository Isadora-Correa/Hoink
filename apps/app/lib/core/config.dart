/// URL da API. Defina em build/execução com `--dart-define=API_BASE_URL=https://...`.
/// Emulador Android: use http://10.0.2.2:3333.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3333');

/// Identificação da versão publicada (injetada no build pelo pipeline de CD).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
const gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
