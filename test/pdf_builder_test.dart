import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

/// A photo-like PNG: soft gradients plus grain, so it resists flate and shows
/// what compression is for.
SelectedImage _photoLike(int width, int height) {
  final img.Image image = img.Image(width: width, height: height);
  final math.Random random = math.Random(7);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int base = ((x * 255) ~/ width + (y * 255) ~/ height) ~/ 2;
      image.setPixelRgb(
        x,
        y,
        (base + random.nextInt(50)).clamp(0, 255),
        (base ~/ 2 + random.nextInt(50)).clamp(0, 255),
        (255 - base + random.nextInt(50)).clamp(0, 255),
      );
    }
  }
  final Uint8List bytes = img.encodePng(image);
  return SelectedImage(
    id: 99,
    name: 'photo.png',
    bytes: bytes,
    width: width,
    height: height,
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

    test('fill covers the page without changing its size', () async {
      // sample.jpg is 800x600 on a portrait A4 page, the case that leaves bars.
      final List<List<double>> fitPages = pageSizes(
        await buildPdf(
          <SelectedImage>[_load('sample.jpg')],
          const PdfOptions(orientation: PageOrientation.vertical),
        ),
      );
      final Uint8List filled = await buildPdf(
        <SelectedImage>[_load('sample.jpg')],
        const PdfOptions(
          orientation: PageOrientation.vertical,
          imageFit: ImageFit.fill,
        ),
      );

      expect(pageSizes(filled), fitPages, reason: 'only the photo moves');
      expect(ImageFit.fill.fillsPage, isTrue);
      expect(ImageFit.fit.fillsPage, isFalse);
      expect(String.fromCharCodes(filled.take(5)), '%PDF-');
    });

    test('compression makes a heavy photo much smaller', () async {
      // A noisy photo is what a camera roll is full of, and it is the case the
      // PNG-to-raw-pixels path cannot shrink on its own.
      final SelectedImage photo = _photoLike(900, 700);

      final Uint8List plain = await buildPdf(<SelectedImage>[photo], const PdfOptions());
      final Uint8List small = await buildPdf(
        <SelectedImage>[photo],
        const PdfOptions(compression: CompressionLevel.small),
      );

      expect(small.length, lessThan(plain.length ~/ 4));
      expect(String.fromCharCodes(small.take(5)), '%PDF-');
    });

    test('original compression leaves the bytes alone', () async {
      final SelectedImage photo = _photoLike(320, 240);

      final Uint8List plain = await buildPdf(<SelectedImage>[photo], const PdfOptions());
      final Uint8List again = await buildPdf(
        <SelectedImage>[photo],
        const PdfOptions(compression: CompressionLevel.original),
      );

      expect(again.length, plain.length);
    });

    test('compression keeps the photo the right way round', () async {
      final List<List<double>> pages = pageSizes(
        await buildPdf(
          <SelectedImage>[_load('sample.jpg')],
          const PdfOptions(compression: CompressionLevel.balanced),
        ),
      );

      expect(pages.first[0], greaterThan(pages.first[1]));
    });

    test('locks the document when a password is given', () async {
      final Uint8List locked = await buildPdf(
        <SelectedImage>[_load('sample.jpg')],
        const PdfOptions(password: 'hunter2'),
      );
      final String text = String.fromCharCodes(locked);

      expect(text.contains('/Encrypt'), isTrue);
      expect(text.contains('/Standard'), isTrue);
      expect(text.contains('/R 3'), isTrue);
    });

    test('leaves the document open without a password', () async {
      final String text = String.fromCharCodes(
        await buildPdf(<SelectedImage>[_load('sample.jpg')], const PdfOptions()),
      );

      expect(text.contains('/Encrypt'), isFalse);
    });

    test('rejects an empty image list', () {
      expect(
        () => buildPdf(<SelectedImage>[], const PdfOptions()),
        throwsArgumentError,
      );
    });
  });
}
