/* ============================================================================
 * RACERIDER - v7 SCALE FOCUS TEST - PINK bike
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
  late DebugText debugText;

  double rawTilt = 0;
  double smoothedTilt = 0;

  bool isGas = false;
  bool isBrake = false;

  RaceRiderGame();

  @override
  Future<void> onLoad() async {
    track = Track();
    add(track);

    player = Bike(Vector2(-40, 3.0));
    add(player);

    debugText = DebugText();
    add(debugText);

    camera.follow(player);
    camera.viewfinder.zoom = 2.2;        // Very strong zoom
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Force zoom every frame
    camera.viewfinder.zoom = 2.2;

    double normalizedTilt = (rawTilt / 8).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.5 + normalizedTilt * 0.5;

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

class DebugText extends Component {
  @override
  void render(Canvas canvas) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: "v7 - PINK bike\nZOOM FORCED = 2.2",
        style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, const Offset(40, 40));
  }
}

// ===================================================================
// BIKE - PINK
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(7.0, 3.5);   // Large visual size
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += 45 * dt;

    double torque = tilt * 45;
    if (onGround) torque *= 3.5;

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    if (onGround) {
      double drive = gas ? 62 : (brake ? -16 : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.81;
      velocity.x = velocity.x.clamp(-70, 70);
    }

    position += velocity * dt;

    // Simple ground check
    final rearPos = position + (Vector2(-2.2, 1.0)..rotate(angle));
    final frontPos = position + (Vector2(2.2, 1.0)..rotate(angle));
    onGround = rearPos.y > 4.0 || frontPos.y > 4.0;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    // PINK chassis
    final chassisPaint = Paint()..color = const Color(0xFFFF00AA);
    canvas.drawRect(const Rect.fromLTWH(-3.5, -0.8, 7.0, 1.6), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFF00FFEE);
    canvas.drawRect(const Rect.fromLTWH(-1.1, -2.1, 2.0, 1.8), riderPaint);

    // Wheels
    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-2.2, 1.0), 0.9, wheelPaint);
    canvas.drawCircle(const Offset(2.2, 1.0), 0.9, wheelPaint);

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
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(path, paint);
  }
}