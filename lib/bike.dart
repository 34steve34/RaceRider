import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  static const double wheelBase = 2.4;
  static const double wheelRadius = 0.45;
  static const double headHeight = 1.2;
  static const double tiltSpeed = 5.5; 
  static const double acceleration = 65.0; 

  Bike({required this.initialPosition});

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      position: initialPosition,
      type: BodyType.dynamic,
      fixedRotation: false,
      angularDamping: 1.8, 
      linearDamping: 0.1,
    );

    final body = world.createBody(bodyDef);

    // 1. Rear Wheel Fixture
    final rearShape = CircleShape()..radius = wheelRadius;
    rearShape.position.setValues(-wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(rearShape, friction: 1.0, density: 1.0));

    // 2. Front Wheel Fixture (Lower friction for smoother loops)
    final frontShape = CircleShape()..radius = wheelRadius;
    frontShape.position.setValues(wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(frontShape, friction: 0.2, density: 1.0));

    // 3. The Head (The crash sensor/point)
    final headShape = CircleShape()..radius = 0.3;
    headShape.position.setValues(0, -headHeight);
    body.createFixture(FixtureDef(headShape, density: 0.5));

    return body;
  }

  void updateControl(double tiltInput, bool isGas, bool isBrake) {
    // TILT: Direct angular velocity for that "Classic" feel
    if (tiltInput != 0) {
      body.angularVelocity = tiltInput * tiltSpeed;
    }

    // GAS: Apply force at the rear wheel to allow for small wheelies
    if (isGas) {
      final forwardDir = Vector2(math.cos(body.angle), math.sin(body.angle));
      final forcePoint = body.getWorldPoint(Vector2(-wheelBase / 2, 0.5));
      body.applyForce(forwardDir * acceleration * body.mass, point: forcePoint);
    }

    // BRAKE: Simple linear drag
    if (isBrake) {
      body.linearVelocity.scale(0.95);
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFFFF69B4)
      ..strokeWidth = 0.15
      ..style = PaintingStyle.stroke;
    
    // Draw the chassis lines (Visual only - no hitboxes here)
    canvas.drawLine(const Offset(0, -headHeight), const Offset(wheelBase/2, 0.5), paint);
    canvas.drawLine(const Offset(0, -headHeight), const Offset(-wheelBase/2, 0.5), paint);
    canvas.drawLine(const Offset(-wheelBase/2, 0.5), const Offset(wheelBase/2, 0.5), paint);
    
    // Render the Head
    canvas.drawCircle(const Offset(0, -headHeight), 0.3, Paint()..color = Colors.white);
    
    // Render the Wheels
    final wheelPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.1;
    canvas.drawCircle(const Offset(wheelBase/2, 0.5), wheelRadius, wheelPaint);
    canvas.drawCircle(const Offset(-wheelBase/2, 0.5), wheelRadius, wheelPaint);
  }
}