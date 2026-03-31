import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'track.dart'; // Import our new track file

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame {
  // Strong gravity for the "heavy" feel
  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Set up the camera to look at our track
    camera.viewfinder.position = Vector2(20, -5);
    camera.viewfinder.zoom = 15.0; // Zoom in (Forge2D uses meters, not pixels)

    // Drop the track into the world!
    world.add(TrackComponent());
    
    debugPrint("RaceRider: Track Loaded");
  }
}
