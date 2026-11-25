import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';

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

  /// Writes [bytes] to a file the user chooses.
  ///
  /// Android has no save dialog that Flutter itself can drive, so the file goes
  /// to the shared Downloads folder there. Desktop platforms get a real
  /// "Save as" dialog through the GTK / Win32 / Cocoa pickers.
  static Future<SaveResult> save(Uint8List bytes, String fileName) async {
    final String stem = fileName.toLowerCase().endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    if (Platform.isAndroid || Platform.isIOS) {
      final String displayName = 'Downloads/$stem.pdf';

      // The public Downloads folder is where people look for the result. It can
      // be unavailable (no MediaStore entry, permission denial), so fall back to
      // the app's own files directory rather than losing the document.
      try {
        final String? path = await FileSaver.instance.saveToDownloads(
          name: stem,
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.custom,
          customMimeType: 'application/pdf',
        );
        if (path != null && path.isNotEmpty) {
          return SaveResult(path: path, displayPath: displayName);
        }
      } on Exception {
        // Fall through to the private directory.
      }

      final String path = await FileSaver.instance.saveFile(
        name: stem,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.custom,
        customMimeType: 'application/pdf',
      );
      return SaveResult(
        path: path,
        displayPath: '$stem.pdf',
      );
    }

    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: '$stem.pdf',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'PDF document',
          extensions: <String>['pdf'],
          mimeTypes: <String>['application/pdf'],
        ),
      ],
    );
    if (location == null) {
      return const SaveResult();
    }

    await File(location.path).writeAsBytes(bytes, flush: true);
    return SaveResult(path: location.path, displayPath: location.path);
  }
}
