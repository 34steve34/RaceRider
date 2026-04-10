import 'package:flutter/material.dart' hide Column; 
import 'package:flame/game.dart';
import 'package:flame/events.dart';
// Hide everything related to vectors from these so they don't clash
import 'package:flame_forge2d/flame_forge2d.dart' hide Vector2, World; 
import 'package:sensors_plus/sensors_plus.dart';
// This is the ONLY place Vector2 will come from
import 'package:vector_math/vector_math.dart'; 

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Container(
          color: const Color(0xFF111111),
          child: GameWidget(
            game: ResetRacingGame(),
          ),
        ),
      ),
    ),
  );
}

class ResetRacingGame extends Forge2DGame with TapCallbacks {
  ResetRacingGame() : super(gravity: Vector2(0, 15), zoom: 20);

  late PlayerBox player;
  double tiltX = 0;

  @override
  Future<void> onLoad() async {
    await add(GroundLine());
    player = PlayerBox(Vector2(0, -5));
    await add(player);

    accelerometerEvents.listen((AccelerometerEvent event) {
      tiltX = event.x; 
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    player.body.applyForce(Vector2(-tiltX * 80, 0));
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) {
      player.body.applyLinearImpulse(Vector2(5, -15));
    } else {
      player.body.linearVelocity.x *= 0.1;
    }
  }
}

class PlayerBox extends BodyComponent {
  final Vector2 startPos;
  PlayerBox(this.startPos);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBox(1.0, 1.0, Vector2.zero(), 0);
    final fixtureDef = FixtureDef(shape, friction: 0.5, restitution: 0.4);
    final bodyDef = BodyDef(type: BodyType.dynamic, position: startPos);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(-1, -1, 2, 2), 
      Paint()..color = const Color(0xFF2196F3),
    );
  }
}

class GroundLine extends BodyComponent {
  @override
  Body createBody() {
    final shape = EdgeShape()..set(Vector2(-50, 5), Vector2(50, 5));
    return world.createBody(BodyDef(type: BodyType.static))
      ..createFixture(FixtureDef(shape));
  }

  @override
  void render(Canvas canvas) {
    canvas.drawLine(
      const Offset(-50, 5),
      const Offset(50, 5),
      Paint()..color = const Color(0xFFFFFFFF)..strokeWidth = 0.2,
    );
  }
}