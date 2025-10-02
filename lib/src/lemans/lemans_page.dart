import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'palette.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import '../config.dart';

// Page entry is defined at the bottom as a StatelessWidget.

enum _GameState { countdown, running, paused, gameOver }

const double _kLaneXFactor = 0.42; // horizontal mapping factor (wider lanes)

class _Car {
  double x; // -1..1 relative to road center
  double y; // 0..1 from bottom to top (for AI cars)
  double w; // width in logical units
  double h; // height in logical units
  double prevY = 0.0;
  bool passed = false;
  bool overtake = false; // special flag for post-game occasional passers
  double speedScale = 0.7; // relative to ground flow for AI cars
  _Car(this.x, this.y, this.w, this.h);
  Rect toRect(Rect road, double baseWidth) {
    final cx = road.center.dx + x * (road.width * _kLaneXFactor);
    final widthRef = baseWidth <= 0 ? road.width : baseWidth;
    final hPx = h * widthRef;
    final wPx = w * widthRef;
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
  int lives = 3; // remaining lives
  double speed = 0.0; // 0..1
  double scroll = 0.0; // road scroll offset
  // Effective speed used for visuals/audio (applies nitro boost)
  double effectiveSpeed = 0.0; // can exceed 1.0 for display
  final _Car player = _Car(0, 0.16, 0.12, 0.18);
  final List<_Car> traffic = <_Car>[];
  double spawnCooldown = 0.0;
  // Hazards
  final List<_Hazard> hazards = <_Hazard>[];
  double hazardCooldown = 1.0;
  // Pickups
  final List<_Pickup> pickups = <_Pickup>[];
  double pickupCooldown = 3.0;
  // Input: swipe-only (no button state)
  // UI hints
  bool swipeHint = false; // show "Swipe to steer" overlay
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
  double invuln = 0.0; // seconds of collision grace
  double safeStart = 0.0; // reduced spawns after start
  // Skid marks
  final List<_Skid> skids = <_Skid>[];
  // Risk/reward multiplier (builds over time without hits)
  double risk = 0.0;
  double multiplier = 1.0; // score multiplier (increments each perfect minute)
  double perfectTime = 0.0; // seconds since last life lost
  // Road width dynamics
  double roadWidthFactor = 0.86; // portion of screen width
  double roadWidthTarget = 0.86;
  double roadWidthChangeTimer = 3.0;
  // Post-game occasional overtake timer
  double overtakeCooldown = 0.0;
  // Reference road width (pixels) for stable object sizing
  double refRoadWidth = 0.0;
  // Elapsed running time in seconds (for progression)
  double elapsed = 0.0;
  // Discrete level that increases every 2 minutes
  int level = 1;
  // Transient banner overlay
  String? bannerText;
  double bannerTimer = 0.0; // seconds remaining to show banner
  // Extra life spawn timer (seconds). When <= 0 and lives < 3, spawn a life pickup.
  double lifePickupTimer = 120.0;
  // Continues: player may continue up to 3 times after game over; score resets on continue
  int continuesLeft = 3;
  // Near-miss combo
  int nearMissCombo = 0;
  double nearMissTimer = 0.0;
  // Slipstream
  double draftTimer = 0.0;
  // Nitro (heat-based)
  double nitroHeat = 0.0; // 0..1
  bool nitroActive = false;
  double nitroCooldown = 0.0;
  // Level objective
  int overtakesGoal = 15;
  int overtakesDoneThisLevel = 0;
  // Danger mode (hold)
  bool dangerMode = false;
  // Biome visual index
  int biome = 0;
}

class _Skid {
  Offset a; Offset b; double life;
  _Skid(this.a, this.b, this.life);
}

enum _HazardType { oil, puddle }
enum _PickupType { fuel, life, nitro, coin }

class _Hazard {
  final _HazardType type;
  double x; // -1..1
  double y; // 0..1 from bottom to top
  _Hazard(this.type, this.x, this.y);
  Rect toRect(Rect road, double baseWidth) {
    final cx = road.center.dx + x * (road.width * _kLaneXFactor);
    final widthRef = baseWidth <= 0 ? road.width : baseWidth;
    final s = widthRef * 0.10;
    final bottom = road.bottom - y * road.height;
    return Rect.fromCenter(center: Offset(cx, bottom - s * 0.5), width: s, height: s * 0.65);
  }
}

class _Pickup {
  final _PickupType type;
  double x; // -1..1
  double y; // 0..1 from bottom to top
  _Pickup(this.type, this.x, this.y);
  Rect toRect(Rect road, double baseWidth) {
    final cx = road.center.dx + x * (road.width * _kLaneXFactor);
    final widthRef = baseWidth <= 0 ? road.width : baseWidth;
    final s = widthRef * 0.1;
    final bottom = road.bottom - y * road.height;
    return Rect.fromCenter(center: Offset(cx, bottom - s * 0.5), width: s, height: s);
  }
}

class _GameTicker extends StatefulWidget {
  final Widget Function(BuildContext, _GameModel, CustomPainter) builder;
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
  final _Music _music = _Music();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  late final _LeMansPainter _painter;
  _GameState _lastState = _GameState.countdown;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    // Start background chiptune
    _music.start();
    _painter = _LeMansPainter(model, _repaint);
  }

  void _reset() {
    model.state = _GameState.countdown;
    model.countdown = 3.0;
    model.timeLeft = 60.0;
    model.lives = 3;
    model.speed = 0.0;
    model.scroll = 0.0;
    model.score = 0;
    model.traffic.clear();
    model.spawnCooldown = 0.5;
    model.fuel = 100.0;
    model.combo = 0; model.comboTimer = 0;
    model.shake = 0.0;
    model.safeStart = 8.0;
    model.risk = 0.0;
    model.multiplier = 1.0;
    model.perfectTime = 0.0;
    model.roadWidthFactor = 0.86;
    model.roadWidthTarget = 0.86;
    model.roadWidthChangeTimer = 3.0;
    model.overtakeCooldown = 0.0;
    model.refRoadWidth = 0.0;
    model.continuesLeft = 3;
    model.elapsed = 0.0;
    model.level = 1;
    model.bannerText = null; model.bannerTimer = 0.0;
    model.swipeHint = false;
    // Restart music from the beginning when a new game starts
    _music.start();
  }

