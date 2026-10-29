import 'dart:typed_data';

import 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Salva um arquivo gerado pela API: download no navegador; compartilhar/salvar no celular.
Future<void> saveFile(Uint8List bytes, String fileName, String mimeType) => impl.saveFile(bytes, fileName, mimeType);
