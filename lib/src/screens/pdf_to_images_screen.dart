import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart' show PdfPasswordException;

import '../core/page_selection.dart';
import '../models/selected_image.dart';
import '../services/page_saver.dart';
import '../services/pdf_page_renderer.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';
import '../widgets/notices.dart';

/// Turns the chosen pages of a PDF into JPEGs.
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

  /// The password this document opens with, once known; never written to disk.
  String? _pdfPassword;

  /// How many passwords have been asked for, so a second try can say so.
  int _passwordAttempts = 0;

  /// Pages rendered so far in the current run, out of [_total].
  int _done = 0;
  int _total = 0;
  bool _busy = false;
  SaveLocation _location = const SaveLocation();

  /// What the person typed in the Pages field; empty means every page.
  final TextEditingController _pagesController = TextEditingController();

  /// Shared by the password dialogs and kept for the screen's lifetime: a
  /// controller disposed as the dialog closes still has listeners attached.
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _pagesController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  PageSelection get _selection =>
      PageSelection.parse(_pagesController.text, pageCount: _pageCount);

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

      _pdfPassword = null;
      _passwordAttempts = 0;
      String? accepted;

      // PDFium keeps asking until the password works, so this is asked again
      // after a wrong one; `null` (cancelled) makes the open give up.
      Future<String?> passwordProvider() async {
        final String? entered = await _askPassword();
        if (entered != null) {
          accepted = entered;
        }
        return entered;
      }

      final int pages;
      try {
        pages = await PdfPageRenderer.pageCount(
          bytes,
          sourceName: file.name,
          passwordProvider: passwordProvider,
        );
      } on PdfPasswordException {
        _notify('That PDF is locked and needs its password to open.');
        return;
      }
      if (!mounted) return;

      _pdfPassword = accepted;
      setState(() {
        _name = file.name;
        _bytes = bytes;
        _pageCount = pages;
        _done = 0;
        _total = pages;
        // A range written for the last document rarely fits this one.
        _pagesController.clear();
      });
    } catch (error) {
      _notify('Could not read that PDF: $error', isError: true);
    }
  }

  /// Asks for the password of a locked PDF.
  ///
  /// Returns `null` when the person gives up, which stops the whole attempt.
  Future<String?> _askPassword() async {
    final int attempt = _passwordAttempts++;
    _passwordController.clear();
    final String? entered = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: Text(attempt == 0 ? 'This PDF is locked' : 'Wrong password'),
        content: TextField(
          controller: _passwordController,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'Asked once to open the document. Never saved.',
          ),
          onSubmitted: (String value) {
            if (value.isNotEmpty) {
              Navigator.of(context).pop(value);
            }
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_passwordController.text.isNotEmpty) {
                Navigator.of(context).pop(_passwordController.text);
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
    return entered;
  }

  Future<void> _convert() async {
    final String? name = _name;
    final Uint8List? bytes = _bytes;
    final PageSelection selection = _selection;
    if (name == null ||
        bytes == null ||
        _busy ||
        !selection.isValid ||
        selection.pages.isEmpty) {
      return;
    }

    setState(() {
      _busy = true;
      _done = 0;
      _total = selection.pages.length;
    });

    String location = '';
    int saved = 0;
    try {
      await for (final PdfPageImage page in PdfPageRenderer.render(
        bytes,
        sourceName: name,
        dpi: _dpi,
        pages: selection.pages,
        passwordProvider: () => _pdfPassword,
      )) {
        location = await PageSaver.save(
          page.bytes,
          pageFileName(name, page.number),
          location: _location,
        );
        saved++;
        if (!mounted) return;
        setState(() => _done = saved);
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
    if (mounted) {
      showNotice(context, message, isError: isError);
    }
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
            if (_name != null) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                'Pages',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _buildPagesField(theme),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _name == null ||
                      _busy ||
                      !_selection.isValid ||
                      _selection.pages.isEmpty
                  ? null
                  : _convert,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: Text(_convertLabel),
            ),
            if (_busy && _total > 0) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _done / _total),
              const SizedBox(height: 6),
              Text(
                'Page $_done of $_total',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _convertLabel {
    if (_busy) {
      return 'Rendering…';
    }
    final int count = _selection.pages.length;
    if (_name == null || !_selection.isValid || count == 0) {
      return 'Convert pages';
    }
    return 'Convert ${count == 1 ? '1 page' : '$count pages'} →';
  }

  /// The page range box: what to export, and how many pages that turns out to
  /// be, so the count is known before the button is pressed.
  Widget _buildPagesField(ThemeData theme) {
    final PageSelection selection = _selection;
    final String? error = selection.error;
    final int count = selection.pages.length;

    return TextField(
      controller: _pagesController,
      enabled: !_busy,
      textInputAction: TextInputAction.done,
      // Only the characters a page range is made of: digits, `-` and `,`.
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp('[0-9, -]')),
      ],
      onChanged: (String _) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'All pages',
        prefixIcon: const Icon(Icons.tag, size: 20),
        helperText: error ?? _countLabel(count),
        helperMaxLines: 2,
        helperStyle: error == null
            ? null
            : TextStyle(color: theme.colorScheme.error),
        border: const OutlineInputBorder(),
      ),
    );
  }

  String _countLabel(int count) {
    if (count == 0) {
      return 'No pages chosen.';
    }
    if (count == _pageCount) {
      return 'Will save all $_pageCount page${_pageCount == 1 ? '' : 's'}.';
    }
    return 'Will save $count of $_pageCount pages.';
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
              '${formatBytes(_bytes?.length ?? 0)}'
              '${_pdfPassword == null ? '' : ' · password protected'}',
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
