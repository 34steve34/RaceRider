import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// --- THE TUNING TABLE (v1.0.9 - BR Edition) ---
class BikeConfig {
  static const double maxMotorTorque = 150.0;  // High torque for wall climbing
  static const double motorSpeed = 45.0;      
  static const double tireFriction = 1.6;      // Extra grip for loops
  static const double chassisDensity = 1.5;    
  
  // TILT SETTINGS
  static const double tiltTorque = 1000.0;      // Constant force, not a "hit"
  static const double angularDamping = 1.5;    // Stops the "Tornado" spin
  
  // Suspension
  static const double rearStiffness = 4.5; 
  static const double rearDamping = 0.7;
  static const double frontStiffness = 5.0; 
  static const double frontDamping = 0.7;
}

class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(shape, density: 0.5, friction: BikeConfig.tireFriction, restitution: 0.05);
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
    final fixtureDef = FixtureDef(shape, density: BikeConfig.chassisDensity, friction: 0.3, restitution: 0.1);
    
    final bodyDef = BodyDef(
      userData: this, 
      position: initialPosition, 
      type: BodyType.dynamic,
      angularDamping: BikeConfig.angularDamping, // Keeps the spin under control
    );
    
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.blueAccent;
    canvas.drawRect(const Rect.fromLTRB(-2, -0.5, 2, 0.5), paint);
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

    final rearJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, rearWheel.body, rearWheel.body.position, (Vector2(-0.2, 1.0)..normalize()))
      ..dampingRatio = BikeConfig.rearDamping
      ..frequencyHz = BikeConfig.rearStiffness
      ..enableMotor = true
      ..maxMotorTorque = BikeConfig.maxMotorTorque;

    _rearJoint = WheelJoint(rearJointDef);
    world.physicsWorld.createJoint(_rearJoint);

    final frontJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, frontWheel.body, frontWheel.body.position, (Vector2(0.4, 1.0)..normalize()))
      ..dampingRatio = BikeConfig.frontDamping
      ..frequencyHz = BikeConfig.frontStiffness;

    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }

  // UPDATED: This is where the magic happens
  void updateInput(bool isGas, bool isLeft, bool isRight) {
    // 1. Motor
    if (isGas) {
      _rearJoint.enableMotor(true);
      _rearJoint.motorSpeed = BikeConfig.motorSpeed;
    } else {
      _rearJoint.enableMotor(false); 
    }

    // 2. Smooth Tilt
    if (isLeft) {
      // Counter-clockwise (Backflip)
      _chassisRef.body.applyTorque(-BikeConfig.tiltTorque);
    }
    if (isRight) {
      // Clockwise (Frontflip/Leaning forward)
      _chassisRef.body.applyTorque(BikeConfig.tiltTorque);
    }
  }

  Vector2 getChassisPosition() => _chassisRef.isLoaded ? _chassisRef.body.position : initialPosition;
}