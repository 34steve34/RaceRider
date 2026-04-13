/* ============================================================================
 * RACERIDER: GAME DESIGN MANIFESTO & AI CONTEXT
 * ============================================================================
 * Target Feel: 2D Arcade Physics Motorcycle Game (Clone of "Bike Race")
 * Engine: Flutter + Flame + Forge2D (Box2D)
 * * CORE ARCADE MECHANICS (SINGLE-LOGIC PHYSICS MODEL):
 * 1. Offset COG ("The Heavy Tail"): Mass shifted backward/upward.
 * 2. Velocity Controller ("The Spin"): Tilting targets rotational speed, not 
 * absolute position. This allows continuous flips in the air and forces the 
 * player to actively balance on the ground against gravity.
 * 3. Mass Disparity: Chassis is very heavy, wheels are paper-light. This prevents
 * centrifugal force from stretching the suspension during air-spins.
 * 4. Micro-Magnetic Wheels: Localized normal force (lightly tuned).
 * ============================================================================ */

import 'dart:async';
import 'package:flutter/material.dart' hide Column;
import 'package:flame/game.dart' hide Vector2, World;
import 'package:flame/components.dart' hide Vector2, World;
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart'; 
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with TapCallbacks {
  late Bike player;
  
  double rawTilt = 0;
  double smoothedTilt = 0;
  
  bool isGas = false;
  bool isBrake = false;

  RaceRiderGame() : super(gravity: Vector2(0, 35), zoom: 15);

  @override
  Future<void> onLoad() async {
    await world.add(Track());
    player = Bike(Vector2(0, -2));
    await add(player); 
    
    accelerometerEvents.listen((event) => rawTilt = event.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    double normalizedTilt = (rawTilt / 10).clamp(-1.0, 1.0);
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.8; 
    
    player.updateControl(smoothedTilt, isGas, isBrake);
    
    camera.viewfinder.position = player.chassis.body.position + Vector2(5, 0);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) {
      isGas = true;
    } else {
      isBrake = true;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }
}

class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 pos;
  late Part chassis, frontW, rearW;
  late WheelJoint jointF, jointR;

  final double magneticStrength = 8.0; 

  Bike(this.pos);

  @override
  Future<void> onLoad() async {
    chassis = Part(pos, isWheel: false);
    frontW = Part(pos + Vector2(1.5, 0.8), isWheel: true);
    rearW = Part(pos + Vector2(-1.5, 0.8), isWheel: true);

    await gameRef.world.addAll([chassis, frontW, rearW]);

    jointF = _makeJoint(chassis.body, frontW.body, frontW.body.position);
    jointR = _makeJoint(chassis.body, rearW.body, rearW.body.position);
    gameRef.world.physicsWorld.createJoint(jointF);
    gameRef.world.physicsWorld.createJoint(jointR);
  }

  WheelJoint _makeJoint(Body a, Body b, Vector2 anchor) {
    return WheelJoint(WheelJointDef()
      ..initialize(a, b, anchor, Vector2(0, 1))
      ..frequencyHz = 10.0  // Bumped slightly to support the new, heavier chassis 
      ..dampingRatio = 0.5 
      ..maxMotorTorque = 250.0); // MUSCLE: Massive increase to climb hills
  }

  void _applyMicroMagnet(Part wheel) {
    if (!wheel.isMounted) return;
    
    for (final contact in wheel.body.contacts) {
      if (contact.isTouching()) {
        final manifold = WorldManifold();
        contact.getWorldManifold(manifold); 
        Vector2 surfaceNormal = manifold.normal;
        
        if (contact.fixtureB.body == wheel.body) {
           surfaceNormal = -surfaceNormal;
        }
        
        wheel.body.applyForce(surfaceNormal * -magneticStrength); 
        break; 
      }
    }
  }

  void updateControl(double tilt, bool gas, bool brake) {
    // 1. VELOCITY CONTROLLER (Fixes the "Servo-Lock" Stoppie Issue)
    // Tilt now commands a rotation speed, allowing continuous flips and removing the artificial angle lock.
    double targetVelocity = (tilt * tilt.abs()) * 12.0; 
    double velocityError = targetVelocity - chassis.body.angularVelocity;
    
    // Apply torque to achieve that spin speed. Scaled up because the chassis is heavy.
    double tiltTorque = velocityError * 150.0; 
    chassis.body.applyAngularImpulse(tiltTorque.clamp(-400.0, 400.0));

    // 2. Micro-Magnetics
    _applyMicroMagnet(frontW);
    _applyMicroMagnet(rearW);

    // 3. Drive Train & Friction
    double friction = (gas || brake) ? 0.9 : 0.1;
    frontW.setFriction(friction);
    rearW.setFriction(friction);

    jointR.enableMotor(gas || brake);
    
    if (brake) {
      jointR.motorSpeed = 0;
      jointF.enableMotor(true); 
      jointF.motorSpeed = 0;
    } else {
      jointF.enableMotor(false);
      jointR.motorSpeed = gas ? 90 : 0; // SPEED: 1.5x faster 
    }
  }
}

class Part extends BodyComponent {
  final Vector2 pos;
  final bool isWheel;
  Part(this.pos, {this.isWheel = false});

  @override
  Body createBody() {
    late Shape shape;
    
    if (isWheel) {
      shape = CircleShape()..radius = 0.5;
    } else {
      shape = PolygonShape()
        ..setAsBox(1.2, 0.3, Vector2(-0.5, -0.2), 0);
    }
    
    final bodyDef = BodyDef(type: BodyType.dynamic, position: pos);
    
    // MASS DISPARITY: Chassis is a brick, wheels are feathers.
    // This stops the centrifugal force of a flip from tearing the wheels off.
    final double partDensity = isWheel ? 0.1 : 4.0; 
    
    return world.createBody(bodyDef)
      ..createFixture(FixtureDef(shape, density: partDensity, friction: 0.9, restitution: 0.0));
  }

  void setFriction(double newFriction) {
    if (!isMounted || body.fixtures.isEmpty) return;
    final fixture = body.fixtures.first;
    if (fixture.friction == newFriction) return; 
    fixture.friction = newFriction;
    for (final contact in body.contacts) {
      contact.resetFriction();
    }
  }

  @override
  void render(Canvas canvas) {
    final color = isWheel ? const Color(0xFFFFFFFF) : const Color(0xFFFF69B4); 
    if (isWheel) {
      canvas.drawCircle(Offset.zero, 0.5, Paint()..color = color);
    } else {
      canvas.drawRect(const Rect.fromLTWH(-1.2, -0.3, 2.4, 0.6), Paint()..color = color);
    }
  }
}

class Track extends BodyComponent {
  final List<Vector2> pts = [
    Vector2(-50, 5), 
    Vector2(20, 5), 
    Vector2(35, -2), 
    Vector2(50, 5),
    Vector2(70, -5), 
    Vector2(90, -5), 
    Vector2(100, 5),
    Vector2(300, 5) 
  ];

  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    for (var i = 0; i < pts.length - 1; i++) {
      body.createFixture(FixtureDef(EdgeShape()..set(pts[i], pts[i+1]), friction: 0.8));
    }
    return body;
  }
  
  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 0.5 
      ..style = PaintingStyle.stroke;
      
    final path = Path();
    path.moveTo(pts[0].x, pts[0].y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    canvas.drawPath(path, paint);
  }
}