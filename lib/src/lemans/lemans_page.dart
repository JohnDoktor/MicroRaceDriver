import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'palette.dart';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

// Page entry is defined at the bottom as a StatelessWidget.

enum _GameState { countdown, running, gameOver }

class _Car {
  double x; // -1..1 relative to road center
  double y; // 0..1 from bottom to top (for AI cars)
  double w; // width in logical units
  double h; // height in logical units
  _Car(this.x, this.y, this.w, this.h);
  Rect toRect(Rect road) {
    final cx = road.center.dx + x * (road.width * 0.45);
    final hPx = h * road.width; // size relative to road width for stability
    final wPx = w * road.width;
    final bottom = road.bottom - y * road.height;
    return Rect.fromCenter(center: Offset(cx, bottom - hPx * 0.5), width: wPx, height: hPx);
  }
}

class _GameModel {
  _GameState state = _GameState.countdown;
  double countdown = 3.0; // 3..0 seconds
  double timeLeft = 60.0;
  int score = 0;
  int hiScore = 0;
  double speed = 0.0; // 0..1
  double scroll = 0.0; // road scroll offset
  final _Car player = _Car(0, 0.16, 0.12, 0.18);
  final List<_Car> traffic = <_Car>[];
  double spawnCooldown = 0.0;
  // Hazards
  final List<_Hazard> hazards = <_Hazard>[];
  double hazardCooldown = 1.0;
  // Input
  bool leftPressed = false;
  bool rightPressed = false;
  // Day/Night factor 0 (day) .. 1 (night)
  double night = 0.0;
  int countdownTick = 3; // last whole number observed
  int passed = 0;
}

enum _HazardType { oil, puddle }

class _Hazard {
  final _HazardType type;
  double x; // -1..1
  double y; // 0..1 from bottom to top
  _Hazard(this.type, this.x, this.y);
  Rect toRect(Rect road) {
    final cx = road.center.dx + x * (road.width * 0.45);
    final s = road.width * 0.11;
    final bottom = road.bottom - y * road.height;
    return Rect.fromCenter(center: Offset(cx, bottom - s * 0.5), width: s, height: s * 0.65);
  }
}

class _GameTicker extends StatefulWidget {
  final Widget Function(BuildContext, _GameModel, Rect) builder;
  const _GameTicker({required this.builder});
  @override
  State<_GameTicker> createState() => _GameTickerState();
}

