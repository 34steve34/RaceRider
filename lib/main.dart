/* ============================================================================
 * RACERIDER - v20 - BIG RED bike + FIXED POSITIONING
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

    player = Bike(Vector2(-10, 2));   // Spawn BELOW the track
    add(player);

    debug = DebugOverlay();
    add(debug);

    camera.follow(player);
    camera.viewfinder.zoom = 5.5;
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

// Background
class Background extends Component with HasGameRef<Forge2DGame> {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, gameRef.size.x, gameRef.size.y),
      Paint()..color = const Color(0xFF112233),
    );
  }
}

// Debug Text
class DebugOverlay extends Component {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: const TextSpan(
        text: "v20 - BIG RED bike\nLeft = Brake | Right = Gas\nTilt phone left/right",
        style: TextStyle(color: Colors.yellow, fontSize: 26, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 30));
  }
}

// ===================================================================
// BIG RED BIKE
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 48.0;
  final double acceleration = 60.0;
  final double brakePower = 24.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(7.5, 3.5);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    double torque = tilt * leanStrength;
    if (!onGround) angularVelocity *= 0.96;

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.82;
    }

    position += velocity * dt;

    onGround = position.y > 4.8;
    if (onGround) angularVelocity *= 0.55;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    final chassisPaint = Paint()..color = const Color(0xFFFF0000); // BIG RED
    canvas.drawRect(const Rect.fromLTWH(-3.75, -0.9, 7.5, 1.8), chassisPaint);

    final riderPaint = Paint()..color = const Color(0xFFFFFF00);
    canvas.drawRect(const Rect.fromLTWH(-1.1, -2.4, 2.3, 2.0), riderPaint);

    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-2.4, 1.05), 0.95, wheelPaint);
    canvas.drawCircle(const Offset(2.4, 1.05), 0.95, wheelPaint);

    canvas.restore();
  }
}

// ===================================================================
// TRACK - lowered
// ===================================================================
class Track extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);
    final points = [Vector2(-100, 8), Vector2(300, 8)];   // lowered to y=8
    body.createFixture(FixtureDef(EdgeShape()..set(points[0], points[1]))..friction = 0.9);
    return body;
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 14.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-100, 8), const Offset(300, 8), paint);
  }
}