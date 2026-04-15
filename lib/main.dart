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

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.zoom = 25.0;
    camera.viewfinder.anchor = Anchor.center;

    player = Bike(initialPosition: Vector2(0, 0));
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
  void onTapDown(TapDownInfo info) {
    _isGas = true;
  }

  @override
  void onTapUp(TapUpInfo info) {
    _isGas = false;
  }

  @override
  void onRemove() {
    _subscription?.cancel();
    super.onRemove();
  }
}

class Ground extends BodyComponent {
  @override
  Body createBody() {
    final shape = EdgeShape()..set(Vector2(-100, 5), Vector2(100, 5));
    final bodyDef = BodyDef()..type = BodyType.static;
    final fixtureDef = FixtureDef(shape)..friction = 0.8;
    return world.createBody(bodyDef)..createFixture(fixtureDef);
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
    
    if (!isWheel) {
      bodyDef.angularDamping = 1.8;
    }

    final body = world.createBody(bodyDef);
    final shape = isWheel 
        ? (CircleShape()..radius = 0.5) 
        : (PolygonShape()..setAsBox(0.4, 0.2, Vector2.zero(), 0));

    body.createFixture(FixtureDef(shape)
      ..density = 1.0
      ..friction = isWheel ? 0.9 : 0.5
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

  static const double wheelBase = 2.8;
  static const double hz = 15.0; 
  static const double damping = 0.7;

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    final frontPos = initialPosition + Vector2(wheelBase / 2, 0.8);
    final rearPos = initialPosition + Vector2(-wheelBase / 2, 0.8);

    chassisComp = _Part(pos: initialPosition);
    _frontWheelComp = _Part(pos: frontPos, isWheel: true);
    _rearWheelComp = _Part(pos: rearPos, isWheel: true);

    // Adding components to the game
    await add(chassisComp);
    await add(_frontWheelComp);
    await add(_rearWheelComp);

    // We must wait for bodies to be created before making joints
    // This is handled by Forge2DGame's lifecycle, but for joints 
    // we can use the world object directly.
    
    final jointDefFront = f2d.WheelJointDef()
      ..initialize(chassisComp.body, _frontWheelComp.body, _frontWheelComp.body.position, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping;

    final jointDefRear = f2d.WheelJointDef()
      ..initialize(chassisComp.body, _rearWheelComp.body, _rearWheelComp.body.position, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping
      ..enableMotor = true;

    frontJoint = f2d.WheelJoint(jointDefFront);
    rearJoint = f2d.WheelJoint(jointDefRear);

    gameRef.world.physicsWorld.createJoint(frontJoint!);
    gameRef.world.physicsWorld.createJoint(rearJoint!);
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    if (!chassisComp.isLoaded) return;

    // TILT - Apply impulse for air control/leaning
    chassisComp.body.applyAngularImpulse(tilt * 0.5);

    // GAS/BRAKE logic
    final joint = rearJoint;
    if (joint != null) {
      if (isGas) {
        joint.motorSpeed = -55.0; // Assignment, not a method call
        joint.maxMotorTorque = 25.0; // Assignment, not a method call
      } else if (isBrake) {
        joint.motorSpeed = 0;
        joint.maxMotorTorque = 150.0; // High torque to lock the wheel
      } else {
        joint.motorSpeed = 0;
        joint.maxMotorTorque = 0.5; // Rolling resistance
      }
    }
  }
}