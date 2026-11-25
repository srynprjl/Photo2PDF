import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

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
  static Future<int> pageCount(
    Uint8List bytes, {
    required String sourceName,
  }) async {
    final PdfDocument document = await PdfDocument.openData(
      bytes,
      sourceName: sourceName,
    );
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  /// Renders every page as a JPEG, one page at a time so a long PDF never holds
  /// all the pixels in memory at once.
  ///
  /// [dpi] is the resolution the page is drawn at: 150 is a screen-sized sheet,
  /// 300 is print quality and roughly four times the pixels.
  static Stream<PdfPageImage> render(
    Uint8List bytes, {
    required String sourceName,
    required int dpi,
  }) async* {
    final PdfDocument document = await PdfDocument.openData(
      bytes,
      sourceName: sourceName,
    );
    try {
      final List<PdfPage> pages = document.pages;
      for (int i = 0; i < pages.length; i++) {
        final PdfPage page = pages[i];
        final PdfImage? raster = await page.render(
          // Page sizes are in points; 72 of them make an inch.
          fullWidth: page.width / 72 * dpi,
          fullHeight: page.height / 72 * dpi,
        );
        if (raster == null) {
          continue;
        }

        // PDFium hands back BGRA, which is what the encoder expects to be told.
        final img.Image decoded = img.Image.fromBytes(
          width: raster.width,
          height: raster.height,
          bytes: raster.pixels.buffer,
          numChannels: 4,
          order: img.ChannelOrder.bgra,
        );
        final Uint8List jpeg = img.encodeJpg(decoded, quality: 85);
        raster.dispose();

        yield PdfPageImage(number: i + 1, bytes: jpeg);
      }
    } finally {
      await document.dispose();
    }
  }
}

