import 'package:flutter_test/flutter_test.dart';
import 'package:photo2pdf/src/core/pdf_builder.dart';
import 'package:photo2pdf/src/services/image_picker_service.dart';
import 'package:photo2pdf/src/services/save_location.dart';
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

  test('remembers the page orientation', () async {
    await SettingsStore.instance.save(
      const PdfSettings(
        pageSize: PageSizeMode.a4,
        marginMm: 10,
        orientation: PageOrientation.vertical,
      ),
    );

    final PdfSettings? loaded = await SettingsStore.instance.load();

    expect(loaded!.orientation, PageOrientation.vertical);
  });

  test('starts with the gallery as the photo source', () async {
    expect(await SettingsStore.instance.loadPhotoSource(), PhotoSource.gallery);
  });

  test('remembers the file browser as the photo source', () async {
    await SettingsStore.instance.savePhotoSource(PhotoSource.files);

    expect(await SettingsStore.instance.loadPhotoSource(), PhotoSource.files);
  });

  test('starts with the default save location', () async {
    final SaveLocation location =
        await SettingsStore.instance.loadSaveLocation();

    expect(location.folder, isNull);
    expect(location.askEveryTime, isFalse);
  });

  test('remembers the chosen folder', () async {
    await SettingsStore.instance.saveSaveLocation(
      const SaveLocation(folder: '/home/me/Documents/PDFs'),
    );

    final SaveLocation location =
        await SettingsStore.instance.loadSaveLocation();

    expect(location.folder, '/home/me/Documents/PDFs');
    expect(location.askEveryTime, isFalse);
  });

  test('remembers the ask switch and forgets the custom folder', () async {
    await SettingsStore.instance.saveSaveLocation(
      const SaveLocation(folder: '/tmp/x'),
    );
    await SettingsStore.instance.saveSaveLocation(
      const SaveLocation(askEveryTime: true),
    );

    final SaveLocation location =
        await SettingsStore.instance.loadSaveLocation();

    expect(location.folder, isNull);
    expect(location.askEveryTime, isTrue);
  });
}
