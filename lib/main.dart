import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'track.dart';
import 'bike.dart'; // Import the crash test dummy!

void main() {
  runApp(const GameWidget.controlled(gameFactory: RaceRiderGame.new));
}

class RaceRiderGame extends Forge2DGame {
  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Position the camera to see the drop
    camera.viewfinder.position = Vector2(20, -5);
    camera.viewfinder.zoom = 15.0;

    // 1. Build the ground
    world.add(TrackComponent());
    
    // 2. Drop the chassis from the sky!
    // X = 5 (above the first hill), Y = -20 (20 meters in the air)
    world.add(BikeChassis(initialPosition: Vector2(5, -20)));
    
    debugPrint("RaceRider: Crash Test Dummy Deployed");
  }
}
