import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Photo container formats we can read.
enum PhotoFormat { jpeg, png, webp, gif, bmp, tiff, tga, ico, psd, pnm, exr, pvr, other }

/// What we need to know about a photo before it can go on a page.
class PhotoInfo {
  const PhotoInfo({
    required this.width,
    required this.height,
    required this.format,
  });

  final int width;
  final int height;
  final PhotoFormat format;

  bool get isLandscape => width > height;
}

/// Reads the pixel size of a photo from its header.
///
/// JPEG is parsed directly (fast, and it also tells us the component count).
/// Every other format goes through the `image` package's decoder, which covers
/// PNG, WebP, GIF, BMP, TIFF, TGA, ICO, PSD, PNM, EXR and PVR.
///
/// Returns `null` when nothing can read the data — for example HEIC/AVIF, which
/// need a platform codec (see `platform_decoder.dart`).
PhotoInfo? readPhotoInfo(Uint8List bytes) {
  final JpegInfo? jpeg = readJpegInfo(bytes);
  if (jpeg != null) {
    return PhotoInfo(
      width: jpeg.width,
      height: jpeg.height,
      format: PhotoFormat.jpeg,
    );
  }

  final img.Decoder? decoder = img.findDecoderForData(bytes);
  if (decoder == null) {
    return null;
  }

  try {
    final img.DecodeInfo? info = decoder.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      return null;
    }
    return PhotoInfo(
      width: info.width,
      height: info.height,
      format: sniffFormat(bytes),
    );
  } on Exception {
    return null;
  }
}

/// Identifies a format from its magic bytes, for the formats we display.
PhotoFormat sniffFormat(Uint8List bytes) {
  bool startsWith(List<int> magic, {int offset = 0}) {
    if (bytes.length < offset + magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(<int>[0xFF, 0xD8, 0xFF])) return PhotoFormat.jpeg;
  if (startsWith(<int>[0x89, 0x50, 0x4E, 0x47])) return PhotoFormat.png;
  if (startsWith(<int>[0x47, 0x49, 0x46, 0x38])) return PhotoFormat.gif;
  if (startsWith(<int>[0x42, 0x4D])) return PhotoFormat.bmp;
  if (startsWith(<int>[0x49, 0x49, 0x2A, 0x00]) ||
      startsWith(<int>[0x4D, 0x4D, 0x00, 0x2A])) {
    return PhotoFormat.tiff;
  }
  if (startsWith(<int>[0x38, 0x42, 0x50, 0x53])) return PhotoFormat.psd;
  if (startsWith(<int>[0x52, 0x49, 0x46, 0x46]) &&
      startsWith(<int>[0x57, 0x45, 0x42, 0x50], offset: 8)) {
    return PhotoFormat.webp;
  }
  return PhotoFormat.other;
}

/// What we need from a JPEG before it can go on a PDF page.
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
}

/// Reads the frame header (SOFn) of a JPEG to get its pixel dimensions.
///
/// Returns `null` when the data is not a baseline/progressive JPEG or the
/// header cannot be parsed, so callers can try another decoder.
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