  void _continueGame() {
    if (model.continuesLeft <= 0) return;
    model.continuesLeft -= 1;
    model.state = _GameState.countdown;
    model.countdown = 3.0;
    model.lives = 3;
    model.score = 0;
    model.speed = 0.0;
    model.fuel = 100.0;
    model.combo = 0; model.comboTimer = 0;
    model.risk = 0.0; model.multiplier = 1.0; model.perfectTime = 0.0;
    model.invuln = 1.0;
    model.safeStart = 6.0;
    model.traffic.clear();
    model.hazards.clear();
    model.pickups.clear();
    model.spawnCooldown = 0.5;
    model.hazardCooldown = 1.0;
    model.pickupCooldown = 2.0;
    model.swipeHint = false;
    _music.start();
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
    Rect road = _roadRectForSize(Size(size.width, size.height));
    if (model.refRoadWidth <= 0) {
      model.refRoadWidth = road.width;
    }

    // Nitro flow multiplier (uses last frame's heat)
    final speedMult = (model.nitroActive && model.nitroCooldown <= 0)
        ? (1.0 + 0.8 * model.nitroHeat)
        : 1.0;
    // Effective speed for visuals/audio
    model.effectiveSpeed = model.speed * speedMult;

    // Simulate
    switch (model.state) {
      case _GameState.countdown:
        final previous = model.countdown.ceil();
        model.countdown -= dt;
        final current = model.countdown.ceil().clamp(0, 3);
        if (current < previous && current > 0) {
          audio.beep(440, 90);
        }
        // Keep speed at 0 during countdown so road is still
        model.speed = 0.0;
        if (model.countdown <= 0) {
          model.state = _GameState.running;
          model.speed = 0.0;
          model.elapsed = 0.0;
          model.swipeHint = true; // show hint at start of run
          audio.beep(880, 140); // go beep
        }
        break;
      case _GameState.running:
        // target speed ramps to 1.0
        model.speed = (model.speed + dt * 0.25 / model.config.difficulty).clamp(0.0, 1.0);
        model.elapsed += dt; // accumulate runtime for progressive difficulty
        if (model.swipeHint && model.elapsed >= 3.0) {
          model.swipeHint = false;
          if (mounted) setState(() {}); // remove hint overlay
        }
        // Level up every 120s of runtime
        final newLevel = 1 + (model.elapsed ~/ 120);
        if (newLevel > model.level) {
          model.level = newLevel;
          model.biome = (model.level - 1) % 3;
          // refresh level objective
          model.overtakesDoneThisLevel = 0;
          model.overtakesGoal = 10 + (model.level * 5).clamp(0, 40);
          _showBanner('LEVEL ${model.level}');
        }
        // Fuel consumption scales with speed and difficulty (+danger mode drain)
        final drainFactor = model.dangerMode ? 1.6 : 1.0;
        model.fuel -= dt * (0.5 + model.speed * 1.2) * model.config.difficulty * drainFactor;
        if (model.fuel < 0) model.fuel = 0;
        // Perfect run timer -> every full minute increases multiplier by 1x
        model.perfectTime += dt;
        final targetMult = 1 + (model.perfectTime ~/ 60);
        if (targetMult.toDouble() > model.multiplier) {
          model.multiplier = targetMult.toDouble();
          _showBanner('PERFECT RUN - ${targetMult}x POINTS');
        }
        // No countdown timer; game ends only when lives reach 0
        break;
      case _GameState.paused:
        // no simulation while paused
        break;
      case _GameState.gameOver:
        // Pause background simulation during continue screen
        model.speed = 0.0;
        _music.stop();
        break;
    }

    // Button steering disabled: swipe-only control

    // Scroll road relative to perceived forward speed.
    // Use road height to convert normalized speed to pixels per second and
    // bias stripes to move a bit faster than traffic for stronger motion.
    final stripeBias = 2.0; // stripes a bit faster than traffic
    // Road should not move when speed is 0
    final pixelsPerSec = (2.8 * model.speed) * speedMult * road.height * stripeBias * _speedFactor;
    if (pixelsPerSec > 0) {
      model.scroll = (model.scroll + dt * pixelsPerSec) % (road.height * 1000);
    }

    // Day/Night cycle over ~40s
    final phase = (elapsed.inMilliseconds / 40000.0) % 2.0; // 0..2
    model.night = phase < 1 ? phase : (2 - phase);

    // Curvature evolution: freeze when speed is 0 (no turning)
    if (model.speed > 0) {
      model.curveChangeTimer -= dt;
      if (model.curveChangeTimer <= 0) {
        model.curveChangeTimer = rng.nextDouble() * 4.0 + 3.0; // 3..7s
        model.curveTarget = (rng.nextDouble() * 2 - 1) * 0.9; // -0.9..0.9
      }
      final curveDelta = (model.curveTarget - model.curveOffset);
      final maxStep = dt * 0.25 * (0.6 + model.speed); // faster at speed
      if (curveDelta.abs() > maxStep) {
        model.curveOffset += maxStep * curveDelta.sign;
      } else {
        model.curveOffset = model.curveTarget;
      }
    }

    // Keep player's absolute X stable when road sways (car shouldn't auto-turn)
    final newRoad = _roadRectForSize(Size(size.width, size.height));
    final dxRoad = newRoad.center.dx - road.center.dx;
    if (dxRoad != 0) {
      model.player.x -= dxRoad / (road.width * _kLaneXFactor);
    }

    // Road width evolution (freeze at 0 speed). When active, keep player position stable
    if (model.speed > 0) {
      // First minute: keep width stable (no slimming)
      if (model.elapsed >= 60.0) {
        model.roadWidthChangeTimer -= dt;
        if (model.roadWidthChangeTimer <= 0) {
          model.roadWidthChangeTimer = rng.nextDouble() * 5.0 + 4.0; // 4..9s
          // Progressive min width per minute; after ~4 min reach ~0.37
          final minutes = model.elapsed / 60.0;
          final t = minutes.clamp(0.0, 4.0) / 4.0; // 0..1 over 0..4 min
          final minWidth = 0.86 - (0.49 * t); // 0.86 -> ~0.37
          final maxWidth = 0.90;
          model.roadWidthTarget = rng.nextDouble() * (maxWidth - minWidth) + minWidth;
        }
        final oldWidth = road.width;
        final wDelta = model.roadWidthTarget - model.roadWidthFactor;
        final wStep = (dt * 0.12).clamp(0.0, 0.12);
        if (wDelta.abs() > wStep) {
          model.roadWidthFactor += wStep * wDelta.sign;
        } else {
          model.roadWidthFactor = model.roadWidthTarget;
        }
        // Recompute road and compensate player x to keep screen position stable
        final roadAfterWidth = _roadRectForSize(Size(size.width, size.height));
        final scale = oldWidth / roadAfterWidth.width;
        model.player.x = (model.player.x * scale).clamp(-1.0, 1.0);
        road = roadAfterWidth;
      }
    }

    // Spawn AI traffic while running
    if (model.state == _GameState.running) {
      // Progressive spawn intensity increases over time
      final minutes = model.elapsed / 60.0;
      final spawnIntensity = 1.0 + minutes * 0.35; // up to ~2.75x at 5 min
      model.spawnCooldown -= dt * (0.6 + model.speed) * _speedFactor * model.config.difficulty * spawnIntensity;
      if (model.spawnCooldown <= 0) {
        var base = (rng.nextDouble() * 1.2 + 0.8) / model.config.difficulty * (1.0 + model.safeStart * 0.08);
        if (model.elapsed < 60.0) base *= 1.6; // fewer cars during first minute
        base /= spawnIntensity;
        model.spawnCooldown = base;
        int lane = rng.nextInt(3) - 1; // -1,0,1
        // Avoid player's lane often
        final playerLane = (model.player.x.abs() < 0.25) ? 0 : (model.player.x.isNegative ? -1 : 1);
        if ((model.safeStart > 4.0) || (lane == playerLane && rng.nextDouble() < 0.7)) {
          final alternatives = <int>[-1, 0, 1]..remove(playerLane);
          lane = alternatives[rng.nextInt(alternatives.length)];
        }
        // Keep distance from same-lane cars near spawn
        final tooClose = model.traffic.any((c) => (c.x - lane * 0.5).abs() < 0.1 && (c.y > 0.7));
        if (!tooClose) {
          final car = _Car(lane * 0.5, 1.1, 0.10, 0.18);
          // Randomize AI relative speed around ~70% of ground
          car.speedScale = 0.7 + (rng.nextDouble() - 0.5) * 0.2; // 0.6..0.8
          model.traffic.add(car);
        } else {
          model.spawnCooldown *= 0.4; // retry sooner
        }
      }
      // Hazards spawn
      final hazardIntensity = 1.0 + minutes * 0.30;
      model.hazardCooldown -= dt * (0.35 + model.speed * 0.6) * _speedFactor * model.config.difficulty * hazardIntensity;
      if (model.hazardCooldown <= 0) {
        var base = (rng.nextDouble() * 3.4 + 1.6) / model.config.difficulty;
        if (model.elapsed < 60.0) base *= 1.4; // fewer hazards in first minute
        base /= hazardIntensity;
        model.hazardCooldown = base; // less frequent initially, more as time passes
        int laneIndex = rng.nextInt(3) - 1;
        final playerLane = (model.player.x.abs() < 0.25) ? 0 : (model.player.x.isNegative ? -1 : 1);
        if (laneIndex == playerLane && rng.nextBool()) {
          laneIndex = (laneIndex == 1 ? 0 : laneIndex + 1);
        }
        final lane = (laneIndex * 0.5).toDouble();
        final type = rng.nextBool() ? _HazardType.oil : _HazardType.puddle;
        model.hazards.add(_Hazard(type, lane, 1.05));
      }
      // Fuel/Nitro/Coin pickups: spawn more frequently overall, and slightly more over time
      final pickupIntensity = 1.0 + minutes * 0.20; // modest ramp
      model.pickupCooldown -= dt * (0.35 + model.speed * 0.7) * _speedFactor * pickupIntensity;
      if (model.pickupCooldown <= 0) {
        var base = rng.nextDouble() * 3.0 + 3.0; // ~3..6s
        base /= pickupIntensity;
        model.pickupCooldown = base;
        final lane = (rng.nextInt(3) - 1) * 0.5;
        final roll = rng.nextDouble();
        if (roll < 0.7) {
          model.pickups.add(_Pickup(_PickupType.fuel, lane.toDouble(), 1.05));
        } else if (roll < 0.9) {
          model.pickups.add(_Pickup(_PickupType.nitro, lane.toDouble(), 1.05));
        } else {
          // coin line across lanes
          for (final l in [-0.5, 0.0, 0.5]) {
            model.pickups.add(_Pickup(_PickupType.coin, l.toDouble(), 1.05 + rng.nextDouble() * 0.05));
          }
        }
      }
      // Extra life pickup: every 120s when lives < 3
      if (model.lifePickupTimer > 0) {
        model.lifePickupTimer -= dt;
      }
      if (model.lifePickupTimer <= 0 && model.lives < 3) {
        final hasExistingLife = model.pickups.any((p) => p.type == _PickupType.life && p.y > 0);
        if (!hasExistingLife) {
          final lane = (rng.nextInt(3) - 1) * 0.5;
          model.pickups.add(_Pickup(_PickupType.life, lane.toDouble(), 1.05));
          model.lifePickupTimer = 120.0; // reset timer after spawning
        }
      }
      // Combo timer decay
      model.comboTimer -= dt;
      if (model.comboTimer < 0) { model.comboTimer = 0; model.combo = 0; }
    }

    // Move traffic toward player; remove offscreen and add score (only while running)
    if (model.state == _GameState.running) {
        for (final c in model.traffic) {
          c.prevY = c.y;
          // Base ground flow (matches road movement speed)
          final baseFlow = (2.8 * model.speed) * _speedFactor;
          // AI traffic should appear to drive forward, but slower than player → move slower than ground
          double v = baseFlow * (c.speedScale.clamp(0.5, 0.9)); // randomized per car
          // During nitro, increase absolute world flow and make AI relatively slower
          if (model.nitroActive && model.nitroCooldown <= 0) {
            v *= speedMult; // approach faster
            v *= (1.0 - 0.2 * model.nitroHeat); // but relatively slower than player
          }
          if (model.state == _GameState.gameOver && model.speed == 0.0 && !c.overtake) {
            v = 0.0; // freeze normal traffic when fully stopped at game over
          }
          if (c.overtake) {
            v = -0.9 * _speedFactor; // negative makes it move upward (bottom -> top)
          }
          c.y -= dt * v;
          // Mark pass and play whoosh when crossing the player's Y
          if (!c.passed && !c.overtake && c.y <= model.player.y + 0.02) {
            c.passed = true;
            final dx = (c.x - model.player.x).abs();
            if (dx < 0.22) {
              audio.whoosh();
            }
            // Near-miss: very close pass grants combo and points
            if (dx < 0.06) {
              model.nearMissCombo += 1;
              model.nearMissTimer = 2.0;
              final bonus = 30 * model.nearMissCombo;
              model.score += (bonus * model.multiplier).round();
              _showBanner('NEAR MISS +$bonus');
            }
          }
          if (!c.passed && c.overtake && c.y >= model.player.y - 0.02) {
            c.passed = true;
            if ((c.x - model.player.x).abs() < 0.22) {
              audio.whoosh();
            }
          }
        }
        model.traffic.removeWhere((c) {
          // Remove offscreen: normal traffic when it goes below bottom, overtake when it exits above top
          final offscreen = c.overtake ? (c.y > 1.3) : (c.y < -0.3);
          if (offscreen) {
            if (model.state == _GameState.running) {
              model.combo += 1; model.comboTimer = 2.0;
              final base = 10 * math.max(1, model.combo ~/ 3);
              model.score += (base * model.multiplier).round();
              model.passed += 1;
              model.overtakesDoneThisLevel += 1;
              if (model.overtakesDoneThisLevel >= model.overtakesGoal) {
                model.overtakesDoneThisLevel = 0;
                model.overtakesGoal = (model.overtakesGoal + 5).clamp(10, 50);
                model.multiplier += 1.0;
                _showBanner('OVERTAKE QUOTA! +1x');
              }
            }
            return true;
          }
          return false;
        });
    
    }
    
    _clampPlayer();

    // Collisions (only while running)
    final baseW = model.refRoadWidth > 0 ? model.refRoadWidth : road.width;
    var pRect = model.player.toRect(road, baseW);
    if (model.dangerMode) {
      final shrink = baseW * 0.02;
      pRect = pRect.deflate(shrink);
    }
    // Hazards and pickups move only while running
    if (model.state == _GameState.running) {
      final groundFlow = (2.8 * model.speed) * _speedFactor * speedMult;
      for (final h in model.hazards) {
        h.y -= dt * groundFlow;
      }
      model.hazards.removeWhere((h) => h.y < -0.2);
      for (final p in model.pickups) {
        p.y -= dt * groundFlow;
      }
      model.pickups.removeWhere((p) => p.y < -0.2);
    }

    if (model.state == _GameState.running) {
      for (final h in model.hazards) {
      if (model.invuln <= 0 && h.toRect(road, baseW).deflate(baseW * 0.02).overlaps(pRect.deflate(baseW * 0.02))) {
          if (h.type == _HazardType.oil) {
            // brief slip effect
            model.player.x += (rng.nextDouble() - 0.5) * 0.3;
            model.speed = math.max(0.3, model.speed * 0.6);
            audio.screech();
            model.shake = 0.2;
            // Drop quick skid marks at tires
          final pr = model.player.toRect(road, baseW);
            final l = Offset(pr.left + pr.width*0.05, pr.bottom - pr.height*0.2);
            final r = Offset(pr.right - pr.width*0.05, pr.bottom - pr.height*0.2);
            model.skids.add(_Skid(l.translate(-6, -2), l.translate(6, 2), 0.6));
            model.skids.add(_Skid(r.translate(-6, -2), r.translate(6, 2), 0.6));
          } else {
            // puddle slows down a bit and darkens screen briefly
            model.speed = math.max(0.25, model.speed * 0.7);
            audio.splash();
            model.shake = 0.15;
          }
          model.invuln = 1.0; // grace window to avoid chain hits
          model.risk = 0.0; model.multiplier = 1.0; // reset multiplier on hit
          // Lose a life when hitting a hazard
          _onLifeLost();
          if (model.lives <= 0) {
            model.state = _GameState.gameOver;
            model.hiScore = math.max(model.hiScore, model.score);
            audio.gameOver();
          }
        }
      }
      for (final p in model.pickups) {
        if (p.toRect(road, baseW).overlaps(pRect)) {
          switch (p.type) {
            case _PickupType.fuel:
              model.fuel = math.min(100.0, model.fuel + 25);
              model.score += 50;
              audio.beep(880, 70);
              audio.beep(660, 70);
              break;
            case _PickupType.life:
              if (model.lives < 3) {
                model.lives += 1;
                model.score += 100;
              }
              // distinctive chime
              audio.beep(990, 80);
              audio.beep(1320, 80);
              break;
            case _PickupType.nitro:
              model.nitroHeat = math.max(model.nitroHeat, 0.2);
              model.nitroActive = true;
              model.nitroCooldown = 0.0;
              _showBanner('NITRO!');
              break;
            case _PickupType.coin:
              model.score += (20 * model.multiplier).round();
              audio.beep(1200, 50);
              break;
          }
          p.y = -1; // mark for removal
        }
      }
      model.pickups.removeWhere((p) => p.y < 0);
    for (final car in model.traffic) {
      if (model.invuln <= 0 && car.toRect(road, baseW).deflate(baseW * 0.02).overlaps(pRect.deflate(baseW * 0.02))) {
        // Simple collision penalty
        model.speed = 0.2;
        audio.crash();
        model.shake = 0.25;
        model.invuln = 1.0;
        model.risk = 0.0; model.multiplier = 1.0;
        // Lose a life on traffic collision
        _onLifeLost();
        if (model.lives <= 0) {
          model.state = _GameState.gameOver;
          model.hiScore = math.max(model.hiScore, model.score);
          audio.gameOver();
        }
        break;
        }
      }
      // Side collisions with road edges
      final driveLeft = road.left + road.width * 0.08;
      final driveRight = road.right - road.width * 0.08;
      if (model.invuln <= 0 && (pRect.left < driveLeft || pRect.right > driveRight)) {
      model.speed = math.max(0.25, model.speed * 0.6);
      audio.crash();
      model.shake = 0.2;
      model.invuln = 0.5;
        // Nudge back onto road
        if (pRect.left < driveLeft) {
          model.player.x += 0.08;
        } else {
          model.player.x -= 0.08;
        }
        // Lose a life on hard edge impact
        _onLifeLost();
        if (model.lives <= 0) {
          model.state = _GameState.gameOver;
          model.hiScore = math.max(model.hiScore, model.score);
          audio.gameOver();
        }
      }
    }

    // Slipstream: behind a car boosts speed gradually
    if (model.state == _GameState.running) {
      bool drafting = false;
      for (final c in model.traffic) {
        final ahead = (c.y < model.player.y) && (model.player.y - c.y) < 0.12;
        final dx = (c.x - model.player.x).abs();
        if (ahead && dx < 0.1) { drafting = true; break; }
      }
      if (drafting) {
        model.draftTimer = math.min(1.5, model.draftTimer + dt);
        model.speed = (model.speed + 0.15 * dt).clamp(0.0, 1.0);
      } else {
        model.draftTimer = math.max(0.0, model.draftTimer - dt);
      }
      // Nitro heats up while active, cools otherwise
      if (model.nitroActive && model.nitroCooldown <= 0) {
        model.nitroHeat = math.min(1.0, model.nitroHeat + dt * 0.25);
        model.speed = (model.speed + 0.25 * dt).clamp(0.0, 1.0);
        if (model.nitroHeat >= 1.0) { model.nitroActive = false; model.nitroCooldown = 5.0; }
      } else {
        model.nitroHeat = math.max(0.0, model.nitroHeat - dt * 0.12);
        if (model.nitroCooldown > 0) model.nitroCooldown = math.max(0.0, model.nitroCooldown - dt);
      }
      // Near-miss timer decay resets combo
      if (model.nearMissTimer > 0) {
        model.nearMissTimer = math.max(0.0, model.nearMissTimer - dt);
      } else {
        model.nearMissCombo = 0;
      }
    }

    // Engine audio follow speed
    _engine.update(model.effectiveSpeed.clamp(0.0, 1.0));
    // Shake & invulnerability decay
    if (model.shake > 0) model.shake = math.max(0, model.shake - dt * 1.4);
    if (model.invuln > 0) model.invuln = math.max(0, model.invuln - dt);

    // Painter-driven repaint each frame
    _repaint.value++;
    // Decay banner timer
    if (model.bannerTimer > 0) {
      model.bannerTimer = math.max(0, model.bannerTimer - dt);
      if (model.bannerTimer == 0) model.bannerText = null;
    }
    // Only rebuild widget tree on state transitions (e.g., overlay changes)
    if (model.state != _lastState) {
      _lastState = model.state;
      if (mounted) setState(() {});
    }
  }

