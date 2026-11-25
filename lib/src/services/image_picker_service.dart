import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/photo_info.dart';
import '../core/photo_normalizer.dart';
import '../core/platform_decoder.dart';
import '../models/selected_image.dart';

/// Where the picker looks for photos.
enum PhotoSource { gallery, files, camera }

extension PhotoSourceLabels on PhotoSource {
  String get label => switch (this) {
    PhotoSource.gallery => 'Gallery',
    PhotoSource.files => 'Files',
    PhotoSource.camera => 'Camera',
  };
}

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

  /// Opens the gallery or the file browser. Returns `null` when the user
  /// cancels.
  ///
  /// The gallery is the default because it is the shortest way to a photo on a
  /// phone; the file browser stays one setting away for downloads and for the
  /// formats a gallery may hide.
  Future<PickedImages?> pick({PhotoSource source = PhotoSource.gallery}) async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: 'Choose photos',
      type: source == PhotoSource.gallery ? FileType.image : FileType.custom,
      allowedExtensions: source == PhotoSource.gallery
          ? null
          : const <String>[
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
      final SelectedImage? image = await _toSelected(
        await _readBytes(file),
        file.name,
      );
      if (image == null) {
        rejected.add(file.name);
      } else {
        images.add(image);
      }
    }

    return PickedImages(images: images, rejected: rejected);
  }

  /// Photos dropped onto the desktop window, which arrive as plain paths.
  ///
  /// They go through the same checks as picked files, so an unsupported file is
  /// reported rather than half-added.
  Future<PickedImages> addPaths(List<String> paths) async {
    final List<SelectedImage> images = <SelectedImage>[];
    final List<String> rejected = <String>[];

    for (final String path in paths) {
      final String name = path.split(Platform.pathSeparator).last;
      Uint8List? bytes;
      try {
        bytes = await File(path).readAsBytes();
      } on Exception {
        bytes = null;
      }
      final SelectedImage? image = await _toSelected(bytes, name);
      if (image == null) {
        rejected.add(name);
      } else {
        images.add(image);
      }
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

  /// Photos taken with the camera, which arrive as JPEG bytes.
  ///
  /// Each gets a distinct name, so a batch of pages does not all claim to be
  /// the same file when the PDF is named after the first photo.
  Future<PickedImages> addCaptures(List<Uint8List> photos) async {
    final DateTime at = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final String stamp =
        '${at.year}${two(at.month)}${two(at.day)}_'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';

    final List<SelectedImage> images = <SelectedImage>[];
    final List<String> rejected = <String>[];
    for (int i = 0; i < photos.length; i++) {
      final String name = 'camera_${stamp}_${i + 1}.jpg';
      final SelectedImage? image = await _toSelected(photos[i], name);
      if (image == null) {
        rejected.add(name);
      } else {
        images.add(image);
      }
    }
    return PickedImages(images: images, rejected: rejected);
  }

  /// A photo coming back from the saved draft, rather than from a picker.
  ///
  /// Ids still come from here, so a restored photo and one added afterwards
  /// can never share a key and confuse the reorderable list.
  SelectedImage adopt(Uint8List bytes, String name, int width, int height) {
    return SelectedImage(
      id: _nextId++,
      name: name,
      bytes: bytes,
      width: width,
      height: height,
    );
  }

  /// One file's journey into the list: right way up, decodable, measured.
  Future<SelectedImage?> _toSelected(Uint8List? raw, String name) async {
    if (raw == null) {
      return null;
    }

    // EXIF rotation lives in metadata, which PDF viewers ignore.
    Uint8List bytes = bakeJpegOrientation(raw);
    PhotoInfo? info = readPhotoInfo(bytes);

    // HEIC/AVIF and other container formats only the engine understands:
    // transcode once here so the PDF writer gets pixels it can embed.
    if (info == null) {
      final Uint8List? converted = await decodeWithPlatformCodec(bytes);
      if (converted == null) {
        return null;
      }
      final PhotoInfo? convertedInfo = readPhotoInfo(converted);
      if (convertedInfo == null) {
        return null;
      }
      bytes = converted;
      info = convertedInfo;
    }

    return SelectedImage(
      id: _nextId++,
      name: name,
      bytes: bytes,
      width: info.width,
      height: info.height,
    );
  }
}
