import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/pdf_builder.dart';
import 'package:photo2pdf/src/core/photo_info.dart';
import 'package:photo2pdf/src/models/selected_image.dart';

SelectedImage _load(String name, {int id = 1}) {
  final Uint8List bytes = File('test/fixtures/$name').readAsBytesSync();
  final PhotoInfo info = readPhotoInfo(bytes)!;
  return SelectedImage(
    id: id,
    name: name,
    bytes: bytes,
    width: info.width,
    height: info.height,
  );
}

void main() {
  group('buildPdf', () {
    test('produces a valid PDF for every page size mode', () async {
      final SelectedImage image = _load('sample.jpg');

      for (final PageSizeMode mode in PageSizeMode.values) {
        final Uint8List bytes = await buildPdf(
          <SelectedImage>[image],
          PdfOptions(pageSize: mode),
        );

        expect(bytes.length, greaterThan(1000), reason: 'mode ${mode.name}');
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(
          String.fromCharCodes(bytes.skip(bytes.length - 8)),
          contains('%%EOF'),
        );
      }
    });

    test('writes one page per photo', () async {
      final Uint8List bytes = await buildPdf(
        <SelectedImage>[_load('sample.jpg', id: 1), _load('sample.jpg', id: 2)],
        const PdfOptions(),
      );

      expect(
        RegExp(r'/Count\s+2\b').hasMatch(String.fromCharCodes(bytes)),
        isTrue,
      );
    });

    test('embeds every supported photo format', () async {
      const List<String> files = <String>[
        'sample.jpg',
        'sample.png',
        'sample.webp',
        'sample.gif',
        'sample.bmp',
        'sample.tiff',
      ];

      final Uint8List bytes = await buildPdf(
        <SelectedImage>[
          for (int i = 0; i < files.length; i++) _load(files[i], id: i),
        ],
        const PdfOptions(),
      );

      final String text = String.fromCharCodes(bytes);
      expect(RegExp(r'/Count\s+6\b').hasMatch(text), isTrue);
      expect(bytes.length, greaterThan(20000));
    });

    test('rejects an empty image list', () {
      expect(
        () => buildPdf(<SelectedImage>[], const PdfOptions()),
        throwsArgumentError,
      );
    });
  });
}
