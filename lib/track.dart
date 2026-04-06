import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final points = _generateTrackPoints();
    
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
    p.add(Vector2(90, 5));

    // 2. Entry Ramp (Lifts the bike into the loop)
    p.add(Vector2(105, 4.0));
    p.add(Vector2(115, 2.0));

    // 3. The Loop (Radius 14)
    const double centerX = 135;
    const double centerY = -11;
    const double radius = 14;
    const int segments = 60;
    
    // Entry point calculated at 0.75 PI (~135 degrees)
    // End point calculated at 0.25 PI (~45 degrees)
    for (int i = 0; i <= segments; i++) {
      // Sweep from 0.75pi around the circle to -1.25pi
      double angle = (0.75 * pi) - (i / segments) * (2.0 * pi);
      p.add(Vector2(
        centerX + radius * cos(angle),
        centerY + radius * sin(angle),
      ));
    }

    // 4. Exit Ramp (Connects loop back to ground)
    p.add(Vector2(155, 2.0));
    p.add(Vector2(165, 4.0));
    p.add(Vector2(180, 5));
    p.add(Vector2(400, 5));

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
      canvas.drawLine(Offset(points[i].x, points[i].y), Offset(points[i+1].x, points[i+1].y), paint);
    }
  }
}