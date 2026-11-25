import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/services/pdf_saver.dart';
import 'package:photo2pdf/src/services/save_location.dart';

void main() {
  group('defaultSaveFolderFor', () {
    test('prefers Downloads', () {
      expect(
        defaultSaveFolderFor('/home/me', hasDownloads: true),
        '/home/me/Downloads/Photo2PDF',
      );
    });

    test('falls back to Documents', () {
      expect(
        defaultSaveFolderFor('/home/me', hasDownloads: false),
        '/home/me/Documents/Photo2PDF',
      );
    });

    test('uses the platform separator', () {
      expect(
        defaultSaveFolderFor(r'C:\Users\me', hasDownloads: true, separator: r'\'),
        r'C:\Users\me\Downloads\Photo2PDF',
      );
    });
  });

  group('freeFilePath', () {
    test('keeps the name when it is free', () {
      expect(
        freeFilePath('/tmp/pdf', 'scan.pdf', isTaken: (_) => false),
        '/tmp/pdf/scan.pdf',
      );
    });

    test('counts up instead of overwriting', () {
      final Set<String> taken = <String>{'/tmp/pdf/scan.pdf', '/tmp/pdf/scan (2).pdf'};
      expect(
        freeFilePath('/tmp/pdf', 'scan.pdf', isTaken: taken.contains),
        '/tmp/pdf/scan (3).pdf',
      );
    });

    test('keeps the extension it was given', () {
      expect(
        freeFilePath(
          '/tmp/pdf',
          'scan-page-2.jpg',
          isTaken: (String path) => path == '/tmp/pdf/scan-page-2.jpg',
        ),
        '/tmp/pdf/scan-page-2 (2).jpg',
      );
    });
  });

  group('pageFileName', () {
    test('names a photo after the PDF and its page', () {
      expect(pageFileName('holiday.pdf', 3), 'holiday-page-3.jpg');
    });

    test('drops characters a file system may refuse', () {
      expect(pageFileName('2026/notes: final.pdf', 1), '2026_notes_ final-page-1.jpg');
    });
  });

  test('prettyPath hides the home folder', () {
    expect(
      prettyPath('/home/me/Downloads/Photo2PDF/x.pdf', home: '/home/me'),
      '~/Downloads/Photo2PDF/x.pdf',
    );
    expect(prettyPath('/sdcard/x.pdf', home: '/home/me'), '/sdcard/x.pdf');
  });

  group('saveLocationLabel', () {
    test('names the android folder', () {
      expect(
        saveLocationLabel(const SaveLocation(), android: true),
        'Downloads/Photo2PDF',
      );
    });

    test('names the desktop folder', () {
      expect(
        saveLocationLabel(
          const SaveLocation(folder: '/home/me/Documents/PDFs'),
          android: false,
        ),
        '/home/me/Documents/PDFs',
      );
    });

    test('says so when the dialog is used', () {
      expect(
        saveLocationLabel(
          const SaveLocation(askEveryTime: true),
          android: true,
        ),
        'Ask every time',
      );
    });
  });

  group('PdfSaver in a folder', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('photo2pdf_test');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('writes into the chosen folder without a dialog', () async {
      final Uint8List bytes = Uint8List.fromList(<int>[37, 80, 68, 70]);

      final SaveResult result = await PdfSaver.save(
        bytes,
        'scan.pdf',
        location: SaveLocation(folder: temp.path),
      );

      expect(result.saved, isTrue);
      expect(File('${temp.path}/scan.pdf').readAsBytesSync(), bytes);
      expect(result.displayPath, '${temp.path}/scan.pdf');
    });

    test('does not overwrite an earlier PDF', () async {
      final Uint8List bytes = Uint8List.fromList(<int>[37, 80, 68, 70]);
      final SaveLocation location = SaveLocation(folder: temp.path);

      await PdfSaver.save(bytes, 'scan.pdf', location: location);
      await PdfSaver.save(bytes, 'scan.pdf', location: location);

      expect(File('${temp.path}/scan (2).pdf').existsSync(), isTrue);
    });

    test('creates the folder when it is missing', () async {
      final String nested = '${temp.path}/Photos/PDF';

      await PdfSaver.save(
        Uint8List.fromList(<int>[37, 80, 68, 70]),
        'scan.pdf',
        location: SaveLocation(folder: nested),
      );

      expect(File('$nested/scan.pdf').existsSync(), isTrue);
    });
  });
}
