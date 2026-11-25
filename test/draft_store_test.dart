import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/models/selected_image.dart';
import 'package:photo2pdf/src/services/draft_store.dart';
import 'package:photo2pdf/src/services/image_picker_service.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

SelectedImage _photo(String name, String fixture, int id) {
  final Uint8List bytes = _fixture(fixture);
  return SelectedImage(
    id: id,
    name: name,
    bytes: bytes,
    width: 800,
    height: 600,
  );
}

void main() {
  late Directory folder;
  late DraftStore store;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('photo2pdf_draft');
    store = DraftStore(directory: folder);
  });

  tearDown(() {
    if (folder.existsSync()) {
      folder.deleteSync(recursive: true);
    }
  });

  test('an untouched start has no draft', () async {
    expect(await store.load(), isEmpty);
  });

  test('the list comes back in order, with names and sizes', () async {
    final SelectedImage first = _photo('one.jpg', 'sample.jpg', 1);
    final SelectedImage second = _photo('two.png', 'sample.png', 2);

    await store.save(<SelectedImage>[first, second]);

    final List<SelectedImage> loaded = await store.load();
    expect(loaded.map((SelectedImage image) => image.name).toList(), <String>[
      'one.jpg',
      'two.png',
    ]);
    expect(loaded.first.bytes, first.bytes);
    expect(loaded.first.width, 800);
    expect(loaded.first.height, 600);
    expect(loaded.map((SelectedImage image) => image.id).toSet(), hasLength(2));
  });

  test('a reorder is just the manifest, not the photos again', () async {
    final SelectedImage first = _photo('one.jpg', 'sample.jpg', 1);
    final SelectedImage second = _photo('two.png', 'sample.png', 2);

    await store.save(<SelectedImage>[first, second]);
    final Map<String, DateTime> writtenAt = <String, DateTime>{
      for (final FileSystemEntity entity in folder.listSync())
        entity.path: entity.statSync().modified,
    };

    await store.save(<SelectedImage>[second, first]);

    final List<SelectedImage> loaded = await store.load();
    expect(loaded.map((SelectedImage image) => image.name).toList(), <String>[
      'two.png',
      'one.jpg',
    ]);

    final List<File> photos = folder
        .listSync()
        .whereType<File>()
        .where((File file) => !file.path.endsWith('draft.json'))
        .toList();
    expect(photos, hasLength(2));
    for (final File photo in photos) {
      expect(photo.statSync().modified, writtenAt[photo.path]);
    }
  });

  test('the same photo twice takes one file', () async {
    final SelectedImage first = _photo('one.jpg', 'sample.jpg', 1);
    final SelectedImage again = _photo('one again.jpg', 'sample.jpg', 2);

    await store.save(<SelectedImage>[first, again]);

    final List<SelectedImage> loaded = await store.load();
    expect(loaded.map((SelectedImage image) => image.name), <String>[
      'one.jpg',
      'one again.jpg',
    ]);

    final int files = folder
        .listSync()
        .whereType<File>()
        .where((File file) => !file.path.endsWith('draft.json'))
        .length;
    expect(files, 1);
  });

  test('a photo whose file vanished is skipped, the rest still load', () async {
    await store.save(<SelectedImage>[
      _photo('one.jpg', 'sample.jpg', 1),
      _photo('two.png', 'sample.png', 2),
    ]);

    final File victim = folder.listSync().whereType<File>().firstWhere(
      (File file) => file.path.endsWith('.jpg'),
    );
    victim.deleteSync();

    final List<SelectedImage> loaded = await store.load();
    expect(loaded.map((SelectedImage image) => image.name), <String>[
      'two.png',
    ]);
  });

  test('removing the last photo clears the folder', () async {
    await store.save(<SelectedImage>[_photo('one.jpg', 'sample.jpg', 1)]);
    await store.save(<SelectedImage>[]);

    expect(folder.listSync(), isEmpty);
    expect(await store.load(), isEmpty);
  });

  test('rubbish in the manifest is ignored rather than thrown', () async {
    File('${folder.path}/draft.json').writeAsStringSync('not json');

    expect(await store.load(), isEmpty);
  });

  test('a restored photo gets a fresh id', () async {
    await store.save(<SelectedImage>[_photo('one.jpg', 'sample.jpg', 1)]);
    final SelectedImage restored = (await store.load()).single;
    final SelectedImage added = ImagePickerService.instance.adopt(
      _fixture('sample.png'),
      'later.png',
      800,
      600,
    );

    expect(restored.id, isNot(added.id));
  });
}
