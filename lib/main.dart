import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import 'src/menu/menu_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Configure global audio context to ensure playback works even with the silent switch on iOS
  await AudioPlayer.global.setAudioContext(AudioContext(
    iOS: const AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: [],
    ),
    android: const AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
      isSpeakerphoneOn: false,
      stayAwake: false,
    ),
  ));
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
