import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final List<Vector2> points = [];

    // 1. Start Ground
    points.add(Vector2(-100, 5));
    points.add(Vector2(60, 5));

    // 2. Entry Ramp (Transitions ground into loop entry height)
    points.add(Vector2(85, 4.5));
    points.add(Vector2(100, 2.0));
    
    // 3. THE LOOP (One continuous path)
    const double centerX = 120;
    const double centerY = -12;
    const double radius = 14;
    const int segments = 50;
    
    // Sweep from bottom-right (0.75pi) around to bottom-left (-1.15pi)
    // This creates an entrance at the bottom and an exit on the other side
    for (int i = 0; i <= segments; i++) {
      double angle = (0.75 * pi) - (i / segments) * (1.9 * pi); 
      points.add(Vector2(centerX + radius * cos(angle), centerY + radius * sin(angle)));
    }

    // 4. Exit Ramp (Transitions loop back to ground height)
    points.add(Vector2(140, 2.0));
    points.add(Vector2(155, 4.5));
    points.add(Vector2(170, 5));
    points.add(Vector2(1000, 5));

    // Create the physical edge fixtures
    for (int i = 0; i < points.length - 1; i++) {
      final shape = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape, friction: 0.6));
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    // The physics path handles collisions; visual rendering can follow the same points
    final paint = Paint()..color = Colors.greenAccent..strokeWidth = 0.2..style = PaintingStyle.stroke;
  }
}