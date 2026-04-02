import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

// --- THE BR PURIST TUNING TABLE (v1.1.4) ---
class BikeConfig {
  static const double driveForce = 2500.0;     
  static const double maxSpeed = 35.0;         
  static const double tireFriction = 1.6;
  static const double tiltTorque = 1000.0;     
  static const double angularDamping = 2.0;    

  // Suspension - These keep the bike together!
  static const double stiffness = 5.0;
  static const double damping = 0.7;
}

class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(
      shape, 
      density: 0.5, 
      friction: BikeConfig.tireFriction, 
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
    canvas.drawLine(
      Offset.zero, 
      const Offset(0.75, 0), 
      paint..strokeWidth = 0.18,
    );
  }
}

class Chassis extends BodyComponent {
  final Vector2 initialPosition;
  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(2.0, 0.5);
    final fixtureDef = FixtureDef(
      shape, 
      density: 1.2, 
      friction: 0.3, 
      restitution: 0.1,
    );
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
    canvas.drawRect(const Rect.fromLTRB(-2.0, -0.5, 2.0, 0.5), paint);
    canvas.drawRect(
      const Rect.fromLTRB(0.5, -1.0, 1.8, -0.5), 
      Paint()..color = Colors.lightBlueAccent,
    );
  }
}

class Bike extends Component with HasWorldReference<Forge2DWorld> {
  final Vector2 initialPosition;
  late Chassis _chassisRef;
  late Wheel _rearWheelRef;
  late Wheel _frontWheelRef;

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _chassisRef = Chassis(initialPosition);
    // Position wheels relative to the chassis center
    _rearWheelRef = Wheel(initialPosition + Vector2(-1.5, 1.0));
    _frontWheelRef = Wheel(initialPosition + Vector2(1.5, 1.0));

    // Add bodies to the world
    await world.addAll([_chassisRef, _rearWheelRef, _frontWheelRef]);

    // JOINTS: Physical connection using WheelJoints
    final rearJointDef = WheelJointDef()
      ..initialize(
        _chassisRef.body, 
        _rearWheelRef.body, 
        _rearWheelRef.body.position, 
        Vector2(0, 1),
      )
      ..frequencyHz = BikeConfig.stiffness
      ..dampingRatio = BikeConfig.damping
      ..enableMotor = false;

    final frontJointDef = WheelJointDef()
      ..initialize(
        _chassisRef.body, 
        _frontWheelRef.body, 
        _frontWheelRef.body.position, 
        Vector2(0, 1),
      )
      ..frequencyHz = BikeConfig.stiffness
      ..dampingRatio = BikeConfig.damping
      ..enableMotor = false;

    world.physicsWorld.createJoint(WheelJoint(rearJointDef));
    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }

  /// Checks if a wheel is actually touching the ground to prevent "air-swimming"
  bool _hasTraction(Body wheelBody) {
    for (var contactEdge = wheelBody.contacts; 
         contactEdge != null; 
         contactEdge = contactEdge.next) {
      if (contactEdge.contact.isTouching()) {
        return true;
      }
    }
    return false;
  }

  void updateInput(bool isGas, bool isLeft, bool isRight) {
    // DRIVE LOGIC: Gas only works if rear wheel is touching ground
    if (isGas && 
        _chassisRef.body.linearVelocity.length < BikeConfig.maxSpeed &&
        _hasTraction(_rearWheelRef.body)) {
      
      final angle = _chassisRef.body.angle;
      final forwardVector = Vector2(cos(angle), sin(angle));
      _rearWheelRef.body.applyForce(forwardVector * BikeConfig.driveForce);
    }

    // ROTATION LOGIC: Pure torque on chassis for mid-air/ground leaning
    if (isLeft) _chassisRef.body.applyTorque(-BikeConfig.tiltTorque);
    if (isRight) _chassisRef.body.applyTorque(BikeConfig.tiltTorque);
  }

  Vector2 getChassisPosition() => 
      _chassisRef.isLoaded ? _chassisRef.body.position : initialPosition;
}