  Duration? _lastTime;

  Rect _roadRectForSize(Size s) {
    final w = s.width * (model.roadWidthFactor); // road+edges width region (dynamic)
    final maxShift = s.width * 0.18; // sway left/right
    final centerX = s.width * 0.5 + model.curveOffset.clamp(-1.0, 1.0) * maxShift;
    final left = (centerX - w * 0.5).clamp(0.0, s.width - w);
    return Rect.fromLTWH(left, 0, w, s.height);
  }

  void _onHorizontalDrag(DragUpdateDetails d) {
    final size = context.size;
    if (size == null) return;
    final road = _roadRectForSize(size);
    final nx = ((d.localPosition.dx - road.center.dx) / (road.width * _kLaneXFactor)).clamp(-1.0, 1.0);
    model.player.x = nx.toDouble();
  }

  void _clampPlayer() {
    if (model.player.x <= -1.0 || model.player.x >= 1.0) {
      model.speed = math.max(0.2, model.speed * 0.85);
    }
    model.player.x = model.player.x.clamp(-1.0, 1.0);
  }

  void _onLifeLost() {
    model.lives = math.max(0, model.lives - 1);
    // Reset perfect run and multiplier
    model.perfectTime = 0.0;
    model.multiplier = 1.0;
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

  void _showBanner(String text) {
    model.bannerText = text;
    model.bannerTimer = 1.5;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDrag,
      onTap: _onTap,
      onLongPressStart: (_) { model.dangerMode = true; },
      onLongPressEnd: (_) { model.dangerMode = false; },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // keep audio mixers in sync with config each frame
          // Keep audio mixers in sync with config each frame
          // Apply menu config; in low graphics, mute SFX/engine to avoid CPU spikes
          final mus = model.config.musicEnabled ? model.config.musicVolume : 0.0;
          final sfxBase = model.config.sfxEnabled ? model.config.sfxVolume : 0.0;
          final sfx = model.config.lowGraphics ? 0.0 : sfxBase;
          _engine.master = sfx; // engine treated as SFX
          audio.sfxVolume = sfx;
          _music.setVolume(mus);
          return widget.builder(context, model, _painter);
        },
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    audio.dispose();
    _engine.dispose();
    _music.dispose();
    super.dispose();
  }
}

