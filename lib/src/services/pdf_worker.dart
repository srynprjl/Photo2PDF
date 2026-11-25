import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/pdf_builder.dart';
import '../models/selected_image.dart';

/// How far the PDF has got.
class PdfProgress {
  const PdfProgress({required this.done, required this.total});

  final int done;
  final int total;

  /// Every page is in; what is left is writing the file.
  bool get lastPageDone => done >= total;

  String get label =>
      lastPageDone ? 'Writing the file…' : 'Page $done of $total';

  /// 0..1 for a progress bar; `null` when there is nothing to divide by.
  double? get fraction =>
      total <= 0 ? null : (done / total).clamp(0.0, 1.0).toDouble();
}

/// Builds the PDF in a background isolate.
///
/// Encoding a few dozen photos takes seconds, and doing it on the UI isolate
/// freezes the app for exactly that long. Everything the builder needs is plain
/// data, so the work moves across and the page count comes back as it goes.
class PdfWorker {
  PdfWorker._();

  static Future<Uint8List> build(
    List<SelectedImage> images,
    PdfOptions options, {
    void Function(PdfProgress progress)? onProgress,
  }) async {
    if (images.isEmpty) {
      throw ArgumentError.value(images, 'images', 'cannot be empty');
    }

    final int total = images.length;
    final List<Map<String, Object?>> encodedImages = <Map<String, Object?>>[
      for (final SelectedImage image in images)
        <String, Object?>{
          'name': image.name,
          'bytes': image.bytes,
          'width': image.width,
          'height': image.height,
        },
    ];
    final Map<String, Object?> encodedOptions = <String, Object?>{
      'pageSize': options.pageSize.name,
      'marginMm': options.marginMm,
      'orientation': options.orientation.name,
      'imageFit': options.imageFit.name,
      'compression': options.compression.name,
      'password': options.password,
    };

    onProgress?.call(PdfProgress(done: 0, total: total));

    final ReceivePort reports = ReceivePort();
    final SendPort send = reports.sendPort;
    final StreamSubscription<Object?> pages = reports.listen((Object? event) {
      if (event is List<Object?> && event.length == 2) {
        final Object? done = event[0];
        final Object? of = event[1];
        if (done is int && of is int) {
          onProgress?.call(PdfProgress(done: done, total: of));
        }
      }
    });

    try {
      return await _buildOnIsolate(encodedImages, encodedOptions, send);
    } finally {
      await pages.cancel();
      reports.close();
    }
  }
}

/// Hands the job to `Isolate.run`.
///
/// The closure is made here, at the top level, rather than in [PdfWorker.build]
/// on purpose: a closure carries the whole context of the function that made
/// it, and `build` holds the caller's progress callback — which reaches back
/// into a screen and makes the message unsendable.
Future<Uint8List> _buildOnIsolate(
  List<Map<String, Object?>> encodedImages,
  Map<String, Object?> encodedOptions,
  SendPort send,
) {
  return Isolate.run(
    () => buildPdf(
      _decodeImages(encodedImages),
      _decodeOptions(encodedOptions),
      onPage: (int done, int total) => send.send(<Object?>[done, total]),
    ),
  );
}

/// Only plain lists, maps and typed data cross an isolate boundary, so both
/// sides rebuild the small objects from those.
List<SelectedImage> _decodeImages(List<Map<String, Object?>> encoded) {
  final List<SelectedImage> images = <SelectedImage>[];
  for (int i = 0; i < encoded.length; i++) {
    final Map<String, Object?> entry = encoded[i];
    final Object? bytes = entry['bytes'];
    if (bytes is! Uint8List) continue;
    images.add(
      SelectedImage(
        id: i,
        name: entry['name'] as String? ?? 'photo_$i',
        bytes: bytes,
        width: entry['width'] as int? ?? 0,
        height: entry['height'] as int? ?? 0,
      ),
    );
  }
  return images;
}

PdfOptions _decodeOptions(Map<String, Object?> encoded) {
  return PdfOptions(
    pageSize: PageSizeMode.values.byName(
      encoded['pageSize'] as String? ?? PageSizeMode.a4.name,
    ),
    marginMm: (encoded['marginMm'] as num?)?.toDouble() ?? 10,
    orientation: PageOrientation.values.byName(
      encoded['orientation'] as String? ?? PageOrientation.auto.name,
    ),
    imageFit: ImageFit.values.byName(
      encoded['imageFit'] as String? ?? ImageFit.fit.name,
    ),
    compression: CompressionLevel.values.byName(
      encoded['compression'] as String? ?? CompressionLevel.original.name,
    ),
    password: encoded['password'] as String?,
  );
}
