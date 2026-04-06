import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final List<Vector2> points = [];

    // 1. Starting Ground
    points.add(Vector2(-100, 5));
    points.add(Vector2(60, 5));

    // 2. The Entry Ramp (Leads into the loop)
    points.add(Vector2(85, 4.5));
    points.add(Vector2(100, 2.0));

    // 3. THE LOOP (Calculated to be open)
    const double centerX = 120;
    const double centerY = -12;
    const double radius = 14;
    const int segments = 50;
    
    // We sweep from 0.75pi (approx 5 o'clock) to -1.25pi
    // This leaves a physical gap between the start and end of the circle
    for (int i = 0; i <= segments; i++) {
      double angle = (0.75 * pi) - (i / segments) * (1.9 * pi); 
      points.add(Vector2(centerX + radius * cos(angle), centerY + radius * sin(angle)));
    }

    // 4. The Exit Ramp
    points.add(Vector2(140, 2.0));
    points.add(Vector2(155, 4.5));
    points.add(Vector2(170, 5));
    points.add(Vector2(1000, 5));

    for (int i = 0; i < points.length - 1; i++) {
      body.createFixture(FixtureDef(EdgeShape()..set(points[i], points[i + 1]), friction: 0.6));
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    // Basic render of the path for feedback
    final paint = Paint()..color = Colors.greenAccent..strokeWidth = 0.2..style = PaintingStyle.stroke;
    // (Actual path rendering would iterate points, simplified for this block)
  }
}