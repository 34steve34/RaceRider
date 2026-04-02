import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// --- THE TUNING TABLE (v1.1.0) ---
class BikeConfig {
  static const double maxMotorTorque = 120.0;  
  static const double motorSpeed = 40.0;      
  static const double tireFriction = 1.6;      
  
  // ANTI-WHEELIE SETTINGS
  static const double chassisDensity = 2.5;    // Heavier chassis = harder to lift
  static const double angularDamping = 2.0;    // More resistance to accidental rotation
  
  // TILT SETTINGS
  static const double tiltTorque = 900.0;      
  
  // Suspension
  static const double rearStiffness = 5.0; 
  static const double rearDamping = 0.5;
  static const double frontStiffness = 6.0; 
  static const double frontDamping = 0.6;
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
    // Making the box slightly wider (2.5 instead of 2.0) to stabilize the center of gravity
    final shape = PolygonShape()..setAsBoxXY(2.5, 0.5);
    final fixtureDef = FixtureDef(shape, density: BikeConfig.chassisDensity, friction: 0.3, restitution: 0.1);
    
    final bodyDef = BodyDef(
      userData: this, 
      position: initialPosition, 
      type: BodyType.dynamic,
      angularDamping: BikeConfig.angularDamping,
    );
    
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.blueAccent;
    canvas.drawRect(const Rect.fromLTRB(-2.5, -0.5, 2.5, 0.5), paint);
    // Front Windshield (on the right)
    canvas.drawRect(const Rect.fromLTRB(1.0, -1.0, 2.3, -0.5), Paint()..color = Colors.lightBlueAccent);
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
    // Spread the wheels further apart to prevent the wheelie
    final rearWheel = Wheel(initialPosition + Vector2(-2.0, 1.2));
    final frontWheel = Wheel(initialPosition + Vector2(2.0, 1.2));

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

  void updateInput(bool isGas, bool isLeft, bool isRight) {
    if (isGas) {
      _rearJoint.enableMotor(true);
      _rearJoint.motorSpeed = BikeConfig.motorSpeed;
    } else {
      _rearJoint.enableMotor(false); 
    }

    if (isLeft) {
      _chassisRef.body.applyTorque(-BikeConfig.tiltTorque);
    }
    if (isRight) {
      _chassisRef.body.applyTorque(BikeConfig.tiltTorque);
    }
  }

  Vector2 getChassisPosition() => _chassisRef.isLoaded ? _chassisRef.body.position : initialPosition;
}