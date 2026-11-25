import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../models/selected_image.dart';
import '../services/page_saver.dart';
import '../services/pdf_page_renderer.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';

/// Turns every page of a PDF into a JPEG.
class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key});

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  static const List<int> _dpiChoices = <int>[150, 200, 300];

  String? _name;
  Uint8List? _bytes;
  int _pageCount = 0;
  int _dpi = 200;
  int _done = 0;
  bool _busy = false;
  SaveLocation _location = const SaveLocation();

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final SaveLocation location = await SettingsStore.instance.loadSaveLocation();
    if (!mounted) return;
    setState(() => _location = location);
  }

  Future<void> _choosePdf() async {
    if (_busy) return;
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        dialogTitle: 'Choose a PDF',
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
      );
      if (files.isEmpty) return;

      final PlatformFile file = files.first;
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;

      final int pages = await PdfPageRenderer.pageCount(
        bytes,
        sourceName: file.name,
      );
      if (!mounted) return;
      setState(() {
        _name = file.name;
        _bytes = bytes;
        _pageCount = pages;
        _done = 0;
      });
    } catch (error) {
      _notify('Could not read that PDF: $error', isError: true);
    }
  }

  Future<void> _convert() async {
    final String? name = _name;
    final Uint8List? bytes = _bytes;
    if (name == null || bytes == null || _busy) return;

    setState(() {
      _busy = true;
      _done = 0;
    });

    String location = '';
    int saved = 0;
    try {
      await for (final PdfPageImage page in PdfPageRenderer.render(
        bytes,
        sourceName: name,
        dpi: _dpi,
      )) {
        location = await PageSaver.save(
          page.bytes,
          pageFileName(name, page.number),
          location: _location,
        );
        saved++;
        if (!mounted) return;
        setState(() => _done = page.number);
      }

      if (!mounted) return;
      _notify(
        saved == 0
            ? 'That PDF has no pages to save'
            : 'Saved $saved photo${saved == 1 ? '' : 's'} to $location',
        isError: saved == 0,
      );
    } catch (error) {
      if (mounted) {
        _notify('Could not convert the PDF: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? scheme.errorContainer : null,
          showCloseIcon: isError,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('PDF to photos')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (_name == null) _buildEmptyState(theme) else _buildPicked(theme),
            const SizedBox(height: 20),
            Text(
              'Resolution',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: <ButtonSegment<int>>[
                for (final int dpi in _dpiChoices)
                  ButtonSegment<int>(value: dpi, label: Text('$dpi DPI')),
              ],
              selected: <int>{_dpi},
              onSelectionChanged: _busy
                  ? null
                  : (Set<int> selection) => setState(() => _dpi = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              'Each page is saved as a JPEG next to your PDFs. 200 DPI is a '
              'good screen size; 300 DPI is print quality and about twice the '
              'file size.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _name == null || _busy ? null : _convert,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: Text(_busy ? 'Rendering…' : 'Convert pages'),
            ),
            if (_busy && _pageCount > 0) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _done / _pageCount),
              const SizedBox(height: 6),
              Text(
                'Page $_done of $_pageCount',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(
          Icons.photo_library_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'No PDF yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a PDF and every page becomes its own photo.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: _busy ? null : _choosePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Choose PDF'),
          ),
        ),
      ],
    );
  }

  Widget _buildPicked(ThemeData theme) {
    return Card(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: Icon(
              Icons.picture_as_pdf_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(_name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '$_pageCount page${_pageCount == 1 ? '' : 's'} · '
              '${formatBytes(_bytes?.length ?? 0)}',
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
              child: TextButton(
                onPressed: _busy ? null : _choosePdf,
                child: const Text('Choose another'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
