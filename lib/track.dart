import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));

    final points = _generateTrackPoints();
    
    // Use individual EdgeShapes instead of one ChainShape to prevent "ghost walls"
    // and ensure the loop entrance is wide open.
    for (int i = 0; i < points.length - 1; i++) {
      final shape = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape, friction: 0.8));
    }

    return body;
  }

  List<Vector2> _generateTrackPoints() {
    final List<Vector2> p = [];

    // 1. Starting Ground
    p.add(Vector2(-50, 5));
    p.add(Vector2(50, 5));

    // 2. Approach Ramp
    p.add(Vector2(70, 5));
    p.add(Vector2(90, 0));

    // 3. The Loop (Calculated to leave a physical gap at the bottom)
    const double centerX = 120;
    const double centerY = -10;
    const double radius = 12;
    const int segments = 40;
    
    // Start at 1.7*PI (bottom-right) and go around to 1.3*PI (bottom-left)
    for (int i = 0; i <= segments; i++) {
      double angle = (1.6 * pi) + (i / segments) * (1.8 * pi);
      p.add(Vector2(
        centerX + radius * cos(angle),
        centerY + radius * sin(angle),
      ));
    }

    // 4. Exit
    p.add(Vector2(150, 5));
    p.add(Vector2(300, 5));

    return p;
  }

  @override
  void render(Canvas canvas) {
    final points = _generateTrackPoints();
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 0.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(
        Offset(points[i].x, points[i].y),
        Offset(points[i+1].x, points[i+1].y),
        paint,
      );
    }
  }
}