import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../services/image_picker_service.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';

/// Where photos come from, and where finished PDFs land.
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

  void _setPhotoSource(PhotoSource source) {
    setState(() => _photoSource = source);
    SettingsStore.instance.savePhotoSource(source);
  }

  void _setLocation(SaveLocation next) {
    setState(() => _location = next);
    SettingsStore.instance.saveSaveLocation(next);
  }

  Future<void> _pickFolder() async {
    final String? chosen = await getDirectoryPath(
      initialDirectory: _location.folder ?? defaultSaveFolder(),
      confirmButtonText: 'Use this folder',
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    _setLocation(_location.copyWith(folder: chosen));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('PDFs will go to ${prettyPath(chosen)}')));
  }

  void _useDefaultFolder() {
    _setLocation(_location.resetFolder());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('PDFs will go to ${prettyPath(defaultSaveFolder())}')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const _SectionTitle('Photos'),
                _PhotoSourceCard(
                  source: _photoSource,
                  onChanged: _setPhotoSource,
                ),
                const SizedBox(height: 20),
                const _SectionTitle('Save location'),
                _SaveLocationCard(
                  location: _location,
                  isPhone: _isPhone,
                  onChangeFolder: _pickFolder,
                  onUseDefaultFolder: _location.folder == null ? null : _useDefaultFolder,
                  onAskEveryTime: (bool value) =>
                      _setLocation(_location.copyWith(askEveryTime: value)),
                ),
                const SizedBox(height: 12),
                _Hint(
                  _isPhone
                      ? 'Android only lets an app write into its own folder in '
                          'Downloads without asking. Turn on "Ask each time" to '
                          'put a PDF somewhere else.'
                      : 'Turning this off keeps PDFs in the folder above, so '
                          'one tap is enough to save.',
                ),
              ],
            ),
    );
  }
}

class _PhotoSourceCard extends StatelessWidget {
  const _PhotoSourceCard({required this.source, required this.onChanged});

  final PhotoSource source;
  final ValueChanged<PhotoSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              selected: <PhotoSource>{source},
              onSelectionChanged: (Set<PhotoSource> selection) =>
                  onChanged(selection.first),
            ),
            const SizedBox(height: 12),
            _Hint(
              source == PhotoSource.gallery
                  ? 'Add photos opens the gallery, the fastest way in on a phone.'
                  : 'Add photos opens the file browser, for downloads and '
                      'unusual formats.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveLocationCard extends StatelessWidget {
  const _SaveLocationCard({
    required this.location,
    required this.isPhone,
    required this.onChangeFolder,
    required this.onUseDefaultFolder,
    required this.onAskEveryTime,
  });

  final SaveLocation location;
  final bool isPhone;

  /// Only desktop can choose a folder; a phone writes to Downloads instead.
  final VoidCallback onChangeFolder;

  /// `null` when the default folder is already in use.
  final VoidCallback? onUseDefaultFolder;

  final ValueChanged<bool> onAskEveryTime;

  @override
  Widget build(BuildContext context) {
    final String folderText = isPhone
        ? 'Downloads/$androidSaveFolder'
        : prettyPath(location.folder ?? defaultSaveFolder());

    return Card(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Folder'),
            subtitle: Text(folderText),
            trailing: isPhone
                ? null
                : TextButton(
                    onPressed: onChangeFolder,
                    child: const Text('Change'),
                  ),
          ),
          if (onUseDefaultFolder != null)
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Use the default folder'),
              subtitle: Text(prettyPath(defaultSaveFolder())),
              onTap: onUseDefaultFolder,
            ),
          const Divider(height: 1),
          SwitchListTile(
            value: location.askEveryTime,
            onChanged: onAskEveryTime,
            secondary: const Icon(Icons.save_as_outlined),
            title: const Text('Ask each time'),
            subtitle: Text(
              location.askEveryTime
                  ? 'The save dialog opens for every PDF.'
                  : 'PDFs are written straight to the folder above.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// The grey line of explanation under a control.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
