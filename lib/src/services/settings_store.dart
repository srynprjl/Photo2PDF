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
    this.imageFit = ImageFit.fit,
    this.compression = CompressionLevel.original,
  });

  final PageSizeMode pageSize;
  final double marginMm;
  final PageOrientation orientation;
  final ImageFit imageFit;
  final CompressionLevel compression;

  PdfSettings copyWith({
    PageSizeMode? pageSize,
    double? marginMm,
    PageOrientation? orientation,
    ImageFit? imageFit,
    CompressionLevel? compression,
  }) {
    return PdfSettings(
      pageSize: pageSize ?? this.pageSize,
      marginMm: marginMm ?? this.marginMm,
      orientation: orientation ?? this.orientation,
      imageFit: imageFit ?? this.imageFit,
      compression: compression ?? this.compression,
    );
  }
}

class SettingsStore {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const String _pageSizeKey = 'pageSize';
  static const String _marginKey = 'marginMm';
  static const String _orientationKey = 'pageOrientation';
  static const String _imageFitKey = 'imageFit';
  static const String _compressionKey = 'compression';
  static const String _saveFolderKey = 'saveFolder';
  static const String _photoSourceKey = 'photoSource';
  static const String _askSaveKey = 'askWhereToSave';

  /// Names stored on disk can outlive an enum, so an unknown one falls back to
  /// the default instead of throwing.
  static T _stored<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere(
        (T value) => value.name == name,
        orElse: () => fallback,
      );

  /// Returns the saved setup, or `null` on a first run.
  Future<PdfSettings?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? name = prefs.getString(_pageSizeKey);
      final double? margin = prefs.getDouble(_marginKey);
      final String? orientationName = prefs.getString(_orientationKey);
      final String? imageFitName = prefs.getString(_imageFitKey);
      final String? compressionName = prefs.getString(_compressionKey);
      if (name == null &&
          margin == null &&
          orientationName == null &&
          imageFitName == null &&
          compressionName == null) {
        return null;
      }

      return PdfSettings(
        pageSize: _stored(PageSizeMode.values, name, PageSizeMode.a4),
        marginMm: (margin ?? 10).clamp(0, 30).toDouble(),
        orientation: _stored(
          PageOrientation.values,
          orientationName,
          PageOrientation.auto,
        ),
        imageFit: _stored(ImageFit.values, imageFitName, ImageFit.fit),
        compression: _stored(
          CompressionLevel.values,
          compressionName,
          CompressionLevel.original,
        ),
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
      await prefs.setString(_imageFitKey, settings.imageFit.name);
      await prefs.setString(_compressionKey, settings.compression.name);
    } on Exception {
      // Best effort: the current session keeps working without it.
    }
  }

  /// Whether `Add photos` opens the gallery or the file browser.
  Future<PhotoSource> loadPhotoSource() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return _stored(
        PhotoSource.values,
        prefs.getString(_photoSourceKey),
        PhotoSource.gallery,
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
