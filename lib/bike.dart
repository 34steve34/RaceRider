import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// 1. THE WHEEL COMPONENT
class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(
      shape,
      density: 0.5,
      friction: 1.4,     // 50% Boost: Super grippy tires
      restitution: 0.1, 
    );
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;

    canvas.drawCircle(Offset.zero, 0.75, paint);
    // Spoke line
    canvas.drawLine(
      Offset.zero, 
      const Offset(0.75, 0), 
      paint..strokeWidth = 0.18
    );
  }
}

// 2. THE CHASSIS COMPONENT (Now with a "Front" indicator)
class Chassis extends BodyComponent {
  final Vector2 initialPosition;
  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(2.0, 0.5);
    final fixtureDef = FixtureDef(
      shape,
      density: 1.0, 
      friction: 0.3,
      restitution: 0.2,
    );
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.blueAccent;
    // Main Body
    canvas.drawRect(const Rect.fromLTRB(-2, -0.5, 2, 0.5), paint);
    
    // --- FRONT INDICATOR (A small cockpit/windshield on the right side) ---
    final frontPaint = Paint()..color = Colors.lightBlueAccent;
    // This puts a small "bump" on the right half of the block
    canvas.drawRect(const Rect.fromLTRB(0.5, -1.0, 1.8, -0.5), frontPaint);
  }
}

// 3. THE BIKE ASSEMBLER
class Bike extends Component with HasWorldReference<Forge2DWorld> {
  final Vector2 initialPosition;
  
  late Chassis _chassisRef;
  late WheelJoint _rearJoint; 

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _chassisRef = Chassis(initialPosition);
    final rearWheel = Wheel(initialPosition + Vector2(-1.5, 1.0));
    final frontWheel = Wheel(initialPosition + Vector2(1.5, 1.0));

    await world.addAll([_chassisRef, rearWheel, frontWheel]);

    // REAR SUSPENSION & MOTOR
    final rearAxis = Vector2(-0.2, 1.0)..normalize();
    final rearJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, rearWheel.body, rearWheel.body.position, rearAxis)
      ..dampingRatio = 0.4
      ..frequencyHz = 4.0
      ..enableMotor = true
      ..maxMotorTorque = 45.0   // Bumped torque for the extra traction
      ..motorSpeed = 0.0;       

    _rearJoint = WheelJoint(rearJointDef);
    world.physicsWorld.createJoint(_rearJoint);

    // FRONT SUSPENSION
    final frontAxis = Vector2(0.4, 1.0)..normalize();
    final frontJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, frontWheel.body, frontWheel.body.position, frontAxis)
      ..dampingRatio = 0.5
      ..frequencyHz = 5.0;

    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }

  void setGas(bool isOn) {
    // FLIPPED: Positive 25.0 spins the bike RIGHT
    _rearJoint.motorSpeed = isOn ? 25.0 : 0.0;
  }

  Vector2 getChassisPosition() {
    return _chassisRef.isLoaded ? _chassisRef.body.position : initialPosition;
  }
}