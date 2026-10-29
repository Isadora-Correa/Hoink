import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveFile(Uint8List bytes, String fileName, String mimeType) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      fileNameOverrides: [fileName],
    ),
  );
}