class _LeMansPainter extends CustomPainter {
  final _GameModel model;
  late Rect road;
  final _HudTextCache _hud = _HudTextCache();
  final TextStyle _hudWhite = const TextStyle(fontFamily: 'VT323', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white);
  _LeMansPainter(this.model, Listenable repaint) : super(repaint: repaint);
  Rect _roadRectForSize(Size s) {
    final w = s.width * (model.roadWidthFactor);
    final maxShift = s.width * 0.18;
    final centerX = s.width * 0.5 + model.curveOffset.clamp(-1.0, 1.0) * maxShift;
    final left = (centerX - w * 0.5).clamp(0.0, s.width - w);
    return Rect.fromLTWH(left, 0, w, s.height);
  }

  // Color utilities to simulate night dimming and simple alpha-less fade.
  int _r(Color c) => (c.r * 255.0).round() & 0xFF;
  int _g(Color c) => (c.g * 255.0).round() & 0xFF;
  int _b(Color c) => (c.b * 255.0).round() & 0xFF;
  Color _dim(Color c, [double factor = 1.0]) {
    final dayBlend = 1.0 - model.night * 0.85; // stronger night dimming
    final f = (dayBlend * factor).clamp(0.0, 1.0);
    return Color.fromARGB(255, (_r(c) * f).round(), (_g(c) * f).round(), (_b(c) * f).round());
  }

