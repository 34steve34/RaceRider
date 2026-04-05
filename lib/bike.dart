import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────
// BIKE CONFIG - "HOT PINK" BR EDITION
// ─────────────────────────────────────────────────────────────
class BikeConfig {
  static const double cruiseSpeed = 5.0;
  static const double maxSpeed = 48.0;
  static const double acceleration = 45.0;
  
  static const double wheelRadius = 0.6;
  static const double wheelBase = 2.8;
  static const double chassisWidth = 2.2;
  static const double chassisHeight = 0.5;
  
  // BR Style: High stiffness, low damping for "bouncy" feel
  static const double suspensionRestLength = 0.8; 
  static const double suspensionStiffness = 8000.0; 
  static const double suspensionDamping = 40.0; 
  
  static const double bikeMass = 2.0;
  static const double worldGravity = 22.0;
  static const double stickyForce = 8.0; 
  static const double brakeForce = 80.0; // <-- Restored missing variable!
}

// ─────────────────────────────────────────────────────────────
// BIKE COMPONENT (HOT PINK VERSION)
// ─────────────────────────────────────────────────────────────
class Bike extends BodyComponent {
  final Vector2 initialPosition;
  
  double _targetAngle = 0.0;
  bool _isGasPressed = false;
  bool _isBrakePressed = false;
  bool _isLockedAtZero = false;
  
  bool _frontWheelGrounded = false;
  bool _rearWheelGrounded = false;
  Vector2 _frontWheelWorldPos = Vector2.zero();
  Vector2 _rearWheelWorldPos = Vector2.zero();
  
  Vector2 _groundNormal = Vector2(0, -1);
  Vector2 _groundPoint = Vector2.zero();

  Bike({required this.initialPosition});

  Vector2 get bodyPosition => body.position;

  @override
  Body createBody() {
    final chassisShape = PolygonShape()
      ..setAsBoxXY(BikeConfig.chassisWidth, BikeConfig.chassisHeight);
    
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
      gravityOverride: Vector2(0, BikeConfig.worldGravity),
    );
    
    final body = world.createBody(bodyDef)
      ..createFixture(FixtureDef(chassisShape, density: BikeConfig.bikeMass, friction: 0.1));
    
