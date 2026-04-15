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

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // ✅ Fixed world size (in "meters")
    camera.viewport = FixedResolutionViewportComponent(
      resolution: Vector2(25, 15), // width x height of visible world
    );

    camera.viewfinder.anchor = Anchor.center;

    player = Bike(initialPosition: Vector2(0, -2));
    await add(player);
    await add(Ground());

    camera.follow(player.chassisComp);

    _subscription = accelerometerEvents.listen((AccelerometerEvent event) {
      _currentTilt = -event.x;
    });
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
    final shape = EdgeShape()..set(Vector2(-500, 5), Vector2(500, 5));
    final bodyDef = BodyDef()..type = BodyType.static;

    return world.createBody(bodyDef)
      ..createFixture(FixtureDef(shape)..friction = 0.9);
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