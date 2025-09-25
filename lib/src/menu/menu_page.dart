import 'package:flutter/material.dart';
// unused audio test imports removed
import '../config.dart';
import '../lemans/lemans_page.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  bool _musicEnabled = true;
  bool _sfxEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('RaceDriver', style: TextStyle(fontFamily: 'VT323', fontSize: 48, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Le Mans style', style: TextStyle(fontFamily: 'VT323', fontSize: 20, color: Colors.white70)),
              const SizedBox(height: 32),
              // Controls selector hidden; difficulty removed
              const SizedBox(height: 8),
              // Volume sliders removed
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: _musicEnabled,
                      onChanged: (v) => setState(() => _musicEnabled = v ?? true),
                    ),
                    const Text('Music', style: TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white70)),
                    const Spacer(),
                    Checkbox(
                      value: _sfxEnabled,
                      onChanged: (v) => setState(() => _sfxEnabled = v ?? true),
                    ),
                    const Text('Sound Effects', style: TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white70)),
                  ],
                ),
              ),
              // Test sound button removed
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LeMansPage(config: GameConfig(
                      musicEnabled: _musicEnabled,
                      sfxEnabled: _sfxEnabled,
                    )),
                  ));
                },
                child: const Text('Start', style: TextStyle(fontFamily: 'VT323', fontSize: 24)),
              )
            ],
          ),
        ),
      ),
    );
  }

  // audio test function removed
}

// Controls selector and difficulty slider removed

// removed old slider/test widgets and helpers
