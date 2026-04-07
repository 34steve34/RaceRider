import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:forge2d/forge2d.dart' as f2d; // Prefix to avoid ambiguity
import 'package:flutter/material.dart';

class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 initialPosition;
  late Body chassis;
  late Body frontWheel;
  late Body rearWheel;
  late WheelJoint rearJoint;
  late WheelJoint frontJoint;

  static const double wheelBase = 2.8;
  static const double wheelRadius = 0.5;
  static const double hz = 18.0; 
  static const double damping = 0.8; 

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    // FIX 1: Access the underlying physics World object
    final f2d.World physicsWorld = gameRef.world.physicsWorld;

    // 1. CHASSIS
    final chassisDef = BodyDef()
      ..position = initialPosition
      ..type = BodyType.dynamic
      ..angularDamping = 1.8;
    chassis = physicsWorld.createBody(chassisDef);
    
    final headFix = chassis.createFixture(FixtureDef(
      f2d.CircleShape()..radius = 0.4,
      density: 1.0,
    ));
    headFix.userData = 'head';

    // 2. WHEELS
    frontWheel = _makeWheel(physicsWorld, initialPosition + Vector2(wheelBase / 2, 0.8));
    rearWheel = _makeWheel(physicsWorld, initialPosition + Vector2(-wheelBase / 2, 0.8));

    // 3. JOINTS (The Suspension)
    frontJoint = _makeJoint(physicsWorld, chassis, frontWheel, Vector2(wheelBase / 2, 0.8));
    rearJoint = _makeJoint(physicsWorld, chassis, rearWheel, Vector2(-wheelBase / 2, 0.8));
  }

  Body _makeWheel(f2d.World world, Vector2 pos) {
    final shape = f2d.CircleShape()..radius = wheelRadius;
    return world.createBody(BodyDef()
      ..position = pos
      ..type = BodyType.dynamic)
      ..createFixture(FixtureDef(shape)..friction = 0.9..density = 1.2);
  }

  WheelJoint _makeJoint(f2d.World world, Body bodyA, Body bodyB, Vector2 anchor) {
    final def = WheelJointDef()
      ..initialize(bodyA, bodyB, anchor, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping
      ..maxMotorTorque = 25.0
      ..enableMotor = false;
    final joint = f2d.WheelJoint(def);
    world.createJoint(joint);
    return joint;
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    chassis.angularVelocity = tilt * 6.5;

    if (isGas) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = -55.0;
      rearJoint.setMaxMotorTorque(25.0);
    } else {
      // Disabling motor allows the bike to roll backwards on hills
      rearJoint.enableMotor(false);
    }

    if (isBrake) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = 0;
      rearJoint.setMaxMotorTorque(125.0);
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    // Visual for the head hitbox
    canvas.drawCircle(Offset.zero, 0.4, paint);
  }
}