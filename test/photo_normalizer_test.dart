import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/photo_info.dart';
import 'package:photo2pdf/src/core/photo_normalizer.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('bakeJpegOrientation', () {
    test('rotates the pixels of a photo stored sideways', () {
      final Uint8List bytes = _fixture('rotated.jpg');
      expect(readPhotoInfo(bytes)!.width, 800);

      final PhotoInfo info = readPhotoInfo(bakeJpegOrientation(bytes))!;

      expect(info.width, 600);
      expect(info.height, 800);
    });

    test('leaves photos that are already upright alone', () {
      final Uint8List bytes = _fixture('sample.jpg');

      expect(identical(bakeJpegOrientation(bytes), bytes), isTrue);
    });

    test('leaves other formats alone', () {
      final Uint8List bytes = _fixture('sample.png');

      expect(identical(bakeJpegOrientation(bytes), bytes), isTrue);
    });
  });
}
