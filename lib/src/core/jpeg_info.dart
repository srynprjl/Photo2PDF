import 'dart:typed_data';

/// What we need to know about a JPEG before it can be placed on a PDF page.
class JpegInfo {
  const JpegInfo({
    required this.width,
    required this.height,
    required this.components,
  });

  final int width;
  final int height;

  /// 1 = greyscale, 3 = YCbCr, 4 = CMYK/YCCK.
  final int components;

  /// The bundled PDF writer can only pass 1 and 3 component JPEGs through.
  bool get isCmyk => components == 4;
}

/// Reads the frame header (SOFn) of a JPEG to get its pixel dimensions.
///
/// Returns `null` when the data is not a baseline/progressive JPEG or the
/// header cannot be parsed, so callers can skip the file with a message.
JpegInfo? readJpegInfo(Uint8List bytes) {
  // Every JPEG starts with SOI (FF D8).
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }

  int offset = 2;
  while (offset + 3 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      // Stray byte between segments: resynchronise on the next marker.
      offset++;
      continue;
    }

    final int marker = bytes[offset + 1];
    if (marker == 0xFF) {
      // Fill byte before the real marker.
      offset++;
      continue;
    }
    if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
      // Standalone markers carry no length field.
      offset += 2;
      continue;
    }
    if (marker == 0xDA) {
      // Start of scan before any frame header - nothing to read.
      return null;
    }

    final int segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segmentLength < 2) {
      return null;
    }

    // SOF0-SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
    final bool isFrameHeader = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;

    if (isFrameHeader) {
      if (offset + 9 >= bytes.length) {
        return null;
      }
      final int height = (bytes[offset + 5] << 8) | bytes[offset + 6];
      final int width = (bytes[offset + 7] << 8) | bytes[offset + 8];
      final int components = bytes[offset + 9];
      if (width == 0 || height == 0) {
        return null;
      }
      return JpegInfo(width: width, height: height, components: components);
    }

    offset += 2 + segmentLength;
  }

  return null;
}