class _GameTickerState extends State<_GameTicker> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _GameModel model = _GameModel();
  final math.Random rng = math.Random();
  final _Audio audio = _Audio();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _reset() {
    model.state = _GameState.countdown;
    model.countdown = 3.0;
    model.timeLeft = 60.0;
    model.speed = 0.0;
    model.scroll = 0.0;
    model.score = 0;
    model.traffic.clear();
    model.spawnCooldown = 0.5;
  }

  void _onTick(Duration elapsed) {
    // Called every frame; compute dt from the ticker itself.
    final dt = _lastTime == null
        ? 0.0
        : (elapsed.inMicroseconds - _lastTime!.inMicroseconds) / 1e6;
    _lastTime = elapsed;
    if (dt <= 0) return;

    // Obtain size from context if available
    final size = context.size;
    if (size == null) return;

    // Simulate
    switch (model.state) {
      case _GameState.countdown:
        final previous = model.countdown.ceil();
        model.countdown -= dt;
        final current = model.countdown.ceil().clamp(0, 3);
        if (current < previous && current > 0) {
          audio.beep(440, 90);
        }
        model.speed = model.speed * 0.98 + 0.02 * 0.2; // slow idle scroll
        if (model.countdown <= 0) {
          model.state = _GameState.running;
          model.speed = 0.0;
          audio.beep(880, 140); // go beep
        }
        break;
      case _GameState.running:
        // target speed ramps to 1.0
        model.speed = (model.speed + dt * 0.35).clamp(0.0, 1.0);
        model.timeLeft -= dt;
        if (model.timeLeft <= 0) {
          model.timeLeft = 0;
          model.state = _GameState.gameOver;
          model.hiScore = math.max(model.hiScore, model.score);
        }
        break;
      case _GameState.gameOver:
        model.speed = model.speed * 0.98;
        break;
    }

    // Apply button input steering
    final steer = (model.rightPressed ? 1.0 : 0.0) - (model.leftPressed ? 1.0 : 0.0);
    if (steer != 0) {
      model.player.x = (model.player.x + steer * dt * 1.4).clamp(-1.0, 1.0);
    }

    // Scroll road relative to speed
    model.scroll = (model.scroll + dt * (2.5 + 6.0 * model.speed)) % 1000;

    // Day/Night cycle over ~40s
    final phase = (elapsed.inMilliseconds / 40000.0) % 2.0; // 0..2
    model.night = phase < 1 ? phase : (2 - phase);

    // Spawn AI traffic while running
    if (model.state == _GameState.running) {
      model.spawnCooldown -= dt * (0.6 + model.speed);
      if (model.spawnCooldown <= 0) {
        model.spawnCooldown = rng.nextDouble() * 0.9 + 0.6; // 0.6..1.5s
        final lane = rng.nextInt(3) - 1; // -1,0,1
        model.traffic.add(_Car(lane * 0.5, 1.1, 0.12, 0.18));
      }
      // Hazards spawn
      model.hazardCooldown -= dt * (0.5 + model.speed * 0.8);
      if (model.hazardCooldown <= 0) {
        model.hazardCooldown = rng.nextDouble() * 2.0 + 1.0; // 1..3s
        final lane = (rng.nextInt(3) - 1) * 0.5;
        final type = rng.nextBool() ? _HazardType.oil : _HazardType.puddle;
        model.hazards.add(_Hazard(type, lane.toDouble(), 1.05));
      }
    }

    // Move traffic toward player; remove offscreen and add score
    for (final c in model.traffic) {
      c.y -= dt * (0.8 + 2.8 * model.speed);
    }
    model.traffic.removeWhere((c) {
      if (c.y < -0.3) {
        model.score += 10;
        model.passed += 1;
        if (model.passed % 5 == 0 && model.state == _GameState.running) {
          model.timeLeft = math.min(99, model.timeLeft + 1.0); // small reward
          audio.beep(660, 80);
        }
        return true;
      }
      return false;
    });

    _clampPlayer();

    // Collisions
    final road = _roadRectForSize(Size(size.width, size.height));
    final pRect = model.player.toRect(road);
    // Hazards move
    for (final h in model.hazards) {
      h.y -= dt * (0.7 + 2.4 * model.speed);
    }
    model.hazards.removeWhere((h) => h.y < -0.2);
    for (final h in model.hazards) {
      if (h.toRect(road).overlaps(pRect)) {
        if (h.type == _HazardType.oil) {
          // brief slip effect
          model.player.x += (rng.nextDouble() - 0.5) * 0.3;
          model.speed = math.max(0.3, model.speed * 0.6);
          audio.beep(220, 90);
        } else {
          // puddle slows down a bit and darkens screen briefly
          model.speed = math.max(0.25, model.speed * 0.7);
          audio.beep(300, 80);
        }
      }
    }
    for (final car in model.traffic) {
      if (car.toRect(road).overlaps(pRect)) {
        // Simple collision penalty
        model.speed = 0.2;
        model.timeLeft = math.max(0, model.timeLeft - 3.0);
        audio.beep(120, 120);
        break;
      }
    }

    setState(() {});
  }

  Duration? _lastTime;

  Rect _roadRectForSize(Size s) {
    final w = s.width * 0.86; // road+edges width region
    final left = (s.width - w) * 0.5;
    return Rect.fromLTWH(left, 0, w, s.height);
  }

  void _onHorizontalDrag(DragUpdateDetails d) {
    final size = context.size;
    if (size == null) return;
    final road = _roadRectForSize(size);
    final nx = ((d.localPosition.dx - road.center.dx) / (road.width * 0.45)).clamp(-1.0, 1.0);
    model.player.x = nx.toDouble();
  }

  void _clampPlayer() {
    if (model.player.x <= -1.0 || model.player.x >= 1.0) {
      model.speed = math.max(0.2, model.speed * 0.85);
    }
    model.player.x = model.player.x.clamp(-1.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _onTap() {
    if (model.state == _GameState.gameOver) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDrag,
      onTap: _onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final road = _roadRectForSize(Size(constraints.maxWidth, constraints.maxHeight));
          return widget.builder(context, model, road);
        },
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    audio.dispose();
    super.dispose();
  }
}

class _LeMansPainter extends CustomPainter {
  final _GameModel model;
  final Rect road;
  _LeMansPainter(this.model, this.road);

