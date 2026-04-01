import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// --- THE TUNING TABLE (Adjust these for the "Exquisite" feel) ---
class BikeConfig {
  static const double maxMotorTorque = 60.0;   // Engine Power
  static const double motorSpeed = 35.0;       // Top Speed
  static const double tireFriction = 1.4;      // 1.4 = Super Sticky
  static const double chassisDensity = 1.0;    // Weight
  static const double tiltStrength = 50.0;     // Backflip/Frontflip power
  
  // Suspension (Rear)
  static const double rearStiffness = 4.0; 
  static const double rearDamping = 0.4;
  
  // Suspension (Front)
  static const double frontStiffness = 5.0; 
  static const double frontDamping = 0.5;
}

class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(shape, density: 0.5, friction: BikeConfig.tireFriction, restitution: 0.1);
    final bodyDef = BodyDef(userData: this, position: initialPosition, type: BodyType.dynamic);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.12;
    canvas.drawCircle(Offset.zero, 0.75, paint);
    canvas.drawLine(Offset.zero, const Offset(0.75, 0), paint..strokeWidth = 0.18);
  }
}

class Chassis extends BodyComponent {
  final Vector2 initialPosition;
  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(2.0, 0.5);
    final fixtureDef = FixtureDef(shape, density: BikeConfig.chassisDensity, friction: 0.3, restitution: 0.2);
    final bodyDef = BodyDef(userData: this, position: initialPosition, type: BodyType.dynamic);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.blueAccent;
    canvas.drawRect(const Rect.fromLTRB(-2, -0.5, 2, 0.5), paint);
    // Front Windshield
    canvas.drawRect(const Rect.fromLTRB(0.5, -1.0, 1.8, -0.5), Paint()..color = Colors.lightBlueAccent);
  }
}

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

    // REAR
    final rearJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, rearWheel.body, rearWheel.body.position, (Vector2(-0.2, 1.0)..normalize()))
      ..dampingRatio = BikeConfig.rearDamping
      ..frequencyHz = BikeConfig.rearStiffness
      ..enableMotor = true
      ..maxMotorTorque = BikeConfig.maxMotorTorque;

    _rearJoint = WheelJoint(rearJointDef);
    world.physicsWorld.createJoint(_rearJoint);

    // FRONT
    final frontJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, frontWheel.body, frontWheel.body.position, (Vector2(0.4, 1.0)..normalize()))
      ..dampingRatio = BikeConfig.frontDamping
      ..frequencyHz = BikeConfig.frontStiffness;

    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }

  void updateInput(bool isGas, bool isLeft, bool isRight) {
    // 1. MOTOR (Gas) - Neutral Gear Fix
    if (isGas) {
      _rearJoint.enableMotor(true); // Engages the gear
      _rearJoint.motorSpeed = BikeConfig.motorSpeed;
    } else {
      _rearJoint.enableMotor(false); // Neutral: rolls freely!
    }

    // 2. TILT (Angular Impulse)
    if (isLeft) {
      _chassisRef.body.applyAngularImpulse(-BikeConfig.tiltStrength);
    }
    if (isRight) {
      _chassisRef.body.applyAngularImpulse(BikeConfig.tiltStrength);
    }
  }

  Vector2 getChassisPosition() => _chassisRef.isLoaded ? _chassisRef.body.position : initialPosition;
}