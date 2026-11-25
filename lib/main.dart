import 'package:material_ui/material_ui.dart';

import 'src/screens/converter_screen.dart';
import 'src/theme.dart';

void main() {
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
      home: const ConverterScreen(),
    );
  }
}
