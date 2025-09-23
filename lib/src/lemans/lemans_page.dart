import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'palette.dart';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import '../config.dart';

// Page entry is defined at the bottom as a StatelessWidget.

enum _GameState { countdown, running, paused, gameOver }

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
  // Pickups
  final List<_Pickup> pickups = <_Pickup>[];
  double pickupCooldown = 3.0;
  // Input
  bool leftPressed = false;
  bool rightPressed = false;
  // Day/Night factor 0 (day) .. 1 (night)
  double night = 0.0;
  int countdownTick = 3; // last whole number observed
  int passed = 0;
  double fuel = 100.0; // 0..100
  double comboTimer = 0.0; int combo = 0;
  double shake = 0.0; // camera shake time
  GameConfig config = const GameConfig();
  // Curving road state
  double curveOffset = 0.0; // -1..1, shifts road center
  double curveTarget = 0.0; // target offset
  double curveChangeTimer = 2.0; // seconds until new target
}

enum _HazardType { oil, puddle }
enum _PickupType { fuel }

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

class _Pickup {
  final _PickupType type;
  double x; // -1..1
  double y; // 0..1 from bottom to top
  _Pickup(this.type, this.x, this.y);
  Rect toRect(Rect road) {
    final cx = road.center.dx + x * (road.width * 0.45);
    final s = road.width * 0.1;
    final bottom = road.bottom - y * road.height;
    return Rect.fromCenter(center: Offset(cx, bottom - s * 0.5), width: s, height: s);
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
  static const double _speedFactor = 0.35; // Global pacing: slower overall
  final _EngineAudio _engine = _EngineAudio();

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
    model.fuel = 100.0;
    model.combo = 0; model.comboTimer = 0;
    model.shake = 0.0;
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

    // Calculate road rect once per frame (needed for pixel-based scroll pacing)
    final road = _roadRectForSize(Size(size.width, size.height));

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
        model.speed = (model.speed + dt * 0.25 / model.config.difficulty).clamp(0.0, 1.0);
        model.timeLeft -= dt;
        // Fuel consumption scales with speed and difficulty
        model.fuel -= dt * (0.5 + model.speed * 1.2) * model.config.difficulty;
        if (model.fuel < 0) model.fuel = 0;
        if (model.timeLeft <= 0) {
          model.timeLeft = 0;
          model.state = _GameState.gameOver;
          model.hiScore = math.max(model.hiScore, model.score);
        }
        break;
      case _GameState.paused:
        // no simulation while paused
        break;
      case _GameState.gameOver:
        model.speed = model.speed * 0.98;
        break;
    }

    // Apply button input steering
    final steer = (model.rightPressed ? 1.0 : 0.0) - (model.leftPressed ? 1.0 : 0.0);
    if (steer != 0) {
      model.player.x = (model.player.x + steer * dt * 0.55).clamp(-1.0, 1.0);
    }

    // Scroll road relative to perceived forward speed.
    // Use road height to convert normalized speed to pixels per second and
    // bias stripes to move a bit faster than traffic for stronger motion.
    final stripeBias = 2.0; // stripes a bit faster than traffic
    final pixelsPerSec = (0.8 + 2.8 * model.speed) * road.height * stripeBias * _speedFactor;
    model.scroll = (model.scroll + dt * pixelsPerSec) % (road.height * 1000);

    // Day/Night cycle over ~40s
    final phase = (elapsed.inMilliseconds / 40000.0) % 2.0; // 0..2
    model.night = phase < 1 ? phase : (2 - phase);

    // Curvature evolution: pick a new target periodically and ease toward it.
    model.curveChangeTimer -= dt;
    if (model.curveChangeTimer <= 0) {
      model.curveChangeTimer = rng.nextDouble() * 4.0 + 3.0; // 3..7s
      model.curveTarget = (rng.nextDouble() * 2 - 1) * 0.9; // -0.9..0.9
    }
    final oldCurve = model.curveOffset;
    final curveDelta = (model.curveTarget - model.curveOffset);
    final maxStep = dt * 0.25 * (0.6 + model.speed); // faster at speed
    if (curveDelta.abs() > maxStep) {
      model.curveOffset += maxStep * curveDelta.sign;
    } else {
      model.curveOffset = model.curveTarget;
    }
    // Inertial drift pushes the car outward during curve transitions
    final curveVel = (model.curveOffset - oldCurve) / (dt > 0 ? dt : 1);
    model.player.x += curveVel * 0.15 * (0.6 + model.speed);

