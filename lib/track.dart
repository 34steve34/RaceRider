import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final points = _generateTrackPoints();
    
    // We use individual EdgeShapes to ensure loop transitions are smooth
    for (int i = 0; i < points.length - 1; i++) {
      final shape = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape, friction: 0.8));
    }
    return body;
  }

  List<Vector2> _generateTrackPoints() {
    final List<Vector2> p = [];

    // 1. Flat Start
    p.add(Vector2(-50, 5));
    p.add(Vector2(50, 5));

    // 2. Approach
    p.add(Vector2(80, 5));
    p.add(Vector2(100, 4.5)); 

    // 3. The Loop (Radius 14, Opening at the bottom)
    const double centerX = 125;
    const double centerY = -10;
    const double radius = 14;
    const int segments = 50;
    
    // We rotate from 0.4pi to 2.6pi to create a clear entrance gap
    for (int i = 0; i <= segments; i++) {
      double angle = (0.4 * pi) - (i / segments) * (1.8 * pi);
      p.add(Vector2(
        centerX + radius * cos(angle),
        centerY + radius * sin(angle),
      ));
    }

    // 4. Flat Exit
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
        paint
      );
    }
  }
}