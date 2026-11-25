import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/jpeg_info.dart';
import '../models/selected_image.dart';

/// Result of one picker session.
class PickedImages {
  const PickedImages({required this.images, required this.rejected});

  final List<SelectedImage> images;

  /// File names that were not usable (not a JPEG, broken header or CMYK).
  final List<String> rejected;
}

class ImagePickerService {
  ImagePickerService._();

  static final ImagePickerService instance = ImagePickerService._();

  int _nextId = 0;

  /// Opens the platform file picker. Returns `null` when the user cancels.
  Future<PickedImages?> pick() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: 'Choose JPG images',
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg'],
    );

    if (files.isEmpty) {
      return null;
    }

    final List<SelectedImage> images = <SelectedImage>[];
    final List<String> rejected = <String>[];

    for (final PlatformFile file in files) {
      final Uint8List? bytes = await _readBytes(file);
      final JpegInfo? info = bytes == null ? null : readJpegInfo(bytes);
      if (bytes == null || info == null || info.isCmyk) {
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
