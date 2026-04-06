import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  static const double wheelBase = 2.8;
  static const double wheelRadius = 0.5;
  static const double headHeight = 1.3;
  static const double tiltSpeed = 6.2; // Fast for quick recovery
  static const double acceleration = 65.0; 

  Bike({required this.initialPosition});

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      position: initialPosition,
      type: BodyType.dynamic,
      angularDamping: 2.2, // Prevents over-rotation
    );

    final body = world.createBody(bodyDef);

    // Wheels - Using restitution 0 to prevent 'bouncing' off track
    final wheelShape = CircleShape()..radius = wheelRadius;
    
    // Rear Wheel
    wheelShape.position.setValues(-wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(wheelShape, friction: 1.0, density: 1.0));

    // Front Wheel
    wheelShape.position.setValues(wheelBase / 2, 0.5);
    body.createFixture(FixtureDef(wheelShape, friction: 0.1, density: 1.0));

    // The Head - The Crash Zone
    final headShape = CircleShape()..radius = 0.4;
    headShape.position.setValues(0, -headHeight);
    body.createFixture(FixtureDef(headShape, density: 0.5, friction: 0.3));

    return body;
  }

  void updateControl(double tiltInput, bool isGas, bool isBrake) {
    if (tiltInput != 0) {
      body.angularVelocity = tiltInput * tiltSpeed;
    }

    if (isGas) {
      final forwardDir = Vector2(math.cos(body.angle), math.sin(body.angle));
      // Applying force at the rear wheel position
      final forcePoint = body.worldPoint(Vector2(-wheelBase / 2, 0.5));
      body.applyForce(forwardDir * acceleration * body.mass, point: forcePoint);
    }

    if (isBrake) {
      body.linearVelocity.scale(0.96);
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFFFF69B4)
      ..strokeWidth = 0.15
      ..style = PaintingStyle.stroke;
    
    // Chassis Lines
    canvas.drawLine(const Offset(0, -headHeight), const Offset(wheelBase/2, 0.5), paint);
    canvas.drawLine(const Offset(0, -headHeight), const Offset(-wheelBase/2, 0.5), paint);
    canvas.drawLine(const Offset(-wheelBase/2, 0.5), const Offset(wheelBase/2, 0.5), paint);
    
    // Draw the Head
    canvas.drawCircle(const Offset(0, -headHeight), 0.4, Paint()..color = Colors.white);
    
    // Draw Wheels
    final wheelPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.1;
    canvas.drawCircle(const Offset(wheelBase/2, 0.5), wheelRadius, wheelPaint);
    canvas.drawCircle(const Offset(-wheelBase/2, 0.5), wheelRadius, wheelPaint);
  }
}