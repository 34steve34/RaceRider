import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'track.dart';
import 'bike.dart';

const String gameVersion = "v1.0.5"; 

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame {
  Bike? playerBike;

  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    world.add(TrackComponent());
    
    playerBike = Bike(initialPosition: Vector2(-10, -30));
    await world.add(playerBike!);

    camera.viewport.add(
      TextComponent(
        text: 'RaceRider $gameVersion',
        position: Vector2(20, 20),
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );

    camera.viewfinder.zoom = 15.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    final bike = playerBike;
    if (bike != null && bike.isLoaded) {
      final targetPos = bike.getChassisPosition();
      
      // Smoothly move camera toward bike
      // (Current Pos) + (Distance to Target * Speed)
      final currentPos = camera.viewfinder.position;
      final delta = (targetPos - currentPos)..scale(0.1);
      camera.viewfinder.position.add(delta);
    }
  }
}
