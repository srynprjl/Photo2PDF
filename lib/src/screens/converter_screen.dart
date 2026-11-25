import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../core/pdf_builder.dart';
import '../models/selected_image.dart';
import '../services/image_picker_service.dart';
import '../services/pdf_saver.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';
import '../widgets/empty_state.dart';
import '../widgets/image_card.dart';
import '../widgets/notices.dart';
import '../widgets/output_panel.dart';
import 'settings_screen.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

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

  /// Never persisted: a PDF password should not sit in the app's preferences.
  String? _password;

  /// Lives with the screen: the dialog is gone before its text is read, and a
  /// controller disposed any earlier trips a framework assertion.
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSettings() async {
    final PdfSettings? saved = await SettingsStore.instance.load();
    final SaveLocation location = await SettingsStore.instance.loadSaveLocation();
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsScreen(),
      ),
    );
    if (!mounted) return;
    final SaveLocation location = await SettingsStore.instance.loadSaveLocation();
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

  int get _totalBytes =>
      _images.fold(0, (int total, SelectedImage image) => total + image.byteSize);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    SizedBox(
                      width: 340,
                      child: SingleChildScrollView(child: panel),
                    ),
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
                    // The options need room, or "Add photos" scrolls out of
                    // sight on a phone once the navigation bar is accounted for.
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.8,
                    ),
                    child: SingleChildScrollView(child: panel),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageArea(BuildContext context) {
    if (_images.isEmpty) {
      return EmptyState(onAddImages: _busy ? null : _addImages);
    }

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
      final PickedImages? picked =
          await ImagePickerService.instance.pick(source: _photoSource);
      if (picked == null || !mounted) return;

      setState(() => _images.addAll(picked.images));

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
    } catch (error) {
      _notify('Could not open the images: $error', isError: true);
    }
  }

  Future<void> _createPdf() async {
    if (_images.isEmpty || _busy) return;
    setState(() => _busy = true);

    try {
      final Uint8List bytes = await buildPdf(
        List<SelectedImage>.of(_images),
        PdfOptions(
          pageSize: _settings.pageSize,
          marginMm: _settings.marginMm,
          orientation: _settings.orientation,
          compression: _settings.compression,
          password: _password,
        ),
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
        setState(() => _busy = false);
      }
    }
  }

  void _remove(int id) {
    setState(() => _images.removeWhere((SelectedImage image) => image.id == id));
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
