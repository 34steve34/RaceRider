import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;

import 'track.dart';
import 'bike.dart';

// --- MAJOR VERSION CHANGE - PUPPET PHYSICS REWRITE ---
const String gameVersion = "v2.0.0";

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with HasKeyboardHandlerComponents {
  Bike? playerBike;
  double phoneTiltAngle = 0.0; // Radians, 0 = horizontal, positive = right side down
  bool isGasPressed = false;
  
  // Accelerometer subscription
  Stream<AccelerometerEvent>? _accelerometerStream;

  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 1. Build the track
    world.add(TrackComponent());
    
    // 2. Spawn the bike
    playerBike = Bike(initialPosition: Vector2(-15, -5));
    await world.add(playerBike!);

    // 3. HUD
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

    // 4. Camera
    camera.viewfinder.zoom = 12.0;
    
    // 5. Start accelerometer listener for mobile
    _startAccelerometer();
  }

  void _startAccelerometer() {
    // Use accelerometer to determine phone tilt
    // In landscape mode, X axis is the tilt axis
    accelerometerEventStream().listen((event) {
      // event.x is the tilt when phone is in landscape
      // Normalize to angle: -pi/2 to +pi/2
      // Positive x = right side down (in landscape)
      phoneTiltAngle = _clampAngle(math.atan2(event.x, 9.8));
    });
  }
  
  double _clampAngle(double angle) {
    // Clamp to reasonable range, e.g., -135° to +135°
    const maxAngle = 135.0 * math.pi / 180.0;
    return angle.clamp(-maxAngle, maxAngle);
  }

  @override
  void update(double dt) {
    super.update(dt);

    final bike = playerBike;
    if (bike == null) return;

    // Update bike with phone tilt and gas state
    bike.updateControl(phoneTiltAngle, isGasPressed);

    // Camera follow
    final bikePos = bike.bodyPosition;
    camera.viewfinder.position = Vector2(
      bikePos.x + 8.0,
      bikePos.y,
    );
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Gas
    isGasPressed = keysPressed.contains(LogicalKeyboardKey.space) || 
                   keysPressed.contains(LogicalKeyboardKey.arrowUp);
    
    // Keyboard tilt simulation (for desktop testing)
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      phoneTiltAngle = -0.5; // Tilt left (left side down)
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      phoneTiltAngle = 0.5; // Tilt right (right side down)
    } else if (!keysPressed.contains(LogicalKeyboardKey.arrowLeft) && 
               !keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      // Return to horizontal when no arrow pressed (keyboard only)
      // On mobile, this is handled by accelerometer
      if (event is KeyUpEvent) {
        phoneTiltAngle = 0.0;
      }
    }

    return KeyEventResult.handled;
  }
}