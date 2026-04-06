import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'track.dart';
import 'bike.dart';

const String gameVersion = "v2.3.1";

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame 
    with HasKeyboardHandlerComponents, TapCallbacks {
  Bike? playerBike;
  double phoneTiltAngle = 0.0; 
  bool isGasPressed = false;
  bool isBrakePressed = false;
  
  // High gravity (40.0) makes the bike feel grounded and snappy
  RaceRiderGame() : super(gravity: Vector2(0, 40.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Add the track
    await world.add(TrackComponent());
    
    // Spawn bike above the start line
    playerBike = Bike(initialPosition: Vector2(0, -5));
    await world.add(playerBike!);

    // UI Overlay for versioning
    camera.viewport.add(
      TextComponent(
        text: 'RaceRider $gameVersion',
        position: Vector2(20, 20),
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );

    camera.viewfinder.zoom = 10.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (playerBike == null) return;

    // Pass inputs to the bike
    playerBike!.updateControl(phoneTiltAngle, isGasPressed, isBrakePressed);

    // Camera follow logic
    camera.viewfinder.position = playerBike!.body.position + Vector2(8, -2);
  }
  
  @override
  void onTapDown(TapDownEvent event) {
    // Simple split-screen controls
    if (event.canvasPosition.x < camera.viewport.size.x / 2) {
      isBrakePressed = true;
    } else {
      isGasPressed = true;
    }
  }
  
  @override
  void onTapUp(TapUpEvent event) {
    isGasPressed = false;
    isBrakePressed = false;
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Desktop testing controls
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      phoneTiltAngle = -1.0;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      phoneTiltAngle = 1.0;
    } else {
      phoneTiltAngle = 0.0;
    }
    
    isGasPressed = keysPressed.contains(LogicalKeyboardKey.space);
    isBrakePressed = keysPressed.contains(LogicalKeyboardKey.shiftLeft);

    return KeyEventResult.handled;
  }
}