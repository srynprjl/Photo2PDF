import 'package:shared_preferences/shared_preferences.dart';

import '../core/pdf_builder.dart';

/// The parts of the output setup worth remembering between runs.
class PdfSettings {
  const PdfSettings({required this.pageSize, required this.marginMm});

  final PageSizeMode pageSize;
  final double marginMm;
}

class SettingsStore {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const String _pageSizeKey = 'pageSize';
  static const String _marginKey = 'marginMm';

  /// Returns the saved setup, or `null` on a first run.
  Future<PdfSettings?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? name = prefs.getString(_pageSizeKey);
      final double? margin = prefs.getDouble(_marginKey);
      if (name == null && margin == null) {
        return null;
      }

      final PageSizeMode pageSize = PageSizeMode.values.firstWhere(
        (PageSizeMode mode) => mode.name == name,
        orElse: () => PageSizeMode.a4,
      );
      return PdfSettings(
        pageSize: pageSize,
        marginMm: (margin ?? 10).clamp(0, 30).toDouble(),
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
    } on Exception {
      // Best effort: the current session keeps working without it.
    }
  }
}
