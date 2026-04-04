import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────
// BIKE CONFIG - PUPPET PHYSICS MODEL
// ─────────────────────────────────────────────────────────────
class BikeConfig {
  // Movement
  static const double maxSpeed = 45.0;        // World units/sec
  static const double uphillSpeedFactor = 0.6; // Speed multiplier going uphill
  static const double downhillSpeedFactor = 1.3; // Speed multiplier going downhill
  
  // Rotation (radians/sec)
  static const double maxAngularVelocity = 8.0;  // How fast bike rotates to target
  static const double airAngularVelocity = 6.0;  // Slightly slower in air
  static const double groundSnapSpeed = 12.0;    // How fast bike snaps to ground
  
  // Dimensions
  static const double wheelRadius = 0.75;
  static const double wheelBase = 3.0;           // Distance between wheels
  static const double chassisWidth = 2.5;
  static const double chassisHeight = 0.5;
  static const double headOffsetX = 1.8;         // Head position from center
  static const double headOffsetY = -1.0;        // Head above chassis
  static const double headRadius = 0.4;
  
  // Physics
  static const double bikeMass = 1.0;
  static const double groundSnapStrength = 50.0; // Force pulling wheels to ground
  static const double microGravityStrength = 20.0; // Magnetic pull when grounded
  
  // Crash detection
  static const double headCrashVelocity = 5.0;   // Min velocity for head crash
  static const double wheelCrashVelocity = 15.0; // Min velocity for wheel crash
}

