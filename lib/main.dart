import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'track.dart';
import 'bike.dart';

const String gameVersion = "v2.3.0";

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame 
    with HasKeyboardHandlerComponents, TapCallbacks {
  Bike? playerBike;
  double tiltInput = 0.0; // -1.0 to 1.0
  bool isGasPressed = false;
  bool isBrakePressed = false;
  
  RaceRiderGame() : super(gravity: Vector2(0, 35.0)); // High gravity is key

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Add Track
    await world.add(TrackComponent());
    
    // Start bike at a visible position
    playerBike = Bike(initialPosition: Vector2(0, -5));
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

    camera.viewfinder.zoom = 12.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (playerBike == null) return;

    playerBike!.updateControl(tiltInput, isGasPressed, isBrakePressed);

    // Follow bike
    camera.viewfinder.position = playerBike!.body.position + Vector2(5, 0);
  }
  
  @override
  void onTapDown(TapDownEvent event) {
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
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      tiltInput = -1.0;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      tiltInput = 1.0;
    } else {
      tiltInput = 0.0;
    }
    
    isGasPressed = keysPressed.contains(LogicalKeyboardKey.space);
    isBrakePressed = keysPressed.contains(LogicalKeyboardKey.shiftLeft);

    return KeyEventResult.handled;
  }
}