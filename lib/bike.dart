import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
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
  static const double hz = 18.0;     // Stiff suspension
  static const double damping = 0.8; 
  static const double motorSpeed = -55.0; 
  static const double maxTorque = 22.0;   // Low torque for subtle wheelies

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    final world = gameRef.world;

    // 1. CHASSIS
    chassis = world.createBody(BodyDef(position: initialPosition, type: BodyType.dynamic, angularDamping: 1.8));
    final headFix = FixtureDef(CircleShape()..radius = 0.4, density: 1.0);
    final f = chassis.createFixture(headFix);
    f.userData = 'head'; // Correct for your Forge2D version

    // 2. WHEELS
    frontWheel = _makeWheel(world, initialPosition + Vector2(wheelBase / 2, 0.8));
    rearWheel = _makeWheel(world, initialPosition + Vector2(-wheelBase / 2, 0.8));

    // 3. JOINTS
    frontJoint = _makeJoint(world, chassis, frontWheel, Vector2(wheelBase / 2, 0.8));
    rearJoint = _makeJoint(world, chassis, rearWheel, Vector2(-wheelBase / 2, 0.8));
  }

  Body _makeWheel(Forge2DWorld world, Vector2 pos) {
    return world.createBody(BodyDef(position: pos, type: BodyType.dynamic))
      ..createFixture(FixtureDef(CircleShape()..radius = wheelRadius, friction: 0.9, density: 1.2));
  }

  WheelJoint _makeJoint(Forge2DWorld world, Body bodyA, Body bodyB, Vector2 anchor) {
    final def = WheelJointDef()
      ..initialize(bodyA, bodyB, anchor, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping
      ..maxMotorTorque = maxTorque
      ..enableMotor = false;
    return world.createJoint(def) as WheelJoint;
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    chassis.angularVelocity = tilt * 6.5;

    if (isGas) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = motorSpeed; // Correct property assignment
    } else {
      rearJoint.enableMotor(false); // Allows rolling backwards
    }

    if (isBrake) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = 0;
      rearJoint.maxMotorTorque = maxTorque * 5;
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFFF69B4)..strokeWidth = 0.15..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset.zero, 0.4, paint..style = PaintingStyle.fill..color = Colors.white);
  }
}