import 'package:shared_preferences/shared_preferences.dart';

import '../core/pdf_builder.dart';
import 'image_picker_service.dart';
import 'save_location.dart';

/// The parts of the output setup worth remembering between runs.
class PdfSettings {
  const PdfSettings({
    required this.pageSize,
    required this.marginMm,
    this.orientation = PageOrientation.auto,
    this.compression = CompressionLevel.original,
  });

  final PageSizeMode pageSize;
  final double marginMm;
  final PageOrientation orientation;
  final CompressionLevel compression;
}

class SettingsStore {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const String _pageSizeKey = 'pageSize';
  static const String _marginKey = 'marginMm';
  static const String _orientationKey = 'pageOrientation';
  static const String _compressionKey = 'compression';
  static const String _saveFolderKey = 'saveFolder';
  static const String _photoSourceKey = 'photoSource';
  static const String _askSaveKey = 'askWhereToSave';

  /// Returns the saved setup, or `null` on a first run.
  Future<PdfSettings?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? name = prefs.getString(_pageSizeKey);
      final double? margin = prefs.getDouble(_marginKey);
      final String? orientationName = prefs.getString(_orientationKey);
      final String? compressionName = prefs.getString(_compressionKey);
      if (name == null &&
          margin == null &&
          orientationName == null &&
          compressionName == null) {
        return null;
      }

      final PageSizeMode pageSize = PageSizeMode.values.firstWhere(
        (PageSizeMode mode) => mode.name == name,
        orElse: () => PageSizeMode.a4,
      );
      final PageOrientation orientation = PageOrientation.values.firstWhere(
        (PageOrientation value) => value.name == orientationName,
        orElse: () => PageOrientation.auto,
      );
      final CompressionLevel compression = CompressionLevel.values.firstWhere(
        (CompressionLevel value) => value.name == compressionName,
        orElse: () => CompressionLevel.original,
      );
      return PdfSettings(
        pageSize: pageSize,
        marginMm: (margin ?? 10).clamp(0, 30).toDouble(),
        orientation: orientation,
        compression: compression,
      );
    } on Exception {
      // Storage trouble must never block the app.
      return null;
    }
  }

  Future<void> save(PdfSettings settings) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pageSizeKey, settings.pageSize.name);
      await prefs.setDouble(_marginKey, settings.marginMm);
      await prefs.setString(_orientationKey, settings.orientation.name);
      await prefs.setString(_compressionKey, settings.compression.name);
    } on Exception {
      // Best effort: the current session keeps working without it.
    }
  }

  /// Whether `Add photos` opens the gallery or the file browser.
  Future<PhotoSource> loadPhotoSource() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? name = prefs.getString(_photoSourceKey);
      return PhotoSource.values.firstWhere(
        (PhotoSource source) => source.name == name,
        orElse: () => PhotoSource.gallery,
      );
    } on Exception {
      return PhotoSource.gallery;
    }
  }

  Future<void> savePhotoSource(PhotoSource source) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_photoSourceKey, source.name);
    } on Exception {
      // Best effort: the gallery stays the fallback for this session.
    }
  }

  /// The folder (or the "ask me" switch) chosen in the settings screen.
  Future<SaveLocation> loadSaveLocation() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return SaveLocation(
        folder: prefs.getString(_saveFolderKey),
        askEveryTime: prefs.getBool(_askSaveKey) ?? false,
      );
    } on Exception {
      return const SaveLocation();
    }
  }

  Future<void> saveSaveLocation(SaveLocation location) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? folder = location.folder;
      if (folder == null) {
        await prefs.remove(_saveFolderKey);
      } else {
        await prefs.setString(_saveFolderKey, folder);
      }
      await prefs.setBool(_askSaveKey, location.askEveryTime);
    } on Exception {
      // Best effort: the current session keeps working without it.
    }
  }
}
