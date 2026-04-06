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
  static const double hz = 20.0;     // Stiff "Bike Race" suspension
  static const double damping = 0.8; 
  static const double motorSpeed = -55.0; 
  static const double maxTorque = 22.0;   // Low torque for subtle wheelies

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    // Access the actual physics world
    final physicsWorld = gameRef.physicsWorld;

    // 1. CHASSIS - The main frame
    chassis = physicsWorld.createBody(BodyDef(
      position: initialPosition, 
      type: BodyType.dynamic, 
      angularDamping: 1.8
    ));
    
    // Head hitbox - Death zone
    final headFix = chassis.createFixture(FixtureDef(
      CircleShape()..radius = 0.4, 
      density: 1.0, 
      friction: 0.5
    ));
    headFix.userData = 'head';

    // 2. WHEELS
    frontWheel = _makeWheel(physicsWorld, initialPosition + Vector2(wheelBase / 2, 0.8));
    rearWheel = _makeWheel(physicsWorld, initialPosition + Vector2(-wheelBase / 2, 0.8));

    // 3. JOINTS - Suspension springs
    frontJoint = _makeJoint(physicsWorld, chassis, frontWheel, Vector2(wheelBase / 2, 0.8));
    rearJoint = _makeJoint(physicsWorld, chassis, rearWheel, Vector2(-wheelBase / 2, 0.8));
  }

  Body _makeWheel(World world, Vector2 pos) {
    return world.createBody(BodyDef(position: pos, type: BodyType.dynamic))
      ..createFixture(FixtureDef(CircleShape()..radius = wheelRadius, friction: 0.9, density: 1.2));
  }

  WheelJoint _makeJoint(World world, Body bodyA, Body bodyB, Vector2 anchor) {
    final def = WheelJointDef()
      ..initialize(bodyA, bodyB, anchor, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping
      ..maxMotorTorque = maxTorque
      ..enableMotor = false;
    // We pass the def to the physicsWorld's createJoint
    return world.createJoint(def) as WheelJoint;
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    // Direct angular velocity for the 'Puppet' feel
    chassis.angularVelocity = tilt * 6.5;

    if (isGas) {
      rearJoint.enableMotor(true);
      rearJoint.setMotorSpeed(motorSpeed);
      rearJoint.setMaxMotorTorque(maxTorque);
    } else {
      // FREE ROLL: Disabling the motor allows the bike to roll back on hills
      rearJoint.enableMotor(false);
    }

    if (isBrake) {
      rearJoint.enableMotor(true);
      rearJoint.setMotorSpeed(0);
      rearJoint.setMaxMotorTorque(maxTorque * 5); // Stronger holding power
    }
  }

  @override
  void render(Canvas canvas) {
    // We draw the visual chassis lines relative to the chassis body position
    final paint = Paint()..color = const Color(0xFFFF69B4)..strokeWidth = 0.15..style = PaintingStyle.stroke;
    
    // Draw visual head (white circle)
    canvas.drawCircle(Offset.zero, 0.4, paint..style = PaintingStyle.fill..color = Colors.white);
  }
}