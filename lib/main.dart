import 'package:material_ui/material_ui.dart';

import 'src/screens/converter_screen.dart';
import 'src/theme.dart';

void main() {
  runApp(const JpgToPdfApp());
}

class JpgToPdfApp extends StatelessWidget {
  const JpgToPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JPG to PDF',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const ConverterScreen(),
    );
  }
}
