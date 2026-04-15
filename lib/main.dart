import 'dart:async';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:forge2d/forge2d.dart' as f2d;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with TapDetector {
  late final Bike player;
  StreamSubscription<AccelerometerEvent>? _subscription;

  double _currentTilt = 0.0;
  bool _isGas = false;

  RaceRiderGame() : super(gravity: Vector2(0, 15.0));

  // ✅ Centralized camera scaling logic
  void _updateCameraZoom(Vector2 size) {
    // Set a fixed zoom level - higher zoom = more zoomed in (fewer world units visible)
    // zoom = 1.0 means 1 pixel = 1 world unit
    // zoom = 10.0 means 10 pixels = 1 world unit (zoomed in 10x)
    camera.viewfinder
      ..anchor = Anchor.center
      ..zoom = 8.0;  // Zoomed in 8x - should show ~10-15 world units horizontally
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _updateCameraZoom(size); // ✅ apply initial scaling

    player = Bike(initialPosition: Vector2(0, -2));
    await add(player);
    await add(Ground());

    camera.follow(player.chassisComp);

    _subscription = accelerometerEvents.listen((AccelerometerEvent event) {
      _currentTilt = -event.x;
    });
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _updateCameraZoom(size); // ✅ critical for all devices / rotations
  }

  @override
  void update(double dt) {
    super.update(dt);
    player.updateControl(_currentTilt, _isGas, false);
  }

  @override
  void onTapDown(TapDownInfo info) => _isGas = true;

  @override
  void onTapUp(TapUpInfo info) => _isGas = false;

  @override
  void onRemove() {
    _subscription?.cancel();
    super.onRemove();
  }
}

class Ground extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);
    
    // Create a track with bumps and features
    final List<Vector2> points = [
      // Starting flat section
      Vector2(-100, 5),
      Vector2(-20, 5),
      
      // First bump
      Vector2(-15, 3.5),
      Vector2(-10, 2),
      Vector2(-5, 3.5),
      Vector2(0, 5),
      
      // Flat section
      Vector2(20, 5),
      Vector2(40, 5),
      
      // Second bump (bigger)
      Vector2(45, 4),
      Vector2(50, 1.5),
      Vector2(55, 4),
      Vector2(60, 5),
      
      // Flat section
      Vector2(80, 5),
      Vector2(100, 5),
      
      // Third bump (small)
      Vector2(105, 4.2),
      Vector2(110, 3.5),
      Vector2(115, 4.2),
      Vector2(120, 5),
      
      // Final flat section
      Vector2(200, 5),
      Vector2(500, 5),
    ];
    
    // Create edge segments between consecutive points
    for (int i = 0; i < points.length - 1; i++) {
      final shape = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(FixtureDef(shape)..friction = 0.9);
    }
    
    return body;
  }
}

class _Part extends BodyComponent {
  final Vector2 pos;
  final bool isWheel;

  _Part({required this.pos, this.isWheel = false});

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..position = pos
      ..type = BodyType.dynamic;

    if (!isWheel) bodyDef.angularDamping = 2.0;

    final body = world.createBody(bodyDef);

    final shape = isWheel
        ? (CircleShape()..radius = 0.45)
        : (PolygonShape()..setAsBox(1.2, 0.3, Vector2.zero(), 0));

    body.createFixture(FixtureDef(shape)
      ..density = 1.0
      ..friction = isWheel ? 1.0 : 0.5
      ..restitution = 0.1);

    return body;
  }
}

class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 initialPosition;

  late final _Part chassisComp;
  late final _Part _frontWheelComp;
  late final _Part _rearWheelComp;

  f2d.WheelJoint? rearJoint;
  f2d.WheelJoint? frontJoint;

  static const double wheelBase = 1.8;
  static const double hz = 8.0;
  static const double damping = 0.6;

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    final frontPos = initialPosition + Vector2(wheelBase / 2, 0.5);
    final rearPos = initialPosition + Vector2(-wheelBase / 2, 0.5);

    chassisComp = _Part(pos: initialPosition);
    _frontWheelComp = _Part(pos: frontPos, isWheel: true);
    _rearWheelComp = _Part(pos: rearPos, isWheel: true);

    await add(chassisComp);
    await add(_frontWheelComp);
    await add(_rearWheelComp);

    final jointDefFront = f2d.WheelJointDef()
      ..initialize(
        chassisComp.body,
        _frontWheelComp.body,
        _frontWheelComp.body.position,
        Vector2(0, 1),
      )
      ..frequencyHz = hz
      ..dampingRatio = damping;

    final jointDefRear = f2d.WheelJointDef()
      ..initialize(
        chassisComp.body,
        _rearWheelComp.body,
        _rearWheelComp.body.position,
        Vector2(0, 1),
      )
      ..frequencyHz = hz
      ..dampingRatio = damping;

    frontJoint = f2d.WheelJoint(jointDefFront);
    rearJoint = f2d.WheelJoint(jointDefRear);

    gameRef.world.physicsWorld.createJoint(frontJoint!);
    gameRef.world.physicsWorld.createJoint(rearJoint!);
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    if (!chassisComp.isLoaded) return;

    chassisComp.body.applyTorque(tilt * 45.0);

    final Body rearWheel = _rearWheelComp.body;

    if (isGas) {
      rearWheel.applyTorque(80.0);
    }

    if (isBrake) {
      rearWheel.angularVelocity *= 0.9;
    }
  }
}