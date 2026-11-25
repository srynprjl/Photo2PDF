import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/models/selected_image.dart';
import 'package:photo2pdf/src/services/image_picker_service.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('addCaptures', () {
    test('gives every camera shot its own name', () async {
      final Uint8List jpeg = _fixture('sample.jpg');

      final PickedImages picked = await ImagePickerService.instance.addCaptures(
        <Uint8List>[jpeg, jpeg, jpeg],
      );

      expect(picked.images, hasLength(3));
      expect(picked.rejected, isEmpty);
      final Set<String> names = picked.images
          .map((SelectedImage image) => image.name)
          .toSet();
      expect(names, hasLength(3));
      expect(names.every((String name) => name.startsWith('camera_')), isTrue);
      expect(names.every((String name) => name.endsWith('.jpg')), isTrue);
    });

    test('reads the size of what the camera handed over', () async {
      final PickedImages picked = await ImagePickerService.instance.addCaptures(
        <Uint8List>[_fixture('sample.jpg')],
      );

      expect(picked.images.single.width, 800);
      expect(picked.images.single.height, 600);
    });

    test('skips bytes that are not a photo', () async {
      final PickedImages picked = await ImagePickerService.instance.addCaptures(
        <Uint8List>[
          _fixture('sample.jpg'),
          Uint8List.fromList(<int>[1, 2, 3]),
        ],
      );

      expect(picked.images, hasLength(1));
      expect(picked.rejected, hasLength(1));
    });
  });
}
