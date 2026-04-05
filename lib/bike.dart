import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────
// BIKE CONFIG - PUPPET PHYSICS MODEL
// ─────────────────────────────────────────────────────────────
class BikeConfig {
  // Movement
  static const double maxSpeed = 45.0;
  
  // Rotation (radians/sec)
  static const double maxAngularVelocity = 8.0;
  static const double airAngularVelocity = 6.0;
  static const double groundSnapSpeed = 12.0;
  
  // Dimensions
  static const double wheelRadius = 0.6;
  static const double wheelBase = 2.8;
  static const double chassisWidth = 2.0;
  static const double chassisHeight = 0.4;
  static const double headOffsetX = 1.5;
  static const double headOffsetY = -0.8;
  static const double headRadius = 0.35;
  
  // Suspension
  static const double suspensionRestLength = 0.4;
  static const double suspensionMaxCompression = 0.6;
  static const double suspensionStiffness = 2500.0;
  static const double suspensionDamping = 80.0;
  static const double breakImpactVelocity = 25.0;
  
  // Physics
  static const double bikeMass = 2.0;
  static const double microGravityStrength = 30.0;
  
  // Brake
  static const double brakeDeceleration = 30.0;
}

// ─────────────────────────────────────────────────────────────
// BIKE - HYBRID PUPPET PHYSICS
// ─────────────────────────────────────────────────────────────
class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  // Control state
  double _targetAngle = 0.0;
  bool _isGasPressed = false;
  bool _isBrakePressed = false;
  bool _inputLocked = false; // First-touch priority
  
  // Wheel state
  double _frontWheelCompression = 0.0;
  double _rearWheelCompression = 0.0;
  bool _frontWheelGrounded = false;
  bool _rearWheelGrounded = false;
  Vector2 _frontWheelWorldPos = Vector2.zero();
  Vector2 _rearWheelWorldPos = Vector2.zero();
  
  // Ground info
  Vector2 _groundNormal = Vector2(0, -1);
  Vector2 _groundPoint = Vector2.zero();
  
  // Crash state
  bool _isCrashed = false;
  double _impactVelocity = 0.0;

  Bike({required this.initialPosition});

  @override
  Body createBody() {
    // Main chassis body - centered mass
    final chassisShape = PolygonShape()
      ..setAsBoxXY(BikeConfig.chassisWidth, BikeConfig.chassisHeight);
    
    final chassisFixture = FixtureDef(
      chassisShape,
      density: BikeConfig.bikeMass,
      friction: 0.0,
      restitution: 0.0,
    );
    
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
      fixedRotation: false,
      angularDamping: 0.0,
      linearDamping: 0.0,
    );
    
    final body = world.createBody(bodyDef)..createFixture(chassisFixture);
    
    // Add head sensor
    final headShape = CircleShape()
      ..radius = BikeConfig.headRadius
      ..position.setValues(BikeConfig.headOffsetX, BikeConfig.headOffsetY);
    
    body.createFixture(FixtureDef(headShape, isSensor: true, userData: 'head'));
    
    return body;
  }

  // Called every frame from game.update()
  void updateControl(double phoneTiltAngle, bool isGas, bool isBrake) {
    if (_isCrashed) return;
    
    _targetAngle = phoneTiltAngle;
    
    // First-touch priority for gas/brake
    if (!_inputLocked) {
      if (isGas) {
        _isGasPressed = true;
        _isBrakePressed = false;
        _inputLocked = true;
      } else if (isBrake) {
        _isBrakePressed = true;
        _isGasPressed = false;
        _inputLocked = true;
      }
    } else {
      // Keep current input until both are released
      if (!isGas && !isBrake) {
        _isGasPressed = false;
        _isBrakePressed = false;
        _inputLocked = false;
      }
    }
    
    // Update wheel positions and check ground
    _updateWheelPhysics();
    
    // Apply puppet physics
    _applyRotationControl();
    _applyGroundSnap();
    _applyDriveForce();
    _applyBrakeForce();
  }
  
  // ─────────────────────────────────────────────────────────────
  // WHEEL PHYSICS - Manual simulation
  // ─────────────────────────────────────────────────────────────
  void _updateWheelPhysics() {
    final chassisPos = body.position;
    final chassisAngle = body.angle;
    
    // Start the suspension exactly at the edge of the chassis
    final frontAttachLocal = Vector2(BikeConfig.wheelBase / 2, BikeConfig.chassisHeight);
    final rearAttachLocal = Vector2(-BikeConfig.wheelBase / 2, BikeConfig.chassisHeight);
    
    final frontAttachWorld = _localToWorld(frontAttachLocal, chassisPos, chassisAngle);
    final rearAttachWorld = _localToWorld(rearAttachLocal, chassisPos, chassisAngle);
    
    _frontWheelGrounded = false;
    _rearWheelGrounded = false;
    
    // Total reach of the leg is the suspension + the wheel itself
    final rayLength = BikeConfig.suspensionRestLength + BikeConfig.suspensionMaxCompression + BikeConfig.wheelRadius;
    
    // Calculate "down" relative to the bike's current rotation (crucial for the loop)
    final cosA = math.cos(chassisAngle);
    final sinA = math.sin(chassisAngle);
    final rayDir = Vector2(-sinA, cosA); 
    
    // The local UP vector of the bike (the direction the struts push)
    final springDir = Vector2(sinA, -cosA);
    
    // Front wheel raycast
    final frontResult = _raycastWheel(frontAttachWorld, rayDir, rayLength);
    if (frontResult != null) {
      _frontWheelGrounded = true;
      _frontWheelCompression = frontResult['compression'] as double;
      _frontWheelWorldPos = frontResult['wheelPos'] as Vector2;
      _groundNormal = frontResult['normal'] as Vector2;
      _groundPoint = frontResult['contactPoint'] as Vector2;
      _impactVelocity = frontResult['impactVelocity'] as double;
      
      _applySuspensionForce(frontAttachWorld, _frontWheelWorldPos, _frontWheelCompression, true, springDir);
    } else {
      _frontWheelCompression = 0.0;
      _frontWheelWorldPos = frontAttachWorld + (rayDir * (BikeConfig.suspensionRestLength + BikeConfig.wheelRadius));
    }
    
    // Rear wheel raycast
    final rearResult = _raycastWheel(rearAttachWorld, rayDir, rayLength);
    if (rearResult != null) {
      _rearWheelGrounded = true;
      _rearWheelCompression = rearResult['compression'] as double;
      _rearWheelWorldPos = rearResult['wheelPos'] as Vector2;
      if (!_frontWheelGrounded) {
        _groundNormal = rearResult['normal'] as Vector2;
        _groundPoint = rearResult['contactPoint'] as Vector2;
      }
      
      _applySuspensionForce(rearAttachWorld, _rearWheelWorldPos, _rearWheelCompression, false, springDir);
    } else {
      _rearWheelCompression = 0.0;
      _rearWheelWorldPos = rearAttachWorld + (rayDir * (BikeConfig.suspensionRestLength + BikeConfig.wheelRadius));
    }
    
    if (_impactVelocity > BikeConfig.breakImpactVelocity) {
      _isCrashed = true;
    }
  }
  
  Map<String, dynamic>? _raycastWheel(Vector2 attachPoint, Vector2 rayDir, double rayLength) {
    final rayEnd = attachPoint + (rayDir * rayLength);
    final callback = _WheelRaycastCallback(attachPoint, rayDir, rayLength);
    world.physicsWorld.raycast(callback, attachPoint, rayEnd);
    
    if (callback.hit) {
      return {
        'compression': callback.compression,
        'wheelPos': callback.wheelPos,
        'normal': callback.normal,
        'contactPoint': callback.contactPoint,
        'impactVelocity': callback.impactVelocity,
      };
    }
    return null;
  }
  
  void _applySuspensionForce(Vector2 attachPoint, Vector2 wheelPos, double compression, bool isFront, Vector2 springDir) {
    if (compression <= 0) return;
    
    final springForce = compression * BikeConfig.suspensionStiffness;
    
    // CRITICAL: Get velocity at the EXACT wheel attachment point, not the center!
    final attachVel = body.getLinearVelocityFromWorldPoint(attachPoint);
    
    // Dampen against the suspension axis
    final velAlongStrut = attachVel.dot(springDir); 
    final dampingForce = velAlongStrut * BikeConfig.suspensionDamping;
    
    final totalForce = springForce - dampingForce;
    
    // The suspension can only push the bike UP, it cannot pull it down.
    if (totalForce > 0) {
      body.applyForce(springDir * totalForce, point: attachPoint);
    }
  }
  
  Vector2 _localToWorld(Vector2 local, Vector2 worldPos, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector2(
      worldPos.x + local.x * cos - local.y * sin,
      worldPos.y + local.x * sin + local.y * cos,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ROTATION CONTROL
  // ─────────────────────────────────────────────────────────────
  void _applyRotationControl() {
    final currentAngle = body.angle;
    var angleDiff = _targetAngle - currentAngle;
    
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    // Use a PD controller to apply torque. 
    // This lets the bike tilt, but lets physics react to track bumps naturally!
    final p = 80.0; // Spring strength to target angle
    final d = 10.0; // Dampening so it doesn't jitter
    
    final torque = (angleDiff * p) - (body.angularVelocity * d);
    body.applyTorque(torque);
  }

  // ─────────────────────────────────────────────────────────────
  // GROUND SNAP
  // ─────────────────────────────────────────────────────────────
  void _applyGroundSnap() {
    if (!_frontWheelGrounded && !_rearWheelGrounded) return;
    
    final groundAngle = math.atan2(-_groundNormal.x, -_groundNormal.y);
    var angleDiff = groundAngle - body.angle;
    
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    if (angleDiff.abs() > 0.05) {
      // Apply torque instead of forcefully modifying angularVelocity
      final snapTorque = angleDiff * BikeConfig.groundSnapSpeed * 5.0; 
      body.applyTorque(snapTorque);
    }
    
    // Micro-gravity pull toward ground
    final bikePos = body.position;
    final toGround = _groundPoint - bikePos;
    if (toGround.length > 0.1) {
      body.applyForce(toGround.normalized() * BikeConfig.microGravityStrength);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DRIVE FORCE
  // ─────────────────────────────────────────────────────────────
  void _applyDriveForce() {
    if (!_isGasPressed) return;
    if (!_rearWheelGrounded) return;
    
    final bikeAngle = body.angle;
    final slopeFactor = math.cos(bikeAngle);
    
    double targetSpeed;
    if (slopeFactor > 0) {
      targetSpeed = BikeConfig.maxSpeed * (0.5 + 0.5 * slopeFactor);
    } else {
      targetSpeed = BikeConfig.maxSpeed * 1.3;
    }
    
    final currentVel = body.linearVelocity;
    body.linearVelocity = Vector2(
      targetSpeed * math.cos(bikeAngle),
      currentVel.y,
    );
  }
  
  // ─────────────────────────────────────────────────────────────
  // BRAKE FORCE
  // ─────────────────────────────────────────────────────────────
  void _applyBrakeForce() {
    if (!_isBrakePressed) return;
    if (!_frontWheelGrounded && !_rearWheelGrounded) return;
    
    final currentVel = body.linearVelocity;
    final speed = currentVel.length;
    
    if (speed < 0.5) {
      body.linearVelocity = Vector2.zero();
      return;
    }
    
    // Decelerate in opposite direction of movement
    final decel = currentVel.normalized() * (-BikeConfig.brakeDeceleration * 0.016);
    body.linearVelocity = currentVel + decel;
  }

  Vector2 get bodyPosition => body.position.clone();
  Vector2 get frontWheelPosition => _frontWheelWorldPos.