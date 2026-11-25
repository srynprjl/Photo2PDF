import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../core/pdf_builder.dart';
import '../models/selected_image.dart';
import '../services/image_picker_service.dart';
import '../services/pdf_saver.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';
import 'settings_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/image_card.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final List<SelectedImage> _images = <SelectedImage>[];
  PageSizeMode _pageSize = PageSizeMode.a4;
  double _marginMm = 10;
  PageOrientation _orientation = PageOrientation.auto;
  PhotoSource _photoSource = PhotoSource.gallery;
  SaveLocation _saveLocation = const SaveLocation();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    final PdfSettings? saved = await SettingsStore.instance.load();
    final SaveLocation location = await SettingsStore.instance.loadSaveLocation();
    final PhotoSource source = await SettingsStore.instance.loadPhotoSource();
    if (!mounted) return;
    setState(() {
      _photoSource = source;
      if (saved != null) {
        _pageSize = saved.pageSize;
        _marginMm = saved.marginMm;
        _orientation = saved.orientation;
      }
      _saveLocation = location;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext context) => const SettingsScreen()),
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

  void _selectPageSize(PageSizeMode mode) {
    setState(() => _pageSize = mode);
    _rememberSettings();
  }

  void _selectOrientation(PageOrientation orientation) {
    setState(() => _orientation = orientation);
    _rememberSettings();
  }

  void _rememberSettings() {
    SettingsStore.instance.save(
      PdfSettings(
        pageSize: _pageSize,
        marginMm: _marginMm,
        orientation: _orientation,
      ),
    );
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
              tooltip: 'Remove all photos',
              onPressed: _busy ? null : () => setState(_images.clear),
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
            final bool isWide = constraints.maxWidth >= 840;

            if (isWide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: _buildImageArea(context)),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 340,
                      child: SingleChildScrollView(
                        child: _buildOptionsPanel(context),
                      ),
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
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: _buildOptionsPanel(context),
                    ),
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
              Text(
                '${_images.length} photo${_images.length == 1 ? '' : 's'} · ${formatBytes(_totalBytes)}',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Drag the handle to reorder',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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
            proxyDecorator: (Widget child, int index, Animation<double> animation) {
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

  Widget _buildOptionsPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool marginDisabled = _pageSize == PageSizeMode.fitImage || _busy;
    final bool orientationDisabled = marginDisabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Output', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              'Page size',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final PageSizeMode mode in PageSizeMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: _pageSize == mode,
                    onSelected: _busy
                        ? null
                        : (bool selected) {
                            if (selected) {
                              _selectPageSize(mode);
                            }
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Orientation',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final PageOrientation orientation in PageOrientation.values)
                  ChoiceChip(
                    label: Text(orientation.label),
                    selected: _orientation == orientation,
                    onSelected: orientationDisabled
                        ? null
                        : (bool selected) {
                            if (selected) {
                              _selectOrientation(orientation);
                            }
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Text('Margin', style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(
                  '${_marginMm.round()} mm',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: _marginMm,
              max: 30,
              divisions: 30,
              label: '${_marginMm.round()} mm',
              onChanged: marginDisabled
                  ? null
                  : (double value) => setState(() => _marginMm = value),
              onChangeEnd: marginDisabled
                  ? null
                  : (double value) => _rememberSettings(),
            ),
            if (_pageSize == PageSizeMode.fitImage)
              Text(
                'Pages match each photo, so the margin and orientation are not used.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Divider(height: 24),
            if (_images.isNotEmpty) ...<Widget>[
              Text(
                'Output file',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _suggestedFileName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                _saveLocation.askEveryTime
                    ? 'You pick the folder when saving.'
                    : 'Saves to ${saveLocationLabel(_saveLocation)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _images.isEmpty || _busy ? null : _createPdf,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_busy ? 'Creating PDF…' : 'Create PDF'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photos'),
            ),
          ],
        ),
      ),
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
          pageSize: _pageSize,
          marginMm: _marginMm,
          orientation: _orientation,
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
            : 'Save cancelled',
      );
    } catch (error) {
      if (mounted) {
        _notify('Could not create the PDF: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _remove(int id) {
    setState(() => _images.removeWhere((SelectedImage image) => image.id == id));
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
    if (!mounted) return;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: isError ? TextStyle(color: scheme.onErrorContainer) : null,
          ),
          backgroundColor: isError ? scheme.errorContainer : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
