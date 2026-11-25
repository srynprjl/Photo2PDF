import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo2pdf/src/services/page_encoder.dart';

/// A small BGRA bitmap: red on the left half, blue on the right half, which is
/// the channel order PDFium renders in.
Uint8List _bgra(int width, int height) {
  final Uint8List pixels = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int i = (y * width + x) * 4;
      final bool left = x < width ~/ 2;
      pixels[i] = left ? 0 : 255; // blue
      pixels[i + 1] = 0; // green
      pixels[i + 2] = left ? 255 : 0; // red
      pixels[i + 3] = 255; // opaque
    }
  }
  return pixels;
}

void main() {
  group('PageEncoder', () {
    test('turns a BGRA bitmap into a JPEG of the same shape', () {
      final Uint8List jpeg = PageEncoder.encodeSync(
        _bgra(16, 8),
        width: 16,
        height: 8,
      );

      expect(jpeg.sublist(0, 2), <int>[0xff, 0xd8]); // JPEG start of image
      final img.Image decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, 16);
      expect(decoded.height, 8);

      // JPEG is lossy, so the two halves are checked loosely.
      final img.Pixel left = decoded.getPixel(2, 4);
      final img.Pixel right = decoded.getPixel(13, 4);
      expect(left.r, greaterThan(200));
      expect(left.b, lessThan(60));
      expect(right.b, greaterThan(200));
      expect(right.r, lessThan(60));
    });

    test('a view that starts part-way into a buffer starts at its own pixel', () {
      final Uint8List padded = Uint8List(4 + 16 * 8 * 4);
      padded.setRange(4, padded.length, _bgra(16, 8));

      final img.Image decoded = img.decodeJpg(
        PageEncoder.encodeSync(
          Uint8List.sublistView(padded, 4),
          width: 16,
          height: 8,
        ),
      )!;

      expect(decoded.getPixel(2, 4).r, greaterThan(200));
      expect(decoded.getPixel(13, 4).b, greaterThan(200));
    });

    test('the isolate hands back the same bytes as encoding here', () async {
      final Uint8List pixels = _bgra(32, 16);

      final Uint8List offIsolate = await PageEncoder.encode(
        pixels,
        width: 32,
        height: 16,
      );

      expect(
        offIsolate,
        PageEncoder.encodeSync(pixels, width: 32, height: 16),
      );
    });
  });
}
