import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

class TrackComponent extends BodyComponent {
  // Our "Design Table" of points
  final List<Vector2> trackPoints = [
    Vector2(-20, 0),
    Vector2(0, 0),
    Vector2(10, -5),   // A small hill
    Vector2(20, 0),    // Valley
    Vector2(30, -15),  // A steep ramp
    Vector2(60, 0),    // Landing area
  ];

  @override
  Body createBody() {
    // 1. Create the Shape (The physics boundary)
    final shape = ChainShape()..createChain(trackPoints);

    // 2. Define the Body (Static means it doesn't fall due to gravity)
    final bodyDef = BodyDef(
      userData: this,
      position: Vector2.zero(),
      type: BodyType.static,
    );

    // 3. Attach the Shape to the Body with Friction
    final fixtureDef = FixtureDef(
      shape,
      friction: 0.6, // Needs some grip for the back wheel!
    );

    final body = world.createBody(bodyDef);
    body.createFixture(fixtureDef);
    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 4. Draw the visible line so we can see the physics track
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final path = Path();
    path.moveTo(trackPoints[0].x, trackPoints[0].y);
    for (int i = 1; i < trackPoints.length; i++) {
      path.lineTo(trackPoints[i].x, trackPoints[i].y);
    }

    canvas.drawPath(path, paint);
  }
}
