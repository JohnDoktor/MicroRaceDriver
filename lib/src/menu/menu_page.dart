import 'package:flutter/material.dart';
import '../config.dart';
import '../lemans/lemans_page.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  ControlMode _mode = ControlMode.both;
  double _difficulty = 1.0; // 0.7 easy, 1.0 normal, 1.3 hard

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
              _ModeSelector(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
              const SizedBox(height: 16),
              _DifficultySlider(value: _difficulty, onChanged: (v) => setState(() => _difficulty = v)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LeMansPage(config: GameConfig(controlMode: _mode, difficulty: _difficulty)),
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
}

class _ModeSelector extends StatelessWidget {
  final ControlMode mode; final ValueChanged<ControlMode> onChanged;
  const _ModeSelector({required this.mode, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Controls: ', style: TextStyle(fontFamily: 'VT323', fontSize: 20, color: Colors.white70)),
        DropdownButton<ControlMode>(
          value: mode,
          dropdownColor: Colors.black,
          style: const TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white),
          items: const [
            DropdownMenuItem(value: ControlMode.drag, child: Text('Drag')),
            DropdownMenuItem(value: ControlMode.buttons, child: Text('Buttons')),
            DropdownMenuItem(value: ControlMode.both, child: Text('Both')),
          ],
          onChanged: (m) { if (m != null) onChanged(m); },
        ),
      ],
    );
  }
}

class _DifficultySlider extends StatelessWidget {
  final double value; final ValueChanged<double> onChanged;
  const _DifficultySlider({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Difficulty', style: TextStyle(fontFamily: 'VT323', fontSize: 20, color: Colors.white70)),
        Slider(
          min: 0.7, max: 1.3, divisions: 6, value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

