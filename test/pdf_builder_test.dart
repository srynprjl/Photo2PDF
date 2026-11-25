import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpg_to_pdf/src/core/jpeg_info.dart';
import 'package:jpg_to_pdf/src/core/pdf_builder.dart';
import 'package:jpg_to_pdf/src/models/selected_image.dart';

void main() {
  late SelectedImage image;

  setUpAll(() {
    final Uint8List bytes = File('test/fixtures/sample.jpg').readAsBytesSync();
    final JpegInfo info = readJpegInfo(bytes)!;
    image = SelectedImage(
      id: 1,
      name: 'sample.jpg',
      bytes: bytes,
      width: info.width,
      height: info.height,
    );
  });

  group('buildPdf', () {
    test('produces a valid PDF for every page size mode', () async {
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

    test('writes one page per image', () async {
      final Uint8List bytes = await buildPdf(
        <SelectedImage>[image, image, image],
        const PdfOptions(),
      );

      final String text = String.fromCharCodes(bytes);
      expect(RegExp(r'/Count\s+3\b').hasMatch(text), isTrue);
    });

    test('rejects an empty image list', () {
      expect(
        () => buildPdf(<SelectedImage>[], const PdfOptions()),
        throwsArgumentError,
      );
    });
  });
}
