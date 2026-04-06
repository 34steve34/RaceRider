import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final List<Vector2> points = [];

    // 1. Start Flat
    points.add(Vector2(-100, 5));
    points.add(Vector2(60, 5));

    // 2. ENTRY RAMP (Leads physically into the loop radius)
    points.add(Vector2(85, 4.5));
    points.add(Vector2(100, 2.0));
    
    // 3. THE LOOP (Continuous path)
    const double centerX = 120;
    const double centerY = -12;
    const double radius = 14;
    const int segments = 50;
    
    // Sweep from 0.75pi to -1.15pi leaves a 0.1pi gap at the bottom
    for (int i = 0; i <= segments; i++) {
      double angle = (0.75 * pi) - (i / segments) * (1.9 * pi); 
      points.add(Vector2(centerX + radius * cos(angle), centerY + radius * sin(angle)));
    }

    // 4. EXIT RAMP (Leads physically out of the loop)
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
    // Redraw the path logic for visual confirmation
    final paint = Paint()..color = Colors.greenAccent..strokeWidth = 0.2..style = PaintingStyle.stroke;
    // (Actual rendering would iterate points as before)
  }
}