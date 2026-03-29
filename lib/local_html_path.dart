import 'package:file_picker/file_picker.dart';

import 'local_html_path_io.dart'
    if (dart.library.html) 'local_html_path_stub.dart' as path_impl;

bool isHtmlFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

Future<String?> resolveLocalHtmlPath(PlatformFile file) =>
    path_impl.resolveLocalHtmlPath(file);
