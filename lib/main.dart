/* ============================================================================
 * RACERIDER: GAME DESIGN MANIFESTO & AI CONTEXT
 * ============================================================================
 * Target Feel: 2D Arcade Physics Motorcycle Game (Clone of "Bike Race")
 * Engine: Flutter + Flame + Forge2D (Box2D)
 * * VERSION CHECK: CHASSIS IS BLUE.
 * * CORE ARCADE MECHANICS:
 * 1. Anti-Jitter Crash Sensor: If the hull touches the ground, all artificial 
 * torques (Arcade Controller & Motor) shut off, preventing Box2D solver spasms.
 * 2. Reduced Motor Torque: Lowered to 200 to prevent Newton's Third Law from 
 * instantly backflipping the chassis on acceleration.
 * 3. Deep Lead Weight: COG lowered to Y=1.2 (axle level) for maximum stability.
 * 4. High Altitude Drop: Bike spawned at Y = -8 for mid-air stability testing.
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
    
    player = Bike(Vector2(0, -8));
    await add(player); 
    
    camera.viewfinder.position = player.chassis.body.position;
    
    accelerometerEvents.listen((event) => rawTilt = event.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    double normalizedTilt = (rawTilt / 10).clamp(-1.0, 1.0);
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.8; 
    
    player.updateControl(smoothedTilt, isGas, isBrake);
    
    final targetCamPos = player.chassis.body.position + Vector2(5, 0);
    final currentPos = camera.viewfinder.position;
    camera.viewfinder.position = currentPos + (targetCamPos - currentPos) * 0.15;
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

  Bike(this.pos);

  @override
  Future<void> onLoad() async {
    chassis = Part(pos, isWheel: false);
    
    frontW = Part(pos + Vector2(1.5, 1.4), isWheel: true);
    rearW = Part(pos + Vector2(-1.5, 1.4), isWheel: true);

    await gameRef.world.addAll([chassis, frontW, rearW]);

    jointF = _makeJoint(chassis.body, frontW.body, frontW.body.position);
    jointR = _makeJoint(chassis.body, rearW.body, rearW.body.position);
    gameRef.world.physicsWorld.createJoint(jointF);
    gameRef.world.physicsWorld.createJoint(jointR);
  }

  WheelJoint _makeJoint(Body a, Body b, Vector2 anchor) {
    return WheelJoint(WheelJointDef()
      ..initialize(a, b, anchor, Vector2(0, 1))
      ..frequencyHz = 12.0  
      ..dampingRatio = 0.8  
      // MOTOR TORQUE FIX: 
      // Lowered to prevent instant reaction-torque backflips. 
      ..maxMotorTorque = 200.0); 
  }

  // CRASH SENSOR: Checks if the non-wheel parts are touching the ground
  bool _isHullTouchingGround() {
    if (!chassis.isMounted) return false;
    for (final contact in chassis.body.contacts) {
      if (contact.isTouching()) {
        final fixA = contact.fixtureA;
        final fixB = contact.fixtureB;
        // If the hull is touching something that IS NOT a wheel, it's a crash.
        if (fixA.body != frontW.body && fixA.body != rearW.body &&
            fixB.body != frontW.body && fixB.body != rearW.body) {
          return true;
        }
      }
    }
    return false;
  }

  void updateControl(double tilt, bool gas, bool brake) {
    bool isCrashed = _isHullTouchingGround();

    // 1. ARCADE CONTROLLER
    // Completely disabled if crashed to prevent ground-collision jitter
    if (!isCrashed && tilt.abs() > 0.05) {
      double targetVelocity = (tilt * tilt.abs()) * 12.0; 
      double velocityError = targetVelocity - chassis.body.angularVelocity;
      double smoothTorque = velocityError * 2000.0; 
      chassis.body.applyTorque(smoothTorque.clamp(-10000.0, 10000.0));
    }

    // 2. FRICTION
    double friction = (gas || brake) ? 0.9 : 0.1;
    frontW.setFriction(friction);
    rearW.setFriction(friction);

    // 3. DRIVE TRAIN
    if (isCrashed) {
      // Kill the engine on crash so the wheels don't grind against the dirt
      jointR.enableMotor(false);
      jointF.enableMotor(false);
    } else {
      jointR.enableMotor(gas || brake);
      
      if (brake) {
        jointR.motorSpeed = 0;
        jointF.enableMotor(true); 
        jointF.motorSpeed = 0;
      } else {
        jointF.enableMotor(false);
        jointR.motorSpeed = gas ? 90 : 0; 
      }
    }
  }
}

class Part extends BodyComponent {
  final Vector2 pos;
  final bool isWheel;
  Part(this.pos, {this.isWheel = false});

  @override
  Body createBody() {
    final bodyDef = BodyDef(type: BodyType.dynamic, position: pos);
    
    // Increased natural damping so the bike settles quietly after a crash
    if (!isWheel) bodyDef.angularDamping = 3.0; 
    
    final body = world.createBody(bodyDef);
    final double partDensity = isWheel ? 1.0 : 0.5; 
    
    if (isWheel) {
      final shape = CircleShape()..radius = 0.5;
      body.createFixture(FixtureDef(shape, density: partDensity, friction: 0.9, restitution: 0.0));
    } else {
      final hullShape = PolygonShape()
        ..setAsBox(1.2, 0.3, Vector2.zero(), 0);
      body.createFixture(FixtureDef(hullShape, density: partDensity, friction: 0.9, restitution: 0.0));
      
      // DEEP LEAD WEIGHT
      // Y lowered to 1.2 to sit level with the axles. 
      // This minimizes the lever arm for the engine's reaction torque.
      final weightShape = CircleShape()
        ..radius = 0.3;
      weightShape.position.setValues(-1.0, 1.2); 
      
      body.createFixture(FixtureDef(weightShape, density: 20.0, isSensor: true));
    }
    
    return body;
  }

  void setFriction(double newFriction) {
    if (!isMounted || body.fixtures.isEmpty) return;
    for (final fixture in body.fixtures) {
      if (fixture.friction != newFriction) {
        fixture.friction = newFriction;
      }
    }
    for (final contact in body.contacts) {
      contact.resetFriction();
    }
  }

  @override
  void render(Canvas canvas) {
    // VISUAL VERIFICATION: Chassis is BLUE
    final color = isWheel ? const Color(0xFFFFFFFF) : const Color(0xFF0000FF); 
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