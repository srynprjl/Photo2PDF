import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/photo_info.dart';
import '../core/photo_normalizer.dart';
import '../core/platform_decoder.dart';
import '../models/selected_image.dart';

/// Result of one picker session.
class PickedImages {
  const PickedImages({required this.images, required this.rejected});

  final List<SelectedImage> images;

  /// File names that could not be read as a photo.
  final List<String> rejected;
}

class ImagePickerService {
  ImagePickerService._();

  static final ImagePickerService instance = ImagePickerService._();

  int _nextId = 0;

  /// Opens the platform file picker. Returns `null` when the user cancels.
  Future<PickedImages?> pick() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: 'Choose photos',
      type: FileType.custom,
      allowedExtensions: const <String>[
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'heif',
        'avif',
        'bmp',
        'gif',
        'tif',
        'tiff',
      ],
    );

    if (files.isEmpty) {
      return null;
    }

    final List<SelectedImage> images = <SelectedImage>[];
    final List<String> rejected = <String>[];

    for (final PlatformFile file in files) {
      Uint8List? bytes = await _readBytes(file);
      // EXIF rotation lives in metadata, which PDF viewers ignore.
      if (bytes != null) {
        bytes = bakeJpegOrientation(bytes);
      }
      PhotoInfo? info = bytes == null ? null : readPhotoInfo(bytes);

      // HEIC/AVIF and other container formats only the engine understands:
      // transcode once here so the PDF writer gets pixels it can embed.
      if (bytes != null && info == null) {
        final Uint8List? converted = await decodeWithPlatformCodec(bytes);
        if (converted != null) {
          final PhotoInfo? convertedInfo = readPhotoInfo(converted);
          if (convertedInfo != null) {
            bytes = converted;
            info = convertedInfo;
          }
        }
      }

      if (bytes == null || info == null) {
        rejected.add(file.name);
        continue;
      }

      images.add(
        SelectedImage(
          id: _nextId++,
          name: file.name,
          bytes: bytes,
          width: info.width,
          height: info.height,
        ),
      );
    }

    return PickedImages(images: images, rejected: rejected);
  }

  Future<Uint8List?> _readBytes(PlatformFile file) async {
    try {
      return await file.readAsBytes();
    } on Exception {
      return null;
    }
  }
}
