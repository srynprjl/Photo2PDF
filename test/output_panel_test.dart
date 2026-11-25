import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo2pdf/src/core/pdf_builder.dart';
import 'package:photo2pdf/src/services/pdf_worker.dart';
import 'package:photo2pdf/src/services/save_location.dart';
import 'package:photo2pdf/src/services/settings_store.dart';
import 'package:photo2pdf/src/widgets/output_panel.dart';

Widget _panel({
  required bool busy,
  required PdfProgress? progress,
  int photoCount = 3,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 700,
        child: OutputPanel(
          settings: const PdfSettings(pageSize: PageSizeMode.a4, marginMm: 10),
          password: null,
          busy: busy,
          progress: progress,
          photoCount: photoCount,
          fileName: 'scan.pdf',
          location: const SaveLocation(),
          onSettingsChanged: (PdfSettings _) {},
          onMarginChanged: (double _) {},
          onMarginChangeEnd: () {},
          onEditPassword: () {},
          onRemovePassword: () {},
          onCreate: () {},
          onAddPhotos: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a running build shows the page it is on, not a spinner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _panel(busy: true, progress: const PdfProgress(done: 2, total: 5)),
    );

    expect(find.text('Page 2 of 5'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Creating PDF…'), findsOneWidget);

    final LinearProgressIndicator bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.4, 1e-9));
  });

  testWidgets('the last page hands over to writing the file', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _panel(busy: true, progress: const PdfProgress(done: 5, total: 5)),
    );

    expect(find.text('Writing the file…'), findsOneWidget);
    expect(find.text('Page 5 of 5'), findsNothing);
  });

  testWidgets('an idle panel has no progress bar', (WidgetTester tester) async {
    await tester.pumpWidget(_panel(busy: false, progress: null));

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Create PDF'), findsOneWidget);
  });
}
