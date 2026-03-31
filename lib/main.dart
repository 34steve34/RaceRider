import 'package:flutter/material.dart';
import 'package:flame/game.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    print("RaceRider Engine Online");
  }
}
