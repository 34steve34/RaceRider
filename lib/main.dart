import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'track.dart';
import 'bike.dart'; // Import our new 3-piece assembly

void main() {
  runApp(const GameWidget.controlled(gameFactory: RaceRiderGame.new));
}

class RaceRiderGame extends Forge2DGame {
  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    camera.viewfinder.position = Vector2(20, -5);
    camera.viewfinder.zoom = 15.0;

    world.add(TrackComponent());
    
    // Drop the fully assembled Bike!
    world.add(Bike(initialPosition: Vector2(5, -20)));
    
    debugPrint("RaceRider: Multi-body Bike Deployed");
  }
}
