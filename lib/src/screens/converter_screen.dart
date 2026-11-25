import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import '../core/pdf_builder.dart';
import '../models/selected_image.dart';
import '../services/draft_store.dart';
import '../services/image_picker_service.dart';
import '../services/pdf_saver.dart';
import '../services/pdf_worker.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';
import '../widgets/draft_banner.dart';
import '../widgets/empty_state.dart';
import '../widgets/image_card.dart';
import '../widgets/notices.dart';
import '../widgets/output_panel.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({this.active = true, super.key});

  /// False while the other tab is showing: a desktop drop target keeps
  /// receiving files even when it is out of sight.
  final bool active;

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final List<SelectedImage> _images = <SelectedImage>[];

  PdfSettings _settings = const PdfSettings(
    pageSize: PageSizeMode.a4,
    marginMm: 10,
  );
  PhotoSource _photoSource = PhotoSource.gallery;
  SaveLocation _saveLocation = const SaveLocation();
  bool _busy = false;

  /// Set while a PDF is being built, so the panel can count pages.
  PdfProgress? _progress;

  /// A file is hovering over the window, on desktop.
  bool _dragging = false;

  /// The settings screen sits on top, so drops there are not ours.
  bool _settingsOpen = false;

  static final bool _isDesktop =
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// What the last visit left behind, waiting for a yes or a no.
  List<SelectedImage>? _draft;

  /// Never persisted: a PDF password should not sit in the app's preferences.
  String? _password;

  /// Lives with the screen: the dialog is gone before its text is read, and a
  /// controller disposed any earlier trips a framework assertion.
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreSettings();
    _restoreDraft();
  }

  /// The photo list lives on disk between runs, so a long selection is not
  /// lost to a restart, a rotation that runs the app out of memory, or a swipe
  /// away from the app.
  Future<void> _restoreDraft() async {
    final List<SelectedImage> saved = await DraftStore.instance.load();
    if (!mounted || saved.isEmpty) return;
    setState(() => _draft = saved);
  }

  /// Mirrors the list to disk after every change; failures are silent by
  /// design, since the photos in memory are still the truth.
  void _persist() {
    DraftStore.instance.save(List<SelectedImage>.of(_images));
  }

  void _continueDraft() {
    final List<SelectedImage>? draft = _draft;
    if (draft == null) return;
    setState(() {
      _images.addAll(draft);
      _draft = null;
    });
    _persist();
    _notify('Brought back ${draft.length} photo(s)');
  }

  void _discardDraft() {
    setState(() => _draft = null);
    DraftStore.instance.clear();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSettings() async {
    final PdfSettings? saved = await SettingsStore.instance.load();
    final SaveLocation location = await SettingsStore.instance
        .loadSaveLocation();
    final PhotoSource source = await SettingsStore.instance.loadPhotoSource();
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        _settings = saved;
      }
      _saveLocation = location;
      _photoSource = source;
    });
  }

  Future<void> _openSettings() async {
    setState(() => _settingsOpen = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const SettingsScreen(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _settingsOpen = false);
      }
    }
    if (!mounted) return;
    final SaveLocation location = await SettingsStore.instance
        .loadSaveLocation();
    final PhotoSource source = await SettingsStore.instance.loadPhotoSource();
    if (!mounted) return;
    setState(() {
      _saveLocation = location;
      _photoSource = source;
    });
  }

  /// A choice made in the panel: apply it, then remember it.
  void _applySettings(PdfSettings next) {
    setState(() => _settings = next);
    _rememberSettings();
  }

  void _dragMargin(double marginMm) {
    setState(() => _settings = _settings.copyWith(marginMm: marginMm));
  }

  void _rememberSettings() {
    SettingsStore.instance.save(_settings);
  }

  Future<void> _editPassword() async {
    _passwordController.text = _password ?? '';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          _password == null ? 'Protect with a password' : 'Change the password',
        ),
        content: TextField(
          controller: _passwordController,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'Asked for when the PDF is opened. Never saved.',
          ),
          onSubmitted: (String _) => Navigator.of(context).pop(true),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use password'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final String value = _passwordController.text;
    setState(() => _password = value.isEmpty ? null : value);
  }

  int get _totalBytes => _images.fold(
    0,
    (int total, SelectedImage image) => total + image.byteSize,
  );

  @override
  Widget build(BuildContext context) {
    final Widget page = Scaffold(
      appBar: AppBar(
        title: const Text('Photo2PDF'),
        actions: <Widget>[
          if (_images.isNotEmpty)
            IconButton(
              tooltip: 'Clear all photos',
              onPressed: _busy ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _busy ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget panel = OutputPanel(
              settings: _settings,
              password: _password,
              busy: _busy,
              progress: _progress,
              photoCount: _images.length,
              fileName: _suggestedFileName(),
              location: _saveLocation,
              onSettingsChanged: _applySettings,
              onMarginChanged: _dragMargin,
              onMarginChangeEnd: _rememberSettings,
              onEditPassword: _editPassword,
              onRemovePassword: () => setState(() => _password = null),
              onCreate: _createPdf,
              onAddPhotos: _addImages,
            );

            if (constraints.maxWidth >= 840) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: _buildImageArea(context)),
                    const SizedBox(width: 24),
                    SizedBox(width: 340, child: panel),
                  ],
                ),
              );
            }

            return Column(
              children: <Widget>[
                Expanded(child: _buildImageArea(context)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ConstrainedBox(
                    // The panel scrolls its own settings and keeps the buttons
                    // visible, so this only has to leave the list some room.
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.65,
                    ),
                    child: panel,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (!_isDesktop) {
      return page;
    }

    return DropTarget(
      enable: widget.active && !_busy && !_settingsOpen,
      onDragEntered: (DropEventDetails details) {
        if (!_busy) {
          setState(() => _dragging = true);
        }
      },
      onDragExited: (DropEventDetails details) =>
          setState(() => _dragging = false),
      onDragDone: (DropDoneDetails details) {
        setState(() => _dragging = false);
        _addDropped(<String>[
          for (final DropItem file in details.files) file.path,
        ]);
      },
      child: Stack(
        children: <Widget>[
          page,
          if (_dragging) const Positioned.fill(child: _DropHint()),
        ],
      ),
    );
  }

  Widget _buildImageArea(BuildContext context) {
    final Widget area = _images.isEmpty
        ? EmptyState(onAddImages: _busy ? null : _addImages)
        : _buildPhotoList(context);

    final List<SelectedImage>? draft = _draft;
    if (draft == null) {
      return area;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: DraftBanner(
            photos: draft,
            onContinue: _continueDraft,
            onDiscard: _discardDraft,
          ),
        ),
        Expanded(child: area),
      ],
    );
  }

  Widget _buildPhotoList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${_images.length} photo${_images.length == 1 ? '' : 's'} · '
                  '${formatBytes(_totalBytes)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _busy ? null : _clearAll,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 8, top: 2),
            itemCount: _images.length,
            onReorderItem: _reorder,
            proxyDecorator:
                (Widget child, int index, Animation<double> animation) {
                  return Material(color: Colors.transparent, child: child);
                },
            itemBuilder: (BuildContext context, int index) {
              final SelectedImage image = _images[index];
              return ImageCard(
                key: ValueKey<int>(image.id),
                image: image,
                position: index + 1,
                onRemove: _busy ? null : () => _remove(image.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addImages() async {
    if (_busy) return;
    try {
      // The camera plugin has no desktop build, so a saved Camera choice falls
      // back to the gallery if the app is ever opened somewhere else.
      final bool wantsCamera =
          _photoSource == PhotoSource.camera &&
          (Platform.isAndroid || Platform.isIOS);
      if (wantsCamera) {
        final List<Uint8List> shots = await CameraScreen.open(context);
        if (!mounted || shots.isEmpty) return;
        _ingest(await ImagePickerService.instance.addCaptures(shots));
        return;
      }

      _ingest(await ImagePickerService.instance.pick(source: _photoSource));
    } catch (error) {
      _notify('Could not open the images: $error', isError: true);
    }
  }

  /// Desktop only: photos dragged from the file manager onto the window.
  Future<void> _addDropped(List<String> paths) async {
    if (_busy || paths.isEmpty) return;
    try {
      _ingest(await ImagePickerService.instance.addPaths(paths));
    } catch (error) {
      _notify('Could not read the dropped files: $error', isError: true);
    }
  }

  /// Adds whatever came back from a picker or a drop, and says what happened.
  void _ingest(PickedImages? picked) {
    if (picked == null || !mounted) return;

    setState(() => _images.addAll(picked.images));
    _persist();

    if (picked.rejected.isNotEmpty) {
      final String names = picked.rejected.take(2).join(', ');
      final String suffix = picked.rejected.length > 2 ? '…' : '';
      _notify(
        'Skipped ${picked.rejected.length} unsupported file(s): $names$suffix',
        isError: true,
      );
    } else if (picked.images.isNotEmpty) {
      _notify('Added ${picked.images.length} photo(s)');
    }
  }

  Future<void> _createPdf() async {
    if (_images.isEmpty || _busy) return;
    final int total = _images.length;
    setState(() {
      _busy = true;
      _progress = PdfProgress(done: 0, total: total);
    });

    try {
      // Built on a background isolate: a dozen photos is seconds of encoding,
      // and the window has to keep scrolling while that happens.
      final Uint8List bytes = await PdfWorker.build(
        List<SelectedImage>.of(_images),
        PdfOptions(
          pageSize: _settings.pageSize,
          marginMm: _settings.marginMm,
          orientation: _settings.orientation,
          imageFit: _settings.imageFit,
          compression: _settings.compression,
          password: _password,
        ),
        onProgress: (PdfProgress progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      if (!mounted) return;

      final SaveResult result = await PdfSaver.save(
        bytes,
        _suggestedFileName(),
        location: _saveLocation,
      );
      if (!mounted) return;

      _notify(
        result.saved
            ? 'Saved to ${result.displayPath ?? result.path}'
                  '${_password == null ? '' : ' (password protected)'}'
            : 'Save cancelled',
      );
    } catch (error) {
      _notify('Could not create the PDF: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _remove(int id) {
    setState(
      () => _images.removeWhere((SelectedImage image) => image.id == id),
    );
    _persist();
  }

  /// Beyond a photo or two, wiping the list asks first: the undo button only
  /// lives for a few seconds, so a mis-tap after that is a lost selection.
  static const int _confirmClearFrom = 3;

  Future<void> _clearAll() async {
    if (_images.isEmpty || _busy) return;

    if (_images.length >= _confirmClearFrom) {
      final int count = _images.length;
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('Clear $count photos?'),
          content: const Text(
            'Every photo leaves the list. You can still undo right after.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep them'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear all'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    _clearNow();
  }

  /// Empties the list and offers one tap of undo in case it was a slip.
  void _clearNow() {
    if (_images.isEmpty || _busy) return;
    final List<SelectedImage> removed = List<SelectedImage>.of(_images);
    setState(_images.clear);
    _persist();

    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Cleared ${removed.length} photo${removed.length == 1 ? '' : 's'}',
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: scheme.inversePrimary,
            onPressed: () {
              if (!mounted) return;
              setState(() => _images.insertAll(0, removed));
              _persist();
            },
          ),
        ),
      );
  }

  void _reorder(int oldIndex, int newIndex) {
    // onReorderItem already adjusts newIndex for the removed item.
    setState(() {
      final SelectedImage image = _images.removeAt(oldIndex);
      _images.insert(newIndex, image);
    });
    _persist();
  }

  String _suggestedFileName() {
    if (_images.length == 1) {
      final String stem = _images.first.name.replaceFirst(
        RegExp(r'\.[^.]+$'),
        '',
      );
      if (stem.isNotEmpty) {
        return '$stem.pdf';
      }
    }
    final DateTime now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'photo2pdf_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.pdf';
  }

  void _notify(String message, {bool isError = false}) {
    if (mounted) {
      showNotice(context, message, isError: isError);
    }
  }
}

/// Covers the window while a file is held over it, so the drop has a target.
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.primaryContainer.withValues(alpha: 0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 48,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(height: 12),
              Text(
                'Drop the photos here',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
