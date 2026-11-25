import 'dart:io';

/// The folder name used inside the shared Downloads folder on Android.
const String androidSaveFolder = 'Photo2PDF';

/// Where the finished PDF goes.
class SaveLocation {
  const SaveLocation({this.folder, this.askEveryTime = false});

  /// Absolute folder on desktop, or `null` for the platform default.
  ///
  /// Android ignores it: a phone app can only write into the shared
  /// `Downloads/Photo2PDF` folder without asking, or use a system dialog.
  final String? folder;

  /// Show the system file dialog for every PDF instead of writing straight to
  /// [folder].
  final bool askEveryTime;

  SaveLocation copyWith({String? folder, bool? askEveryTime}) {
    return SaveLocation(
      folder: folder ?? this.folder,
      askEveryTime: askEveryTime ?? this.askEveryTime,
    );
  }

  /// Drops a custom folder and goes back to the platform default.
  SaveLocation resetFolder() {
    return SaveLocation(askEveryTime: askEveryTime);
  }
}

/// `~/Downloads/Photo2PDF`, or `~/Documents/Photo2PDF` when there is no
/// Downloads folder.
String defaultSaveFolderFor(
  String home, {
  required bool hasDownloads,
  String separator = '/',
}) {
  final String base = hasDownloads ? 'Downloads' : 'Documents';
  return <String>[home, base, androidSaveFolder].join(separator);
}

/// The default folder on this machine.
String defaultSaveFolder() {
  final Map<String, String> env = Platform.environment;
  final String home = env['HOME'] ??
      env['USERPROFILE'] ??
      Directory.current.path;
  final String separator = Platform.pathSeparator;
  return defaultSaveFolderFor(
    home,
    hasDownloads: Directory('$home${separator}Downloads').existsSync(),
    separator: separator,
  );
}

/// A path in [directory] that is not taken yet: `scan.pdf`, then `scan (2).pdf`.
String freeFilePath(
  String directory,
  String fileName, {
  bool Function(String path)? isTaken,
}) {
  final bool Function(String) taken =
      isTaken ?? (String path) => File(path).existsSync();
  final String separator = Platform.pathSeparator;
  final String prefix = directory.endsWith(separator) || directory.endsWith('/')
      ? directory
      : '$directory$separator';
  final Match? extension = RegExp(r'\.[^./\\]+$').firstMatch(fileName);
  final String stem = extension == null
      ? fileName
      : fileName.substring(0, extension.start);
  final String suffix = extension?.group(0) ?? '';

  String candidate = '$prefix$fileName';
  // Bounded so a broken "is it taken" answer can never spin forever.
  for (int counter = 2; counter < 1000 && taken(candidate); counter++) {
    candidate = '$prefix$stem ($counter)$suffix';
  }
  return candidate;
}

/// `holiday-page-3.jpg`: one photo per page, named after the document that
/// produced it and safe for every file system.
String pageFileName(String sourceName, int number) {
  final String stem = sourceName.replaceFirst(
    RegExp(r'\.pdf$', caseSensitive: false),
    '',
  );
  final String safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '_').trim();
  return '${safe.isEmpty ? 'page' : safe}-page-$number.jpg';
}

/// Shortens an absolute path so it fits in a snackbar: `~/Downloads/x.pdf`.
String prettyPath(String path, {String? home}) {
  final String? prefix =
      home ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (prefix == null || prefix.isEmpty || !path.startsWith(prefix)) {
    return path;
  }
  if (path.length == prefix.length) {
    return '~';
  }
  return '~${path.substring(prefix.length)}';
}

/// One line describing where the next PDF will land.
String saveLocationLabel(SaveLocation location, {bool? android}) {
  if (location.askEveryTime) {
    return 'Ask every time';
  }
  final bool onAndroid = android ?? (Platform.isAndroid || Platform.isIOS);
  if (onAndroid) {
    return 'Downloads/$androidSaveFolder';
  }
  return prettyPath(location.folder ?? defaultSaveFolder());
}
