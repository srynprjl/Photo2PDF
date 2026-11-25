import 'package:material_ui/material_ui.dart';

import '../models/selected_image.dart';

/// One row in the image list: thumbnail, details, remove and drag handle.
class ImageCard extends StatelessWidget {
  const ImageCard({
    required this.image,
    required this.position,
    this.onRemove,
    super.key,
  });

  final SelectedImage image;

  /// 1-based page position shown to the user.
  final int position;

  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
                cacheWidth: 168,
                gaplessPlayback: true,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) {
                  return Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          ),
          title: Text(
            image.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${image.dimensionsLabel} px · ${image.sizeLabel} · page $position',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
              ReorderableDragStartListener(
                index: position - 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
