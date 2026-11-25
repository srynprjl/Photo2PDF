import 'dart:math' as math;

/// Which pages of a PDF to turn into photos.
///
/// The text people type stays simple: empty means every page, and `1-3, 7`
/// means the first three pages and the seventh. Ranges can be written
/// backwards, duplicates are dropped and the result is always in page order,
/// so the files come out in the same order as the document.
class PageSelection {
  const PageSelection({required this.pages, this.error});

  /// Selected pages, 1-based, ascending and unique.
  final List<int> pages;

  /// Why the text could not be read, or `null` when it could.
  final String? error;

  bool get isValid => error == null;

  /// Reads [text] for a document of [pageCount] pages.
  ///
  /// An empty field selects every page; anything unreadable selects nothing and
  /// carries an [error] to show under the field.
  factory PageSelection.parse(String text, {required int pageCount}) {
    final List<int> all = <int>[
      for (int page = 1; page <= pageCount; page++) page,
    ];
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return PageSelection(pages: all);
    }
    if (pageCount <= 0) {
      return const PageSelection(
        pages: <int>[],
        error: 'That PDF has no pages.',
      );
    }

    const PageSelection invalid = PageSelection(
      pages: <int>[],
      error: 'Use numbers like 1-3 or 2,5.',
    );

    final Set<int> picked = <int>{};
    for (final String chunk in trimmed.split(',')) {
      final String part = chunk.trim();
      if (part.isEmpty) {
        return invalid;
      }

      final List<String> bounds = part.split('-');
      if (bounds.length > 2) {
        return invalid;
      }
      final int? start = int.tryParse(bounds[0].trim());
      final int end = bounds.length == 2
          ? (int.tryParse(bounds[1].trim()) ?? -1)
          : (start ?? -1);
      if (start == null || end < 0) {
        return invalid;
      }

      final int low = math.min(start, end);
      final int high = math.max(start, end);
      if (low < 1 || high > pageCount) {
        return PageSelection(
          pages: const <int>[],
          error: 'Only pages 1–$pageCount exist in this PDF.',
        );
      }
      for (int page = low; page <= high; page++) {
        picked.add(page);
      }
    }

    final List<int> pages = picked.toList()..sort();
    return PageSelection(pages: pages);
  }
}
