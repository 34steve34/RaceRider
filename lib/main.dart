/* ============================================================================
 * RACERIDER - Custom Physics v3 (GREEN bike = new version)
 * ============================================================================ */

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
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

    player = Bike(Vector2(-35, 2.5));   // Spawn earlier on flat
    add(player);

    camera.follow(player);
    camera.viewfinder.zoom = 5.8;       // Bigger view

    // Faster sensor response
    accelerometerEvents.listen((event) {
      rawTilt = -event.x;   // Changed axis + sign for Samsung phones
    });
  }

  @override
  void update(double dt) {
    super.update(dt);

    double normalizedTilt = (rawTilt / 8).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.6 + normalizedTilt * 0.4; // Much faster response

    player.updateBike(dt, smoothedTilt, isGas, isBrake);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) isGas = true;
    else isBrake = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }
}

// ===================================================================
// BIKE v3 - GREEN for easy identification
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;
  double groundAngle = 0.0;

  // ==================== TUNING v3 ====================
  final double gravity = 42.0;
  final double airDamping = 0.958;
  final double groundFriction = 0.86;
  final double leanStrength = 34.0;           // Stronger lean
  final double groundLeanMultiplier = 3.1;
  final double airControl = 0.85;
  final double acceleration = 48.0;           // Stronger forward
  final double brakePower = 18.0;             // Weaker brake
  final double maxSpeed = 58.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(4.5, 2.4);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    double torque = tilt * leanStrength;

    if (onGround) {
      torque *= groundLeanMultiplier;
      angle = angle * 0.55 + groundAngle * 0.45;
    } else {
      torque *= airControl;
      angularVelocity *= airDamping;
    }

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    if (onGround) {
      double drive = 0.0;
      if (gas) drive = acceleration;
      if (brake) drive = -brakePower;

      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;

      velocity.x *= groundFriction;
      velocity.y *= groundFriction * 0.5;

      velocity.x = velocity.x.clamp(-maxSpeed, maxSpeed);
    }

    position += velocity * dt;
    _checkGround();
  }

  void _checkGround() {
    final rearOffset = Vector2(-1.8, 0.75)..rotate(angle);
    final frontOffset = Vector2(1.8, 0.75)..rotate(angle);

    final rearPos = position + rearOffset;
    final frontPos = position + frontOffset;

    const groundLevel = 5.0;
    const tolerance = 1.2;

    onGround = rearPos.y >= groundLevel - tolerance || frontPos.y >= groundLevel - tolerance;

    if (onGround) {
      angularVelocity *= 0.48;
      groundAngle = 0.0;
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    // Chassis - GREEN (new version indicator)
    final chassisPaint = Paint()..color = const Color(0xFF00CC00);
    canvas.drawRect(const Rect.fromLTWH(-2.25, -0.55, 4.5, 1.1), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFFFFDD00);
    canvas.drawRect(const Rect.fromLTWH(-0.75, -1.5, 1.5, 1.3), riderPaint);

    // Wheels
    final wheelPaint = Paint()..color = Colors.white;
    final outline = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 0.16;

    canvas.drawCircle(const Offset(-1.65, 0.7), 0.65, wheelPaint);
    canvas.drawCircle(const Offset(1.65, 0.7), 0.65, wheelPaint);
    canvas.drawCircle(const Offset(-1.65, 0.7), 0.65, outline);
    canvas.drawCircle(const Offset(1.65, 0.7), 0.65, outline);

    canvas.restore();
  }
}

// ===================================================================
// TRACK
// ===================================================================
class Track extends Component {
  final List<Vector2> points = [
    Vector2(-80, 5), Vector2(20, 5),
    Vector2(35, -1), Vector2(52, 5),
    Vector2(70, -4), Vector2(88, -4),
    Vector2(105, 5), Vector2(300, 5),
  ];

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(path, paint);
  }
}