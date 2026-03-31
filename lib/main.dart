import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'track.dart';
import 'bike.dart';

const String gameVersion = "v1.0.4"; 

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame {
  // We'll make this nullable to prevent "Late Initialization" crashes
  Bike? playerBike;

  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    world.add(TrackComponent());
    
    // Create the bike and store it
    playerBike = Bike(initialPosition: Vector2(-10, -30));
    await world.add(playerBike!);

    // HUD Version Text
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
    
    // Smooth Camera Follow Logic
    final bike = playerBike;
    if (bike != null && bike.isLoaded) {
      final targetPos = bike.getChassisPosition();
      
      // Explicitly set the position by lerping between current and target
      camera.viewfinder.position.setFrom(
        camera.viewfinder.position + (targetPos - camera.viewfinder.position) * 0.1
      );
    }
  }
}
