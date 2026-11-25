import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';

/// Where the PDF ended up, or `null` when the user cancelled.
class SaveResult {
  const SaveResult({this.path});

  final String? path;

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
      final String path = await FileSaver.instance.saveFile(
        name: stem,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.custom,
        customMimeType: 'application/pdf',
      );
      return SaveResult(path: path);
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
    return SaveResult(path: location.path);
  }
}
