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

    /// Width and height of every page, in points, in page order.
    List<List<double>> pageSizes(Uint8List bytes) {
      final String text = String.fromCharCodes(bytes);
      return <List<double>>[
        for (final RegExpMatch match
            in RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]')
                .allMatches(text))
          <double>[double.parse(match.group(1)!), double.parse(match.group(2)!)],
      ];
    }

    test('turns a landscape page when asked for horizontal', () async {
      final List<List<double>> pages = pageSizes(
        await buildPdf(
          <SelectedImage>[_load('sample.jpg')],
          const PdfOptions(orientation: PageOrientation.horizontal),
        ),
      );

      expect(pages, hasLength(1));
      expect(pages.first[0], greaterThan(pages.first[1]));
    });

    test('keeps a landscape photo on a portrait page when asked', () async {
      // sample.jpg is 800x600, so auto would turn the page.
      final List<List<double>> pages = pageSizes(
        await buildPdf(
          <SelectedImage>[_load('sample.jpg')],
          const PdfOptions(orientation: PageOrientation.vertical),
        ),
      );

      expect(pages.first[0], lessThan(pages.first[1]));
    });

    test('auto follows each photo', () async {
      final List<List<double>> pages = pageSizes(
        await buildPdf(
          <SelectedImage>[_load('sample.jpg', id: 1), _load('sample.png', id: 2)],
          const PdfOptions(orientation: PageOrientation.auto),
        ),
      );

      // Both fixtures are 800x600, so both pages come out landscape.
      expect(pages, hasLength(2));
      for (final List<double> size in pages) {
        expect(size[0], greaterThan(size[1]));
      }
    });

    test('rejects an empty image list', () {
      expect(
        () => buildPdf(<SelectedImage>[], const PdfOptions()),
        throwsArgumentError,
      );
    });
  });
}
