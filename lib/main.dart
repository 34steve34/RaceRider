/* ============================================================================
 * RACERIDER - v16 FIXED - ORANGE bike
 * ============================================================================ */

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with TapCallbacks {
  late Bike player;
  late Track track;
  late DebugOverlay debug;

  double rawTilt = 0.0;
  double smoothedTilt = 0.0;

  bool isGas = false;
  bool isBrake = false;

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 5.0);

  @override
  Future<void> onLoad() async {
    add(Background());
    track = Track();
    add(track);

    player = Bike(Vector2(-20, -8));   // Spawn higher so it's visible
    add(player);

    debug = DebugOverlay();
    add(debug);

    camera.follow(player);
    camera.viewfinder.zoom = 4.8;
  }

  @override
  void update(double dt) {
    super.update(dt);

    double normalizedTilt = (rawTilt / 8.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.4 + normalizedTilt * 0.6;

    player.updateBike(dt, smoothedTilt, isGas, isBrake);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final isLeftSide = event.localPosition.x < size.x / 2;
    if (isLeftSide) isBrake = true;
    else isGas = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }
}

// ===================================================================
// BACKGROUND (Fixed)
// ===================================================================
class Background extends Component with HasGameRef<Forge2DGame> {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, gameRef.size.x, gameRef.size.y),
      Paint()..color = const Color(0xFF112233),
    );
  }
}

// ===================================================================
// DEBUG TEXT
// ===================================================================
class DebugOverlay extends Component {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: const TextSpan(
        text: "v16 - ORANGE bike\nLeft = Brake | Right = Gas\nTilt phone left/right",
        style: TextStyle(color: Colors.yellow, fontSize: 24, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 30));
  }
}

// ===================================================================
// CUSTOM BIKE - ORANGE
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 45.0;
  final double acceleration = 58.0;
  final double brakePower = 22.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(6.5, 3.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    double torque = tilt * leanStrength;
    if (!onGround) angularVelocity *=