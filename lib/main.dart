/* ============================================================================
 * RACERIDER - Custom Arcade Physics (Bike Race style)
 * Engine: Flutter + Flame (No Forge2D for bike)
 * ============================================================================ */

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends FlameGame with TapCallbacks {
  late Bike player;
  late Track track;

  double rawTilt = 0;
  double smoothedTilt = 0;

  bool isGas = false;
  bool isBrake = false;

  RaceRiderGame();

  @override
  Future<void> onLoad() async {
    track = Track();
    add(track);

    player = Bike(Vector2(0, -8));
    add(player);

    // Camera setup
    camera.follow(player);
    camera.viewfinder.zoom = 12.0;           // Adjust zoom to your liking

    accelerometerEvents.listen((event) {
      rawTilt = event.y;
    });
  }

  @override
  void update(double dt) {
    super.update(dt);

    double normalizedTilt = (rawTilt / 10).clamp(-1.0, 1.0);
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.75;

    player.updateBike(dt, smoothedTilt, isGas, isBrake);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) {
      isGas = true;
    } else {
      isBrake = true;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }
}

// ===================================================================
// CUSTOM BIKE PHYSICS
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;
  double groundAngle = 0.0;

  // ==================== TUNING ====================
  final double gravity = 38.0;
  final double airDamping = 0.965;
  final double groundFriction = 0.89;
  final double leanStrength = 19.5;
  final double groundLeanMultiplier = 2.4;
  final double airControl = 0.78;
  final double acceleration = 32.0;
  final double brakePower = 48.0;
  final double maxSpeed = 48.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(3.8, 1.8);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    // Lean control
    double torque = tilt * leanStrength;

    if (onGround) {
      torque *= groundLeanMultiplier;
      angle = angle * 0.65 + groundAngle * 0.35;
    } else {
      torque *= airControl;
      angularVelocity *= airDamping;
    }

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    // Drive
    if (onGround) {
      double driveForce = 0.0;
      if (gas) driveForce = acceleration;
      if (brake) driveForce = -brakePower;

      velocity.x += driveForce * cos(angle) * dt;
      velocity.y += driveForce * sin(angle) * dt;

      velocity.x *= groundFriction;
      velocity.y *= groundFriction * 0.6;

      velocity.x = velocity.x.clamp(-maxSpeed, maxSpeed);
    }

    position += velocity * dt;

    _checkGround();
  }

  void _checkGround() {
    // Wheel positions
    final rearOffset = Vector2(-1.6, 0.6)..rotate(angle);
    final frontOffset = Vector2(1.6, 0.6)..rotate(angle);

    final rearPos = position + rearOffset;
    final frontPos = position + frontOffset;

    const groundLevel = 5.0;
    const tolerance = 0.9;

    onGround = rearPos.y >= groundLevel - tolerance || frontPos.y >= groundLevel - tolerance;

    if (onGround) {
      angularVelocity *= 0.45;
      groundAngle = 0.0; // TODO: improve with real slope
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    // Chassis
    final chassisPaint = Paint()..color = const Color(0xFF0000FF);
    canvas.drawRect(const Rect.fromLTWH(-1.9, -0.45, 3.8, 0.9), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFFFFAA00);
    canvas.drawRect(const Rect.fromLTWH(-0.6, -1.2, 1.2, 1.0), riderPaint);

    // Wheels
    final wheelPaint = Paint()..color = Colors.white;
    final wheelOutline = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;

    canvas.drawCircle(const Offset(-1.45, 0.55), 0.55, wheelPaint);
    canvas.drawCircle(const Offset(1.45, 0.55), 0.55, wheelPaint);
    canvas.drawCircle(const Offset(-1.45, 0.55), 0.55, wheelOutline);
    canvas.drawCircle(const Offset(1.45, 0.55), 0.55, wheelOutline);

    canvas.restore();
  }
}

// ===================================================================
// TRACK
// ===================================================================
class Track extends Component {
  final List<Vector2> points = [
    Vector2(-80, 5),
    Vector2(20, 5),
    Vector2(35, -1),
    Vector2(52, 5),
    Vector2(70, -4),
    Vector2(88, -4),
    Vector2(105, 5),
    Vector2(300, 5),
  ];

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(path, paint);
  }
}