import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

class TrackComponent extends BodyComponent {

  @override
  Body createBody() {
    final points = [
      Vector2(-20, 0.0),
      Vector2(200, 0.0),
    ];
    final shape      = ChainShape()..createChain(points);
    final bodyDef    = BodyDef(
      userData: this,
      position: Vector2.zero(),
      type:     BodyType.static,
    );
    final fixtureDef = FixtureDef(shape, friction: 0.6);
    final body       = world.createBody(bodyDef);
    body.createFixture(fixtureDef);
    return body;
  } // END createBody

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()
      ..color       = Colors.greenAccent
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.3;
    canvas.drawLine(
      const Offset(-20, 0),
      const Offset(200, 0),
      paint,
    );
  } // END render

} // END TrackComponent