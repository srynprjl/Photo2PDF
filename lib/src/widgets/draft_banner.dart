import 'package:material_ui/material_ui.dart';

import '../models/selected_image.dart';

/// Offers the selection from last time instead of dropping it silently.
///
/// It only appears on a fresh start; once answered it is gone, and the list it
/// brings back is saved again like any other.
class DraftBanner extends StatelessWidget {
  const DraftBanner({
    required this.photos,
    required this.onContinue,
    required this.onDiscard,
    super.key,
  });

  final List<SelectedImage> photos;
  final VoidCallback onContinue;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int count = photos.length;
    final int bytes = photos.fold<int>(
      0,
      (int sum, SelectedImage image) => sum + image.byteSize,
    );

    return Card(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.history,
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Continue where you left off?',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$count photo${count == 1 ? '' : 's'} · ${formatBytes(bytes)} '
              '${count == 1 ? 'was' : 'were'} open last time.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: onDiscard,
                  child: const Text('Start fresh'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onContinue,
                  child: Text('Continue ($count)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
