import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/selected_image.dart';
import 'pdf_encryption.dart';

/// How the page is sized for each image.
enum PageSizeMode { a4, letter, fitImage }

extension PageSizeModeLabels on PageSizeMode {
  String get label => switch (this) {
    PageSizeMode.a4 => 'A4',
    PageSizeMode.letter => 'Letter',
    PageSizeMode.fitImage => 'Fit image',
  };
}

/// Which way up a fixed page goes.
enum PageOrientation { auto, vertical, horizontal }

extension PageOrientationLabels on PageOrientation {
  String get label => switch (this) {
    PageOrientation.auto => 'Auto',
    PageOrientation.vertical => 'Vertical',
    PageOrientation.horizontal => 'Horizontal',
  };
}

/// How a photo sits on a fixed page (A4, Letter).
enum ImageFit { fit, fill }

extension ImageFitLabels on ImageFit {
  String get label => switch (this) {
    ImageFit.fit => 'Fit',
    ImageFit.fill => 'Fill',
  };

  /// Fill scales the photo up until it covers the page and crops the overflow;
  /// fit shrinks it until the whole photo is visible, which leaves the bands.
  bool get fillsPage => this == ImageFit.fill;
}

/// How hard the photos are squeezed on the way into the PDF.
enum CompressionLevel { original, balanced, small }

extension CompressionLevelLabels on CompressionLevel {
  String get label => switch (this) {
    CompressionLevel.original => 'Original',
    CompressionLevel.balanced => 'Balanced',
    CompressionLevel.small => 'Small',
  };

  /// Longest side a photo is allowed to keep, or 0 for untouched. Every level
  /// except `original` re-encodes as JPEG, which is what makes PDFs small.
  int get maxSidePixels => switch (this) {
    CompressionLevel.original => 0,
    CompressionLevel.balanced => 2000,
    CompressionLevel.small => 1280,
  };

  int get jpegQuality => switch (this) {
    CompressionLevel.original => 100,
    CompressionLevel.balanced => 80,
    CompressionLevel.small => 60,
  };
}

class PdfOptions {
  const PdfOptions({
    this.pageSize = PageSizeMode.a4,
    this.marginMm = 10,
    this.orientation = PageOrientation.auto,
    this.imageFit = ImageFit.fit,
    this.compression = CompressionLevel.original,
    this.password,
  });

  final PageSizeMode pageSize;

  /// White border around the image on fixed page sizes, in millimetres.
  final double marginMm;

  /// Page direction for fixed page sizes. `auto` turns each page to match its
  /// photo; the others are fixed. Photo-sized pages follow the photo anyway.
  final PageOrientation orientation;

  /// Fit leaves white bands where the photo is shorter than the page; fill
  /// crops the photo's edges so it covers the page. Photo-sized pages have the
  /// photo's own shape, so this only matters for A4 and Letter.
  final ImageFit imageFit;

  final CompressionLevel compression;

  /// When set, the PDF can only be opened with this password.
  final String? password;

  bool get hasPassword => password != null && password!.isNotEmpty;
}

/// DPI used to turn pixels into points when the page should match the photo.
/// 150 DPI keeps a 12 MP photo at roughly A4 size instead of a 40 inch page.
const double _imageDpi = 150;

/// PDF viewers reject pages larger than 14400 points per side.
const double _maxPageSide = 14400;

/// Print resolution used for photos that have to be rasterised (PNG, WebP,
/// HEIC...). Without it a 12 MP photo becomes a 31 MB raw RGB stream; at
/// 300 DPI it is still a sharp A4 page for a fraction of the size. JPEGs skip
/// this: their compressed stream is small and is embedded untouched.
const double _rasterDpi = 300;

/// Builds a single PDF with one page per photo, in the given order.
///
/// JPEG bytes are embedded as-is (no re-encoding), so the output stays small and
/// keeps the original quality. Other formats are decoded by the PDF writer and
/// stored as pixels.
Future<Uint8List> buildPdf(
  List<SelectedImage> images,
  PdfOptions options, {

  /// Called as each page is finished, with how many are done and how many
  /// there are in total.
  void Function(int done, int total)? onPage,
}) async {
  if (images.isEmpty) {
    throw ArgumentError.value(images, 'images', 'cannot be empty');
  }

  final pw.Document document = pw.Document();
  final bool marginIsDisabled = options.pageSize == PageSizeMode.fitImage;
  final pw.EdgeInsets margin = marginIsDisabled
      ? pw.EdgeInsets.zero
      : pw.EdgeInsets.all(options.marginMm * PdfPageFormat.mm);

  if (options.hasPassword) {
    document.document.encryption = PdfPasswordProtection(
      document.document,
      password: options.password!,
    );
  }

  for (int i = 0; i < images.length; i++) {
    // One photo at a time: squeezing them all first would sit on a silent pass
    // over the whole set before the first page exists.
    final Uint8List bytes = await _prepareBytes(images[i], options.compression);
    document.addPage(
      pw.Page(
        pageFormat: _pageFormatFor(images[i], options),
        margin: margin,
        build: (pw.Context context) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(bytes, dpi: isJpegBytes(bytes) ? null : _rasterDpi),
            fit: options.imageFit.fillsPage
                ? pw.BoxFit.cover
                : pw.BoxFit.contain,
          ),
        ),
      ),
    );
    onPage?.call(i + 1, images.length);
  }

  return document.save();
}

/// Squeezes a photo for the chosen [level], on the way into the PDF.
///
/// `original` returns the untouched bytes, so JPEGs keep their exact quality
/// and cost nothing. The other levels decode, shrink the longest side and
/// re-encode as JPEG, which is also what strips any leftover metadata.
Future<Uint8List> _prepareBytes(
  SelectedImage image,
  CompressionLevel level,
) async {
  final int maxSide = level.maxSidePixels;
  if (maxSide == 0) {
    return image.bytes;
  }

  final img.Image? decoded = img.decodeImage(image.bytes);
  if (decoded == null) {
    return image.bytes;
  }

  final int longest = math.max(decoded.width, decoded.height);
  final img.Image scaled = longest <= maxSide
      ? decoded
      : img.copyResize(
          decoded,
          width: math.max(1, (decoded.width * maxSide / longest).round()),
          height: math.max(1, (decoded.height * maxSide / longest).round()),
          interpolation: img.Interpolation.average,
        );

  return img.encodeJpg(scaled, quality: level.jpegQuality);
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

  // Auto turns the page on its side when the photo is landscape, so it fills
  // more of the sheet instead of leaving two large white bands.
  final bool landscape = switch (options.orientation) {
    PageOrientation.auto => image.isLandscape,
    PageOrientation.vertical => false,
    PageOrientation.horizontal => true,
  };

  return landscape
      ? PdfPageFormat(base.height, base.width)
      : PdfPageFormat(base.width, base.height);
}
