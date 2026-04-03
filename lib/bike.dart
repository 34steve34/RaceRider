import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// TUNING TABLE v3.0.0
// ─────────────────────────────────────────────────────────────
class BikeConfig {
  static const double maxSpeed           = 50.0;  // world units/sec, instant on gas
  static const double tireFriction       = 1.8;   // front wheel
  static const double rearTireFriction   = 2.2;   // rear wheel (drive wheel)
  static const double tiltTorque         = 900.0; // lean left/right
  static const double angularDamping     = 2.5;   // chassis resists free spin
  static const double wheelSpinRate      = 25.0;  // cosmetic spin speed
  static const double suspensionStiffness = 6.0;
  static const double suspensionDamping  = 0.8;
  static const double wheelRadius        = 0.75;
  static const double wheelDensity       = 1.2;
  static const double chassisHalfWidth   = 2.0;
  static const double chassisHalfHeight  = 0.4;
  static const double chassisDensity     = 1.5;
} // END BikeConfig

// ─────────────────────────────────────────────────────────────
// WHEEL
// ─────────────────────────────────────────────────────────────
class Wheel extends BodyComponent {

  final Vector2 initialPosition;
  final double friction;

  Wheel(this.initialPosition, {this.friction = BikeConfig.tireFriction});

  @override
  Body createBody() {
    final shape = CircleShape()..radius = BikeConfig.wheelRadius;
    final fixtureDef = FixtureDef(
      shape,
      density:     BikeConfig.wheelDensity,
      friction:    friction,
      restitution: 0.05,
    );
    final bodyDef = BodyDef(
      userData:       this,
      position:       initialPosition,
      type:           BodyType.dynamic,
      angularDamping: 1.0,
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  } // END createBody

  // Cosmetic only — no effect on motion
  void spinUp() {
    if (body.angularVelocity > -BikeConfig.wheelSpinRate) {
      body.applyAngularImpulse(-0.4);
    }
  } // END spinUp

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color       = Colors.white
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.12;
    canvas.drawCircle(Offset.zero, BikeConfig.wheelRadius, paint);
    canvas.drawLine(
      Offset.zero,
      Offset(BikeConfig.wheelRadius, 0),
      paint..strokeWidth = 0.18,
    );
  } // END render

} // END Wheel

// ─────────────────────────────────────────────────────────────
// CHASSIS
// ─────────────────────────────────────────────────────────────
class Chassis extends BodyComponent {

  final Vector2 initialPosition;

  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()
      ..setAsBoxXY(
        BikeConfig.chassisHalfWidth,
        BikeConfig.chassisHalfHeight,
      );
    final fixtureDef = FixtureDef(
      shape,
      density:     BikeConfig.chassisDensity,
      friction:    0.1,
      restitution: 0.05,
    );
    final bodyDef = BodyDef(
      userData:       this,
      position:       initialPosition,
      type:           BodyType.dynamic,
      angularDamping: BikeConfig.angularDamping,
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  } // END createBody

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTRB(
        -BikeConfig.chassisHalfWidth,
        -BikeConfig.chassisHalfHeight,
         BikeConfig.chassisHalfWidth,
         BikeConfig.chassisHalfHeight,
      ),
      Paint()..color = Colors.blueAccent,
    );
    canvas.drawRect(
      const Rect.fromLTRB(0.5, -0.9, 1.8, -0.4),
      Paint()..color = Colors.lightBlueAccent,
    );
  } // END render

} // END Chassis

// ─────────────────────────────────────────────────────────────
// BIKE
// ─────────────────────────────────────────────────────────────
class Bike extends Component with HasWorldReference<Forge2DWorld> {

  final Vector2 initialPosition;
  late Chassis _chassis;
  late Wheel   _rearWheel;
  late Wheel   _frontWheel;

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _chassis    = Chassis(initialPosition);
    _rearWheel  = Wheel(
      initialPosition + Vector2(-1.5, 0.9),
      friction: BikeConfig.rearTireFriction,
    );
    _frontWheel = Wheel(
      initialPosition + Vector2(1.5, 0.9),
    );

    await world.addAll([_chassis, _rearWheel, _frontWheel]);

    final rearJointDef = WheelJointDef()
      ..initialize(
        _chassis.body,
        _rearWheel.body,
        _rearWheel.body.position,
        Vector2(0, 1),
      )
      ..frequencyHz    = BikeConfig.suspensionStiffness
      ..dampingRatio   = BikeConfig.suspensionDamping
      ..enableMotor    = false
      ..motorSpeed     = 0
      ..maxMotorTorque = 0;

    final frontJointDef = WheelJointDef()
      ..initialize(
        _chassis.body,
        _frontWheel.body,
        _frontWheel.body.position,
        Vector2(0, 1),
      )
      ..frequencyHz    = BikeConfig.suspensionStiffness
      ..dampingRatio   = BikeConfig.suspensionDamping
      ..enableMotor    = false
      ..motorSpeed     = 0
      ..maxMotorTorque = 0;

    world.physicsWorld.createJoint(WheelJoint(rearJointDef));
    world.physicsWorld.createJoint(WheelJoint(frontJointDef));

  } // END onLoad

  bool _rearHasTraction() {
    for (final contact in _rearWheel.body.contacts) {
      if (contact.isTouching()) {
        final bodyA = contact.fixtureA.body;
        final bodyB = contact.fixtureB.body;
        final other = (bodyA == _rearWheel.body) ? bodyB : bodyA;
        if (other != _chassis.body &&
            other != _frontWheel.body &&
            other != _rearWheel.body) {
          return true;
        }
      }
    }
    return false;
  } // END _rearHasTraction

  void updateInput(bool isGas, bool isLeft, bool isRight) {

    // ── GAS ──────────────────────────────────────────
    // Instantly sets X velocity to maxSpeed — zero lag.
    // Y velocity preserved so jumps and gravity are unaffected.
    // No traction = no drive, physics takes over completely.
    if (isGas && _rearHasTraction()) {
      _rearWheel.spinUp();
      _frontWheel.spinUp();
      final vel = _rearWheel.body.linearVelocity;
      _rearWheel.body.linearVelocity = Vector2(BikeConfig.maxSpeed, vel.y);
    } // END if isGas

    // ── TILT ─────────────────────────────────────────
    // Fully independent of gas. Torque only, never affects drive.
    if (isLeft)  _chassis.body.applyTorque(-BikeConfig.tiltTorque);
    if (isRight) _chassis.body.applyTorque( BikeConfig.tiltTorque);

  } // END updateInput

  Vector2 getChassisPosition() =>
      _chassis.isLoaded ? _chassis.body.position : initialPosition;

} // END Bike