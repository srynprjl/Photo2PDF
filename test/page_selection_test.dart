import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/page_selection.dart';

void main() {
  group('PageSelection.parse', () {
    test('an empty field means every page', () {
      expect(PageSelection.parse('', pageCount: 4).pages, <int>[1, 2, 3, 4]);
      expect(PageSelection.parse('   ', pageCount: 2).pages, <int>[1, 2]);
      expect(PageSelection.parse('', pageCount: 1).pages, <int>[1]);
    });

    test('reads single pages and ranges', () {
      expect(PageSelection.parse('2', pageCount: 9).pages, <int>[2]);
      expect(PageSelection.parse('1-3', pageCount: 9).pages, <int>[1, 2, 3]);
      expect(PageSelection.parse('1-3,7', pageCount: 9).pages, <int>[1, 2, 3, 7]);
      expect(
        PageSelection.parse(' 2 , 5 ', pageCount: 9).pages,
        <int>[2, 5],
      );
      expect(
        PageSelection.parse('4,1-2', pageCount: 9).pages,
        <int>[1, 2, 4],
        reason: 'the result is always in page order',
      );
      expect(
        PageSelection.parse('2,2,3', pageCount: 9).pages,
        <int>[2, 3],
        reason: 'duplicates are dropped',
      );
      expect(
        PageSelection.parse('3-1', pageCount: 9).pages,
        <int>[1, 2, 3],
        reason: 'a backwards range is read forwards',
      );
    });

    test('refuses text it cannot read', () {
      const PageSelection expected = PageSelection(
        pages: <int>[],
        error: 'Use numbers like 1-3 or 2,5.',
      );

      for (final String text in <String>['abc', '1-', '-3', '1,,2', '1-2-3']) {
        final PageSelection selection =
            PageSelection.parse(text, pageCount: 5);
        expect(selection.error, expected.error, reason: text);
        expect(selection.pages, isEmpty, reason: text);
        expect(selection.isValid, isFalse, reason: text);
      }
    });

    test('refuses pages the document does not have', () {
      final PageSelection tooHigh = PageSelection.parse('4-6', pageCount: 4);
      expect(tooHigh.isValid, isFalse);
      expect(tooHigh.pages, isEmpty);
      expect(tooHigh.error, 'Only pages 1–4 exist in this PDF.');

      expect(PageSelection.parse('0', pageCount: 4).isValid, isFalse);
      expect(PageSelection.parse('1-5', pageCount: 4).isValid, isFalse);
    });

    test('a document with no pages selects nothing', () {
      final PageSelection selection = PageSelection.parse('', pageCount: 0);
      expect(selection.pages, isEmpty);
      expect(selection.isValid, isTrue);
    });
  });
}
