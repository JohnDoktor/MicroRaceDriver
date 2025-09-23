import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/menu/menu_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RaceDriverApp());
}

class RaceDriverApp extends StatelessWidget {
  const RaceDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RaceDriver',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'VT323', fontSize: 18),
          bodyLarge: TextStyle(fontFamily: 'VT323', fontSize: 22),
          titleLarge: TextStyle(fontFamily: 'VT323', fontSize: 24),
        ),
      ),
      home: const MenuPage(),
    );
  }
}
