/* ============================================================================
 * RACERIDER - Improved Custom Physics v2 (Closer to Bike Race)
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

    player = Bike(Vector2(-20, 2));   // Spawn on the track
    add(player);

    // Camera setup for good visibility
    camera.follow(player);
    camera.viewfinder.zoom = 6.5;        // Much larger view

    accelerometerEvents.listen((event) {
      rawTilt = event.y;   // S25 Ultra - we may need to flip sign later
    });
  }

  @override
  void update(double dt) {
    super.update(dt);

    double normalizedTilt = (rawTilt / 9).clamp(-1.0, 1.0);
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.85; // faster smoothing

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
// BIKE v2
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;
  double groundAngle = 0.0;

  // ==================== TUNING ====================
  final double gravity = 42.0;
  final double airDamping = 0.96;
  final double groundFriction = 0.88;
  final double leanStrength = 28.0;           // Increased a lot
  final double groundLeanMultiplier = 2.8;
  final double airControl = 0.82;
  final double acceleration = 38.0;
  final double brakePower = 22.0;             // Much weaker brakes
  final double maxSpeed = 55.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(4.2, 2.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    // Lean (core of the feel)
    double torque = tilt * leanStrength;

    if (onGround) {
      torque *= groundLeanMultiplier;
      angle = angle * 0.6 + groundAngle * 0.4;
    } else {
      torque *= airControl;
      angularVelocity *= airDamping;
    }

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    // Drive
    if (onGround) {
      double drive = 0.0;
      if (gas) drive = acceleration;
      if (brake) drive = -brakePower;

      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;

      velocity.x *= groundFriction;
      velocity.y *= groundFriction * 0.55;

      velocity.x = velocity.x.clamp(-maxSpeed, maxSpeed);
    }

    position += velocity * dt;
    _checkGround();
  }

  void _checkGround() {
    final rearOffset = Vector2(-1.7, 0.7)..rotate(angle);
    final frontOffset = Vector2(1.7, 0.7)..rotate(angle);

    final rearPos = position + rearOffset;
    final frontPos = position + frontOffset;

    const groundLevel = 5.0;
    const tolerance = 1.1;

    onGround = rearPos.y >= groundLevel - tolerance || frontPos.y >= groundLevel - tolerance;

    if (onGround) {
      angularVelocity *= 0.5;
      groundAngle = 0.0;
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    // Chassis
    final chassisPaint = Paint()..color = const Color(0xFF0000FF);
    canvas.drawRect(const Rect.fromLTWH(-2.1, -0.5, 4.2, 1.0), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFFFF8800);
    canvas.drawRect(const Rect.fromLTWH(-0.7, -1.4, 1.4, 1.2), riderPaint);

    // Wheels
    final wheelPaint = Paint()..color = Colors.white;
    final outline = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 0.15;

    canvas.drawCircle(const Offset(-1.55, 0.65), 0.62, wheelPaint);
    canvas.drawCircle(const Offset(1.55, 0.65), 0.62, wheelPaint);
    canvas.drawCircle(const Offset(-1.55, 0.65), 0.62, outline);
    canvas.drawCircle(const Offset(1.55, 0.65), 0.62, outline);

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
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(path, paint);
  }
}