  // Color utilities to simulate night dimming and simple alpha-less fade.
  int _r(Color c) => (c.r * 255.0).round() & 0xFF;
  int _g(Color c) => (c.g * 255.0).round() & 0xFF;
  int _b(Color c) => (c.b * 255.0).round() & 0xFF;
  Color _dim(Color c, [double factor = 1.0]) {
    final dayBlend = 1.0 - model.night * 0.7; // darker at night
    final f = (dayBlend * factor).clamp(0.0, 1.0);
    return Color.fromARGB(255, (_r(c) * f).round(), (_g(c) * f).round(), (_b(c) * f).round());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = C64Palette.black;
    canvas.drawRect(Offset.zero & size, bg);

    // Road bands: left blue, right purple
    // Central road area (implicit by the two bands drawn below)
    final leftBand = Rect.fromLTWH(road.left, 0, road.width * 0.5, size.height);
    final rightBand = Rect.fromLTWH(road.left + road.width * 0.5, 0, road.width * 0.36, size.height);
    // Road base fill with dimming applied
    canvas.drawRect(leftBand, Paint()..color = _dim(C64Palette.roadBlue));
    canvas.drawRect(rightBand, Paint()..color = _dim(C64Palette.roadPurple));

    // Side strips
    final sideStripW = road.width * 0.04;
    final leftStrip = Rect.fromLTWH(road.left + road.width * 0.04, 0, sideStripW, size.height);
    final rightStrip = Rect.fromLTWH(road.right - road.width * 0.08 - sideStripW, 0, sideStripW, size.height);
    canvas.drawRect(leftStrip, Paint()..color = _dim(C64Palette.gray, 0.65));
    canvas.drawRect(rightStrip, Paint()..color = _dim(C64Palette.gray, 0.65));

    // Edge hatch stripes
    _drawHatch(canvas, Rect.fromLTWH(road.left, 0, road.width * 0.04, size.height));
    _drawHatch(canvas, Rect.fromLTWH(road.right - road.width * 0.04, 0, road.width * 0.04, size.height));

    // Center dashed line
    _drawCenterDashes(canvas, size);

    // Start line and lights when in countdown
    if (model.state == _GameState.countdown) {
      _drawStartLine(canvas, size);
      _drawStartLights(canvas);
    }

    // Hazards
    for (final h in model.hazards) {
      final r = h.toRect(road);
      switch (h.type) {
        case _HazardType.oil:
          final p = Paint()..color = const Color(0xFF101010);
          canvas.drawOval(r, p);
          break;
        case _HazardType.puddle:
          final p = Paint()..color = _dim(const Color(0xFF1B9AFF));
          canvas.drawOval(r, p);
          break;
      }
    }

    // Traffic
    for (final c in model.traffic) {
      _drawCar(canvas, c.toRect(road), body: _dim(const Color(0xFFDDDDDD)));
    }

    // Player car
    _drawCar(canvas, model.player.toRect(road), body: _dim(const Color(0xFF7EB7FF)));

    // HUD
    _drawHud(canvas, size);
  }

  void _drawHatch(Canvas canvas, Rect r) {
    final p1 = Paint()..color = C64Palette.white;
    final p2 = Paint()..color = C64Palette.black;
    final stripeH = 12.0;
    double y = -model.scroll % (stripeH * 2);
    while (y < r.height) {
      canvas.drawRect(Rect.fromLTWH(r.left, y, r.width, stripeH), p1);
      canvas.drawRect(Rect.fromLTWH(r.left, y + stripeH, r.width, stripeH), p2);
      y += stripeH * 2;
    }
  }

  void _drawCenterDashes(Canvas canvas, Size size) {
    final cx = road.center.dx;
    final dashH = 24.0;
    final dashW = road.width * 0.018;
    final p = Paint()..color = C64Palette.white;
    double y = -model.scroll % (dashH * 3);
    while (y < size.height) {
      canvas.drawRect(Rect.fromCenter(center: Offset(cx, y), width: dashW, height: dashH), p);
      y += dashH * 3;
    }
  }