    // Spawn AI traffic while running
    if (model.state == _GameState.running) {
      model.spawnCooldown -= dt * (0.6 + model.speed) * _speedFactor * model.config.difficulty;
      if (model.spawnCooldown <= 0) {
        model.spawnCooldown = (rng.nextDouble() * 1.2 + 0.8) / model.config.difficulty; // fewer cars at easy pace
        final lane = rng.nextInt(3) - 1; // -1,0,1
        model.traffic.add(_Car(lane * 0.5, 1.1, 0.12, 0.18));
      }
      // Hazards spawn
      model.hazardCooldown -= dt * (0.5 + model.speed * 0.8) * _speedFactor * model.config.difficulty;
      if (model.hazardCooldown <= 0) {
        model.hazardCooldown = (rng.nextDouble() * 2.8 + 1.2) / model.config.difficulty; // spawn less often
        final lane = (rng.nextInt(3) - 1) * 0.5;
        final type = rng.nextBool() ? _HazardType.oil : _HazardType.puddle;
        model.hazards.add(_Hazard(type, lane.toDouble(), 1.05));
      }
      // Fuel pickups spawn more rarely
      model.pickupCooldown -= dt * (0.25 + model.speed * 0.5) * _speedFactor;
      if (model.pickupCooldown <= 0) {
        model.pickupCooldown = rng.nextDouble() * 5.0 + 6.0; // ~6..11s
        final lane = (rng.nextInt(3) - 1) * 0.5;
        model.pickups.add(_Pickup(_PickupType.fuel, lane.toDouble(), 1.05));
      }
      // Combo timer decay
      model.comboTimer -= dt;
      if (model.comboTimer < 0) { model.comboTimer = 0; model.combo = 0; }
    }

