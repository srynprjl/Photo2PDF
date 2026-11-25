import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/selected_image.dart';

/// How the page is sized for each image.
enum PageSizeMode { a4, letter, fitImage }

extension PageSizeModeLabels on PageSizeMode {
  String get label => switch (this) {
    PageSizeMode.a4 => 'A4',
    PageSizeMode.letter => 'Letter',
    PageSizeMode.fitImage => 'Fit image',
  };
}

class PdfOptions {
  const PdfOptions({this.pageSize = PageSizeMode.a4, this.marginMm = 10});

  final PageSizeMode pageSize;

  /// White border around the image on fixed page sizes, in millimetres.
  final double marginMm;
}

/// DPI used to turn pixels into points when the page should match the photo.
/// 150 DPI keeps a 12 MP photo at roughly A4 size instead of a 40 inch page.
const double _imageDpi = 150;

/// PDF viewers reject pages larger than 14400 points per side.
const double _maxPageSide = 14400;

/// Builds a single PDF with one page per photo, in the given order.
///
/// JPEG bytes are embedded as-is (no re-encoding), so the output stays small and
/// keeps the original quality. Other formats are decoded by the PDF writer and
/// stored as pixels.
Future<Uint8List> buildPdf(
  List<SelectedImage> images,
  PdfOptions options,
) async {
  if (images.isEmpty) {
    throw ArgumentError.value(images, 'images', 'cannot be empty');
  }

  final pw.Document document = pw.Document();
  final bool marginIsDisabled = options.pageSize == PageSizeMode.fitImage;
  final pw.EdgeInsets margin = marginIsDisabled
      ? pw.EdgeInsets.zero
      : pw.EdgeInsets.all(options.marginMm * PdfPageFormat.mm);

  for (final SelectedImage image in images) {
    document.addPage(
      pw.Page(
        pageFormat: _pageFormatFor(image, options),
        margin: margin,
        build: (pw.Context context) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(image.bytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
  }

  return document.save();
}

PdfPageFormat _pageFormatFor(SelectedImage image, PdfOptions options) {
  if (options.pageSize == PageSizeMode.fitImage) {
    double toPoints(int pixels) =>
        (pixels / _imageDpi * PdfPageFormat.inch).clamp(1, _maxPageSide);
    return PdfPageFormat(
      toPoints(image.width),
      toPoints(image.height),
      marginAll: 0,
    );
  }

  final PdfPageFormat base = options.pageSize == PageSizeMode.a4
      ? PdfPageFormat.a4
      : PdfPageFormat.letter;

  // Turn the page on its side when the photo is landscape, so it fills more of
  // the sheet instead of leaving two large white bands.
  return image.isLandscape
      ? PdfPageFormat(base.height, base.width)
      : PdfPageFormat(base.width, base.height);
}
