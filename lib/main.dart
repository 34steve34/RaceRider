import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'track.dart';
import 'bike.dart';

// --- UPDATE THE VERSION HERE EACH TIME ---
const String gameVersion = "v1.0.3"; 

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame {
  late final Bike playerBike;

  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 1. Build the ground
    world.add(TrackComponent());
    
    // 2. Drop the Bike
    playerBike = Bike(initialPosition: Vector2(-10, -30));
    await world.add(playerBike);

    // 3. Add the Version Text to the HUD
    // This stays fixed on screen while the camera moves
    camera.viewport.add(
      TextComponent(
        text: 'RaceRider $gameVersion',
        position: Vector2(20, 20),
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );

    // 4. Set up Camera Zoom and Follow
    camera.viewfinder.zoom = 15.0;
  }

 @override
  void update(double dt) {
    super.update(dt);
    
    if (playerBike.isLoaded) {
      final chassisPos = playerBike.getChassisPosition();
      
      // 0.1 means the camera moves 10% of the way to the bike every frame.
      // This creates that "smooth trailing" effect.
      // Increase to 0.2 for a tighter follow, decrease to 0.05 for "looser" feel.
      double followSpeed = 0.1;

      camera.viewfinder.position.lerp(chassisPos, followSpeed);
    }
  }
}
