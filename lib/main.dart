import 'dart:async';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'track.dart';
import 'bike.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // LOCK TO LANDSCAPE
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(
    GameWidget(
      game: RaceRiderGame(),
      overlayBuilderMap: {
        'version': (context, game) => const Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'RaceRider v3.0.7',
                  style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
                ),
              ),
            ),
      },
      initialActiveOverlays: const ['version'],
    ),
  );
}

class RaceRiderGame extends Forge2DGame 
    with HasKeyboardHandlerComponents, TapCallbacks {
  Bike? playerBike;
  double phoneTiltAngle = 0.0;
  bool isGasPressed = false;
  bool isBrakePressed = false;
  bool sensorsInitialized = false;
  StreamSubscription? _accel;

  RaceRiderGame() : super(gravity: Vector2(0, 42.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await world.add(TrackComponent());
    
    // Spawn point further back to test rolling/momentum
    playerBike = Bike(initialPosition: Vector2(-30, -5));
    await world.add(playerBike!);
    
    camera.viewfinder.zoom = 10.0;
  }

  // Mobile browsers require a user interaction (tap) to allow sensor access
  void _startSensors() {
    if (sensorsInitialized) return;
    _accel = accelerometerEvents.listen((event) {
      // Sensitivity: divisor 5.0 is standard. 
      // If it feels inverted, change '+' to '-' in the clamp.
      phoneTiltAngle = (event.y / 5.0).clamp(-1.0, 1.0);
    });
    sensorsInitialized = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (playerBike != null && playerBike!.isLoaded) {
      playerBike!.updateControl(phoneTiltAngle, isGasPressed, isBrakePressed);
      camera.viewfinder.position = playerBike!.chassisBody.position + Vector2(8, -2);
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    _startSensors(); 
    if (event.canvasPosition.x < camera.viewport.size.x / 2) {
      isBrakePressed = true;
    } else {
      isGasPressed = true;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGasPressed = isBrakePressed = false;
  }

  @override
  void onRemove() {
    _accel?.cancel();
    super.onRemove();
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
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