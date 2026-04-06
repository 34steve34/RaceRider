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

const String gameVersion = "v2.3.6";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock orientation for PWA/Mobile
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame 
    with HasKeyboardHandlerComponents, TapCallbacks {
  Bike? playerBike;
  double phoneTiltAngle = 0.0;
  bool isGasPressed = false;
  bool isBrakePressed = false;
  
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  // 42.0 gravity is the "Bike Race" sweet spot for snappiness
  RaceRiderGame() : super(gravity: Vector2(0, 42.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    await world.add(TrackComponent());
    
    playerBike = Bike(initialPosition: Vector2(-10, -5));
    await world.add(playerBike!);

    // Fix for sensors_plus ^4.0.0 API
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      // Sensitivity: divisor 4.5 makes it responsive but not twitchy
      phoneTiltAngle = (event.y / 4.5).clamp(-1.0, 1.0);
    });

    camera.viewport.add(
      TextComponent(
        text: 'RaceRider $gameVersion',
        position: Vector2(20, 20),
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );

    camera.viewfinder.zoom = 10.0;
  }

  @override
  void onRemove() {
    _accelSubscription?.cancel();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (playerBike == null) return;

    playerBike!.updateControl(phoneTiltAngle, isGasPressed, isBrakePressed);
    camera.viewfinder.position = playerBike!.body.position + Vector2(10, -2);
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
  void onTapUp(TapUpEvent event) => isGasPressed = isBrakePressed = false;

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