/* ============================================================================
 * RACERIDER: GAME DESIGN MANIFESTO & AI CONTEXT
 * ============================================================================
 * Target Feel: 2D Arcade Physics Motorcycle Game (Clone of "Bike Race")
 * Engine: Flutter + Flame + Forge2D (Box2D)
 * * VERSION CHECK: CHASSIS IS NEON ORANGE.
 * * CORE ARCADE MECHANICS:
 * 1. The "Lead Weight" COG Fix: The visual hull is centered and light, but an 
 * invisible, super-dense sensor is placed near the rear wheel. This creates a 
 * "Weeble-Wobble" effect, eliminating instant torque-reaction backflips while 
 * preserving the accurate visual collision boundary.
 * 2. Velocity Controller (TRUE DEADZONE): Shuts off completely when resting.
 * 3. Safe Mass Ratio (7.5:1): Prevents wheel stretching & ground vibrations.
 * 4. Stiffened Suspension (14.0 Hz): Tight shock absorbers.
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
      ..frequencyHz = 14.0  
      ..dampingRatio = 0.8  
      // Torque reduced slightly from 250 to 180. 
      // With the new low COG, the power goes entirely into moving forward instead of flipping.
      ..maxMotorTorque = 180.0); 
  }

  void updateControl(double tilt, bool gas, bool brake) {
    if (tilt.abs() > 0.05) {
      double targetVelocity = (tilt * tilt.abs()) * 12.0; 
      double velocityError = targetVelocity - chassis.body.angularVelocity;
      
      // Increased Arcade Torque slightly to compensate for the new Lead Weight inertia
      double smoothTorque = velocityError * 300.0; 
      chassis.body.applyTorque(smoothTorque.clamp(-1500.0, 1500.0));
    }

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
      jointR.motorSpeed = gas ? 90 : 0; 
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
    if (!isWheel) bodyDef.angularDamping = 1.5; 
    
    final body = world.createBody(bodyDef);
    
    if (isWheel) {
      final shape = CircleShape()..radius = 0.5;
      body.createFixture(FixtureDef(shape, density: 0.2, friction: 0.9, restitution: 0.0));
    } else {
      // 1. The Main Hull (Visual & Collision Boundary)
      // Perfectly centered, low density.
      final hullShape = PolygonShape()
        ..setAsBox(1.2, 0.3, Vector2.zero(), 0);
      body.createFixture(FixtureDef(hullShape, density: 0.5, friction: 0.9, restitution: 0.0));
      
      // 2. THE LEAD WEIGHT (COG Override)
      // Tiny, invisible, high-density sensor placed extremely low and near the rear axle.
      // This forces the Center of Mass down without messing up collisions.
      final weightShape = CircleShape()
        ..radius = 0.1;
      weightShape.position.setValues(-1.2, 1.0); 
      
      body.createFixture(FixtureDef(weightShape, density: 10.0, isSensor: true));
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
    // VISUAL VERIFICATION: Chassis is Neon Orange
    final color = isWheel ? const Color(0xFFFFFFFF) : const Color(0xFFFFA500); 
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