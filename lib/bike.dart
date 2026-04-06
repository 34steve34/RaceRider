import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  // Custom BR tuning
  static const double wheelBase = 2.8;
  static const double wheelRadius = 0.5;
  static const double headHeight = 1.3;
  static const double tiltSpeed = 6.0; 
  static const double acceleration = 65.0; 

  Bike({required this.initialPosition});

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      position: initialPosition,
      type: BodyType.dynamic,
      angularDamping: 2.0, // Prevents spinning like a top
      linearDamping: 0.1,
    );

    final body = world.createBody(bodyDef);

    // 1. REAR WHEEL - High friction for the motor
    final rearShape = CircleShape()..radius = wheelRadius;
    rearShape.position.setValues(-wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(rearShape, friction: 1.0, density: 1.0, restitution: 0.1));

    // 2. FRONT WHEEL - Lower friction to prevent 'grabbing' on steep loops
    final frontShape = CircleShape()..radius = wheelRadius;
    frontShape.position.setValues(wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(frontShape, friction: 0.2, density: 1.0, restitution: 0.1));

    // 3. THE HEAD - The crash point. Any track contact here is 'Death'.
    final headShape = CircleShape()..radius = 0.35;
    headShape.position.setValues(0, -headHeight);
    body.createFixture(FixtureDef(headShape, density: 0.5, restitution: 0.1));

    return body;
  }

  void updateControl(double tiltInput, bool isGas, bool isBrake) {
    // TILT - Setting angular velocity directly creates the 'puppet' feel
    if (tiltInput != 0) {
      body.angularVelocity = tiltInput * tiltSpeed;
    }

    // GAS - Apply force at the rear wheel position for that subtle wheelie 'pop'
    if (isGas) {
      final forwardDir = Vector2(math.cos(body.angle), math.sin(body.angle));
      final forcePoint = body.worldPoint(Vector2(-wheelBase / 2, 0.5));
      body.applyForce(forwardDir * acceleration * body.mass, point: forcePoint);
    }

    if (isBrake) {
      body.linearVelocity.scale(0.96);
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFFF69B4)..strokeWidth = 0.15..style = PaintingStyle.stroke;
    
    // The visual frame (The track passes right through these lines)
    canvas.drawLine(const Offset(0, -headHeight), const Offset(wheelBase/2, 0.5), paint);
    canvas.drawLine(const Offset(0, -headHeight), const Offset(-wheelBase/2, 0.5), paint);
    canvas.drawLine(const Offset(-wheelBase/2, 0.5), const Offset(wheelBase/2, 0.5), paint);
    
    // Head marker
    canvas.drawCircle(const Offset(0, -headHeight), 0.35, Paint()..color = Colors.white);
    
    // Wheel markers
    final wheelPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.1;
    canvas.drawCircle(const Offset(wheelBase/2, 0.5), wheelRadius, wheelPaint);
    canvas.drawCircle(const Offset(-wheelBase/2, 0.5), wheelRadius, wheelPaint);
  }
}