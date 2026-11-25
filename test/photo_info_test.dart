import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/photo_info.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('readPhotoInfo', () {
    test('reads a baseline JPEG', () {
      final PhotoInfo? info = readPhotoInfo(_fixture('sample.jpg'));

      expect(info, isNotNull);
      expect(info!.width, 800);
      expect(info.height, 600);
      expect(info.isLandscape, isTrue);
    });

    test('reads every other common photo format', () {
      const List<String> files = <String>[
        'sample.png',
        'sample.webp',
        'sample.gif',
        'sample.bmp',
        'sample.tiff',
      ];

      for (final String file in files) {
        final PhotoInfo? info = readPhotoInfo(_fixture(file));
        expect(info, isNotNull, reason: file);
        expect(info!.width, 800, reason: file);
        expect(info.height, 600, reason: file);
      }
    });

    test('returns null for data it cannot read', () {
      expect(readPhotoInfo(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
      expect(readPhotoInfo(Uint8List(0)), isNull);
      // HEIC/AVIF headers are not supported by the pure-Dart decoder.
      expect(readPhotoInfo(_fixture('sample.heic')), isNull);
    });
  });

  group('readJpegInfo', () {
    test('reads the frame header', () {
      final JpegInfo? info = readJpegInfo(_fixture('sample.jpg'));

      expect(info, isNotNull);
      expect(info!.width, 800);
      expect(info.height, 600);
    });

    test('ignores non-JPEG data', () {
      expect(readJpegInfo(_fixture('sample.png')), isNull);
      expect(readJpegInfo(Uint8List.fromList(<int>[0xFF, 0xD8, 0x00, 0x00])), isNull);
    });
  });
}
