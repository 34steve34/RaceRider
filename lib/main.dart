/* ============================================================================
 * RACERIDER - v9 HYBRID (Custom Bike Physics + Forge2D Track)
 * Purple bike + big text = new version
 * ============================================================================ */

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));   // Fixed const error
}

class RaceRiderGame extends Forge2DGame with TapCallbacks {
  late Bike player;
  late Track track;

  double rawTilt = 0.0;
  double smoothedTilt = 0.0;

  bool isGas = false;
  bool isBrake = false;

  RaceRiderGame() : super(gravity: Vector2(0, 0)); // We handle gravity ourselves

  @override
  Future<void> onLoad() async {
    track = Track();
    add(track);

    player = Bike(Vector2(-35, 2));
    add(player);

    camera.follow(player);
    camera.viewfinder.zoom = 5.5;        // Good starting zoom

    accelerometerEvents.listen((event) {
      rawTilt = -event.x;
    });
  }

  @override
  void update(double dt) {
    super.update(dt);

    double normalizedTilt = (rawTilt / 8.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.45 + normalizedTilt * 0.55; // fast response

    player.updateBike(dt, smoothedTilt, isGas, isBrake);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final isLeftSide = event.localPosition.x < size.x / 2;
    if (isLeftSide) {
      isGas = true;      // Left = Gas + Lean Left
    } else {
      isBrake = true;    // Right = Brake + Lean Right
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }
}

// ===================================================================
// CUSTOM BIKE PHYSICS (Hybrid)
// ===================================================================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;
  double groundAngle = 0.0;

  // TUNING
  final double gravity = 42.0;
  final double leanStrength = 38.0;
  final double groundLeanMultiplier = 3.2;
  final double airControl = 0.84;
  final double acceleration = 52.0;
  final double brakePower = 18.0;
  final double maxSpeed = 60.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(5.2, 2.6);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    // Lean control
    double torque = tilt * leanStrength;
    if (onGround) {
      torque *= groundLeanMultiplier;
    } else {
      torque *= airControl;
      angularVelocity *= 0.96;
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

      velocity.x *= 0.84;
      velocity.x = velocity.x.clamp(-maxSpeed, maxSpeed);
    }

    position += velocity * dt;
    _checkGround();
  }

  void _checkGround() {
    final rearPos = position + (Vector2(-1.9, 0.8)..rotate(angle));
    final frontPos = position + (Vector2(1.9, 0.8)..rotate(angle));

    onGround = rearPos.y > 4.5 || frontPos.y > 4.5;

    if (onGround) {
      angularVelocity *= 0.5;
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    // PURPLE chassis (v9 indicator)
    final chassisPaint = Paint()..color = const Color(0xFFAA00FF);
    canvas.drawRect(const Rect.fromLTWH(-2.6, -0.65, 5.2, 1.3), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFFFFEE00);
    canvas.drawRect(const Rect.fromLTWH(-0.8, -1.7, 1.6, 1.5), riderPaint);

    // Wheels
    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-1.85, 0.75), 0.72, wheelPaint);
    canvas.drawCircle(const Offset(1.85, 0.75), 0.72, wheelPaint);

    canvas.restore();
  }
}

// ===================================================================
// FORGE2D TRACK (for accurate ground)
// ===================================================================
class Track extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);

    final points = [
      Vector2(-100, 5), Vector2(-20, 5),
      Vector2(-15, 3.5), Vector2(-10, 2.0), Vector2(-5, 3.5), Vector2(0, 5),
      Vector2(20, 5), Vector2(40, 5),
      Vector2(45, 4.0), Vector2(50, 1.5), Vector2(55, 4.0), Vector2(60, 5),
      Vector2(80, 5), Vector2(200, 5),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      body.createFixture(FixtureDef(EdgeShape()..set(points[i], points[i + 1]))
        ..friction = 0.9);
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    // You can improve this visual later
    final paint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    
    // Simple line for now
  }
}