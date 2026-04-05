import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────
// BIKE CONFIG
// ─────────────────────────────────────────────────────────────
class BikeConfig {
  static const double maxSpeed = 45.0;
  static const double maxAngularVelocity = 8.0;
  static const double airAngularVelocity = 6.0;
  static const double groundSnapSpeed = 12.0;
  
  static const double wheelRadius = 0.6;
  static const double wheelBase = 2.8;
  static const double chassisWidth = 2.0;
  static const double chassisHeight = 0.4;
  static const double headOffsetX = 1.5;
  static const double headOffsetY = -0.8;
  static const double headRadius = 0.35;
  
  static const double suspensionRestLength = 0.4;
  static const double suspensionMaxCompression = 0.6;
  static const double suspensionStiffness = 2500.0;
  static const double suspensionDamping = 80.0;
  static const double breakImpactVelocity = 25.0;
  
  static const double bikeMass = 2.0;
  static const double microGravityStrength = 30.0;
  static const double brakeDeceleration = 30.0;
}

// ─────────────────────────────────────────────────────────────
// BIKE COMPONENT
// ─────────────────────────────────────────────────────────────
class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  double _targetAngle = 0.0;
  bool _isGasPressed = false;
  bool _isBrakePressed = false;
  bool _inputLocked = false;
  
  double _frontWheelCompression = 0.0;
  double _rearWheelCompression = 0.0;
  bool _frontWheelGrounded = false;
  bool _rearWheelGrounded = false;
  Vector2 _frontWheelWorldPos = Vector2.zero();
  Vector2 _rearWheelWorldPos = Vector2.zero();
  
  Vector2 _groundNormal = Vector2(0, -1);
  Vector2 _groundPoint = Vector2.zero();
  
  bool _isCrashed = false;

  Bike({required this.initialPosition});

  // Getter used by main.dart
  Vector2 get bodyPosition => body.position;

  @override
  Body createBody() {
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
    );
    
    final body = world.createBody(bodyDef)..createFixture(chassisFixture);
    
    final headShape = CircleShape()
      ..radius = BikeConfig.headRadius
      ..position.setValues(BikeConfig.headOffsetX, BikeConfig.headOffsetY);
    
    body.createFixture(FixtureDef(headShape, isSensor: true, userData: 'head'));
    
    return body;
  }

  void updateControl(double phoneTiltAngle, bool isGas, bool isBrake) {
    if (_isCrashed) return;
    _targetAngle = phoneTiltAngle;
    
    if (!_inputLocked) {
      if (isGas) { _isGasPressed = true; _isBrakePressed = false; _inputLocked = true; }
      else if (isBrake) { _isBrakePressed = true; _isGasPressed = false; _inputLocked = true; }
    } else if (!isGas && !isBrake) {
      _isGasPressed = false; _isBrakePressed = false; _inputLocked = false;
    }
    
    _updateWheelPhysics();
    _applyRotationControl();
    _applyGroundSnap();
    _applyDriveForce();
    _applyBrakeForce();
  }
  
  void _updateWheelPhysics() {
    final chassisPos = body.position;
    final chassisAngle = body.angle;
    
    final frontAttachLocal = Vector2(BikeConfig.wheelBase / 2, BikeConfig.chassisHeight);
    final rearAttachLocal = Vector2(-BikeConfig.wheelBase / 2, BikeConfig.chassisHeight);
    
    final frontAttachWorld = _localToWorld(frontAttachLocal, chassisPos, chassisAngle);
    final rearAttachWorld = _localToWorld(rearAttachLocal, chassisPos, chassisAngle);
    
    final cosA = math.cos(chassisAngle);
    final sinA = math.sin(chassisAngle);
    final rayDir = Vector2(-sinA, cosA); 
    final springDir = Vector2(sinA, -cosA);
    
    final rayLength = BikeConfig.suspensionRestLength + BikeConfig.suspensionMaxCompression + BikeConfig.wheelRadius;
    
    // Front Wheel
    final frontResult = _raycastWheel(frontAttachWorld, rayDir, rayLength);
    if (frontResult != null) {
      _frontWheelGrounded = true;
      _frontWheelCompression = frontResult['compression'];
      _frontWheelWorldPos = frontResult['wheelPos'];
      _groundNormal = frontResult['normal'];
      _groundPoint = frontResult['contactPoint'];
      _applySuspensionForce(frontAttachWorld, _frontWheelCompression, springDir);
    } else {
      _frontWheelGrounded = false;
      _frontWheelWorldPos = frontAttachWorld + (rayDir * (BikeConfig.suspensionRestLength + BikeConfig.wheelRadius));
    }
    
    // Rear Wheel
    final rearResult = _raycastWheel(rearAttachWorld, rayDir, rayLength);
    if (rearResult != null) {
      _rearWheelGrounded = true;
      _rearWheelCompression = rearResult['compression'];
      _rearWheelWorldPos = rearResult['wheelPos'];
      if (!_frontWheelGrounded) {
        _groundNormal = rearResult['normal'];
        _groundPoint = rearResult['contactPoint'];
      }
      _applySuspensionForce(rearAttachWorld, _rearWheelCompression, springDir);
    } else {
      _rearWheelGrounded = false;
      _rearWheelWorldPos = rearAttachWorld + (rayDir * (BikeConfig.suspensionRestLength + BikeConfig.wheelRadius));
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
      };
    }
    return null;
  }
  
  void _applySuspensionForce(Vector2 attachPoint, double compression, Vector2 springDir) {
    final springForce = compression * BikeConfig.suspensionStiffness;
    
    // Fixed: Standard way to get velocity at a specific world point in Forge2D
    final attachVel = body.getLinearVelocityFromWorldPoint(attachPoint);
    
    final velAlongStrut = attachVel.dot(springDir); 
    final dampingForce = velAlongStrut * BikeConfig.suspensionDamping;
    
    final totalForce = springForce - dampingForce;
    if (totalForce > 0) {
      body.applyForce(springDir * totalForce, point: attachPoint);
    }
  }

  void _applyRotationControl() {
    var angleDiff = _targetAngle - body.angle;
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    final torque = (angleDiff * 80.0) - (body.angularVelocity * 10.0);
    body.applyTorque(torque);
  }

  void _applyGroundSnap() {
    if (!_frontWheelGrounded && !_rearWheelGrounded) return;
    final groundAngle = math.atan2(-_groundNormal.x, -_groundNormal.y);
    var angleDiff = groundAngle - body.angle;
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    body.applyTorque(angleDiff * BikeConfig.groundSnapSpeed * 5.0);
    body.applyForce((_groundPoint - body.position).normalized() * BikeConfig.microGravityStrength);
  }

  void _applyDriveForce() {
    if (!_isGasPressed || !_rearWheelGrounded) return;
    final targetSpeed = BikeConfig.maxSpeed * (math.cos(body.angle) > 0 ? 1.0 : 1.3);
    body.linearVelocity = Vector2(targetSpeed * math.cos(body.angle), body.linearVelocity.y);
  }
  
  void _applyBrakeForce() {
    if (!_isBrakePressed || (!isGrounded)) return;
    if (body.linearVelocity.length < 0.5) {
      body.linearVelocity = Vector2.zero();
    } else {
      body.linearVelocity -= body.linearVelocity.normalized() * (BikeConfig.brakeDeceleration * 0.016);
    }
  }

  Vector2 _localToWorld(Vector2 local, Vector2 worldPos, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector2(worldPos.x + local.x * cos - local.y * sin, worldPos.y + local.x * sin + local.y * cos);
  }

  Vector2 _worldToLocal(Vector2 world, Vector2 bodyPos, double angle) {
    final dx = world.x - bodyPos.x;
    final dy = world.y - bodyPos.y;
    final cos = math.cos(-angle);
    final sin = math.sin(-angle);
    return Vector2(dx * cos - dy * sin, dx * sin + dy * cos);
  }

  bool get isGrounded => _frontWheelGrounded || _rearWheelGrounded;
  bool get isCrashed => _isCrashed;

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.blueAccent;
    canvas.drawRect(Rect.fromLTRB(-BikeConfig.chassisWidth, -BikeConfig.chassisHeight, BikeConfig.chassisWidth, BikeConfig.chassisHeight), paint);
    
    final wheelPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.12;
    final fLocal = _worldToLocal(_frontWheelWorldPos, body.position, body.angle);
    final rLocal = _worldToLocal(_rearWheelWorldPos, body.position, body.angle);
    
    canvas.drawCircle(Offset(fLocal.x, fLocal.y), BikeConfig.wheelRadius, wheelPaint);
    canvas.drawCircle(Offset(rLocal.x, rLocal.y), BikeConfig.wheelRadius, wheelPaint);
  }
}

// ─────────────────────────────────────────────────────────────
// RAYCAST CALLBACK
// ─────────────────────────────────────────────────────────────
class _WheelRaycastCallback extends RayCastCallback {
  bool hit = false;
  double compression = 0.0;
  Vector2 wheelPos = Vector2.zero();
  Vector2 normal = Vector2(0, -1);
  Vector2 contactPoint = Vector2.zero();
  
  final Vector2 _startPoint;
  final Vector2 _rayDir;
  final double _rayLength;
  
  _WheelRaycastCallback(this._startPoint, this._rayDir, this._rayLength);
  
  @override
  double reportFixture(Fixture fixture, Vector2 point, Vector2 normal, double fraction) {
    if (fixture.body.userData is Bike) return -1;
    hit = true;
    contactPoint = point.clone();
    this.normal = normal.clone();
    
    final distance = (point - _startPoint).length;
    final restDistance = BikeConfig.suspensionRestLength + BikeConfig.wheelRadius;
    compression = (restDistance - distance).clamp(0.0, BikeConfig.suspensionMaxCompression);
    wheelPos = point + normal * BikeConfig.wheelRadius;
    
    return fraction; 
  }
}