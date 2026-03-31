import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

class BikeChassis extends BodyComponent {
  final Vector2 initialPosition;
  
  BikeChassis({required this.initialPosition});

  @override
  Body createBody() {
    // 1. Define the Shape (A simple rectangle: 4 meters wide, 2 meters tall)
    final shape = PolygonShape()..setAsBoxXY(2.0, 1.0);

    // 2. Define the Body (Dynamic means it falls and reacts to hits)
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
    );

    // 3. Define the Physics Properties
    final fixtureDef = FixtureDef(
      shape,
      density: 1.0,      // How heavy it is
      friction: 0.3,     // How much it slides vs grips
      restitution: 0.4,  // BOUNCINESS! (0 = lead weight, 1 = superball)
    );

    final body = world.createBody(bodyDef);
    body.createFixture(fixtureDef);
    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Draw a blue box to match our physics shape
    final paint = Paint()..color = Colors.blueAccent;
    // Forge2D draws from the center, so a 4x2 box goes from -2 to +2 on X, and -1 to +1 on Y
    canvas.drawRect(const Rect.fromLTRB(-2, -1, 2, 1), paint);
  }
}
