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
  static const double suspensionRestLength = 0.3;
  static const double suspensionMaxCompression = 0.5;
  static const double suspensionStiffness = 800.0;
  static const double suspensionDamping = 50.0;
  static const double breakImpactVelocity = 20.0;
  
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
    
    // Calculate wheel attachment points in world space
    final frontAttachLocal = Vector2(BikeConfig.wheelBase / 2, BikeConfig.chassisHeight);
    final rearAttachLocal = Vector2(-BikeConfig.wheelBase / 2, BikeConfig.chassisHeight);
    
    final frontAttachWorld = _localToWorld(frontAttachLocal, chassisPos, chassisAngle);
    final rearAttachWorld = _localToWorld(rearAttachLocal, chassisPos, chassisAngle);
    
    // Raycast down from each wheel to find ground
    _frontWheelGrounded = false;
    _rearWheelGrounded = false;
    
    final rayLength = BikeConfig.wheelRadius + BikeConfig.suspensionRestLength + BikeConfig.suspensionMaxCompression;
    
    // Front wheel raycast
    final frontResult = _raycastWheel(frontAttachWorld, chassisAngle, rayLength);
    if (frontResult != null) {
      _frontWheelGrounded = true;
      _frontWheelCompression = frontResult['compression'] as double;
      _frontWheelWorldPos = frontResult['wheelPos'] as Vector2;
      _groundNormal = frontResult['normal'] as Vector2;
      _groundPoint = frontResult['contactPoint'] as Vector2;
      _impactVelocity = frontResult['impactVelocity'] as double;
      
      // Apply suspension force
      _applySuspensionForce(frontAttachWorld, _frontWheelWorldPos, _frontWheelCompression, true);
    } else {
      _frontWheelCompression = 0.0;
      _frontWheelWorldPos = frontAttachWorld + Vector2(0, BikeConfig.wheelRadius + BikeConfig.suspensionRestLength);
    }
    
    // Rear wheel raycast
    final rearResult = _raycastWheel(rearAttachWorld, chassisAngle, rayLength);
    if (rearResult != null) {
      _rearWheelGrounded = true;
      _rearWheelCompression = rearResult['compression'] as double;
      _rearWheelWorldPos = rearResult['wheelPos'] as Vector2;
      if (!_frontWheelGrounded) {
        _groundNormal = rearResult['normal'] as Vector2;
        _groundPoint = rearResult['contactPoint'] as Vector2;
      }
      
      _applySuspensionForce(rearAttachWorld, _rearWheelWorldPos, _rearWheelCompression, false);
    } else {
      _rearWheelCompression = 0.0;
      _rearWheelWorldPos = rearAttachWorld + Vector2(0, BikeConfig.wheelRadius + BikeConfig.suspensionRestLength);
    }
    
    // Check for break impact
    if (_impactVelocity > BikeConfig.breakImpactVelocity) {
      _isCrashed = true;
    }
  }
  
  Map<String, dynamic>? _raycastWheel(Vector2 attachPoint, double chassisAngle, double rayLength) {
    // Ray direction: down relative to bike rotation
    final rayDir = Vector2(
      math.sin(chassisAngle),
      math.cos(chassisAngle),
    );
    
    final rayEnd = attachPoint + rayDir * rayLength;
    
    // Perform raycast
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
  
  void _applySuspensionForce(Vector2 attachPoint, Vector2 wheelPos, double compression, bool isFront) {
    if (compression <= 0) return;
    
    // Suspension force pushes chassis up
    final springForce = compression * BikeConfig.suspensionStiffness;
    final dampingForce = body.linearVelocity.y * BikeConfig.suspensionDamping;
    
    final totalForce = springForce - dampingForce;
    final forceDir = -_groundNormal; // Push away from ground
    
    body.applyForce(forceDir * totalForce);
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
    
    // Normalize
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    final isGrounded = _frontWheelGrounded || _rearWheelGrounded;
    final maxRotSpeed = isGrounded 
        ? BikeConfig.maxAngularVelocity 
        : BikeConfig.airAngularVelocity;
    
    final desiredAngularVelocity = (angleDiff * 4.0).clamp(-maxRotSpeed, maxRotSpeed);
    body.angularVelocity = desiredAngularVelocity;
  }

  // ─────────────────────────────────────────────────────────────
  // GROUND SNAP
  // ─────────────────────────────────────────────────────────────
  void _applyGroundSnap() {
    if (!_frontWheelGrounded && !_rearWheelGrounded) return;
    
    // Align bike to ground normal
    final groundAngle = math.atan2(-_groundNormal.x, -_groundNormal.y);
    var angleDiff = groundAngle - body.angle;
    
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    if (angleDiff.abs() > 0.05) {
      final snapTorque = angleDiff * BikeConfig.groundSnapSpeed;
      body.angularVelocity += snapTorque * 0.016;
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
  Vector2 get frontWheelPosition => _frontWheelWorldPos.clone();
  Vector2 get rearWheelPosition => _rearWheelWorldPos.clone();
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
    
    // Rider
    canvas.drawRect(
      const Rect.fromLTRB(0.3, -1.0, 1.2, -0.3),
      Paint()..color = Colors.lightBlueAccent,
    );
    
    // Head
    canvas.drawCircle(
      Offset(BikeConfig.headOffsetX, BikeConfig.headOffsetY),
      BikeConfig.headRadius,
      Paint()..color = Colors.orange,
    );
    
    // Wheels (visual with compression)
    final wheelPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;
    
    // Front wheel
    final frontWheelLocal = _worldToLocal(_frontWheelWorldPos, body.position, body.angle);
    canvas.drawCircle(
      Offset(frontWheelLocal.x, frontWheelLocal.y),
      BikeConfig.wheelRadius,
      wheelPaint,
    );
    
    // Rear wheel
    final rearWheelLocal = _worldToLocal(_rearWheelWorldPos, body.position, body.angle);
    canvas.drawCircle(
      Offset(rearWheelLocal.x, rearWheelLocal.y),
      BikeConfig.wheelRadius,
      wheelPaint,
    );
    
    // Debug: grounded indicator
    if (isGrounded) {
      canvas.drawCircle(Offset.zero, 0.2, Paint()..color = Colors.green);
    }
    
    // Debug: crashed
    if (_isCrashed) {
      canvas.drawRect(
        Rect.fromLTRB(-2, -1.5, 2, 1.5),
        Paint()..color = Colors.red.withOpacity(0.7),
      );
    }
  }
  
  Vector2 _worldToLocal(Vector2 world, Vector2 bodyPos, double angle) {
    final dx = world.x - bodyPos.x;
    final dy = world.y - bodyPos.y;
    final cos = math.cos(-angle);
    final sin = math.sin(-angle);
    return Vector2(dx * cos - dy * sin, dx * sin + dy * cos);
  }
}

// ─────────────────────────────────────────────────────────────
// RAYCAST CALLBACK FOR WHEELS
// ─────────────────────────────────────���───────────────────────
class _WheelRaycastCallback extends RayCastCallback {
  bool hit = false;
  double compression = 0.0;
  Vector2 wheelPos = Vector2.zero();
  Vector2 normal = Vector2(0, -1);
  Vector2 contactPoint = Vector2.zero();
  double impactVelocity = 0.0;
  
  final Vector2 _startPoint;
  final Vector2 _rayDir;
  final double _rayLength;
  
  _WheelRaycastCallback(this._startPoint, this._rayDir, this._rayLength);
  
  @override
  double reportFixture(Fixture fixture, Vector2 point, Vector2 normal, double fraction) {
    // Skip if it's the bike itself
    if (fixture.body.userData is Bike) return -1;
    
    hit = true;
    contactPoint = point.clone();
    this.normal = normal.clone();
    
    // Calculate compression
    final distance = (point - _startPoint).length;
    final restDistance = BikeConfig.wheelRadius + BikeConfig.suspensionRestLength;
    compression = (restDistance - distance + BikeConfig.wheelRadius).clamp(0.0, BikeConfig.suspensionMaxCompression);
    
    // Wheel position (on surface)
    wheelPos = point + normal * BikeConfig.wheelRadius;
    
    // Estimate impact velocity (simplified)
    impactVelocity = 0.0; // Would need body velocity at wheel point
    
    return fraction; // Continue to find closest
  }
}