    return body;
  }

  void updateControl(double phoneTiltAngle, bool isGas, bool isBrake) {
    _targetAngle = phoneTiltAngle;
    _isGasPressed = isGas;
    _isBrakePressed = isBrake;

    if (_isGasPressed) _isLockedAtZero = false;
    
    _updateWheelPhysics();
    _applyRotationControl();
    _applyGroundSnap();
    _applyBikeRaceMotor(); 
  }
  
  void _updateWheelPhysics() {
    final chassisPos = body.position;
    final chassisAngle = body.angle;
    
    final fAttachLocal = Vector2(BikeConfig.wheelBase / 2, 0); 
    final rAttachLocal = Vector2(-BikeConfig.wheelBase / 2, 0);
    
    final fAttachWorld = _localToWorld(fAttachLocal, chassisPos, chassisAngle);
    final rAttachWorld = _localToWorld(rAttachLocal, chassisPos, chassisAngle);
    
    final cosA = math.cos(chassisAngle);
    final sinA = math.sin(chassisAngle);
    final rayDir = Vector2(-sinA, cosA); 
    final springDir = Vector2(sinA, -cosA); // Local Up
    
    final rayLength = BikeConfig.suspensionRestLength + BikeConfig.wheelRadius;
    
    // Front
    final fResult = _raycastWheel(fAttachWorld, rayDir, rayLength);
    if (fResult != null) {
      _frontWheelGrounded = true;
      _frontWheelWorldPos = fResult['wheelPos'];
      _groundNormal = fResult['normal'];
      _groundPoint = fResult['contactPoint'];
      _applySuspensionForce(fAttachWorld, fResult['compression'], springDir);
    } else {
      _frontWheelGrounded = false;
      _frontWheelWorldPos = fAttachWorld + (rayDir * rayLength);
    }
    
    // Rear
    final rResult = _raycastWheel(rAttachWorld, rayDir, rayLength);
    if (rResult != null) {
      _rearWheelGrounded = true;
      _rearWheelWorldPos = rResult['wheelPos'];
      if (!_frontWheelGrounded) {
        _groundNormal = rResult['normal'];
        _groundPoint = rResult['contactPoint'];
      }
      _applySuspensionForce(rAttachWorld, rResult['compression'], springDir);
    } else {
      _rearWheelGrounded = false;
      _rearWheelWorldPos = rAttachWorld + (rayDir * rayLength);
    }
  }

  void _applySuspensionForce(Vector2 attachPoint, double compression, Vector2 springDir) {
    if (compression <= 0) return;

    final springForce = compression * BikeConfig.suspensionStiffness;
    final vel = body.linearVelocityFromWorldPoint(attachPoint);
    final damping = vel.dot(springDir) * BikeConfig.suspensionDamping;
    final totalForce = springForce - damping;
    
    body.applyForce(springDir * totalForce, point: attachPoint);
  }

  void _applyRotationControl() {
    var angleDiff = _targetAngle - body.angle;
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    final torque = (angleDiff * 450.0) - (body.angularVelocity * 10.0);
    body.applyTorque(torque);
  }

  void _applyGroundSnap() {
    if (!isGrounded) return;
    final groundAngle = math.atan2(-_groundNormal.x, -_groundNormal.y);
    var angleDiff = groundAngle - body.angle;
    while (angleDiff > math.pi) angleDiff -= 2 * math.pi;
    while (angleDiff < -math.pi) angleDiff += 2 * math.pi;
    
    body.applyTorque(angleDiff * 50.0);
    
    final force = (_groundPoint - body.position).normalized() * BikeConfig.stickyForce;
    body.applyForce(force);
  }

  void _applyBikeRaceMotor() {
    if (!isGrounded) return;

    final currentVel = body.linearVelocity;
    final forwardDir = Vector2(math.cos(body.angle), math.sin(body.angle));
    
    if (_isBrakePressed) {
      if (currentVel.length > 0.5) {
        body.applyForce(currentVel.normalized() * -BikeConfig.brakeForce * body.mass);
      } else {
        body.linearVelocity = Vector2.zero();
        _isLockedAtZero = true;
      }
      return;
    }

    if (_isLockedAtZero) return;

    double targetSpeed = _isGasPressed ? BikeConfig.maxSpeed : BikeConfig.cruiseSpeed;
    final speedAlongForward = currentVel.dot(forwardDir);
    
    if (speedAlongForward < targetSpeed) {
      body.applyForce(forwardDir * BikeConfig.acceleration * body.mass);
    }
  }

  Map<String, dynamic>? _raycastWheel(Vector2 start, Vector2 dir, double len) {
    final callback = _WheelRaycastCallback(start, len);
    world.physicsWorld.raycast(callback, start, start + (dir * len));
    if (callback.hit) {
      return {
        'compression': (len - callback.dist).clamp(0.0, len),
        'wheelPos': callback.point + callback.normal * BikeConfig.wheelRadius,
        'normal': callback.normal,
        'contactPoint': callback.point,
      };
    }
    return null;
  }

  Vector2 _localToWorld(Vector2 local, Vector2 pos, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vector2(pos.x + local.x * c - local.y * s, pos.y + local.x * s + local.y * c);
  }

  Vector2 _worldToLocal(Vector2 worldP, Vector2 pos, double angle) {
    final dx = worldP.x - pos.x;
    final dy = worldP.y - pos.y;
    final c = math.cos(-angle);
    final s = math.sin(-angle);
    return Vector2(dx * c - dy * s, dx * s + dy * c);
  }

  bool get isGrounded => _frontWheelGrounded || _rearWheelGrounded;
  bool get isCrashed => false; 

  @override
  void render(Canvas canvas) {
    // Chassis - Hot Pink
    final paint = Paint()..color = const Color(0xFFFF69B4);
    canvas.drawRect(Rect.fromLTRB(-BikeConfig.chassisWidth, -BikeConfig.chassisHeight, BikeConfig.chassisWidth, BikeConfig.chassisHeight), paint);
    
    // Rider - White
    canvas.drawRect(const Rect.fromLTRB(0.3, -1.1, 1.1, -0.4), Paint()..color = Colors.white);
    
    final wheelPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.15;
    final fL = _worldToLocal(_frontWheelWorldPos, body.position, body.angle);
    final rL = _worldToLocal(_rearWheelWorldPos, body.position, body.angle);
    
    canvas.drawCircle(Offset(fL.x, fL.y), BikeConfig.wheelRadius, wheelPaint);
    canvas.drawCircle(Offset(rL.x, rL.y), BikeConfig.wheelRadius, wheelPaint);
  }
}

class _WheelRaycastCallback extends RayCastCallback {
  bool hit = false;
  Vector2 point = Vector2.zero();
  Vector2 normal = Vector2.zero();
  double dist = 0.0;
  final Vector2 start;
  final double maxLen;

  _WheelRaycastCallback(this.start, this.maxLen);

  @override
  double reportFixture(Fixture fixture, Vector2 p, Vector2 n, double fraction) {
    if (fixture.body.userData is Bike) return -1;
    hit = true;
    point = p.clone();
    normal = n.clone();
    dist = fraction * maxLen;
    return fraction;
  }
}