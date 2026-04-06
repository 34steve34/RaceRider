import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  // Bike Specs
  static const double wheelBase = 2.4;
  static const double wheelRadius = 0.45;
  static const double headHeight = 1.2;
  static const double tiltSpeed = 5.5; // Direct angular control
  static const double acceleration = 55.0;

  Bike({required this.initialPosition});

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      position: initialPosition,
      type: BodyType.dynamic,
      fixedRotation: false,
      angularDamping: 1.5, // Helps stop "spinning wildly"
      linearDamping: 0.1,
    );

    final body = world.createBody(bodyDef);

    // 1. Rear Wheel Fixture
    final rearShape = CircleShape()..radius = wheelRadius;
    rearShape.position.setValues(-wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(rearShape, friction: 1.0, density: 1.0));

    // 2. Front Wheel Fixture
    final frontShape = CircleShape()..radius = wheelRadius;
    frontShape.position.setValues(wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(frontShape, friction: 0.2, density: 1.0));

    // 3. The Head (Crash Point)
    final headShape = CircleShape()..radius = 0.3;
    headShape.position.setValues(0, -headHeight);
    body.createFixture(FixtureDef(headShape, density: 0.5, isSensor: false));

    return body;
  }

  void updateControl(double tiltInput, bool isGas, bool isBrake) {
    // TILT - Direct manipulation of angular velocity for "Puppet" feel
    if (tiltInput != 0) {
      body.angularVelocity = tiltInput * tiltSpeed;
    }

    // GAS
    if (isGas) {
      final forwardDir = Vector2(math.cos(body.angle), math.sin(body.angle));
      // Apply force slightly behind center to cause a small wheelie pop
      final forcePoint = body.worldValue(Vector2(-wheelBase / 2, 0.5));
      body.applyForce(forwardDir * acceleration * body.mass, point: forcePoint);
    }

    // BRAKE
    if (isBrake) {
      body.linearVelocity.scale(0.95);
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw the "Forks" (The Triangle)
    final paint = Paint()..color = const Color(0xFFFF69B4)..strokeWidth = 0.15..style = PaintingStyle.stroke;
    
    // Front Fork
    canvas.drawLine(const Offset(0, -headHeight), const Offset(wheelBase/2, 0.5), paint);
    // Rear Fork
    canvas.drawLine(const Offset(0, -headHeight), const Offset(-wheelBase/2, 0.5), paint);
    // Base
    canvas.drawLine(const Offset(-wheelBase/2, 0.5), const Offset(wheelBase/2, 0.5), paint);

    // Head
    canvas.drawCircle(const Offset(0, -headHeight), 0.3, Paint()..color = Colors.white);
    
    // Wheels
    final wheelPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.1;
    canvas.drawCircle(const Offset(wheelBase/2, 0.5), wheelRadius, wheelPaint);
    canvas.drawCircle(const Offset(-wheelBase/2, 0.5), wheelRadius, wheelPaint);
  }
}