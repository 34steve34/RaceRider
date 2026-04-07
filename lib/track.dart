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

    // 2. ENTRY RAMP
    const double centerX = 125;
    const double centerY = -12;
    const double radius = 14;
    
    final entryX = centerX + radius * cos(0.75 * pi);
    final entryY = centerY + radius * sin(0.75 * pi);

    points.add(Vector2(entryX - 15, 4.5));
    points.add(Vector2(entryX, entryY));
    
    // 3. THE LOOP (Continuous path arc)
    const int segments = 60;
    for (int i = 0; i <= segments; i++) {
      double angle = (0.75 * pi) - (i / segments) * (1.9 * pi); 
      points.add(Vector2(centerX + radius * cos(angle), centerY + radius * sin(angle)));
    }

    // 4. EXIT RAMP
    final exitX = centerX + radius * cos((0.75 * pi) - (1.9 * pi));
    final exitY = centerY + radius * sin((0.75 * pi) - (1.9 * pi));

    points.add(Vector2(exitX, exitY));
    points.add(Vector2(exitX + 15, 5));
    points.add(Vector2(1000, 5));

    // Create the physical floor segments
    for (int i = 0; i < points.length - 1; i++) {
      final shape = f2d.EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape)..friction = 0.6);
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    // Optional: Visual line for the track
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 0.2
      ..style = PaintingStyle.stroke;
  }
}