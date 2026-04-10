import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
// We use 'hide' to ensure Vector2 only comes from one place
import 'package:flame_forge2d/flame_forge2d.dart' hide Vector2; 
import 'package:forge2d/forge2d.dart' hide Vector2;
import 'package:vector_math/vector_math.dart'; // This is the 32-bit one we want
import 'package:sensors_plus/sensors_plus.dart';


void main() {
  // We use the GameWidget from flame/game.dart
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
  // Zoom 20 ensures 1 physics meter = 20 pixels. No more tiny dots.
  ResetRacingGame() : super(gravity: Vector2(0, 15), zoom: 20);

  late PlayerBox player;
  double tiltX = 0;

  @override
  Future<void> onLoad() async {
    // Add ground at the bottom of the screen
    add(GroundLine());
    
    // Start player in the middle-top
    player = PlayerBox(Vector2(0, -5));
    add(player);

    // Listen for tilt
    accelerometerEvents.listen((AccelerometerEvent event) {
      tiltX = event.x; 
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Apply tilt force
    player.body.applyForce(Vector2(-tiltX * 40, 0));
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) {
      // Right Side: Gas/Jump
      player.body.applyLinearImpulse(Vector2(5, -15));
    } else {
      // Left Side: Brake
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
    // A visible 2x2 meter blue square
    canvas.drawRect(
      Rect.fromLTWH(-1, -1, 2, 2), 
      Paint()..color = Colors.blue
    );
  }
}

class GroundLine extends BodyComponent {
  @override
  Body createBody() {
    // A long line 5 meters down from center
    final shape = EdgeShape()..set(Vector2(-100, 5), Vector2(100, 5));
    return world.createBody(BodyDef(type: BodyType.static))
      ..createFixture(FixtureDef(shape));
  }
}