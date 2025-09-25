class GameConfig {
  final ControlMode controlMode;
  final double difficulty; // 1.0 normal, <1 easy, >1 hard
  final double musicVolume; // 0..1
  final double sfxVolume;   // 0..1
  final bool musicEnabled;
  final bool sfxEnabled;
  const GameConfig({
    this.controlMode = ControlMode.both,
    this.difficulty = 1.0,
    this.musicVolume = 0.2,
    this.sfxVolume = 1.0,
    this.musicEnabled = true,
    this.sfxEnabled = true,
  });
}

enum ControlMode { drag, buttons, both }
