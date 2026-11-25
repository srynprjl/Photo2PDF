import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/services/image_picker_service.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  // Dropped files arrive as plain paths, so this is the desktop drag & drop
  // intake without the window.
  group('ImagePickerService.addPaths', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('drop_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    String write(String name, List<int> bytes) {
      final File file = File('${temp.path}/$name')
        ..writeAsBytesSync(bytes, flush: true);
      return file.path;
    }

    test('reads dropped photos', () async {
      final PickedImages picked = await ImagePickerService.instance.addPaths(
        <String>[
          write('one.jpg', _fixture('sample.jpg')),
          write('two.png', _fixture('sample.png')),
        ],
      );

      expect(picked.rejected, isEmpty);
      expect(picked.images, hasLength(2));
      expect(picked.images.first.name, 'one.jpg');
      expect(picked.images.first.width, 800);
      expect(picked.images.first.height, 600);
      expect(picked.images[1].name, 'two.png');
      expect(picked.images[1].isJpeg, isFalse);
    });

    test('names the files it could not use', () async {
      final PickedImages picked = await ImagePickerService.instance.addPaths(
        <String>[
          write('notes.txt', <int>[1, 2, 3, 4]),
          '${temp.path}/missing.jpg',
          write('good.jpg', _fixture('sample.jpg')),
        ],
      );

      expect(picked.images, hasLength(1));
      expect(picked.images.single.name, 'good.jpg');
      expect(picked.rejected, <String>['notes.txt', 'missing.jpg']);
    });

    test('handles nothing being dropped', () async {
      final PickedImages picked = await ImagePickerService.instance.addPaths(
        <String>[],
      );

      expect(picked.images, isEmpty);
      expect(picked.rejected, isEmpty);
    });
  });
}
