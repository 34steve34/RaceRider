import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart'; // This includes the correct Vector2
import 'package:flutter/material.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame {
  // Use Vector2 directly from the Forge2D library
  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    debugPrint("RaceRider Physics Engine: ONLINE");
  }
}
