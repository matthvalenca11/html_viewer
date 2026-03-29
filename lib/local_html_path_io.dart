import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> resolveLocalHtmlPath(PlatformFile file) async {
  if (file.path != null && file.path!.isNotEmpty) {
    final f = File(file.path!);
    if (await f.exists()) {
      return f.absolute.path;
    }
  }
  if (file.bytes != null) {
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/${file.name}');
    await out.writeAsBytes(file.bytes!);
    return out.absolute.path;
  }
  if (file.readStream != null) {
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/${file.name}');
    final sink = out.openWrite();
    try {
      await for (final chunk in file.readStream!) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    return out.absolute.path;
  }
  return null;
}
