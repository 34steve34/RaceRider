/* ============================================================================
 * RACERIDER - v8 ZOOM FIX - BRIGHT GREEN bike
 * Goal: Bike length ≈ 10% of screen width
 * ============================================================================ */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:forge2d/forge2d.dart' as f2d;
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const MaterialApp(home: Scaffold(body: GameWidget(game: RaceRiderGame()))));
}

class RaceRiderGame extends Forge2DGame with TapCallbacks {
  late final Bike player;
  StreamSubscription<AccelerometerEvent>? _subscription;

  double _currentTilt = 0.0;
  bool _isGas = false;

  RaceRiderGame() : super(gravity: Vector2(0, 18.0), zoom: 8.0); // starting guess

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _applyProperZoom(size);
  }

  void _applyProperZoom(Vector2 screenSize) {
    // Bike is roughly 2.7 units long → we want it ~10% of screen width
    const double desiredBikeScreenPercentage = 0.10;
    const double bikeWorldLength = 2.7;
    
    final double targetZoom = (screenSize.x * desiredBikeScreenPercentage) / bikeWorldLength;
    camera.viewfinder.zoom = targetZoom.clamp(4.0, 25.0);
    camera.viewfinder.anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    player = Bike(initialPosition: Vector2(-30, 0));
    await add(player);
    await add(Ground());

    // Force zoom again after everything is loaded
    _applyProperZoom(size);

    camera.follow(player.chassisComp, snap: false);

    _subscription = accelerometerEvents.listen((event) {
      _currentTilt = -event.x;        // Samsung-friendly axis
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    player.updateControl(_currentTilt, _isGas, false);
  }

  @override
  void onTapDown(TapDownEvent event) => _isGas = true;

  @override
  void onTapUp(TapUpEvent event) => _isGas = false;

  @override
  void onRemove() {
    _subscription?.cancel();
    super.onRemove();
  }
}

// ===================================================================
// GROUND
// ===================================================================
class Ground extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);
    final points = [
      Vector2(-100, 5), Vector2(-20, 5),
      Vector2(-15, 3.5), Vector2(-10, 2), Vector2(-5, 3.5), Vector2(0, 5),
      Vector2(20, 5), Vector2(40, 5),
      Vector2(45, 4), Vector2(50, 1.5), Vector2(55, 4), Vector2(60, 5),
      Vector2(80, 5), Vector2(200, 5),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      body.createFixture(FixtureDef(EdgeShape()..set(points[i], points[i + 1]))
        ..friction = 0.85);
    }
    return body;
  }
}

// ===================================================================
// BIKE
// ===================================================================
class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 initialPosition;

  late final _Part chassisComp;
  late final _Part frontWheelComp;
  late final _Part rearWheelComp;

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    final frontPos = initialPosition + Vector2(0.9, 0.5);
    final rearPos = initialPosition + Vector2(-0.9, 0.5);

    chassisComp = _Part(pos: initialPosition);
    frontWheelComp = _Part(pos: frontPos, isWheel: true);
    rearWheelComp = _Part(pos: rearPos, isWheel: true);

    await add(chassisComp);
    await add(frontWheelComp);
    await add(rearWheelComp);

    final frontJoint = f2d.WheelJoint(f2d.WheelJointDef()
      ..initialize(chassisComp.body, frontWheelComp.body, frontWheelComp.body.position, Vector2(0, 1))
      ..frequencyHz = 8.0
      ..dampingRatio = 0.6);

    final rearJoint = f2d.WheelJoint(f2d.WheelJointDef()
      ..initialize(chassisComp.body, rearWheelComp.body, rearWheelComp.body.position, Vector2(0, 1))
      ..frequencyHz = 8.0
      ..dampingRatio = 0.6);

    gameRef.world.physicsWorld.createJoint(frontJoint);
    gameRef.world.physicsWorld.createJoint(rearJoint);
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    if (!chassisComp.isLoaded) return;

    chassisComp.body.applyTorque(tilt * 55.0);   // lean

    if (isGas) {
      rearWheelComp.body.applyTorque(95.0);
    }
  }
}

class _Part extends BodyComponent {
  final Vector2 pos;
  final bool isWheel;

  _Part({required this.pos, this.isWheel = false});

  @override
  Body createBody() {
    final body = world.createBody(BodyDef()
      ..position = pos
      ..type = BodyType.dynamic
      ..angularDamping = isWheel ? 0.0 : 1.8);

    final shape = isWheel 
        ? (CircleShape()..radius = 0.45)
        : (PolygonShape()..setAsBox(1.35, 0.35, Vector2.zero(), 0));

    body.createFixture(FixtureDef(shape)
      ..density = 1.2
      ..friction = isWheel ? 1.0 : 0.4
      ..restitution = 0.1);

    return body;
  }

  @override
  void render(Canvas canvas) {
    final color = isWheel ? Colors.white : const Color(0xFF00FF44); // BRIGHT GREEN
    if (isWheel) {
      canvas.drawCircle(Offset.zero, 0.45, Paint()..color = color);
    } else {
      canvas.drawRect(const Rect.fromLTWH(-1.35, -0.35, 2.7, 0.7), Paint()..color = color);
    }
  }
}