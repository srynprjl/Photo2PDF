import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/pdf_builder.dart';
import 'package:photo2pdf/src/models/selected_image.dart';
import 'package:photo2pdf/src/services/pdf_worker.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

List<SelectedImage> _photos(int count) {
  const List<String> names = <String>[
    'sample.jpg',
    'sample.png',
    'rotated.jpg',
  ];
  return <SelectedImage>[
    for (int i = 0; i < count; i++)
      SelectedImage(
        id: i,
        name: 'photo_$i.jpg',
        bytes: _fixture(names[i % names.length]),
        width: 800,
        height: 600,
      ),
  ];
}

void main() {
  group('buildPdf progress', () {
    test('counts every page once, in order', () async {
      final List<List<int>> seen = <List<int>>[];

      await buildPdf(
        _photos(3),
        const PdfOptions(),
        onPage: (int done, int total) => seen.add(<int>[done, total]),
      );

      expect(seen, <List<int>>[
        <int>[1, 3],
        <int>[2, 3],
        <int>[3, 3],
      ]);
    });
  });

  group('PdfWorker', () {
    test('builds the PDF off the UI isolate and reports each page', () async {
      final List<PdfProgress> seen = <PdfProgress>[];
      final List<int> values = <int>[];

      final Uint8List bytes = await PdfWorker.build(
        _photos(3),
        const PdfOptions(compression: CompressionLevel.balanced),
        onProgress: (PdfProgress progress) {
          seen.add(progress);
          if (progress.fraction != null) values.add(0);
        },
      );

      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(seen.first.done, 0);
      expect(seen.last.total, 3);
      expect(seen.map((PdfProgress progress) => progress.done).toSet(), <int>{
        0,
        1,
        2,
        3,
      });
      expect(seen.last.lastPageDone, isTrue);
      expect(seen.last.label, 'Writing the file…');
      expect(values, hasLength(seen.length));
    });

    test('the caller\'s own state never travels with the job', () async {
      // A Completer cannot be sent to another isolate. Holding one in the
      // callback is what a screen does with its State, and it used to make the
      // whole build fail with `Illegal argument in isolate message`.
      final Completer<void> finished = Completer<void>();

      final Uint8List bytes = await PdfWorker.build(
        _photos(2),
        const PdfOptions(),
        onProgress: (PdfProgress progress) {
          if (progress.lastPageDone && !finished.isCompleted) {
            finished.complete();
          }
        },
      );

      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(finished.isCompleted, isTrue);
    });

    test('a page in progress reads as a page count', () {
      const PdfProgress progress = PdfProgress(done: 2, total: 5);

      expect(progress.label, 'Page 2 of 5');
      expect(progress.fraction, closeTo(0.4, 1e-9));
      expect(progress.lastPageDone, isFalse);
    });

    test('the options survive the trip to the isolate', () async {
      final Uint8List bytes = await PdfWorker.build(
        _photos(1),
        const PdfOptions(
          pageSize: PageSizeMode.letter,
          orientation: PageOrientation.horizontal,
          imageFit: ImageFit.fill,
          marginMm: 0,
          password: 'test1234',
        ),
      );

      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test(
      'an empty list is refused rather than handing back an empty file',
      () async {
        await expectLater(
          PdfWorker.build(<SelectedImage>[], const PdfOptions()),
          throwsArgumentError,
        );
      },
    );
  });
}
