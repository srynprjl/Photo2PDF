import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Turns PDFium's bitmap into the JPEG that gets saved.
///
/// pdfrx already rasterizes a page on its own worker isolate, so the pixels
/// arrive without blocking the screen. What was left on the UI isolate was the
/// rest of the job — packing the BGRA buffer into an `image` and encoding it —
/// and that is about a quarter of a second for an A4 page at 200 DPI. A long
/// document spent that time on the UI isolate page after page, which is exactly
/// the freeze the PDF build used to have.
///
/// So the encode runs on an isolate of its own, one page at a time: the page
/// comes back as finished bytes and the screen keeps painting in between.
class PageEncoder {
  PageEncoder._();

  /// JPEG quality every exported page is written at.
  static const int quality = 85;

  /// JPEG bytes for a BGRA bitmap of [width] x [height].
  static Future<Uint8List> encode(
    Uint8List pixels, {
    required int width,
    required int height,
  }) {
    return _encodeOnIsolate(pixels, width, height);
  }

  /// The encode itself.
  ///
  /// Synchronous so it can run inside the isolate, and so a test can check the
  /// pixels without waiting for one.
  static Uint8List encodeSync(
    Uint8List pixels, {
    required int width,
    required int height,
  }) {
    // `fromBytes` reads from the start of the buffer, so a view that begins
    // part-way into one is copied out first.
    final Uint8List raw = pixels.offsetInBytes == 0
        ? pixels
        : Uint8List.fromList(pixels);

    // PDFium hands back BGRA, which is what the encoder expects to be told.
    final img.Image decoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: raw.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    return img.encodeJpg(decoded, quality: quality);
  }
}

/// Hands one page to `Isolate.run`.
///
/// The closure is made here, at the top level, with only the pixels and two
/// ints in scope on purpose: a closure carries the context of the function that
/// made it, and a context that reaches the screen — a state object, a callback,
/// a completer — makes the message unsendable.
Future<Uint8List> _encodeOnIsolate(Uint8List pixels, int width, int height) {
  return Isolate.run(
    () => PageEncoder.encodeSync(pixels, width: width, height: height),
  );
}