// ─────────────────────────────────────────────────────────────
// BIKE - SINGLE BODY PUPPET PHYSICS
// ─────────────────────────────────────────────────────────────
class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  // Control state
  double _targetAngle = 0.0;
  bool _isGasPressed = false;
  
  // Ground contact state
  bool _frontWheelGrounded = false;
  bool _rearWheelGrounded = false;
  Vector2 _groundNormal = Vector2(0, -1);
  Vector2 _groundPoint = Vector2.zero();
  
  // Crash state
  bool _isCrashed = false;

  Bike({required this.initialPosition});

  @override
  Body createBody() {
    // Create a single rectangular body for the entire bike
    final shape = PolygonShape()
      ..setAsBoxXY(
        BikeConfig.chassisWidth,
        BikeConfig.chassisHeight,
      );
    
    final fixtureDef = FixtureDef(
      shape,
      density: BikeConfig.bikeMass,
      friction: 0.0,    // We handle friction ourselves
      restitution: 0.1, // Slight bounce
    );
    
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
      fixedRotation: false,
      angularDamping: 0.0,
      linearDamping: 0.0,
    );
    
    final body = world.createBody(bodyDef)..createFixture(fixtureDef);
    
    // Add wheel sensors (for ground detection only)
    _addWheelSensor(body, isFront: true);
    _addWheelSensor(body, isFront: false);
    
    // Add head sensor
    _addHeadSensor(body);
    
    return body;
  }
  
  void _addWheelSensor(Body body, {required bool isFront}) {
    final offsetX = isFront 
        ? BikeConfig.wheelBase / 2 
        : -BikeConfig.wheelBase / 2;
    
    final shape = CircleShape()
      ..radius = BikeConfig.wheelRadius
      ..position.setValues(offsetX, BikeConfig.wheelRadius);
    
    final fixtureDef = FixtureDef(
      shape,
      isSensor: true,  // Sensor only - no collision response
      userData: isFront ? 'frontWheel' : 'rearWheel',
    );
    
    body.createFixture(fixtureDef);
  }
  
  void _addHeadSensor(Body body) {
    final shape = CircleShape()
      ..radius = BikeConfig.headRadius
      ..position.setValues(BikeConfig.headOffsetX, BikeConfig.headOffsetY);
    
    final fixtureDef = FixtureDef(
      shape,
      isSensor: true,
      userData: 'head',
    );
    
    body.createFixture(fixtureDef);
  }

  // Called every frame from game.update()
  void updateControl(double phoneTiltAngle, bool isGasPressed) {
    if (_isCrashed) return;
    
    _targetAngle = phoneTiltAngle;
    _isGasPressed = isGasPressed;
    
    // Update ground contact state
    _updateGroundContact();
    
    // Apply puppet physics
    _applyRotationControl();
    _applyGroundSnap();
    _applyMicroGravity();
    _applyDriveForce();
  }
  
  void _updateGroundContact() {
    _frontWheelGrounded = false;
    _rearWheelGrounded = false;
    
    // Check contacts for wheel sensors
    for (final contact in body.contacts) {
      if (!contact.isTouching()) continue;
      
      final fixtureA = contact.fixtureA;
      final fixtureB = contact.fixtureB;
      
      final userDataA = fixtureA.userData;
      final userDataB = fixtureB.userData;
      
      // Check if either fixture is a wheel sensor
      if (userDataA == 'frontWheel' || userDataB == 'frontWheel') {
        _frontWheelGrounded = true;
        _extractGroundInfo(contact);
      }
      if (userDataA == 'rearWheel' || userDataB == 'rearWheel') {
        _rearWheelGrounded = true;
        _extractGroundInfo(contact);
      }
      
      // Check for head crash
      if (userDataA == 'head' || userDataB == 'head') {
        _checkHeadCrash(contact);
      }
    }
  }
  
  void _extractGroundInfo(Contact contact) {
    // Get the world manifold to find contact normal
    final worldManifold = WorldManifold();
    contact.getWorldManifold(worldManifold);
    if (worldManifold.points.isNotEmpty) {
      _groundNormal.setFrom(worldManifold.normal);
      _groundPoint.setFrom(worldManifold.points[0]);
    }
  }
  
  void _checkHeadCrash(Contact contact) {
    final velocity = body.linearVelocity;
    final speed = velocity.length;
    
    // Check relative velocity at head
    if (speed > BikeConfig.headCrashVelocity) {
      _isCrashed = true;
      // TODO: Trigger crash animation/restart
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ROTATION CONTROL - Player angle matching
  // ─────────────────────────────────────────────────────────────
  void _applyRotationControl() {
    final currentAngle = body.angle;
    final angleDiff = _targetAngle - currentAngle;
    
    // Normalize angle difference to -pi to +pi
    var normalizedDiff = angleDiff;
    while (normalizedDiff > math.pi) normalizedDiff -= 2 * math.pi;
    while (normalizedDiff < -math.pi) normalizedDiff += 2 * math.pi;
    
    // Determine max rotation speed based on grounded state
    final isGrounded = _frontWheelGrounded || _rearWheelGrounded;
    final maxRotSpeed = isGrounded 
        ? BikeConfig.maxAngularVelocity 
        : BikeConfig.airAngularVelocity;
    
    // Calculate desired angular velocity to reach target
    // Simple proportional control
    final desiredAngularVelocity = (normalizedDiff * 4.0).clamp(-maxRotSpeed, maxRotSpeed);
    
    // Directly set angular velocity (puppet physics!)
    body.angularVelocity = desiredAngularVelocity;
  }

  // ─────────────────────────────────────────────────────────────
  // GROUND SNAP - Active correction when wheels touch
  // ─────────────────────────────────────────────────────────────
  void _applyGroundSnap() {
    if (!_frontWheelGrounded && !_rearWheelGrounded) return;
    
    // Calculate angle to ground normal
    // Ground normal points away from surface, so bike should align perpendicular to it
    final groundAngle = math.atan2(-_groundNormal.x, -_groundNormal.y);
    
    // If bike angle is significantly different from ground angle, snap toward it
    final angleDiff = groundAngle - body.angle;
    var normalizedDiff = angleDiff;
    while (normalizedDiff > math.pi) normalizedDiff -= 2 * math.pi;
    while (normalizedDiff < -math.pi) normalizedDiff += 2 * math.pi;
    
    // Apply snap force (this fights against player control)
    // The snap is stronger the more crooked the landing
    if (normalizedDiff.abs() > 0.1) {
      final snapTorque = normalizedDiff * BikeConfig.groundSnapSpeed;
      body.angularVelocity += snapTorque * 0.016; // Approximate dt
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MICRO GRAVITY - Magnetic pull to track
  // ─────────────────────────────────────────────────────────────
  void _applyMicroGravity() {
    if (!_frontWheelGrounded && !_rearWheelGrounded) return;
    
    // Apply force toward ground point
    final bikePos = body.position;
    final toGround = _groundPoint - bikePos;
    final distance = toGround.length;
    
    if (distance > 0.1) {
      final pullForce = toGround.normalized() * BikeConfig.microGravityStrength;
      body.applyForce(pullForce);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DRIVE FORCE - Instant speed with hill adjustment
  // ─────────────────────────────────────────────────────────────
  void _applyDriveForce() {
    if (!_isGasPressed) return;
    if (!_rearWheelGrounded) return; // Need traction
    
    // Calculate speed based on slope
    final bikeAngle = body.angle;
    final slopeFactor = math.cos(bikeAngle); // 1.0 = flat, 0 = vertical
    
    double targetSpeed;
    if (slopeFactor > 0) {
      // Going uphill or flat
      targetSpeed = BikeConfig.maxSpeed * (0.5 + 0.5 * slopeFactor);
    } else {
      // Going downhill (bike pointing down)
      targetSpeed = BikeConfig.maxSpeed * BikeConfig.downhillSpeedFactor;
    }
    
    // Instant velocity set (BR style)
    final currentVel = body.linearVelocity;
    body.linearVelocity = Vector2(
      targetSpeed * math.cos(bikeAngle),
      currentVel.y, // Preserve Y velocity (gravity, jumps)
    );
  }

  Vector2 get bodyPosition => body.position.clone();
  
  bool get isGrounded => _frontWheelGrounded || _rearWheelGrounded;
  bool get isCrashed => _isCrashed;

  @override
  void render(Canvas canvas) {
    // Chassis
    canvas.drawRect(
      Rect.fromLTRB(
        -BikeConfig.chassisWidth,
        -BikeConfig.chassisHeight,
        BikeConfig.chassisWidth,
        BikeConfig.chassisHeight,
      ),
      Paint()..color = Colors.blueAccent,
    );
    
    // Rider area (lighter blue)
    canvas.drawRect(
      const Rect.fromLTRB(0.5, -1.2, 1.5, -0.4),
      Paint()..color = Colors.lightBlueAccent,
    );
    
    // Head
    canvas.drawCircle(
      Offset(BikeConfig.headOffsetX, BikeConfig.headOffsetY),
      BikeConfig.headRadius,
      Paint()..color = Colors.orange,
    );
    
    // Wheels (visual only)
    final wheelPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.15;
    
    // Front wheel
    canvas.drawCircle(
      Offset(BikeConfig.wheelBase / 2, BikeConfig.wheelRadius),
      BikeConfig.wheelRadius,
      wheelPaint,
    );
    
    // Rear wheel
    canvas.drawCircle(
      Offset(-BikeConfig.wheelBase / 2, BikeConfig.wheelRadius),
      BikeConfig.wheelRadius,
      wheelPaint,
    );
    
    // Debug: show ground contact
    if (_frontWheelGrounded || _rearWheelGrounded) {
      final debugPaint = Paint()
        ..color = Colors.green.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, 0.3, debugPaint);
    }
    
    // Debug: show crash
    if (_isCrashed) {
      final crashPaint = Paint()
        ..color = Colors.red.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTRB(-3, -2, 3, 2),
        crashPaint,
      );
    }
  }
}