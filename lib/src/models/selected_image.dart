import 'dart:typed_data';

/// A JPEG the user picked, together with the dimensions read from its header.
class SelectedImage {
  const SelectedImage({
    required this.id,
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
  });

  final int id;
  final String name;
  final Uint8List bytes;
  final int width;
  final int height;

  int get byteSize => bytes.length;

  /// JPEG data can be embedded as-is; every other format has to be rasterised
  /// into the PDF, which is where the size matters.
  bool get isJpeg => bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  bool get isLandscape => width > height;

  String get dimensionsLabel => '$width × $height';

  String get sizeLabel => formatBytes(byteSize);
}

/// Human readable file size, e.g. `812 KB` or `2.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String digits = value >= 100 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$digits ${units[unit]}';
}
