import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/pdf_builder.dart';
import 'package:photo2pdf/src/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('returns null before anything is saved', () async {
    expect(await SettingsStore.instance.load(), isNull);
  });

  test('remembers page size and margin', () async {
    await SettingsStore.instance.save(
      const PdfSettings(pageSize: PageSizeMode.letter, marginMm: 4),
    );

    final PdfSettings? loaded = await SettingsStore.instance.load();

    expect(loaded, isNotNull);
    expect(loaded!.pageSize, PageSizeMode.letter);
    expect(loaded.marginMm, 4);
  });

  test('falls back to A4 and clamps a silly margin', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pageSize': 'nonsense',
      'marginMm': 99.0,
    });

    final PdfSettings? loaded = await SettingsStore.instance.load();

    expect(loaded, isNotNull);
    expect(loaded!.pageSize, PageSizeMode.a4);
    expect(loaded.marginMm, 30);
  });
}
