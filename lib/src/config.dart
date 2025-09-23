class GameConfig {
  final ControlMode controlMode;
  final double difficulty; // 1.0 normal, <1 easy, >1 hard
  const GameConfig({this.controlMode = ControlMode.both, this.difficulty = 1.0});
}

enum ControlMode { drag, buttons, both }

