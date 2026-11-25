import 'package:material_ui/material_ui.dart';

/// One snackbar style for both screens: plain for news, an error container with
/// a close button for anything that went wrong.
void showNotice(BuildContext context, String message, {bool isError = false}) {
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
        showCloseIcon: isError,
      ),
    );
}
