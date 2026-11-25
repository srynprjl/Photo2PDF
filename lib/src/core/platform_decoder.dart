import 'dart:typed_data';
import 'dart:ui' as ui;

/// Last-resort decoder for formats the `image` package cannot read (HEIC, AVIF).
///
/// Android's platform codecs handle HEIF, so this is what makes iPhone-style
/// photos work there. Desktop engines usually cannot decode them and simply
/// return `null`, which the caller reports as an unsupported file.
///
/// Returns PNG bytes, or `null` when the platform cannot decode the data.
Future<Uint8List?> decodeWithPlatformCodec(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    image = frame.image;
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return data?.buffer.asUint8List();
  } on Exception {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
