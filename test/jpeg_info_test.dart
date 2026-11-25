import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jpg_to_pdf/src/core/jpeg_info.dart';

void main() {
  group('readJpegInfo', () {
    test('reads width, height and components from a baseline JPEG', () {
      final Uint8List bytes = File('test/fixtures/sample.jpg').readAsBytesSync();

      final JpegInfo? info = readJpegInfo(bytes);

      expect(info, isNotNull);
      expect(info!.width, 800);
      expect(info.height, 600);
      expect(info.components, 3);
      expect(info.isCmyk, isFalse);
    });

    test('returns null for data that is not a JPEG', () {
      expect(readJpegInfo(Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47])), isNull);
      expect(readJpegInfo(Uint8List.fromList(<int>[0xFF, 0xD8, 0x00, 0x00])), isNull);
      expect(readJpegInfo(Uint8List(0)), isNull);
    });

    test('reports CMYK JPEGs so they can be skipped', () {
      final Uint8List bytes = File('test/fixtures/sample.jpg').readAsBytesSync();
      // Patch the component count in the SOF0 marker to 4 (CMYK).
      final int sofIndex = _indexOfSof0(bytes);
      expect(sofIndex, greaterThan(0));

      final Uint8List patched = Uint8List.fromList(bytes);
      patched[sofIndex + 9] = 4;

      expect(readJpegInfo(patched)!.isCmyk, isTrue);
    });
  });
}

int _indexOfSof0(Uint8List bytes) {
  for (int i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xC0) {
      return i;
    }
  }
  return -1;
}
