import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:forge2d/forge2d.dart' as f2d;
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);
    final List<Vector2> points = [];

    // 1. Starting Ground
    points.add(Vector2(-100, 5));
    points.add(Vector2(60, 5));

    // 2. Entry Ramp (Physically connecting the ground to the loop)
    points.add(Vector2(85, 4.5));
    points.add(Vector2(100, 2.0));
    
    // 3. THE LOOP (Continuous path arc)
    const double centerX = 125;
    const double centerY = -12;
    const double radius = 14;
    const int segments = 50;
    
    for (int i = 0; i <= segments; i++) {
      // Sweep from bottom-right around to bottom-left
      double angle = (0.75 * pi) - (i / segments) * (1.9 * pi); 
      points.add(Vector2(centerX + radius * cos(angle), centerY + radius * sin(angle)));
    }

    // 4. Exit Ramp
    points.add(Vector2(145, 2.0));
    points.add(Vector2(160, 4.5));
    points.add(Vector2(180, 5));
    points.add(Vector2(1000, 5));

    for (int i = 0; i < points.length - 1; i++) {
      final shape = f2d.EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape)..friction = 0.6);
    }
    return body;
  }
}