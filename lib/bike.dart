import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

class Bike extends GroupComponent {
  final Vector2 initialPosition;
  late Body chassis;
  late Body frontWheel;
  late Body rearWheel;
  late WheelJoint rearJoint;
  late WheelJoint frontJoint;

  // Suspension Tuning
  static const double wheelBase = 2.8;
  static const double wheelRadius = 0.5;
  static const double hz = 15.0;     // High stiffness for "Bike Race" feel
  static const double damping = 0.8; // High damping to stop the "jiggle"
  
  static const double motorSpeed = -50.0; // Clockwise rotation
  static const double maxTorque = 25.0;   // Reduced to make wheelies "subtle"

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    final world = (parent as Forge2DWorld);

    // 1. CHASSIS (The Frame)
    final chassisDef = BodyDef(position: initialPosition, type: BodyType.dynamic, angularDamping: 1.5);
    chassis = world.createBody(chassisDef);
    // Head hitbox (Only the top circle collides for death)
    chassis.createFixture(FixtureDef(CircleShape()..radius = 0.4, density: 1.0)..setUserData('head'));

    // 2. WHEELS
    frontWheel = _makeWheel(world, initialPosition + Vector2(wheelBase / 2, 0.8));
    rearWheel = _makeWheel(world, initialPosition + Vector2(-wheelBase / 2, 0.8));

    // 3. JOINTS (The Suspension Springs)
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
      ..enableMotor = false; // Start disabled so we can roll
    return world.createJoint(def) as WheelJoint;
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    // TILT
    chassis.angularVelocity = tilt * 6.5;

    // MOTOR (GAS) - Enables motor to move forward. If false, it rolls freely.
    if (isGas) {
      rearJoint.enableMotor(true);
      rearJoint.setMotorSpeed(motorSpeed);
    } else {
      rearJoint.enableMotor(false); // <--- THIS allows the roll-back on hills
    }

    // BRAKE
    if (isBrake) {
      rearJoint.enableMotor(true);
      rearJoint.setMotorSpeed(0);
      rearJoint.setMaxMotorTorque(maxTorque * 4); // Stronger holding power
    }
  }
}