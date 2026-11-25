import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/selected_image.dart';
import 'image_picker_service.dart';

/// Keeps the photo list on disk, so a selection survives a restart, a rotation
/// that throws the app out of memory, or an accidental swipe away.
///
/// Photos are written as their own files inside the app's support folder and
/// named after their contents, so saving again after a reorder or a removal
/// only rewrites the small manifest. Nothing here is user-visible: the folder
/// is cleared the moment the selection is cleared.
class DraftStore {
  DraftStore({Directory? directory}) : _fixed = directory;

  /// The one the app uses; tests build their own with a temporary folder.
  static final DraftStore instance = DraftStore();

  static const String _manifestName = 'draft.json';

  final Directory? _fixed;
  Directory? _root;

  /// One write at a time: a remove landing while an add is half saved must not
  /// leave a manifest pointing at a file that was just deleted.
  Future<void> _queue = Future<void>.value();

  Future<List<SelectedImage>> load() {
    return _queued(() async {
      try {
        final Directory dir = await _directory();
        final File manifest = File(_pathOf(dir, _manifestName));
        if (!await manifest.exists()) {
          return const <SelectedImage>[];
        }

        final Object? decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map<String, Object?>) {
          return const <SelectedImage>[];
        }
        final Object? photos = decoded['photos'];
        if (photos is! List<Object?>) {
          return const <SelectedImage>[];
        }

        final List<SelectedImage> images = <SelectedImage>[];
        for (final Object? entry in photos) {
          if (entry is! Map<String, Object?>) continue;
          final Object? name = entry['name'];
          final Object? file = entry['file'];
          final Object? width = entry['width'];
          final Object? height = entry['height'];
          if (name is! String || file is! String) continue;

          final File photo = File(_pathOf(dir, file));
          if (!await photo.exists()) continue;
          final Uint8List bytes = await photo.readAsBytes();
          images.add(
            ImagePickerService.instance.adopt(
              bytes,
              name,
              width is int ? width : 0,
              height is int ? height : 0,
            ),
          );
        }
        return images;
      } on Exception {
        return const <SelectedImage>[];
      }
    });
  }

  /// Writes the list as it stands, in order. An empty list clears the draft.
  Future<void> save(List<SelectedImage> images) {
    return _queued(() async {
      try {
        if (images.isEmpty) {
          await _clearNow();
          return;
        }

        final Directory dir = await _directory();
        final List<Map<String, Object>> photos = <Map<String, Object>>[];
        final Set<String> keep = <String>{};

        for (final SelectedImage image in images) {
          final String file = _fileNameOf(image);
          keep.add(file);
          final File target = File(_pathOf(dir, file));
          if (!await target.exists()) {
            await target.writeAsBytes(image.bytes, flush: true);
          }
          photos.add(<String, Object>{
            'name': image.name,
            'width': image.width,
            'height': image.height,
            'file': file,
          });
        }

        // The manifest goes in last, through a rename, so a crash halfway
        // through never leaves a draft pointing at files that are not there.
        final File temp = File(_pathOf(dir, '$_manifestName.tmp'));
        await temp.writeAsString(
          jsonEncode(<String, Object>{'photos': photos}),
          flush: true,
        );
        await temp.rename(_pathOf(dir, _manifestName));

        await _deleteUnused(dir, keep);
      } on Exception {
        // A draft is a convenience: failing to save must never break the app.
      }
    });
  }

  Future<void> clear() {
    return _queued(() async {
      try {
        await _clearNow();
      } on Exception {
        // Same: nothing here is worth an error dialog.
      }
    });
  }

  Future<void> _clearNow() async {
    final Directory dir = await _directory();
    await for (final FileSystemEntity entity in dir.list()) {
      await entity.delete(recursive: true);
    }
  }

  Future<void> _deleteUnused(Directory dir, Set<String> keep) async {
    await for (final FileSystemEntity entity in dir.list()) {
      final String name = entity.uri.pathSegments.last;
      if (name == _manifestName || name == '$_manifestName.tmp') continue;
      if (!keep.contains(name)) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<Directory> _directory() async {
    final Directory? cached = _root;
    if (cached != null) return cached;

    final Directory dir;
    if (_fixed != null) {
      dir = _fixed;
    } else {
      final Directory support = await getApplicationSupportDirectory();
      dir = Directory(_pathOf(support, 'draft'));
    }
    await dir.create(recursive: true);
    return _root = dir;
  }

  Future<T> _queued<T>(Future<T> Function() action) {
    final Future<T> result = _queue.then<T>((void _) => action());
    _queue = result.then<void>((T _) {}, onError: (Object _) {});
    return result;
  }

  static String _pathOf(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';

  /// Named after the bytes, so an unchanged photo is never rewritten and the
  /// same photo picked twice takes one slot on disk.
  static String _fileNameOf(SelectedImage image) {
    final String digest = sha1.convert(image.bytes).toString().substring(0, 24);
    return image.isJpeg ? '$digest.jpg' : '$digest.img';
  }
}
