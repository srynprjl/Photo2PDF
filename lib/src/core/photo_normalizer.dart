import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Applies the EXIF orientation of a JPEG to its pixels.
///
/// PDF viewers ignore EXIF rotation, so a portrait photo stored sideways would
/// land on the page sideways. Photos that need no rotation - and every
/// non-JPEG - come back unchanged, so most files are still embedded without
/// re-encoding.
Uint8List bakeJpegOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return bytes;
  }

  final img.ExifData? exif = img.decodeJpgExif(bytes);
  final bool needsRotation = exif != null &&
      exif.imageIfd.hasOrientation &&
      exif.imageIfd.orientation != 1;
  if (!needsRotation) {
    return bytes;
  }

  final img.Image? decoded = img.decodeJpg(bytes);
  if (decoded == null) {
    return bytes;
  }

  final img.Image baked = img.bakeOrientation(decoded);
  // Drop the metadata: GPS position and device serial numbers have no place in
  // a document, and the rotation is now part of the pixels.
  baked.exif = img.ExifData();
  return img.encodeJpg(baked, quality: 92);
}