    // Move traffic toward player; remove offscreen and add score
    for (final c in model.traffic) {
      c.y -= dt * (0.8 + 2.8 * model.speed) * _speedFactor;
    }
    model.traffic.removeWhere((c) {
      if (c.y < -0.3) {
        model.combo += 1; model.comboTimer = 2.0;
        model.score += 10 * math.max(1, model.combo ~/ 3);
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
    final pRect = model.player.toRect(road);
    // Hazards move
    for (final h in model.hazards) {
      h.y -= dt * (0.7 + 2.4 * model.speed) * _speedFactor;
    }
    model.hazards.removeWhere((h) => h.y < -0.2);
    // Pickups move
    for (final p in model.pickups) {
      p.y -= dt * (0.7 + 2.4 * model.speed) * _speedFactor;
    }
    model.pickups.removeWhere((p) => p.y < -0.2);
    for (final h in model.hazards) {
      if (h.toRect(road).overlaps(pRect)) {
        if (h.type == _HazardType.oil) {
          // brief slip effect
          model.player.x += (rng.nextDouble() - 0.5) * 0.3;
          model.speed = math.max(0.3, model.speed * 0.6);
          audio.beep(220, 90);
          model.shake = 0.2;
        } else {
          // puddle slows down a bit and darkens screen briefly
          model.speed = math.max(0.25, model.speed * 0.7);
          audio.beep(300, 80);
          model.shake = 0.15;
        }
      }
    }
    for (final p in model.pickups) {
      if (p.toRect(road).overlaps(pRect)) {
        switch (p.type) {
          case _PickupType.fuel:
            model.fuel = math.min(100.0, model.fuel + 25);
            model.score += 50;
            audio.beep(880, 70);
            audio.beep(660, 70);
            break;
        }
        p.y = -1; // mark for removal
      }
    }
    model.pickups.removeWhere((p) => p.y < 0);
    for (final car in model.traffic) {
      if (car.toRect(road).overlaps(pRect)) {
        // Simple collision penalty
        model.speed = 0.2;
        model.timeLeft = math.max(0, model.timeLeft - 3.0);
        audio.beep(120, 120);
        model.shake = 0.25;
        break;
      }
    }

    // Engine audio follow speed
    _engine.update(model.speed);
    // Shake decay
    if (model.shake > 0) model.shake = math.max(0, model.shake - dt * 1.4);

    setState(() {});
  }

  Duration? _lastTime;

  Rect _roadRectForSize(Size s) {
    final w = s.width * 0.86; // road+edges width region
    final maxShift = s.width * 0.18; // sway left/right
    final centerX = s.width * 0.5 + model.curveOffset.clamp(-1.0, 1.0) * maxShift;
    final left = (centerX - w * 0.5).clamp(0.0, s.width - w);
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
    _engine.dispose();
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
    // Camera shake
    if (model.shake > 0) {
      final dx = (math.sin(model.scroll * 0.05) * 1.0) * (model.shake * 6);
      final dy = (math.cos(model.scroll * 0.04) * 1.0) * (model.shake * 6);
      canvas.translate(dx, dy);
    }
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
    // Roadside posts (parallax)
    _drawRoadsidePosts(canvas, size);

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

    // Pickups
    for (final p in model.pickups) {
      final r = p.toRect(road);
      switch (p.type) {
        case _PickupType.fuel:
          final paint = Paint()..color = const Color(0xFFFFD54F);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), paint);
          // small fuel icon stripe
          canvas.drawRect(Rect.fromLTWH(r.left + r.width*0.2, r.top + r.height*0.4, r.width*0.6, r.height*0.2),
            Paint()..color = Colors.brown);
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

    // Headlights mask at night
    if (model.night > 0.4) {
      final darkness = (model.night - 0.4) / 0.6; // 0..1
      _drawHeadlights(canvas, size, darkness);
    }
  }

  void _drawHatch(Canvas canvas, Rect r) {
    final p1 = Paint()..color = C64Palette.white;
    final p2 = Paint()..color = C64Palette.black;
    // Fixed stripe height so they scroll (no stretching).
    final stripeH = 12.0;
    double y = model.scroll % (stripeH * 2);
    while (y < r.height) {
      canvas.drawRect(Rect.fromLTWH(r.left, y, r.width, stripeH), p1);
      canvas.drawRect(Rect.fromLTWH(r.left, y + stripeH, r.width, stripeH), p2);
      y += stripeH * 2;
    }
  }

  void _drawCenterDashes(Canvas canvas, Size size) {
    final cx = road.center.dx;
    // Fixed dash size so segments don't stretch while scrolling.
    final dashH = 24.0;
    final dashW = road.width * 0.018;
    final p = Paint()..color = C64Palette.white;
    const spacingFactor = 2.6; // constant spacing for steady motion
    double y = model.scroll % (dashH * spacingFactor);
    while (y < size.height) {
      canvas.drawRect(Rect.fromCenter(center: Offset(cx, y), width: dashW, height: dashH), p);
      y += dashH * spacingFactor;
    }
  }

  void _drawRoadsidePosts(Canvas canvas, Size size) {
    final postW = road.width * 0.014;
    final postH = 18.0;
    final spacing = 46.0; // pixels between posts
    double y = model.scroll % spacing;
    final leftX = road.left - postW * 0.5 + road.width * 0.04; // just outside left strip
    final rightX = road.right - road.width * 0.04 - postW * 0.5; // just outside right strip
    final paint1 = Paint()..color = Colors.white70;
    final paint2 = Paint()..color = Colors.grey.shade700;
    int i = 0;
    while (y < size.height) {
      final p = (i % 2 == 0) ? paint1 : paint2;
      canvas.drawRect(Rect.fromLTWH(leftX, y, postW, postH), p);
      canvas.drawRect(Rect.fromLTWH(rightX, y + spacing * 0.5, postW, postH), p);
      y += spacing;
      i++;
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
    y += text('FUEL   ${model.fuel.round()}%', C64Palette.white, y) + 6;
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
    final kmh = (40 + model.speed * 120).round();
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
    // Hazard/traffic warnings: small arrows if something is close ahead
    _drawWarnings(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _LeMansPainter oldDelegate) => true;

  void _drawHeadlights(Canvas canvas, Size size, double intensity) {
    final paint = Paint();
    // Dark overlay layer
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromARGB((140 * intensity).round(), 0, 0, 0));
    // Carve a soft cone around the player
    final car = model.player.toRect(road);
    final center = Offset(car.center.dx, car.top - car.height * 0.2);
    final radius = road.width * 0.6;
    final gradient = RadialGradient(
      colors: [Colors.black, Colors.transparent],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    paint
      ..shader = gradient
      ..blendMode = BlendMode.dstOut;
    canvas.drawCircle(center, radius, paint);
    canvas.restore();
  }

  void _drawWarnings(Canvas canvas, Size size) {
    final pRect = model.player.toRect(road);
    bool leftWarn = false, rightWarn = false;
    // lookahead window directly ahead of car
    for (final c in model.traffic) {
      final r = c.toRect(road);
      if (r.top < pRect.top - 40 && r.top > pRect.top - size.height * 0.45) {
        if (r.center.dx < pRect.center.dx - pRect.width * 0.2) leftWarn = true;
        if (r.center.dx > pRect.center.dx + pRect.width * 0.2) rightWarn = true;
      }
    }
    for (final h in model.hazards) {
      final r = h.toRect(road);
      if (r.top < pRect.top - 40 && r.top > pRect.top - size.height * 0.45) {
        if (r.center.dx < pRect.center.dx - pRect.width * 0.2) leftWarn = true;
        if (r.center.dx > pRect.center.dx + pRect.width * 0.2) rightWarn = true;
      }
    }
    final paint = Paint()..color = C64Palette.green;
    void arrow(Offset center, bool left) {
      final path = Path();
      final s = 10.0;
      if (left) {
        path.moveTo(center.dx + s, center.dy - s);
        path.lineTo(center.dx - s, center.dy);
        path.lineTo(center.dx + s, center.dy + s);
      } else {
        path.moveTo(center.dx - s, center.dy - s);
        path.lineTo(center.dx + s, center.dy);
        path.lineTo(center.dx - s, center.dy + s);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
    final y = road.top + 40;
    if (leftWarn) arrow(Offset(road.left + 24, y), true);
    if (rightWarn) arrow(Offset(road.right - 24, y), false);
  }
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

class _EngineAudio {
  final AudioPlayer _p = AudioPlayer();
  int _lastFreq = 0;
  bool _started = false;
  Future<void> update(double speed) async {
    final freq = (140 + speed * 320).round();
    final vol = 0.05 + speed * 0.15;
    if (!_started) {
      final bytes = _sineWavBytes(freq: freq, ms: 200, vol: vol);
      await _p.setReleaseMode(ReleaseMode.loop);
      await _p.play(BytesSource(bytes));
      _started = true;
      _lastFreq = freq;
    } else if ((freq - _lastFreq).abs() > 20) {
      // Refresh loop with new pitch occasionally to avoid choppiness
      final bytes = _sineWavBytes(freq: freq, ms: 200, vol: vol);
      await _p.stop();
      await _p.play(BytesSource(bytes));
      _lastFreq = freq;
    } else {
      await _p.setVolume(vol.clamp(0.0, 1.0));
    }
  }
  void dispose() { _p.dispose(); }
}

class LeMansPage extends StatelessWidget {
  final GameConfig config;
  const LeMansPage({super.key, this.config = const GameConfig()});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C64Palette.black,
      body: SafeArea(
        child: _GameTicker(
          builder: (context, model, road) {
            model.config = config;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LeMansPainter(model, road),
                  ),
                ),
                // Pause button
                Positioned(
                  top: 8,
                  left: 8,
                  child: _PauseButton(onPressed: () {
                    if (model.state == _GameState.running) {
                      model.state = _GameState.paused;
                    } else if (model.state == _GameState.paused) {
                      model.state = _GameState.running;
                    }
                  }),
                ),
                if (model.state == _GameState.paused)
                  Positioned.fill(child: _PauseOverlay(model: model)),
                // On-screen buttons
                if (config.controlMode != ControlMode.drag) Positioned(
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

class _PauseButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _PauseButton({required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white30),
        ),
        child: const Text('II', style: TextStyle(fontFamily: 'VT323', fontSize: 22, color: Colors.white)),
      ),
    );
  }
}

class _PauseOverlay extends StatefulWidget {
  final _GameModel model;
  const _PauseOverlay({required this.model});
  @override
  State<_PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<_PauseOverlay> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromARGB(160, 0, 0, 0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(12)),
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paused', style: TextStyle(fontFamily: 'VT323', fontSize: 28, color: Colors.white)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Difficulty', style: TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white70)),
                  Slider(min: 0.7, max: 1.3, divisions: 6, value: widget.model.config.difficulty,
                    onChanged: (v) => setState(() => widget.model.config = GameConfig(controlMode: widget.model.config.controlMode, difficulty: v))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Controls', style: TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white70)),
                  DropdownButton<ControlMode>(
                    value: widget.model.config.controlMode,
                    dropdownColor: Colors.black,
                    style: const TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: ControlMode.drag, child: Text('Drag')),
                      DropdownMenuItem(value: ControlMode.buttons, child: Text('Buttons')),
                      DropdownMenuItem(value: ControlMode.both, child: Text('Both')),
                    ],
                    onChanged: (m) => setState(() => widget.model.config = GameConfig(controlMode: m ?? ControlMode.both, difficulty: widget.model.config.difficulty)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: () => setState(() => widget.model.state = _GameState.running), child: const Text('Resume', style: TextStyle(fontFamily: 'VT323', fontSize: 20))),
                  ElevatedButton(onPressed: () { widget.model.state = _GameState.gameOver; }, child: const Text('End', style: TextStyle(fontFamily: 'VT323', fontSize: 20))),
                ],
              ),
            ],
          ),
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
