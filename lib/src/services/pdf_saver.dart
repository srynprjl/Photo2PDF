import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';

import 'save_location.dart';

/// Where the PDF ended up, or `null` when the user cancelled.
class SaveResult {
  const SaveResult({this.path, this.displayPath});

  /// The real location: a file path on desktop, a content URI on Android.
  final String? path;

  /// A short location a person can understand, e.g. `Downloads/report.pdf`.
  final String? displayPath;

  bool get saved => path != null && path!.isNotEmpty;
}

class PdfSaver {
  PdfSaver._();

  static const XTypeGroup _pdfTypes = XTypeGroup(
    label: 'PDF document',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
  );

  /// Writes [bytes] to the folder chosen in the settings.
  ///
  /// Android cannot write anywhere it likes, so it either drops the file into
  /// the shared `Downloads/Photo2PDF` folder or opens a dialog per save.
  /// Desktop writes straight into the folder, and only opens the "Save as"
  /// dialog when the user asked for it (or when that folder is not writable).
  static Future<SaveResult> save(
    Uint8List bytes,
    String fileName, {
    SaveLocation location = const SaveLocation(),
  }) async {
    final String stem = fileName.toLowerCase().endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    if (Platform.isAndroid || Platform.isIOS) {
      return _saveOnAndroid(bytes, stem, location);
    }
    return _saveOnDesktop(bytes, '$stem.pdf', location);
  }

  static Future<SaveResult> _saveOnAndroid(
    Uint8List bytes,
    String stem,
    SaveLocation location,
  ) async {
    if (location.askEveryTime) {
      final String? path = await FileSaver.instance.saveAs(
        name: stem,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.custom,
        customMimeType: 'application/pdf',
      );
      return SaveResult(path: path, displayPath: path == null ? null : '$stem.pdf');
    }

    final String displayName = 'Downloads/$androidSaveFolder/$stem.pdf';
    try {
      final String? path = await FileSaver.instance.saveToDownloads(
        name: stem,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.custom,
        customMimeType: 'application/pdf',
        subfolder: androidSaveFolder,
      );
      if (path != null && path.isNotEmpty) {
        return SaveResult(path: path, displayPath: displayName);
      }
    } on Exception {
      // Fall through to the private directory rather than losing the document.
    }

    final String path = await FileSaver.instance.saveFile(
      name: stem,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.custom,
      customMimeType: 'application/pdf',
    );
    return SaveResult(path: path, displayPath: '$stem.pdf');
  }

  static Future<SaveResult> _saveOnDesktop(
    Uint8List bytes,
    String fileName,
    SaveLocation location,
  ) async {
    if (!location.askEveryTime) {
      try {
        final String folder = location.folder ?? defaultSaveFolder();
        await Directory(folder).create(recursive: true);
        final String path = freeFilePath(folder, fileName);
        await File(path).writeAsBytes(bytes, flush: true);
        return SaveResult(path: path, displayPath: prettyPath(path));
      } on FileSystemException {
        // The folder is gone or not writable: let the person pick another one.
      }
    }

    final FileSaveLocation? chosen = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[_pdfTypes],
    );
    if (chosen == null) {
      return const SaveResult();
    }

    await File(chosen.path).writeAsBytes(bytes, flush: true);
    return SaveResult(path: chosen.path, displayPath: prettyPath(chosen.path));
  }
}