  void _drawStartLine(Canvas canvas, Size size) {
    final lineY = size.height * 0.28;
    final lineH = 18.0;
    final lineRect = Rect.fromLTWH(road.left + road.width * 0.06, lineY, road.width * 0.88, lineH);
    canvas.drawRect(lineRect, Paint()..color = C64Palette.gray);
    // START text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'S T A R T',
        style: const TextStyle(
          color: C64Palette.startText,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'VT323',
          letterSpacing: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tp = Offset(road.center.dx - textPainter.width / 2, lineY - 2);
    textPainter.paint(canvas, tp);
  }

  void _drawStartLights(Canvas canvas) {
    final base = Offset(road.left + road.width * 0.09, road.height * 0.2);
    final r = 8.0;
    final pad = 6.0;
    int lit = 3 - model.countdown.ceil().clamp(0, 3);
    for (int i = 0; i < 3; i++) {
      final c = (i < lit) ? C64Palette.amber : C64Palette.darkGray;
      canvas.drawCircle(base + Offset(i * (r * 2 + pad), 0), r, Paint()..color = c);
    }
  }

  void _drawCar(Canvas canvas, Rect r, {required Color body}) {
    final car = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(car, Paint()..color = body);
    // windshield / details
    canvas.drawRect(
        Rect.fromLTWH(r.left + r.width * 0.22, r.top + r.height * 0.14, r.width * 0.56, r.height * 0.18),
        Paint()..color = const Color.fromARGB(230, 255, 255, 255));
    // wheels
    final wheelW = r.width * 0.16;
    final wheelH = r.height * 0.22;
    final pWheel = Paint()..color = C64Palette.black;
    canvas.drawRect(Rect.fromLTWH(r.left - wheelW * 0.5, r.top + r.height * 0.12, wheelW, wheelH), pWheel);
    canvas.drawRect(Rect.fromLTWH(r.right - wheelW * 0.5, r.top + r.height * 0.12, wheelW, wheelH), pWheel);
    canvas.drawRect(Rect.fromLTWH(r.left - wheelW * 0.5, r.bottom - wheelH - r.height * 0.12, wheelW, wheelH), pWheel);
    canvas.drawRect(
        Rect.fromLTWH(r.right - wheelW * 0.5, r.bottom - wheelH - r.height * 0.12, wheelW, wheelH), pWheel);
  }

  void _drawHud(Canvas canvas, Size size) {
    final right = size.width - 14.0;
    final x = right - 120.0;
    final top = 16.0;
    double text(String t, Color c, double yy) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(fontFamily: 'VT323', fontSize: 18, fontWeight: FontWeight.w700, color: c),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);
      tp.paint(canvas, Offset(x, yy));
      return tp.height;
    }
    double y = top;
    y += text('SCORE  ${model.score}', C64Palette.white, y) + 6;
    y += text('TIME   ${model.timeLeft.ceil()}', C64Palette.green, y) + 6;
    y += text('HI-SCORE ${model.hiScore}', C64Palette.green, y) + 10;
    y += text('SPEED', C64Palette.white, y) + 4;
    // speed meter boxes (3)
    final boxes = 3;
    final w = 26.0, h = 16.0, gap = 6.0;
    int filled = (model.speed * (boxes + 0.001)).floor().clamp(0, boxes);
    for (int i = 0; i < boxes; i++) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + i * (w + gap), y, w, h), const Radius.circular(2));
      final col = i < filled ? _dim(C64Palette.cyan) : _dim(C64Palette.cyan, 0.15);
      canvas.drawRRect(r, Paint()..color = col);
    }
    final kmh = (40 + model.speed * 240).round();
    text('   $kmh KM/H', C64Palette.white, y + h + 6);

    if (model.state == _GameState.gameOver) {
      final overlay = Paint()..color = const Color.fromARGB(140, 0, 0, 0);
      canvas.drawRect(Offset.zero & size, overlay);
      final tp = TextPainter(
        text: const TextSpan(
          text: 'GAME OVER\nTap to Restart',
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.8);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _LeMansPainter oldDelegate) => true;
}

class _Audio {
  final AudioPlayer _player = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  Future<void> beep(int freq, int ms) async {
    try {
      final bytes = _sineWavBytes(freq: freq, ms: ms, vol: 0.7);
      await _player.play(BytesSource(bytes));
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}

Uint8List _sineWavBytes({required int freq, required int ms, double vol = 1.0}) {
  const sampleRate = 22050;
  final totalSamples = (sampleRate * ms / 1000).floor();
  final data = BytesBuilder();
  // WAV header for 16-bit PCM
  final byteRate = sampleRate * 2;
  final blockAlign = 2;
  final subchunk2Size = totalSamples * 2;
  final chunkSize = 36 + subchunk2Size;
  void w32(int v) => data.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void w16(int v) => data.add([v & 0xFF, (v >> 8) & 0xFF]);
  data.add('RIFF'.codeUnits); w32(chunkSize); data.add('WAVE'.codeUnits);
  data.add('fmt '.codeUnits); w32(16); w16(1); w16(1); w32(sampleRate); w32(byteRate); w16(blockAlign); w16(16);
  data.add('data'.codeUnits); w32(subchunk2Size);
  // samples
  for (int i = 0; i < totalSamples; i++) {
    final t = i / sampleRate;
    final s = (math.sin(2 * math.pi * freq * t) * 0.5 * vol);
    final v = (s * 32767).clamp(-32768, 32767).toInt();
    w16(v);
  }
  return data.toBytes();
}

class LeMansPage extends StatelessWidget {
  const LeMansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C64Palette.black,
      body: SafeArea(
        child: _GameTicker(
          builder: (context, model, road) {
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LeMansPainter(model, road),
                  ),
                ),
                // On-screen buttons
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _HoldButton(
                        label: '<',
                        onChanged: (pressed) => model.leftPressed = pressed,
                      ),
                      const Spacer(),
                      _HoldButton(
                        label: '>',
                        onChanged: (pressed) => model.rightPressed = pressed,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onChanged;
  const _HoldButton({required this.label, required this.onChanged});
  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _pressed = false;
  void _set(bool p) {
    if (_pressed == p) return;
    setState(() => _pressed = p);
    widget.onChanged(p);
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: _pressed ? Colors.white24 : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white30, width: 1),
        ),
        child: Text(widget.label, style: const TextStyle(fontFamily: 'VT323', fontSize: 28)),
      ),
    );
  }
}
