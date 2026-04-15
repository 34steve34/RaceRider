/* ============================================================================
 * RACERIDER - v11 FIXED - MAGENTA bike
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

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 6.0, backgroundColor: const Color(0xFF112233));

  @override
  Future<void> onLoad() async {
    track = Track();
    add(track);

    player = Bike(Vector2(-25, 0));
    add(player);

    debug = DebugOverlay();
    add(debug);

    camera.follow(player);
    camera.viewfinder.zoom = 5.0;
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
    if (isLeftSide) {
      isBrake = true;     // Left side = Brake
    } else {
      isGas = true;       // Right side = Gas
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
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
        text: "v11 - MAGENTA bike\nLeft = Brake | Right = Gas",
        style: TextStyle(color: Colors.yellow, fontSize: 26, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 30));
  }
}

// ===================================================================
// CUSTOM BIKE - MAGENTA
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 42.0;
  final double acceleration = 55.0;
  final double brakePower = 20.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(5.5, 2.8);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    double torque = tilt * leanStrength;
    if (!onGround) angularVelocity *= 0.96;

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    if (onGround) {
      double drive = 0.0;
      if (gas) drive = acceleration;
      if (brake) drive = -brakePower;

      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.83;
    }

    position += velocity * dt;

    onGround = position.y > 4.0;
    if (onGround) angularVelocity *= 0.6;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    // MAGENTA chassis = v11 indicator
    final chassisPaint = Paint()..color = const Color(0xFFFF00AA);
    canvas.drawRect(const Rect.fromLTWH(-2.75, -0.7, 5.5, 1.4), chassisPaint);

    final riderPaint = Paint()..color = const Color(0xFF00FFFF);
    canvas.drawRect(const Rect.fromLTWH(-0.9, -1.8, 1.8, 1.6), riderPaint);

    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-1.9, 0.85), 0.78, wheelPaint);
    canvas.drawCircle(const Offset(1.9, 0.85), 0.78, wheelPaint);

    canvas.restore();
  }
}

// ===================================================================
// TRACK - Very visible
// ===================================================================
class Track extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);

    final points = [
      Vector2(-100, 5), Vector2(-30, 5),
      Vector2(-25, 3), Vector2(-15, 5), Vector2(0, 5),
      Vector2(20, 5), Vector2(40, 3), Vector2(55, 5),
      Vector2(80, 5), Vector2(120, 2), Vector2(160, 5), Vector2(300, 5),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      body.createFixture(FixtureDef(EdgeShape()..set(points[i], points[i+1]))
        ..friction = 0.9);
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(-100, 5);
    path.lineTo(300, 5);
    canvas.drawPath(path, paint);
  }
}