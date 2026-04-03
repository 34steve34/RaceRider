import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart'; // Required for keyboard input
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for LogicalKeyboardKey

import 'track.dart';
import 'bike.dart';

// --- BUMP VERSION TO TRACK REFRESHES ---
const String gameVersion = "v1.3.0"; 

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with HasKeyboardHandlerComponents {
  Bike? playerBike;

  // Set gravity to 19.0 for a "heavy" dirt bike feel
  RaceRiderGame() : super(gravity: Vector2(0, 19.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 1. Build the track
    world.add(TrackComponent());
    
    // 2. Spawn the bike (Started a bit higher and further left)
    playerBike = Bike(initialPosition: Vector2(-15, -15));
    await world.add(playerBike!);

    // 3. HUD - Version Text (Stays fixed to screen)
    camera.viewport.add(
      TextComponent(
        text: 'RaceRider $gameVersion',
        position: Vector2(20, 20),
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 18, 
            fontWeight: FontWeight.bold
          ),
        ),
      ),
    );

    // 4. Initial Camera Setup
    camera.viewfinder.zoom = 15.0;
  }

  @override
  void update(double dt) {
  super.update(dt);

  final bike = playerBike;
  if (bike == null) return;

  final bikePos = bike.getChassisPosition();
  camera.viewfinder.position = Vector2(
    bikePos.x + 10.0,  // look ahead
    bikePos.y,
  );
} // END update

@override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    final isGas = keysPressed.contains(LogicalKeyboardKey.space) || keysPressed.contains(LogicalKeyboardKey.arrowUp);
    final isLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    final isRight = keysPressed.contains(LogicalKeyboardKey.arrowRight);
    
    playerBike?.updateInput(isGas, isLeft, isRight);

    return KeyEventResult.handled;
  }
}