import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

// --- THE BR PURIST TUNING TABLE (v1.2.0) ---
class BikeConfig {
  // Propulsion: applied directly to chassis, always horizontal
  static const double driveForce = 1800.0;

  // Speed cap (meters/sec in physics world)
  static const double maxSpeed = 35.0;

  // Tire grip (affects how well wheels grip terrain)
  static const double tireFriction = 1.6;

  // Tilt controls (torque on chassis only, totally independent of gas)
  static const double tiltTorque = 900.0;

  // How quickly the chassis resists spinning on its own
  static const double angularDamping = 2.5;

  // Cosmetic wheel spin rate when gas is held
  static const double wheelSpinRate = 25.0;

  // Suspension tuning
  static const double suspensionStiffness = 6.0;
  static const double suspensionDamping = 0.8;
}

// ─────────────────────────────────────────────
// WHEEL
// Purely physical contact + cosmetic spin.
// Has NO role in propulsion whatsoever.
// ─────────────────────────────────────────────
class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(
      shape,
      density: 1.2,           // heavier wheels = more stable, less floaty
      friction: BikeConfig.tireFriction,
      restitution: 0.05,      // low bounce
    );
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
      angularDamping: 1.0,    // wheels slow their spin naturally when off gas
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  /// Cosmetic only — spins the wheel visually when gas is pressed.
  /// Has zero effect on forward motion.
  void spinUp() {
    if (body.angularVelocity > -BikeConfig.wheelSpinRate) {
      body.applyAngularImpulse(-0.4); // negative = clockwise = forward roll
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;
    canvas.drawCircle(Offset.zero, 0.75, paint);
    // Spoke line so you can see the wheel rotating
    canvas.drawLine(
      Offset.zero,
      const Offset(0.75, 0),
      paint..strokeWidth = 0.18,
    );
  }
}

// ─────────────────────────────────────────────
// CHASSIS
// This is what actually gets pushed forward.
// ─────────────────────────────────────────────
class Chassis extends BodyComponent {
  final Vector2 initialPosition;
  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(2.0, 0.4);
    final fixtureDef = FixtureDef(
      shape,
      density: 1.5,
      friction: 0.3,
      restitution: 0.05,
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
    canvas.drawRect(const Rect.fromLTRB(-2.0, -0.4, 2.0, 0.4), paint);
    // Fairing / rider hump to show orientation clearly
    canvas.drawRect(
      const Rect.fromLTRB(0.5, -0.9, 1.8, -0.4),
      Paint()..color = Colors.lightBlueAccent,
    );
  }
}

// ─────────────────────────────────────────────
// BIKE
// Wires everything together.
// ─────────────────────────────────────────────
class Bike extends Component with HasWorldReference<Forge2DWorld> {
  final Vector2 initialPosition;

  late Chassis _chassis;
  late Wheel _rearWheel;
  late Wheel _frontWheel;

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Create parts
    _chassis   = Chassis(initialPosition);
    _rearWheel = Wheel(initialPosition + Vector2(-1.5, 0.9));
    _frontWheel = Wheel(initialPosition + Vector2( 1.5, 0.9));

    await world.addAll([_chassis, _rearWheel, _frontWheel]);

    // ── Rear suspension joint ──────────────────
    final rearJointDef = WheelJointDef()
      ..initialize(
        _chassis.body,
        _rearWheel.body,
        _rearWheel.body.position,
        Vector2(0, 1),        // suspension travel axis (local Y)
      )
      ..frequencyHz   = BikeConfig.suspensionStiffness
      ..dampingRatio  = BikeConfig.suspensionDamping
      ..enableMotor   = false // ← motor OFF; propulsion is NOT through this joint
      ..motorSpeed    = 0
      ..maxMotorTorque = 0;

    // ── Front suspension joint ─────────────────
    final frontJointDef = WheelJointDef()
      ..initialize(
        _chassis.body,
        _frontWheel.body,
        _frontWheel.body.position,
        Vector2(0, 1),
      )
      ..frequencyHz   = BikeConfig.suspensionStiffness
      ..dampingRatio  = BikeConfig.suspensionDamping
      ..enableMotor   = false
      ..motorSpeed    = 0
      ..maxMotorTorque = 0;

    world.physicsWorld.createJoint(WheelJoint(rearJointDef));
    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }

  // ── Traction check ─────────────────────────
  // Only propel if at least one wheel is on the ground.
  // Uses contactList linked-list traversal (correct for Forge2D).
  bool _hasTraction(Body wheelBody) {
    var contact = wheelBody.contactList;
    while (contact != null) {
      if (contact.contact!.isTouching()) {
        final other = contact.other;
        if (other != _chassis.body &&
            other != _rearWheel.body &&
            other != _frontWheel.body) {
          return true;
        }
      }
      contact = contact.next;
    }
    return false;
  }

  // ── Main input handler ─────────────────────
  void updateInput(bool isGas, bool isLeft, bool isRight) {

    // ── GAS ────────────────────────────────────
    // Push chassis purely horizontally (world X axis).
    // Completely ignores chassis angle — just like BR.
    // Wheel spin is cosmetic only.
    if (isGas) {
      _rearWheel.spinUp();
      _frontWheel.spinUp(); // optional; BR spun both

      final speed = _chassis.body.linearVelocity.x;
      final hasTraction = _hasTraction(_rearWheel.body) ||
                          _hasTraction(_frontWheel.body);

      if (speed < BikeConfig.maxSpeed && hasTraction) {
        // ↓ THE KEY LINE: purely horizontal force on chassis, ignores tilt angle
        _chassis.body.applyForce(
          Vector2(BikeConfig.driveForce, 0), // always world-X, never world-Y
        );
      }
    }

    // ── TILT ───────────────────────────────────
    // Completely independent of gas.
    // Negative torque = lean forward (clockwise on screen).
    // Positive torque = lean back  (counter-clockwise).
    if (isLeft)  _chassis.body.applyTorque(-BikeConfig.tiltTorque);
    if (isRight) _chassis.body.applyTorque( BikeConfig.tiltTorque);
  }

  // ── Utility ───────────────────────────────
  Vector2 getChassisPosition() =>
      _chassis.isLoaded ? _chassis.body.position : initialPosition;
}