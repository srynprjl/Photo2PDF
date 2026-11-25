import 'package:material_ui/material_ui.dart';

import '../core/pdf_builder.dart';
import '../services/save_location.dart';
import '../services/settings_store.dart';

/// Everything that decides what the PDF looks like, plus the two buttons that
/// act on the photo list.
///
/// Stateless on purpose: the screen owns the values, so a change here is one
/// callback away from the state and the settings store.
class OutputPanel extends StatelessWidget {
  const OutputPanel({
    required this.settings,
    required this.password,
    required this.busy,
    required this.photoCount,
    required this.fileName,
    required this.location,
    required this.onSettingsChanged,
    required this.onMarginChanged,
    required this.onMarginChangeEnd,
    required this.onEditPassword,
    required this.onRemovePassword,
    required this.onCreate,
    required this.onAddPhotos,
    super.key,
  });

  final PdfSettings settings;

  /// `null` when the PDF should be left open.
  final String? password;

  final bool busy;
  final int photoCount;
  final String fileName;
  final SaveLocation location;

  /// A discrete choice (page size, orientation, compression) that is worth
  /// saving straight away.
  final ValueChanged<PdfSettings> onSettingsChanged;

  /// Slider movement: cheap, called on every frame of the drag.
  final ValueChanged<double> onMarginChanged;

  /// The drag ended, so the new margin can be written to the settings store.
  final VoidCallback onMarginChangeEnd;

  final VoidCallback onEditPassword;
  final VoidCallback onRemovePassword;
  final VoidCallback onCreate;
  final VoidCallback onAddPhotos;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // With a page cut to the photo, the margin and orientation do nothing.
    final bool fixedPage = settings.pageSize != PageSizeMode.fitImage;
    final bool pageOptionsDisabled = !fixedPage || busy;

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Only the settings scroll: the two buttons stay in view however many
          // options are added here.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Output', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _Label('Page size', theme: theme),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final PageSizeMode mode in PageSizeMode.values)
                        ChoiceChip(
                          label: Text(mode.label),
                          selected: settings.pageSize == mode,
                          onSelected: busy
                              ? null
                              : (bool selected) {
                                  if (selected) {
                                    onSettingsChanged(
                                      settings.copyWith(pageSize: mode),
                                    );
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Label('Orientation', theme: theme),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final PageOrientation orientation
                          in PageOrientation.values)
                        ChoiceChip(
                          label: Text(orientation.label),
                          selected: settings.orientation == orientation,
                          onSelected: pageOptionsDisabled
                              ? null
                              : (bool selected) {
                                  if (selected) {
                                    onSettingsChanged(
                                      settings.copyWith(
                                        orientation: orientation,
                                      ),
                                    );
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Label('Photo on the page', theme: theme),
                  SegmentedButton<ImageFit>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<ImageFit>>[
                      for (final ImageFit fit in ImageFit.values)
                        ButtonSegment<ImageFit>(
                          value: fit,
                          label: Text(fit.label),
                        ),
                    ],
                    selected: <ImageFit>{settings.imageFit},
                    onSelectionChanged: pageOptionsDisabled
                        ? null
                        : (Set<ImageFit> selection) => onSettingsChanged(
                            settings.copyWith(imageFit: selection.first),
                          ),
                  ),
                  if (fixedPage && settings.imageFit.fillsPage)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _Hint(
                        'Fill crops the edges so the photo covers the page.',
                        theme: theme,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Text('Margin', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text(
                        '${settings.marginMm.round()} mm',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.marginMm,
                    max: 30,
                    divisions: 30,
                    label: '${settings.marginMm.round()} mm',
                    onChanged: pageOptionsDisabled ? null : onMarginChanged,
                    onChangeEnd: pageOptionsDisabled
                        ? null
                        : (double value) => onMarginChangeEnd(),
                  ),
                  if (!fixedPage)
                    _Hint(
                      'Pages match each photo, so the margin and orientation are not '
                      'used.',
                      theme: theme,
                    ),
                  const SizedBox(height: 16),
                  _Label('Compression', theme: theme),
                  SegmentedButton<CompressionLevel>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<CompressionLevel>>[
                      for (final CompressionLevel level
                          in CompressionLevel.values)
                        ButtonSegment<CompressionLevel>(
                          value: level,
                          label: Text(level.label),
                        ),
                    ],
                    selected: <CompressionLevel>{settings.compression},
                    onSelectionChanged: busy
                        ? null
                        : (Set<CompressionLevel> selection) =>
                              onSettingsChanged(
                                settings.copyWith(compression: selection.first),
                              ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(
                        password == null
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          password == null
                              ? 'No password'
                              : 'Password protected',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (password != null)
                        IconButton(
                          tooltip: 'Remove password',
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : onRemovePassword,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      TextButton(
                        onPressed: busy ? null : onEditPassword,
                        child: Text(password == null ? 'Add' : 'Change'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Divider(height: 17),
                if (photoCount > 0) ...<Widget>[
                  _Label('Output file', theme: theme),
                  const SizedBox(height: 2),
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  _Hint(
                    location.askEveryTime
                        ? 'You pick the folder when saving.'
                        : 'Saves to ${saveLocationLabel(location)}',
                    theme: theme,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: photoCount == 0 || busy ? null : onCreate,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(busy ? 'Creating PDF…' : 'Create PDF'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : onAddPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photos'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The small grey heading above each group of chips.
class _Label extends StatelessWidget {
  const _Label(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A grey line of explanation under a control.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
