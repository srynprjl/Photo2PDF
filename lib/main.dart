import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/screens/home_screen.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Needed before the PDF engine is used from the app's own code (not widgets).
  await pdfrxFlutterInitialize();
  runApp(const Photo2PdfApp());
}

class Photo2PdfApp extends StatelessWidget {
  const Photo2PdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo2PDF',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
