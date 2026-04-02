import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// --- THE BR PURIST TUNING TABLE (v2.0.0) ---
class BikeConfig {
  // Drive force applied to chassis — always horizontal, always constant
  // Tune this relative to your world scale
  static const double driveForce = 1800.0;

  // Hard speed cap (world units/sec on X axis)
  static const double maxSpeed = 35.0;

  // Tire friction — this is what creates front wheel drag on loops naturally
  // Higher = more resistive normal force transferred, more realistic loop behavior
  static const double tireFriction = 1.8;

  // Rear wheel friction specifically — higher than front to bias drive traction
  static const double rearTireFriction = 2.2;

  // Tilt torque — independent of gas entirely
  static const double tiltTorque = 900.0;

  // How quickly chassis resists free-spinning on its own
  // Higher = bike wants to stay at current angle, less twitchy
  static const double angularDamping = 2.5;

  // Cosmetic wheel spin speed when gas held
  static const double wheelSpinRate = 25.0;

  // Suspension
  static const double suspensionStiffness = 6.0;
  static const double suspensionDamping   = 0.8;

  // Wheel physical properties
  static const double wheelRadius  = 0.75;
  static const double wheelDensity = 1.2;

  // Chassis physical properties
  static const double chassisHalfWidth  = 2.0;
  static const double chassisHalfHeight = 0.4;
  static const double chassisDensity    = 1.5;
}

// ─────────────────────────────────────────────────────────────
// WHEEL
// Physical contact body only.
// Propulsion has zero relationship to wheel spin.
// Wheel spin is purely cosmetic.
// Front wheel drag on loops is 100% emergent from tireFriction
// interacting with the track normal force — no special code.
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
      angularDamping: 1.0, // wheels slow their cosmetic spin naturally
    );

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  /// Cosmetic only. Spins the wheel visually when gas is pressed.
  /// Has absolutely no effect on chassis motion.
  void spinUp() {
    if (body.angularVelocity > -BikeConfig.wheelSpinRate) {
      body.applyAngularImpulse(-0.4); // negative = clockwise = forward roll
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color       = Colors.white
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.12;
    canvas.drawCircle(Offset.zero, BikeConfig.wheelRadius, paint);
    // Spoke so rotation is visible
    canvas.drawLine(
      Offset.zero,
      Offset(BikeConfig.wheelRadius, 0),
      paint..strokeWidth = 0.18,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHASSIS
// The only body that receives drive force.
// Drive force is always Vector2(driveForce, 0) —
// world X axis, constant magnitude, angle irrelevant.
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
      friction:    0.1,  // chassis itself has low friction — wheels handle grip
      restitution: 0.05,
    );

    final bodyDef = BodyDef(
      userData:       this,
      position:       initialPosition,
      type:           BodyType.dynamic,
      angularDamping: BikeConfig.angularDamping,
    );

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    // Main chassis bar
    canvas.drawRect(
      Rect.fromLTRB(
        -BikeConfig.chassisHalfWidth,
        -BikeConfig.chassisHalfHeight,
         BikeConfig.chassisHalfWidth,
         BikeConfig.chassisHalfHeight,
      ),
      Paint()..color = Colors.blueAccent,
    );
    // Rider hump — shows chassis orientation clearly
    canvas.drawRect(
      const Rect.fromLTRB(0.5, -0.9, 1.8, -0.4),
      Paint()..color = Colors.lightBlueAccent,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BIKE
// Assembles chassis + wheels via WheelJoints.
// All propulsion logic lives here.
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

    // Rear wheel has higher friction to bias traction to drive wheel
    _rearWheel  = Wheel(
      initialPosition + Vector2(-1.5, 0.9),
      friction: BikeConfig.rearTireFriction,
    );

    // Front wheel has standard friction —
    // its drag on loops is purely emergent from normal force geometry
    _frontWheel = Wheel(
      initialPosition + Vector2(1.5, 0.9),
      friction: BikeConfig.tireFriction,
    );

    await world.addAll([_chassis, _rearWheel, _frontWheel]);

    // ── Rear suspension ──────────────────────────────
    final rearJointDef = WheelJointDef()
      ..initialize(
        _chassis.body,
        _rearWheel.body,
        _rearWheel.body.position,
        Vector2(0, 1),
      )
      ..frequencyHz    = BikeConfig.suspensionStiffness
      ..dampingRatio   = BikeConfig.suspensionDamping
      ..enableMotor    = false  // motor OFF — propulsion never goes through joints
      ..motorSpeed     = 0
      ..maxMotorTorque = 0;

    // ── Front suspension ─────────────────────────────
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
  }

  // ── Traction check ───────────────────────────────
  // Checks rear wheel only — that is the drive wheel.
  // Front wheel contact is irrelevant to propulsion.
  // Uses body.contacts iterable (correct for forge2d 0.14.x)
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
  }

  // ── Input handler ────────────────────────────────
  void updateInput(bool isGas, bool isLeft, bool isRight) {

    // ── GAS ──────────────────────────────────────────
    // Constant horizontal force on chassis.
    // Vector2(driveForce, 0) — world X always, chassis angle never consulted.
    // Same force at 0°, 45° wheelie, 90° vertical, or nearly backwards.
    // Speed differences between riding styles emerge purely from:
    //   • Traction loss during tilt rotation (rear wheel briefly unloads)
    //   • Front wheel normal force drag on slopes/loops (emergent from friction)
    // No angle scaling. No power curves. Constant and simple.
    if (isGas) {
      _rearWheel.spinUp();   // cosmetic only
      _frontWheel.spinUp();  // cosmetic only

      if (_chassis.body.linearVelocity.x < BikeConfig.maxSpeed &&
          _rearHasTraction()) {
        _chassis.body.applyForce(
          Vector2(BikeConfig.driveForce, 0), // ← the whole model, right here
        );
      }
    }

    // ── TILT ─────────────────────────────────────────
    // Completely independent of gas.
    // isLeft  = lean forward (clockwise on screen = negative torque)
    // isRight = lean back   (counter-clockwise   = positive torque)
    if (isLeft)  _chassis.body.applyTorque(-BikeConfig.tiltTorque);
    if (isRight) _chassis.body.applyTorque( BikeConfig.tiltTorque);
  }

  // ── Camera target ────────────────────────────────
  Vector2 getChassisPosition() =>
      _chassis.isLoaded ? _chassis.body.position : initialPosition;
}