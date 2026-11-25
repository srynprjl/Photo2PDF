import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../services/image_picker_service.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';

/// Lets the person decide where finished PDFs land.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SaveLocation _location = const SaveLocation();
  PhotoSource _photoSource = PhotoSource.gallery;
  bool _ready = false;

  bool get _isPhone => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SaveLocation saved = await SettingsStore.instance.loadSaveLocation();
    final PhotoSource source = await SettingsStore.instance.loadPhotoSource();
    if (!mounted) return;
    setState(() {
      _location = saved;
      _photoSource = source;
      _ready = true;
    });
  }

  Future<void> _apply(SaveLocation next) async {
    setState(() => _location = next);
    await SettingsStore.instance.saveSaveLocation(next);
  }

  Future<void> _applyPhotoSource(PhotoSource source) async {
    setState(() => _photoSource = source);
    await SettingsStore.instance.savePhotoSource(source);
  }

  Future<void> _pickFolder() async {
    final String? chosen = await getDirectoryPath(
      initialDirectory: _location.folder ?? defaultSaveFolder(),
      confirmButtonText: 'Use this folder',
    );
    if (chosen == null || chosen.isEmpty || !mounted) {
      return;
    }
    await _apply(_location.copyWith(folder: chosen));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('PDFs will go to ${prettyPath(chosen)}')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String folderText = _isPhone
        ? 'Downloads/$androidSaveFolder'
        : prettyPath(_location.folder ?? defaultSaveFolder());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text('Photos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SegmentedButton<PhotoSource>(
                          segments: const <ButtonSegment<PhotoSource>>[
                            ButtonSegment<PhotoSource>(
                              value: PhotoSource.gallery,
                              icon: Icon(Icons.photo_library_outlined),
                              label: Text('Gallery'),
                            ),
                            ButtonSegment<PhotoSource>(
                              value: PhotoSource.files,
                              icon: Icon(Icons.folder_open_outlined),
                              label: Text('Files'),
                            ),
                          ],
                          selected: <PhotoSource>{_photoSource},
                          onSelectionChanged: (Set<PhotoSource> selection) =>
                              _applyPhotoSource(selection.first),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _photoSource == PhotoSource.gallery
                              ? 'Add photos opens the gallery, the fastest way '
                                  'in on a phone.'
                              : 'Add photos opens the file browser, for '
                                  'downloads and unusual formats.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Save location', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('Folder'),
                        subtitle: Text(folderText),
                        trailing: _isPhone
                            ? null
                            : TextButton(
                                onPressed: _pickFolder,
                                child: const Text('Change'),
                              ),
                      ),
                      if (!_isPhone && _location.folder != null)
                        ListTile(
                          leading: const Icon(Icons.settings_backup_restore),
                          title: const Text('Use the default folder'),
                          subtitle: Text(prettyPath(defaultSaveFolder())),
                          onTap: () => _apply(_location.resetFolder()),
                        ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _location.askEveryTime,
                        onChanged: (bool value) =>
                            _apply(_location.copyWith(askEveryTime: value)),
                        secondary: const Icon(Icons.save_as_outlined),
                        title: const Text('Ask each time'),
                        subtitle: Text(
                          _location.askEveryTime
                              ? 'The save dialog opens for every PDF.'
                              : 'PDFs are written straight to the folder above.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isPhone
                      ? 'Android only lets an app write into its own folder in '
                          'Downloads without asking. Turn on "Ask each time" to '
                          'put a PDF somewhere else.'
                      : 'Turning this off keeps PDFs in the folder above, so '
                          'one tap is enough to save.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
