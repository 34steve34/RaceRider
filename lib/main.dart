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
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame 
    with HasKeyboardHandlerComponents, TapCallbacks {
  Bike? playerBike;
  double phoneTiltAngle = 0.0;
  bool isGasPressed = false;
  bool isBrakePressed = false;
  StreamSubscription? _accel;

  RaceRiderGame() : super(gravity: Vector2(0, 42.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await world.add(TrackComponent());
    
    playerBike = Bike(initialPosition: Vector2(-20, -5));
    await world.add(playerBike!);

    _accel = accelerometerEvents.listen((event) {
      // Sensitivity check: 5.0 is standard for mobile racers
      phoneTiltAngle = (event.y / 5.0).clamp(-1.0, 1.0);
    });
    
    camera.viewfinder.zoom = 10.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (playerBike != null) {
      playerBike!.updateControl(phoneTiltAngle, isGasPressed, isBrakePressed);
      camera.viewfinder.position = playerBike!.chassis.position + Vector2(8, -2);
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.canvasPosition.x < camera.viewport.size.x / 2) isBrakePressed = true;
    else isGasPressed = true;
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
}