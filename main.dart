import 'package:flutter/material.dart' hide Column; // Prevent name clashes
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide Vector2, World; 
import 'package:sensors_plus/sensors_plus.dart';
// FORCE everything to use the 64-bit version that Forge2D 0.17.1 wants
import 'package:vector_math/vector_math_64.dart'; 

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        body: GameWidget(
          game: ResetRacingGame(),
        ),
      ),
    ),
  );
}

class ResetRacingGame extends Forge2DGame with TapCallbacks {
  // Use Vector2 from vector_math_64
  ResetRacingGame() : super(gravity: Vector2(0, 15), zoom: 20);

  late PlayerBox player;
  double tiltX = 0;

  @override
  Future<void> onLoad() async {
    add(GroundLine());
    player = PlayerBox(Vector2(0, -5));
    add(player);

    accelerometerEvents.listen((AccelerometerEvent event) {
      tiltX = event.x; 
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    player.body.applyForce(Vector2(-tiltX * 40, 0));
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) {
      player.body.applyLinearImpulse(Vector2(5, -15));
    } else {
      player.body.linearVelocity.x *= 0.2;
    }
  }
}

class PlayerBox extends BodyComponent {
  final Vector2 startPos;
  PlayerBox(this.startPos);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBox(1.0, 1.0, Vector2.zero(), 0);
    final fixtureDef = FixtureDef(shape, friction: 0.3, restitution: 0.4);
    final bodyDef = BodyDef(type: BodyType.dynamic, position: startPos);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    // Explicitly using the Flutter color to avoid the vector_math 'Colors' conflict
    canvas.drawRect(
      Rect.fromLTWH(-1, -1, 2, 2), 
      Paint()..color = const Color(0xFF2196F3) // Blue
    );
  }
}

class GroundLine extends BodyComponent {
  @override
  Body createBody() {
    final shape = EdgeShape()..set(Vector2(-100, 5), Vector2(100, 5));
    return world.createBody(BodyDef(type: BodyType.static))
      ..createFixture(FixtureDef(shape));
  }
}