import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final points = _generateTrackPoints();
    
    // Breaking the track into individual edges prevents loop collision bugs
    for (int i = 0; i < points.length - 1; i++) {
      final shape = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape, friction: 0.8));
    }
    return body;
  }

  List<Vector2> _generateTrackPoints() {
    final List<Vector2> p = [];

    p.add(Vector2(-50, 5));
    p.add(Vector2(50, 5));
    p.add(Vector2(80, 5));
    p.add(Vector2(100, 4.2)); 

    // The Loop (Radius 15 for a nice wide BR-style loop)
    const double centerX = 130;
    const double centerY = -12;
    const double radius = 15;
    const int segments = 60;
    
    // Starts at bottom-right (0.4pi) and wraps around to bottom-left (2.6pi)
    for (int i = 0; i <= segments; i++) {
      double angle = (0.4 * pi) - (i / segments) * (1.8 * pi);
      p.add(Vector2(
        centerX + radius * cos(angle),
        centerY + radius * sin(angle),
      ));
    }

    p.add(Vector2(160, 5));
    p.add(Vector2(400, 5));

    return p;
  }

  @override
  void render(Canvas canvas) {
    final points = _generateTrackPoints();
    final paint = Paint()..color = Colors.greenAccent..strokeWidth = 0.2..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(Offset(points[i].x, points[i].y), Offset(points[i+1].x, points[i+1].y), paint);
    }
  }
}