  @override
  void paint(Canvas canvas, Size size) {
    road = _roadRectForSize(size);
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
    // Biome-tinted road
    Color leftCol = C64Palette.roadBlue;
    Color rightCol = C64Palette.roadPurple;
    if (model.biome == 1) { // city: cooler blue/purple
      leftCol = const Color(0xFF203A70);
      rightCol = const Color(0xFF4B2A6B);
    } else if (model.biome == 2) { // desert: warmer hues
      leftCol = const Color(0xFF5B3A1E);
      rightCol = const Color(0xFF6A4220);
    }
    // Road base fill with dimming applied
    canvas.drawRect(leftBand, Paint()..color = _dim(leftCol));
    canvas.drawRect(rightBand, Paint()..color = _dim(rightCol));

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
    // Skid marks (under cars)
    for (final s in model.skids) {
      final alpha = (s.life.clamp(0, 0.6) / 0.6 * 140).round();
      final paint = Paint()..color = Color.fromARGB(alpha, 40, 40, 40)..strokeWidth = 3;
      canvas.drawLine(s.a, s.b, paint);
    }

    // Center dashed line
    _drawCenterDashes(canvas, size);

    // Start line and lights when in countdown
    if (model.state == _GameState.countdown) {
      _drawStartLine(canvas, size);
      _drawStartLights(canvas);
    }

    final baseW = model.refRoadWidth > 0 ? model.refRoadWidth : road.width;
    // Hazards
    for (final h in model.hazards) {
      final r = h.toRect(road, baseW);
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
      final r = p.toRect(road, baseW);
      switch (p.type) {
        case _PickupType.fuel:
          final paint = Paint()..color = const Color(0xFFFFD54F);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), paint);
          // small fuel icon stripe
          canvas.drawRect(Rect.fromLTWH(r.left + r.width*0.2, r.top + r.height*0.4, r.width*0.6, r.height*0.2),
            Paint()..color = Colors.brown);
          break;
        case _PickupType.life:
          // green life box with white plus icon
          final paint = Paint()..color = C64Palette.green;
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), paint);
          final plusW = r.width * 0.6;
          final plusT = r.height * 0.18;
          canvas.drawRect(Rect.fromCenter(center: r.center, width: plusW, height: plusT), Paint()..color = Colors.white);
          canvas.drawRect(Rect.fromCenter(center: r.center, width: plusT, height: plusW), Paint()..color = Colors.white);
          break;
        case _PickupType.nitro:
          final paint = Paint()..color = const Color(0xFF42A5F5);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), paint);
          // lightning bolt
          final path = Path()
            ..moveTo(r.left + r.width*0.35, r.top + r.height*0.2)
            ..lineTo(r.center.dx, r.center.dy)
            ..lineTo(r.left + r.width*0.55, r.center.dy)
            ..lineTo(r.right - r.width*0.2, r.bottom - r.height*0.2)
            ..close();
          canvas.drawPath(path, Paint()..color = Colors.white);
          break;
        case _PickupType.coin:
          canvas.drawCircle(r.center, r.width*0.45, Paint()..color = const Color(0xFFFFC107));
          canvas.drawCircle(r.center, r.width*0.25, Paint()..color = const Color(0xFFFFF59D));
          break;
      }
    }

    // Traffic
    for (final c in model.traffic) {
      _drawCar(canvas, c.toRect(road, baseW), body: _dim(const Color(0xFFDDDDDD)), tailLights: true);
    }

    // Player car
    // Player car (flash when invulnerable)
    final pBody = _dim(const Color(0xFF7EB7FF));
    _drawCar(canvas, model.player.toRect(road, baseW), body: pBody, tailLights: true, headLights: true);
    if (model.invuln > 0) {
      final flash = (math.sin(model.scroll * 0.1) > 0) ? 160 : 0;
      if (flash > 0) {
        _drawCar(canvas, model.player.toRect(road, baseW), body: Color.fromARGB(flash, 255, 255, 255));
      }
    }

    // Headlights mask at night (always on; simplified in low graphics)
    if (model.night > 0.4) {
      final darkness = (model.night - 0.4) / 0.6; // 0..1
      _drawHeadlights(canvas, size, darkness);
      // Emissive tail lights so they visibly glow in the dark
      _drawTailLightEmission(canvas);
    }

    // HUD (drawn after darkness overlay so it remains bright)
    _drawHud(canvas, size);
  }

  void _drawTailLightEmission(Canvas canvas) {
    // Extra emissive pass drawn after darkness to ensure visibility at night
    final n = ((model.night - 0.4) / 0.6).clamp(0.0, 1.0);
    if (n <= 0.0) return;
    final int alpha = model.config.lowGraphics
        ? (100 + (60 * n).round())
        : (140 + (80 * n).round());
    final glow = Paint()
      ..blendMode = BlendMode.screen
      ..color = Color.fromARGB(alpha.clamp(0, 255), 255, 70, 70)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, model.config.lowGraphics ? 3 : 8);
    void drawFor(Rect r) {
      final tlW = r.width * 0.16;
      final tlH = r.height * 0.10;
      final y = r.bottom - tlH - r.height * 0.06;
      final left = Rect.fromLTWH(r.left + r.width * 0.08, y, tlW, tlH);
      final right = Rect.fromLTWH(r.right - r.width * 0.08 - tlW, y, tlW, tlH);
      final glowInflate = model.config.lowGraphics ? 3.0 : 5.0;
      canvas.drawRect(left.inflate(glowInflate), glow);
      canvas.drawRect(right.inflate(glowInflate), glow);
    }
    // Traffic
    final baseW2 = model.refRoadWidth > 0 ? model.refRoadWidth : road.width;
    for (final c in model.traffic) {
      drawFor(c.toRect(road, baseW2));
    }
    // Player
    drawFor(model.player.toRect(road, baseW2));
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

  void _drawCar(Canvas canvas, Rect r, {required Color body, bool tailLights = false, bool headLights = false}) {
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
    // tail lights for cars — glow intensifies with night
    if (tailLights) {
      final tlW = r.width * 0.16;
      final tlH = r.height * 0.10;
      final y = r.bottom - tlH - r.height * 0.06;
      final left = Rect.fromLTWH(r.left + r.width * 0.08, y, tlW, tlH);
      final right = Rect.fromLTWH(r.right - r.width * 0.08 - tlW, y, tlW, tlH);
      final n = ((model.night - 0.35) / 0.65).clamp(0.0, 1.0);
      // During day: dim lens only; at night: bright core + local glow (also reinforced post-overlay)
      if (n <= 0.0) {
        final lens = Paint()..color = const Color(0xFF7A2020);
        canvas.drawRect(left, lens);
        canvas.drawRect(right, lens);
      } else {
        final int alpha = model.config.lowGraphics
            ? (120 + (50 * n).round())
            : (170 + (70 * n).round());
        final glow = Paint()
          ..color = Color.fromARGB(alpha.clamp(0, 255), 255, 40, 40)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, model.config.lowGraphics ? 2 : 6);
        final core = Paint()..color = const Color(0xFFFF4040);
        final glowInflate = model.config.lowGraphics ? 2.0 : 3.0;
        canvas.drawRect(left.inflate(glowInflate), glow);
        canvas.drawRect(right.inflate(glowInflate), glow);
        canvas.drawRect(left, core);
        canvas.drawRect(right, core);
      }
    }
    // front headlights for player (white)
    if (headLights) {
      final hlW = r.width * 0.14;
      final hlH = r.height * 0.09;
      final y = r.top + r.height * 0.08;
      final left = Rect.fromLTWH(r.left + r.width * 0.12, y, hlW, hlH);
      final right = Rect.fromLTWH(r.right - r.width * 0.12 - hlW, y, hlW, hlH);
      final glow = Paint()
        ..color = const Color.fromARGB(140, 255, 255, 255)
        ..maskFilter = model.config.lowGraphics ? null : const MaskFilter.blur(BlurStyle.normal, 4);
      final core = Paint()..color = const Color(0xFFFFFFFF);
      canvas.drawRect(left.inflate(2), glow);
      canvas.drawRect(right.inflate(2), glow);
      canvas.drawRect(left, core);
      canvas.drawRect(right, core);
    }
  }

  void _drawHud(Canvas canvas, Size size) {
    // Top-left: Hi-Score and lives
    _drawTopLeftHud(canvas, size);

    final right = size.width - 14.0;
    final x = right - 120.0;
    final top = 16.0;
    double drawText(String t, TextStyle style, double yy) {
      final tp = _hud.tp(t, style, maxWidth: 120);
      tp.paint(canvas, Offset(x, yy));
      return tp.height;
    }
    final styleWhite = _hudWhite;
    double y = top;
    y += drawText('SCORE  ${model.score}', styleWhite, y) + 10;
    // Fuel bar
    y += drawText('FUEL', styleWhite, y) + 6;
    final barW = 110.0, barH = 12.0;
    final pct = (model.fuel.clamp(0, 100)) / 100.0;
    final bg = Paint()..color = C64Palette.darkGray;
    Color fuelColor;
    if (pct > 0.5) {
      fuelColor = C64Palette.green;
    } else if (pct > 0.25) {
      fuelColor = C64Palette.amber;
    } else {
      fuelColor = const Color(0xFFFF5555);
    }
    final fg = Paint()..color = fuelColor;
    final barRect = Rect.fromLTWH(x, y, barW, barH);
    canvas.drawRRect(RRect.fromRectAndRadius(barRect, const Radius.circular(3)), bg);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW * pct, barH), const Radius.circular(3)), fg);
    y += barH + 10;
    y += drawText('SPEED', styleWhite, y) + 4;
    // speed meter boxes (3)
    final boxes = 3;
    final w = 26.0, h = 16.0, gap = 6.0;
    final eff = model.effectiveSpeed <= 0 ? model.speed : model.effectiveSpeed;
    int filled = (eff.clamp(0.0, 1.0) * (boxes + 0.001)).floor().clamp(0, boxes);
    for (int i = 0; i < boxes; i++) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + i * (w + gap), y, w, h), const Radius.circular(2));
      final Color col = i < filled
          ? C64Palette.cyan
          : C64Palette.cyan.withValues(alpha: 0.15);
      canvas.drawRRect(r, Paint()..color = col);
    }
    // Show 0 KM/H regardless of state
    final kmh = (eff * 160).round();
    drawText('   $kmh KM/H', styleWhite, y + h + 6);

    // Multiplier badge below speed (only when > 1x)
    if (model.multiplier > 1.0) {
      final r = 14.0; // radius
      final cx = right - r; // near right edge
      final cy = y + h + 34; // below KM/H line
      final badgePaint = Paint()..color = const Color(0xFFFF4040);
      canvas.drawCircle(Offset(cx, cy), r, badgePaint);
      final multiText = _hud.tp('${model.multiplier.toStringAsFixed(0)}x', const TextStyle(
        fontFamily: 'VT323', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white,
      ));
      multiText.paint(canvas, Offset(cx - multiText.width / 2, cy - multiText.height / 2));
    }
    // Nitro heat indicator (thin bar)
    if (model.nitroHeat > 0.01 || model.nitroCooldown > 0) {
      y += 26;
      drawText('NITRO', styleWhite, y);
      final nh = model.nitroHeat.clamp(0.0, 1.0);
      final barY = y + 16;
      final nbBg = Paint()..color = Colors.white10;
      final nbFg = Paint()..color = const Color(0xFFFF7043);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, barY, barW, 6), const Radius.circular(3)), nbBg);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, barY, barW * nh, 6), const Radius.circular(3)), nbFg);
      y = barY + 8;
    }

    // Level and multiplier badges (top-right area, small)
    // Multiplier text removed from top-right to avoid confusion near SCORE

    if (model.state == _GameState.gameOver) {
      final overlay = Paint()..color = const Color.fromARGB(140, 0, 0, 0);
      canvas.drawRect(Offset.zero & size, overlay);
    }
    // Hazard/traffic warnings: small arrows if something is close ahead
    _drawWarnings(canvas, size);

    // Transient banner overlay
    if (model.bannerTimer > 0 && model.bannerText != null) {
      final text = _hud.tp(model.bannerText!, const TextStyle(fontFamily: 'VT323', fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white), maxWidth: size.width * 0.9);
      final fade = model.bannerTimer.clamp(0.0, 1.0);
      final shadow = Paint()..color = Colors.black.withValues(alpha: (0.6 * fade));
      final yCenter = size.height * 0.25;
      final x = (size.width - text.width) / 2;
      // simple shadow
      canvas.drawRect(Rect.fromLTWH(x - 6, yCenter - 4, text.width + 12, text.height + 8), shadow);
      text.paint(canvas, Offset(x, yCenter));
    }
  }

  void _drawTopLeftHud(Canvas canvas, Size size) {
    // Hi-Score text
    final leftX = 14.0;
    final topY = 16.0;
    final hi = _hud.tp('HI-SCORE  ${model.hiScore}', const TextStyle(fontFamily: 'VT323', fontSize: 18, fontWeight: FontWeight.w700, color: C64Palette.green), maxWidth: size.width * 0.5);
    hi.paint(canvas, Offset(leftX, topY));
    // Lives (top-left) — three car icons like old arcade machines
    _drawLives(canvas, size);
    // Level under lives
    final levelStyle = const TextStyle(fontFamily: 'VT323', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70);
    final levelY = 44.0 + 32.0 + 10.0;
    final lvl = _hud.tp('LEVEL ${model.level}', levelStyle, maxWidth: size.width * 0.5);
    lvl.paint(canvas, Offset(14.0, levelY));
    // Show overtake objective progress
    final prog = _hud.tp('QUOTA ${model.overtakesDoneThisLevel}/${model.overtakesGoal}', const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white54), maxWidth: size.width * 0.5);
    prog.paint(canvas, Offset(14.0, levelY + 18));
  }

  // Painter does not control banners; handled by ticker state

  void _drawLives(Canvas canvas, Size size) {
    // Place below the pause button area to avoid overlap
    final double startX = 14.0;
    final double startY = 44.0;
    final double w = 22.0;
    final double h = 32.0;
    final double gap = 10.0;
    for (int i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(startX + i * (w + gap), startY, w, h);
      final alive = i < model.lives;
      final color = alive ? C64Palette.cyan : Colors.white24;
      _drawCar(canvas, rect, body: color);
    }
    // Show level just below lives
    final levelStyle = const TextStyle(fontFamily: 'VT323', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70);
    final levelY = 44.0 + 32.0 + 10.0; // startY + h + gap from _drawLives geometry
    final lvl = _hud.tp('LEVEL ${model.level}', levelStyle, maxWidth: size.width * 0.5);
    lvl.paint(canvas, Offset(startX, levelY));
  }

  @override
  bool shouldRepaint(covariant _LeMansPainter oldDelegate) => false;

  void _drawHeadlights(Canvas canvas, Size size, double intensity) {
    // Dark overlay layer, then cut out two soft cones using dstOut
    canvas.saveLayer(Offset.zero & size, Paint());
    final overlayAlpha = (220 * intensity).round().clamp(0, 255); // stronger darkness
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromARGB(overlayAlpha, 0, 0, 0));

    final baseW = model.refRoadWidth > 0 ? model.refRoadWidth : road.width;
    final car = model.player.toRect(road, baseW);
    final frontY = car.top + car.height * 0.1;
    final leftOrigin = Offset(car.left + car.width * 0.28, frontY);
    final rightOrigin = Offset(car.right - car.width * 0.28, frontY);

    Path conePath(Offset origin, double spreadFrac, double length) {
      final halfSpread = road.width * spreadFrac;
      final tipY = origin.dy - length;
      final leftTip = Offset(origin.dx - halfSpread, tipY);
      final rightTip = Offset(origin.dx + halfSpread, tipY);
      return Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(leftTip.dx, leftTip.dy)
        ..lineTo(rightTip.dx, rightTip.dy)
        ..close();
    }

    final baseLength = road.height * (0.46 + 0.20 * model.speed);
    final spread = 0.15; // wider spread for better coverage
    final leftCone = conePath(leftOrigin, spread, baseLength);
    final rightCone = conePath(rightOrigin, spread, baseLength);
    final p = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Colors.white
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, model.config.lowGraphics ? 4 : 10);
    canvas.drawPath(leftCone, p);
    canvas.drawPath(rightCone, p);
    // Inner brighter cores
    Path core(Offset origin) => conePath(origin, spread * 0.5, baseLength);
    canvas.drawPath(core(leftOrigin), p);
    canvas.drawPath(core(rightOrigin), p);

    canvas.restore();

    // Subtle light glints on objects within the cones (skipped in low graphics)
    if (!model.config.lowGraphics) {
      final combined = Path()..addPath(leftCone, Offset.zero)..addPath(rightCone, Offset.zero);
      canvas.save();
      canvas.clipPath(combined);
      final glint = Paint()
        ..blendMode = BlendMode.screen
        ..color = const Color.fromARGB(80, 255, 255, 255);
      // Traffic highlights
      for (final c in model.traffic) {
        final r = c.toRect(road, baseW);
        // small highlight on top surface
        final cap = Rect.fromLTWH(r.left + r.width * 0.15, r.top + r.height * 0.08, r.width * 0.7, r.height * 0.12);
        canvas.drawRRect(RRect.fromRectAndRadius(cap, const Radius.circular(2)), glint);
      }
      // Hazards
      for (final h in model.hazards) {
        final r = h.toRect(road, baseW);
        final cap = Rect.fromCenter(center: r.center.translate(0, -r.height * 0.15), width: r.width * 0.9, height: r.height * 0.4);
        canvas.drawOval(cap, glint);
      }
      // Pickups
      for (final pck in model.pickups) {
        final r = pck.toRect(road, baseW);
        final cap = Rect.fromCenter(center: r.center.translate(0, -r.height * 0.1), width: r.width * 0.8, height: r.height * 0.3);
        canvas.drawOval(cap, glint);
      }
      canvas.restore();
    }
  }

  void _drawWarnings(Canvas canvas, Size size) {
    final baseW = model.refRoadWidth > 0 ? model.refRoadWidth : road.width;
    final pRect = model.player.toRect(road, baseW);
    bool leftWarn = false, rightWarn = false;
    // lookahead window directly ahead of car
    for (final c in model.traffic) {
      final r = c.toRect(road, baseW);
      if (r.top < pRect.top - 40 && r.top > pRect.top - size.height * 0.45) {
        if (r.center.dx < pRect.center.dx - pRect.width * 0.2) leftWarn = true;
        if (r.center.dx > pRect.center.dx + pRect.width * 0.2) rightWarn = true;
      }
    }
    for (final h in model.hazards) {
      final r = h.toRect(road, baseW);
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
  double sfxVolume = 1.0; // master SFX volume 0..1
  Future<void> beep(int freq, int ms) async {
    if (sfxVolume <= 0) return;
    try {
      final bytes = _sineWavBytes(freq: freq, ms: ms, vol: 0.7 * sfxVolume);
      final path = await _writeTempWav(bytes, prefix: 'beep');
      await _player.play(DeviceFileSource(path));
    } catch (_) {}
  }

  Future<void> whoosh() async {
    if (sfxVolume <= 0) return;
    try {
      final p = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      final p1 = await _writeTempWav(_sineWavBytes(freq: 700, ms: 40, vol: 0.6 * sfxVolume), prefix: 'wh1');
      await p.play(DeviceFileSource(p1));
      await Future.delayed(const Duration(milliseconds: 35));
      final p2 = await _writeTempWav(_sineWavBytes(freq: 1000, ms: 40, vol: 0.6 * sfxVolume), prefix: 'wh2');
      await p.play(DeviceFileSource(p2));
      await Future.delayed(const Duration(milliseconds: 100));
      await p.stop();
      p.dispose();
    } catch (_) {}
  }

  // New synthesized effects
  Future<void> screech() async {
    // short rising tone + noise burst
    if (sfxVolume <= 0) return;
    try {
      final p = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      final s1 = await _writeTempWav(_sineWavBytes(freq: 1200, ms: 60, vol: 0.5 * sfxVolume), prefix: 'scr');
      await p.play(DeviceFileSource(s1));
      final s2 = await _writeTempWav(_noiseWavBytes(ms: 90, vol: 0.35 * sfxVolume), prefix: 'scrN');
      await p.play(DeviceFileSource(s2));
      await Future.delayed(const Duration(milliseconds: 180));
      await p.stop();
      p.dispose();
    } catch (_) {}
  }

  Future<void> splash() async {
    // short filtered noise burst
    if (sfxVolume <= 0) return;
    try {
      final p = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      final s = await _writeTempWav(_noiseWavBytes(ms: 120, vol: 0.45 * sfxVolume), prefix: 'spl');
      await p.play(DeviceFileSource(s));
      await Future.delayed(const Duration(milliseconds: 140));
      await p.stop();
      p.dispose();
    } catch (_) {}
  }

  Future<void> crash() async {
    // thud (low sine) + noise
    if (sfxVolume <= 0) return;
    try {
      final p = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      final s1 = await _writeTempWav(_sineWavBytes(freq: 180, ms: 120, vol: 0.95 * sfxVolume), prefix: 'cr1');
      await p.play(DeviceFileSource(s1));
      final s2 = await _writeTempWav(_noiseWavBytes(ms: 140, vol: 0.8 * sfxVolume), prefix: 'cr2');
      await p.play(DeviceFileSource(s2));
      await Future.delayed(const Duration(milliseconds: 220));
      await p.stop();
      p.dispose();
    } catch (_) {}
  }

  Future<void> gameOver() async {
    if (sfxVolume <= 0) return;
    try {
      final p = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      final a = await _writeTempWav(_sineWavBytes(freq: 660, ms: 120, vol: 0.5 * sfxVolume), prefix: 'go1');
      await p.play(DeviceFileSource(a));
      final b = await _writeTempWav(_sineWavBytes(freq: 440, ms: 150, vol: 0.6 * sfxVolume), prefix: 'go2');
      await p.play(DeviceFileSource(b));
      final c = await _writeTempWav(_sineWavBytes(freq: 330, ms: 180, vol: 0.6 * sfxVolume), prefix: 'go3');
      await p.play(DeviceFileSource(c));
      await Future.delayed(const Duration(milliseconds: 500));
      await p.stop();
      p.dispose();
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}

class _HudTextCache {
  final Map<String, TextPainter> _cache = {};
  TextPainter tp(String text, TextStyle style, {double? maxWidth}) {
    final key = '${style.hashCode}|$text|${maxWidth?.toStringAsFixed(1) ?? ''}';
    final existing = _cache[key];
    if (existing != null) return existing;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth ?? double.infinity);
    _cache[key] = tp;
    return tp;
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

Uint8List _noiseWavBytes({required int ms, double vol = 1.0}) {
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
  final rand = math.Random();
  for (int i = 0; i < totalSamples; i++) {
    // simple white noise, scaled
    final s = ((rand.nextDouble() * 2 - 1) * 0.4 * vol);
    final v = (s * 32767).clamp(-32768, 32767).toInt();
    w16(v);
  }
  return data.toBytes();
}

Future<String> _writeTempWav(Uint8List bytes, {String prefix = 'snd'}) async {
  final dir = Directory.systemTemp;
  final path = '${dir.path}/racedriver_${prefix}_${DateTime.now().microsecondsSinceEpoch}.wav';
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return path;
}

Uint8List _engineWavBytes({required int freq, required int ms}) {
  // Resonant-noise engine: pulse train at f0 + filtered noise through resonators
  const sr = 22050;
  final total = (sr * ms / 1000).floor();
  final bb = BytesBuilder();
  // WAV header mono 16-bit
  final byteRate = sr * 2;
  final blockAlign = 2;
  final subchunk2 = total * 2;
  final chunk = 36 + subchunk2;
  void w32(int v) => bb.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void w16(int v) => bb.add([v & 0xFF, (v >> 8) & 0xFF]);
  bb.add('RIFF'.codeUnits); w32(chunk); bb.add('WAVE'.codeUnits);
  bb.add('fmt '.codeUnits); w32(16); w16(1); w16(1); w32(sr); w32(byteRate); w16(blockAlign); w16(16);
  bb.add('data'.codeUnits); w32(subchunk2);

  // Fundamental (pulse) frequency ~ freq (Hz); duty ~0.25 simulates firing pulses
  final f0 = freq.toDouble().clamp(40.0, 180.0);
  final duty = 0.25;

  // Two resonators to emulate intake/exhaust formants
  // Centers scale mildly with f0 so tone changes with speed
  final fc1 = (350.0 + f0 * 1.5).clamp(300.0, 900.0); // lower formant
  final fc2 = (1100.0 + f0 * 2.0).clamp(900.0, 2200.0); // upper formant
  double r1 = 0.985; // bandwidth
  double r2 = 0.990;
  final c1 = 2.0 * math.cos(2 * math.pi * fc1 / sr);
  final c2 = 2.0 * math.cos(2 * math.pi * fc2 / sr);
  double y1_1 = 0.0, y1_2 = 0.0;
  double y2_1 = 0.0, y2_2 = 0.0;
  final rnd = math.Random();

  double prev = 0.0;
  final fade = (sr * 0.005).round(); // 5ms fade to avoid loop clicks
  for (int i = 0; i < total; i++) {
    final t = i / sr;
    // Pulse train at f0
    final ph = (t * f0) % 1.0;
    final pulse = ph < duty ? 1.0 : -0.8; // asymmetry
    // White noise input
    final n = (rnd.nextDouble() * 2 - 1);
    // Resonators (second-order): y[n] = 2*r*cos(w)*y[n-1] - r^2*y[n-2] + x
    final y1 = c1 * r1 * y1_1 - (r1 * r1) * y1_2 + n * 0.08;
    y1_2 = y1_1; y1_1 = y1;
    final y2 = c2 * r2 * y2_1 - (r2 * r2) * y2_2 + n * 0.05;
    y2_2 = y2_1; y2_1 = y2;
    // Mix: pulse dominates low end, resonators add realistic body
    double s = pulse * 0.28 + y1 * 0.35 + y2 * 0.22;
    // Gentle tremolo for life
    final trem = 0.9 + 0.1 * math.sin(2 * math.pi * 18.0 * t);
    s *= trem;
    // Simple low-pass smoothing to reduce harshness
    const alpha = 0.18;
    s = prev + alpha * (s - prev);
    prev = s;
    // Apply fade-in/out window
    double w = 1.0;
    if (i < fade) {
      w = i / fade;
    } else if (i > total - fade) {
      w = (total - i) / fade;
    }
    final v = (s * w * 32767).clamp(-32768, 32767).toInt();
    w16(v);
  }
  return bb.toBytes();
}

class _EngineAudio {
  final AudioPlayer _a = AudioPlayer();
  final AudioPlayer _b = AudioPlayer();
  bool _usingA = true;
  bool _started = false;
  bool _xfading = false;
  int _lastFreq = 0;
  double _currentVol = 0.0;
  double master = 1.0;
  final Map<int, String> _cache = {};
  AudioPlayer get _curr => _usingA ? _a : _b;
  AudioPlayer get _next => _usingA ? _b : _a;

  Future<void> update(double speed) async {
    if (master <= 0) {
      // Stop engine completely when muted to save CPU
      await stop();
      return;
    }
    final freq = (140 + speed * 320).round();
    final targetVol = (0.02 + speed * 0.06) * master; // further reduced engine loudness
    if (!_started) {
      final path = await _pathForFreq(freq);
      await _a.setReleaseMode(ReleaseMode.loop);
      await _a.setVolume(targetVol.clamp(0.0, 1.0));
      await _a.play(DeviceFileSource(path));
      _usingA = true;
      _started = true;
      _lastFreq = freq;
      _currentVol = targetVol;
      return;
    }
    final df = (freq - _lastFreq).abs();
    if (df > 20 && !_xfading) {
      // Crossfade to new loop to avoid gaps
      final path = await _pathForFreq(freq);
      final from = _curr;
      final to = _next;
      await to.setReleaseMode(ReleaseMode.loop);
      await to.setVolume(0.0);
      await to.play(DeviceFileSource(path));
      _xfading = true;
      // small pre-roll so the 'to' player is actually running before ramp
      await Future.delayed(const Duration(milliseconds: 60));
      const steps = 30; // ~600ms equal-power crossfade
      const stepMs = 20;
      for (int i = 1; i <= steps; i++) {
        final t = i / steps;
        // equal-power crossfade
        final toVol = (targetVol * math.sin(t * math.pi / 2)).clamp(0.0, 1.0);
        final fromVol = (_currentVol * math.cos(t * math.pi / 2)).clamp(0.0, 1.0);
        await to.setVolume(toVol);
        await from.setVolume(fromVol);
        await Future.delayed(const Duration(milliseconds: stepMs));
      }
      await from.stop();
      await to.setVolume(targetVol.clamp(0.0, 1.0));
      _usingA = !_usingA;
      _lastFreq = freq;
      _currentVol = targetVol;
      _xfading = false;
      return;
    }
    // Regular volume tracking when not crossfading
    if (!_xfading) {
      final p = _usingA ? _a : _b;
      await p.setVolume(targetVol.clamp(0.0, 1.0));
      _currentVol = targetVol;
      // Fallback: if player stopped for any reason, restart current loop
      final path = await _pathForFreq(_lastFreq == 0 ? freq : _lastFreq);
      // This call is safe; if already playing, player will ignore
      await p.play(DeviceFileSource(path));
    }
  }

  Future<String> _pathForFreq(int freq) async {
    if (_cache.containsKey(freq)) return _cache[freq]!;
    final bytes = _engineWavBytes(freq: freq, ms: 2000);
    final path = await _writeTempWav(bytes, prefix: 'eng_$freq');
    _cache[freq] = path;
    return path;
  }

  void dispose() {
    _a.dispose();
    _b.dispose();
  }

  Future<void> stop() async {
    try { await _a.stop(); } catch (_) {}
    try { await _b.stop(); } catch (_) {}
    _started = false;
  }
}

class _Music {
  final AudioPlayer _p = AudioPlayer();
  bool _started = false;
  double master = 0.18; // half of previous default
  Future<void> start() async {
    if (_started) return;
    final bytes = _makeLoop();
    await _p.setReleaseMode(ReleaseMode.loop);
    await _p.setVolume(master);
    final path = await _writeTempWav(bytes, prefix: 'music');
    await _p.play(DeviceFileSource(path));
    _started = true;
  }
  Future<void> stop() async { if (_started) { await _p.stop(); _started = false; } }
  Future<void> setVolume(double v) async { master = v.clamp(0.0, 1.0); await _p.setVolume(master); }
  void dispose() { _p.dispose(); }

  Uint8List _makeLoop() {
    // 32-bar chiptune at 120 BPM (4/4), 16th-note steps with A/B/C/D sections for variation
    const sr = 22050;
    const bpm = 120.0;
    const beatSec = 60.0 / bpm; // 0.5s
    const stepSec = beatSec / 4.0; // 16th note = 0.125s
    const bars = 32;
    const stepsPerBar = 16;
    const steps = bars * stepsPerBar;
    final totalSamples = (steps * stepSec * sr).round();
    final mix = List<double>.filled(totalSamples, 0.0);

    double noteHz(int midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    double square(double t, double hz, {double duty = 0.5}) {
      final phase = (t * hz) % 1.0;
      return phase < duty ? 1.0 : -1.0;
    }
    double tri(double t, double hz) {
      final p = (t * hz) % 1.0;
      return 4.0 * (p - 0.5).abs() - 1.0;
    }
    double envAD(double t, double dur, {double a = 0.01, double d = 0.12}) {
      if (t < 0) return 0;
      if (t < a) return t / a;
      final rest = (dur - a).clamp(0.0001, dur);
      final tt = (t - a) / rest;
      return (1.0 - tt).clamp(0.0, 1.0);
    }
    double noise(int i) {
      int x = i * 1103515245 + 12345;
      x = (x >> 3) ^ (x << 1);
      return ((x & 1023) / 511.5) - 1.0;
    }

    void addSteps(List<int> midiSeq, {double vol = 0.2, String wave = 'square', double duty = 0.5, int lenSteps = 1}) {
      for (int s = 0; s < steps; s++) {
        final midi = midiSeq[s % midiSeq.length];
        if (midi <= 0) continue; // rest
        final start = (s * stepSec * sr).round();
        final len = (stepSec * sr * lenSteps).round();
        final f = noteHz(midi);
        for (int i = 0; i < len && start + i < totalSamples; i++) {
          final t = i / sr;
          final e = envAD(t, len / sr, a: 0.004, d: 0.18);
          double w;
          if (wave == 'square') {
            w = square(t, f, duty: duty);
          } else {
            w = tri(t, f);
          }
          mix[start + i] += w * e * vol;
        }
      }
    }

    // Sections chord progressions (triads, MIDI): C minor scenes
    final progA = [[60, 63, 67], [56, 60, 63], [58, 62, 65], [55, 59, 62]]; // Cm Ab Bb G
    final progB = [[53, 56, 60], [51, 55, 58], [58, 62, 65], [55, 58, 62]]; // Fm Db Eb Bb
    final progC = [[56, 60, 63], [53, 56, 60], [55, 59, 62], [58, 62, 65]]; // Ab Fm G Bb
    final progD = [[55, 59, 62], [60, 63, 67], [58, 62, 65], [56, 60, 63]]; // G Cm Bb Ab
    List<List<int>> chordsForBar(int bar) {
      final sec = (bar ~/ 8) % 4; // 8 bars per section
      switch (sec) {
        case 0: return progA;
        case 1: return progB;
        case 2: return progC;
        default: return progD;
      }
    }

    // Build sequences per bar for lead, bass, arp
    final lead = <int>[];
    final lead2 = <int>[];
    final bass = <int>[];
    final arp = <int>[];
    for (int bar = 0; bar < bars; bar++) {
      final chords = chordsForBar(bar);
      final c = chords[bar % 4];
      final root = c[0];
      final third = c[1];
      final fifth = c[2];
      // Variation pattern selection per bar
      final mode = bar % 4;
      List<int> patLead;
      List<int> patLead2;
      List<int> patArp;
      switch (mode) {
        case 0:
          patLead = [root + 12, third + 12, fifth + 12, third + 12];
          patLead2 = [0, root + 24, 0, root + 24];
          patArp = [root + 12, third + 12, fifth + 12, third + 12];
          break;
        case 1:
          patLead = [third + 12, fifth + 12, root + 12, fifth + 12];
          patLead2 = [root + 24, 0, third + 24, 0];
          patArp = [root + 12, fifth + 12, third + 12, fifth + 12];
          break;
        case 2:
          patLead = [fifth + 12, third + 12, root + 12, third + 12];
          patLead2 = [0, 0, root + 24, 0];
          patArp = [third + 12, root + 12, fifth + 12, root + 12];
          break;
        default:
          patLead = [root + 12, root + 19, third + 12, fifth + 12]; // add a 7th-ish color
          patLead2 = [0, root + 24, 0, fifth + 24];
          patArp = [root + 12, third + 12, fifth + 12, root + 12];
      }
      for (int i = 0; i < stepsPerBar; i++) {
        lead.add(patLead[i % 4]);
        lead2.add(patLead2[i % 4]);
        arp.add(patArp[i % 4]);
        // Bass: quarter notes with occasional fifth on off-beats
        if (i % 4 == 0) {
          bass.add(root - 12);
        } else if (i % 8 == 4 && (bar % 8) >= 4) {
          bass.add(fifth - 12);
        } else {
          bass.add(0);
        }
      }
    }

    // Drums
    void addKickSnare() {
      final kickLen = (stepSec * sr * 1.0).round();
      final snLen = (stepSec * sr * 1.0).round();
      for (int bar = 0; bar < bars; bar++) {
        final barStartStep = bar * stepsPerBar;
        // Kicks on beats 1 and 3
        for (final beatStep in [0, 8]) {
          final s = barStartStep + beatStep;
          final idx = (s * stepSec * sr).round();
          for (int i = 0; i < kickLen && idx + i < totalSamples; i++) {
            final t = i / sr;
            final env = envAD(t, kickLen / sr, a: 0.003, d: 0.15);
            final f = 100.0 + 80.0 * (1.0 - t * 8).clamp(0.0, 1.0);
            final w = math.sin(2 * math.pi * f * t);
            mix[idx + i] += w * env * 0.35;
          }
        }
        // Snares on beats 2 and 4
        for (final beatStep in [4, 12]) {
          final s = barStartStep + beatStep;
          final idx = (s * stepSec * sr).round();
          for (int i = 0; i < snLen && idx + i < totalSamples; i++) {
            final t = i / sr;
            final env = envAD(t, snLen / sr, a: 0.002, d: 0.12);
            final w = noise(idx + i);
            mix[idx + i] += w * env * 0.28;
          }
        }
        // Simple fill at the last two 16ths of each 8-bar section
        if ((bar % 8) == 7) {
          for (final step in [14, 15]) {
            final s = barStartStep + step;
            final idx = (s * stepSec * sr).round();
            final len = (stepSec * sr * 0.7).round();
            for (int i = 0; i < len && idx + i < totalSamples; i++) {
              final t = i / sr;
              final env = envAD(t, len / sr, a: 0.0015, d: 0.08);
              final w = noise(idx + i);
              mix[idx + i] += w * env * 0.22;
            }
          }
        }
      }
    }
    void addHats() {
      final hatLen = (stepSec * sr * 0.5).round();
      for (int s = 0; s < steps; s += 2) { // 8ths
        final idx = (s * stepSec * sr).round();
        for (int i = 0; i < hatLen && idx + i < totalSamples; i++) {
          final t = i / sr;
          final env = envAD(t, hatLen / sr, a: 0.001, d: 0.05);
          final w = noise(idx + i);
          mix[idx + i] += w * env * 0.10;
        }
      }
    }

    // Mix voices
    addSteps(lead,  vol: 0.16, wave: 'square', duty: 0.5, lenSteps: 2);
    addSteps(lead2, vol: 0.10, wave: 'square', duty: 0.25, lenSteps: 1);
    addSteps(arp,   vol: 0.11, wave: 'square', duty: 0.25, lenSteps: 1);
    addSteps(bass,  vol: 0.20, wave: 'tri',               lenSteps: 4);
    addKickSnare();
    addHats();

    // Normalize and convert to 16-bit PCM
    double mx = 0.001;
    for (final v in mix) { final av = v.abs(); if (av > mx) mx = av; }
    final scale = 0.85 / mx;
    final bytes = BytesBuilder();
    final byteRate = sr * 2;
    final subchunk2Size = totalSamples * 2;
    final chunkSize = 36 + subchunk2Size;
    void w32(int v) => bytes.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void w16(int v) => bytes.add([v & 0xFF, (v >> 8) & 0xFF]);
    bytes.add('RIFF'.codeUnits); w32(chunkSize); bytes.add('WAVE'.codeUnits);
    bytes.add('fmt '.codeUnits); w32(16); w16(1); w16(1); w32(sr); w32(byteRate); w16(2); w16(16);
    bytes.add('data'.codeUnits); w32(subchunk2Size);
    for (int i = 0; i < totalSamples; i++) {
      final v = (mix[i] * scale * 32767).clamp(-32768, 32767).toInt();
      w16(v);
    }
    return bytes.toBytes();
  }
}

class LeMansPage extends StatelessWidget {
  final GameConfig config;
  const LeMansPage({super.key, this.config = const GameConfig()});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // disable iOS back-swipe/back button
      child: Scaffold(
      backgroundColor: C64Palette.black,
      body: _GameTicker(
          builder: (context, model, painter) {
            model.config = config;
            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: painter,
                    ),
                  ),
                ),
                if (model.state == _GameState.gameOver) Positioned.fill(
                  child: Container(
                    color: const Color.fromARGB(160, 0, 0, 0),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(12)),
                        width: MediaQuery.of(context).size.width * 0.8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('GAME OVER', style: TextStyle(fontFamily: 'VT323', fontSize: 28, color: Colors.white)),
                            const SizedBox(height: 8),
                            if (model.continuesLeft > 0)
                              Text('Continue? (${model.continuesLeft} left)\nScore will reset to 0', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white70)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                if (model.continuesLeft > 0)
                                  ElevatedButton(
                                    onPressed: () {
                                      final st = context.findAncestorStateOfType<_GameTickerState>();
                                      st?._continueGame();
                                    },
                                    child: const Text('Continue', style: TextStyle(fontFamily: 'VT323', fontSize: 22)),
                                  ),
                                ElevatedButton(
                                  onPressed: () {
                                      final st = context.findAncestorStateOfType<_GameTickerState>();
                                      st?._music.stop();
                                      st?._engine.stop();
                                      Navigator.of(context).pop();
                                    },
                                  child: const Text('Quit', style: TextStyle(fontFamily: 'VT323', fontSize: 22)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Pause button removed
                // Swipe hint overlay driven by model.swipeHint
                if (model.swipeHint)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(180, 0, 0, 0),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Swipe to steer',
                            style: TextStyle(fontFamily: 'VT323', fontSize: 22, color: Colors.white),
                          ),
                        ),
                      ),
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


// (swipe-only) on-screen button widget removed
