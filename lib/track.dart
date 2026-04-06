import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final points = _generateTrackPoints();
    
    // Breaking the track into individual EdgeShapes ensures 
    // there are no "gaps" or "ghost walls" at the joints.
    for (int i = 0; i < points.length - 1; i++) {
      final shape = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape, friction: 0.8));
    }
    return body;
  }

  List<Vector2> _generateTrackPoints() {
    final List<Vector2> p = [];

    // 1. Starting Ground
    p.add(Vector2(-100, 5));
    p.add(Vector2(80, 5));

    // 2. ENTRY RAMP: Connects Ground (y=5) to Loop Entry (y=-1.5)
    p.add(Vector2(95, 4.5));
    p.add(Vector2(110, 2.5));
    p.add(Vector2(120, -1.5)); // Transition point into loop circle

    // 3. THE LOOP: Center (135, -12), Radius 14
    const double centerX = 135;
    const double centerY = -12;
    const double radius = 14;
    const int segments = 60;
    
    // We sweep from approx 150 degrees to -150 degrees
    // This creates a circular path that matches our entry/exit ramp points
    for (int i = 0; i <= segments; i++) {
      double angle = (0.8 * pi) - (i / segments) * (2.1 * pi);
      p.add(Vector2(
        centerX + radius * cos(angle),
        centerY + radius * sin(angle),
      ));
    }

    // 4. EXIT RAMP: Connects Loop Exit (y=-1.5) back to Ground (y=5)
    p.add(Vector2(150, -1.5));
    p.add(Vector2(160, 2.5));
    p.add(Vector2(175, 4.5));
    p.add(Vector2(190, 5));

    // 5. Flat Exit
    p.add(Vector2(500, 5));

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