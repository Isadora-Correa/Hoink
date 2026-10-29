# App mobile (Android e iOS)

O mesmo código Flutter gera Web, Android e iOS. Identificador: `dev.hoink.hoink`; nome exibido: **hoink.**;
ícones gerados do ícone oficial (`apps/app/assets/icon/app-icon.png`, `dart run flutter_launcher_icons`).

## Permissões

| Plataforma | Permissão | Uso |
|---|---|---|
| Android | `INTERNET` | Falar com a API (declarada também na versão de produção) |
| Android / iOS | Câmera | Ler o QR Code da nota fiscal |
| iOS | Fotos | Escolher a foto de perfil |

## Gerar

```bash
cd apps/app
# Android (APK) apontando para a API publicada
flutter build apk --release --dart-define=API_BASE_URL=https://SUA-API
# Android (para a Play Store)
flutter build appbundle --release --dart-define=API_BASE_URL=https://SUA-API
# iOS (requer macOS com Xcode completo e conta Apple)
flutter build ipa --release --dart-define=API_BASE_URL=https://SUA-API
```

No emulador Android, a API local fica em `http://10.0.2.2:3333`.

## No CI

O job **App Android — build do APK** compila o APK a cada push e o publica como artefato
(`hoink-android-apk`). A URL da API vem da variável do repositório `API_PUBLIC_URL`.

## Antes de publicar nas lojas

- Assinatura de release do Android (keystore própria guardada como secret) — hoje o template usa a assinatura de
  debug no `release`.
- Conta de desenvolvedor (Google Play / Apple) e política de privacidade publicada.
- Testar em aparelho real a câmera (QR da NFC-e) e a escolha de foto.
