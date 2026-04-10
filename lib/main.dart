import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: ResetRacingGame()));
}

class ResetRacingGame extends Forge2DGame with TapCallbacks {
  // 1. Set a fixed zoom so we don't see "tiny dots"
  ResetRacingGame() : super(gravity: Vector2(0, 15), zoom: 20);

  late PlayerBox player;
  double tiltX = 0;

  @override
  Future<void> onLoad() async {
    // 2. Add the Ground
    add(GroundLine());
    
    // 3. Add the Player
    player = PlayerBox(Vector2(0, -5));
    add(player);

    // 4. Listen to Accelerometer
    accelerometerEvents.listen((AccelerometerEvent event) {
      tiltX = event.x; // Sensitivity logic
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Apply tilt force to the player
    player.body.applyForce(Vector2(-tiltX * 50, 0));
  }

  @override
  void onTapDown(TapDownEvent event) {
    final screenWidth = size.x;
    if (event.localPosition.x > screenWidth / 2) {
      // Right side: Gas (Jump/Boost for now to test)
      player.body.applyLinearImpulse(Vector2(5, -10));
    } else {
      // Left side: Brake
      player.body.linearVelocity.x *= 0.5;
    }
  }
}

class PlayerBox extends BodyComponent {
  final Vector2 startPosition;
  PlayerBox(this.startPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBox(1.0, 1.0, Vector2.zero(), 0);
    final fixtureDef = FixtureDef(shape, friction: 0.3, restitution: 0.5); // Restitution = Bounce
    final bodyDef = BodyDef(type: BodyType.dynamic, position: startPosition);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    // Draw a simple blue square so we can actually SEE it
    canvas.drawRect(const Rect.fromLTWH(-1, -1, 2, 2), Paint()..color = Colors.blue);
  }
}

class GroundLine extends BodyComponent {
  @override
  Body createBody() {
    final shape = EdgeShape()..set(Vector2(-100, 5), Vector2(100, 5));
    final bodyDef = BodyDef(type: BodyType.static);
    return world.createBody(bodyDef)..createFixture(FixtureDef(shape));
  }
}