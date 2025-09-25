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
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _CassetteArtPainter())),
            Center(
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
          ],
        ),
      ),
    );
  }

  // audio test function removed
}

// Controls selector and difficulty slider removed

// removed old slider/test widgets and helpers

class _CassetteArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Sky gradient
    final sky = Rect.fromLTWH(0, 0, size.width, size.height);
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1B1742), Color(0xFF0A0A0A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(sky);
    canvas.drawRect(sky, skyPaint);

    // Horizon glow
    final horizonY = size.height * 0.55;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0x55FF2EC4), Colors.transparent],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(size.width/2, horizonY), radius: size.width*0.8));
    canvas.drawCircle(Offset(size.width/2, horizonY), size.width*0.8, glowPaint);

    // Track (perspective trapezoid)
    final trackTopW = size.width * 0.18;
    final trackBottomW = size.width * 0.95;
    final topY = size.height * 0.58;
    final bottomY = size.height * 0.98;
    final trackPath = Path()
      ..moveTo(size.width/2 - trackTopW/2, topY)
      ..lineTo(size.width/2 + trackTopW/2, topY)
      ..lineTo(size.width/2 + trackBottomW/2, bottomY)
      ..lineTo(size.width/2 - trackBottomW/2, bottomY)
      ..close();
    canvas.drawPath(trackPath, Paint()..color = const Color(0xFF0F1230));

    // Guardrails
    final railPaint = Paint()..color = const Color(0xFFEA4C89);
    canvas.drawPath(
      Path()
        ..moveTo(size.width/2 - trackTopW/2, topY)
        ..lineTo(size.width/2 - trackBottomW/2, bottomY)
        ..lineTo(size.width/2 - trackBottomW/2 + 6, bottomY)
        ..lineTo(size.width/2 - trackTopW/2 + 3, topY)
        ..close(),
      railPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width/2 + trackTopW/2, topY)
        ..lineTo(size.width/2 + trackBottomW/2, bottomY)
        ..lineTo(size.width/2 + trackBottomW/2 - 6, bottomY)
        ..lineTo(size.width/2 + trackTopW/2 - 3, topY)
        ..close(),
      railPaint,
    );

    // Center dashes (stylized)
    final dashPaint = Paint()..color = const Color(0xFFEEEEEE);
    for (int i = 0; i < 10; i++) {
      final t = i / 10.0;
      final y = topY + (bottomY - topY) * t;
      final w = (trackTopW + (trackBottomW - trackTopW) * t) * 0.02;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(size.width/2, y), width: w, height: 10 + 24 * t),
          const Radius.circular(2),
        ),
        dashPaint,
      );
    }

    // Foreground car (cartoonish, jumping out)
    final carW = size.width * 0.6;
    final carH = size.height * 0.22;
    final carRect = Rect.fromCenter(
      center: Offset(size.width/2, size.height*0.7),
      width: carW,
      height: carH,
    );
    // Car body
    final body = RRect.fromRectAndRadius(carRect, const Radius.circular(18));
    canvas.drawRRect(body, Paint()..color = const Color(0xFF2EC4B6));
    // Hood highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(carRect.left+carW*0.06, carRect.top+carH*0.22, carW*0.88, carH*0.22),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0x8822FFFF),
    );
    // Windshield
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(carRect.left+carW*0.18, carRect.top+carH*0.08, carW*0.64, carH*0.18),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFF1B1742),
    );
    // Headlights with glow
    final hlGlow = Paint()
      ..color = const Color(0x99FFFFAA)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final hlCore = Paint()..color = const Color(0xFFFFFFCC);
    final lHl = Rect.fromLTWH(carRect.left+carW*0.12, carRect.bottom-carH*0.28, carW*0.14, carH*0.16);
    final rHl = Rect.fromLTWH(carRect.right-carW*0.26, carRect.bottom-carH*0.28, carW*0.14, carH*0.16);
    canvas.drawRRect(RRect.fromRectAndRadius(lHl.inflate(6), const Radius.circular(6)), hlGlow);
    canvas.drawRRect(RRect.fromRectAndRadius(rHl.inflate(6), const Radius.circular(6)), hlGlow);
    canvas.drawRRect(RRect.fromRectAndRadius(lHl, const Radius.circular(6)), hlCore);
    canvas.drawRRect(RRect.fromRectAndRadius(rHl, const Radius.circular(6)), hlCore);

    // Wheels (shadowed)
    final wheelPaint = Paint()..color = const Color(0xFF0A0A0A);
    final lw = Rect.fromLTWH(carRect.left+carW*0.06, carRect.bottom-carH*0.12, carW*0.18, carH*0.12);
    final rw = Rect.fromLTWH(carRect.right-carW*0.24, carRect.bottom-carH*0.12, carW*0.18, carH*0.12);
    canvas.drawRRect(RRect.fromRectAndRadius(lw, const Radius.circular(8)), wheelPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rw, const Radius.circular(8)), wheelPaint);

    // 80s frame lines
    final frame = Paint()
      ..color = const Color(0x55EA4C89)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(8, 8, size.width-16, size.height-16), frame);
  }

  @override
  bool shouldRepaint(covariant _CassetteArtPainter oldDelegate) => false;
}
