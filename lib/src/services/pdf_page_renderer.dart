import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'page_encoder.dart';

/// One page of a PDF, already turned into pixels.
class PdfPageImage {
  const PdfPageImage({required this.number, required this.bytes});

  /// 1-based page number.
  final int number;

  /// JPEG bytes.
  final Uint8List bytes;
}

class PdfPageRenderer {
  PdfPageRenderer._();

  /// How many pages the document has, without rendering anything.
  ///
  /// [passwordProvider] is asked for a password when the document is locked,
  /// and asked again after a wrong one; returning `null` gives up.
  static Future<int> pageCount(
    Uint8List bytes, {
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
  }) async {
    final PdfDocument document = await PdfDocument.openData(
      bytes,
      sourceName: sourceName,
      passwordProvider: passwordProvider,
    );
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  /// Renders the chosen pages as JPEGs, one page at a time so a long PDF never
  /// holds all the pixels in memory at once.
  ///
  /// PDFium draws on pdfrx's own worker isolate; the JPEG encode then runs on a
  /// second one ([PageEncoder]), so a page's worth of work never sits on the UI
  /// isolate and the progress bar keeps moving through a long document.
  ///
  /// [dpi] is the resolution the page is drawn at: 150 is a screen-sized sheet,
  /// 300 is print quality and roughly four times the pixels.
  ///
  /// [pages] are 1-based page numbers; `null` means every page. They are
  /// rendered in the order given, and numbers outside the document are skipped.
  static Stream<PdfPageImage> render(
    Uint8List bytes, {
    required String sourceName,
    required int dpi,
    List<int>? pages,
    PdfPasswordProvider? passwordProvider,
  }) async* {
    final PdfDocument document = await PdfDocument.openData(
      bytes,
      sourceName: sourceName,
      passwordProvider: passwordProvider,
    );
    try {
      final List<PdfPage> all = document.pages;
      final List<int> wanted = pages ??
          <int>[for (int i = 0; i < all.length; i++) i + 1];
      for (final int number in wanted) {
        if (number < 1 || number > all.length) {
          continue;
        }
        final PdfPage page = all[number - 1];
        final PdfImage? raster = await page.render(
          // Page sizes are in points; 72 of them make an inch.
          fullWidth: page.width / 72 * dpi,
          fullHeight: page.height / 72 * dpi,
        );
        if (raster == null) {
          continue;
        }

        final Uint8List jpeg = await PageEncoder.encode(
          raster.pixels,
          width: raster.width,
          height: raster.height,
        );
        raster.dispose();

        yield PdfPageImage(number: number, bytes: jpeg);
      }
    } finally {
      await document.dispose();
    }
  }
}

