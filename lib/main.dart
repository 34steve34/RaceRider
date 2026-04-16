/* ============================================================================
 * RACERIDER - v21 - TRACK POSITION FIX (no bike color change)
 * Goal: Green line in the middle of the screen, bike clearly visible above it
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

    player = Bike(Vector2(0, 6));        // clearly above the track
    add(player);

    debug = DebugOverlay();
    add(debug);

    camera.follow(player);

    // FORCE the camera to look at a good area
    camera.viewfinder.zoom = 5.5;
    camera.viewfinder.position = Vector2(0, 10);   // look at the play area
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
    canvas.drawRect(Rect.fromLTWH(0, 0, gameRef.size.x, gameRef.size.y), 
      Paint()..color = const Color(0xFF112233));
  }
}

// Debug Text
class DebugOverlay extends Component {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: const TextSpan(
        text: "v21 - TRACK FIX\nGreen line should now be in the middle\nLeft=Brake | Right=Gas",
        style: TextStyle(color: Colors.yellow, fontSize: 24, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 30));
  }
}

// Bike (unchanged color)
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

    onGround = position.y > 10.5;
    if (onGround) angularVelocity *= 0.55;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    final chassisPaint = Paint()..color = const Color(0xFFFF8800);
    canvas.drawRect(const Rect.fromLTWH(-3.25, -0.8, 6.5, 1.6), chassisPaint);

    final riderPaint = Paint()..color = const Color(0xFF00FFFF);
    canvas.drawRect(const Rect.fromLTWH(-1.0, -2.1, 2.0, 1.8), riderPaint);

    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-2.1, 0.95), 0.85, wheelPaint);
    canvas.drawCircle(const Offset(2.1, 0.95), 0.85, wheelPaint);

    canvas.restore();
  }
}

// Track - moved way down
class Track extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);
    final points = [Vector2(-100, 12), Vector2(300, 12)];   // lowered significantly
    body.createFixture(FixtureDef(EdgeShape()..set(points[0], points[1]))..friction = 0.9);
    return body;
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 16.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-100, 12), const Offset(300, 12), paint);
  }
}