import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import 'track.dart';
import 'bike.dart';

const String gameVersion = "v2.1.0";

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame 
    with HasKeyboardHandlerComponents, HasDragDetector, HasTappDetector {
  Bike? playerBike;
  double phoneTiltAngle = 0.0;
  bool isGasPressed = false;
  bool isBrakePressed = false;
  
  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    world.add(TrackComponent());
    
    playerBike = Bike(initialPosition: Vector2(-15, -5));
    await world.add(playerBike!);

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

    camera.viewfinder.zoom = 12.0;
    
    _startAccelerometer();
  }

  void _startAccelerometer() {
    // Accelerometer for phone tilt (mobile only)
    // On web/desktop, this won't work but keyboard will
  }

  @override
  void update(double dt) {
    super.update(dt);

    final bike = playerBike;
    if (bike == null) return;

    bike.updateControl(phoneTiltAngle, isGasPressed, isBrakePressed);

    final bikePos = bike.bodyPosition;
    camera.viewfinder.position = Vector2(
      bikePos.x + 8.0,
      bikePos.y,
    );
  }
  
  // ─────────────────────────────────────────────────────────────
  // TOUCH CONTROLS - Left side = brake, Right side = gas
  // ─────────────────────────────────────────────────────────────
  @override
  void onTapDown(int pointerId, TapDownInfo info) {
    final screenWidth = camera.viewport.size.x;
    final tapX = info.eventPosition.global.x;
    
    if (tapX < screenWidth / 2) {
      // Left side = brake
      isBrakePressed = true;
    } else {
      // Right side = gas
      isGasPressed = true;
    }
  }
  
  @override
  void onTapUp(int pointerId, TapUpInfo info) {
    isGasPressed = false;
    isBrakePressed = false;
  }
  
  @override
  void onTapCancel(int pointerId) {
    isGasPressed = false;
    isBrakePressed = false;
  }

  // ─────────────────────────────────────────────────────────────
  // KEYBOARD CONTROLS - For desktop testing
  // ─────────────────────────────────────────────────────────────
  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Arrow keys for tilt
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      phoneTiltAngle = -0.5;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      phoneTiltAngle = 0.5;
    } else {
      phoneTiltAngle = 0.0;
    }
    
    // Space = gas, Shift = brake
    isGasPressed = keysPressed.contains(LogicalKeyboardKey.space);
    isBrakePressed = keysPressed.contains(LogicalKeyboardKey.shiftLeft) || 
                     keysPressed.contains(LogicalKeyboardKey.shiftRight);

    return KeyEventResult.handled;
  }
}