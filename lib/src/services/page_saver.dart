import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import 'save_location.dart';

/// Writes the photos that come out of a PDF.
///
/// Unlike a PDF export there is no dialog here: a 20 page document would mean
/// 20 dialogs. The pages land next to the PDFs, which is where people look.
class PageSaver {
  PageSaver._();

  /// Saves one JPEG and returns the location as a person would say it.
  static Future<String> save(
    Uint8List bytes,
    String fileName, {
    SaveLocation location = const SaveLocation(),
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final String stem = fileName.replaceFirst(
        RegExp(r'\.jpg$', caseSensitive: false),
        '',
      );
      final String displayName = 'Downloads/$androidSaveFolder/$fileName';
      try {
        final String? path = await FileSaver.instance.saveToDownloads(
          name: stem,
          bytes: bytes,
          fileExtension: 'jpg',
          mimeType: MimeType.jpeg,
          subfolder: androidSaveFolder,
        );
        if (path != null && path.isNotEmpty) {
          return displayName;
        }
      } on Exception {
        // Fall through to the app's own folder.
      }

      final String path = await FileSaver.instance.saveFile(
        name: stem,
        bytes: bytes,
        fileExtension: 'jpg',
        mimeType: MimeType.jpeg,
      );
      return path;
    }

    final String folder = location.folder ?? defaultSaveFolder();
    await Directory(folder).create(recursive: true);
    final String path = freeFilePath(folder, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    return prettyPath(path);
  }
}
