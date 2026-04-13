/* ============================================================================
 * RACERIDER: GAME DESIGN MANIFESTO & AI CONTEXT
 * ============================================================================
 * Target Feel: 2D Arcade Physics Motorcycle Game (Clone of "Bike Race")
 * Engine: Flutter + Flame + Forge2D (Box2D)
 * * CORE ARCADE MECHANICS:
 * 1. Offset COG: Mass shifted backward/upward for rear stability.
 * 2. Velocity Controller (TORQUE OVERHAUL): Tilting commands rotational speed. 
 * Uses continuous applyTorque instead of violent impulses to prevent joint tearing.
 * 3. Safe Mass Ratio (7.5:1): Chassis is 1.5, wheels are 0.2. 
 * 4. Stable Suspension: frequencyHz reduced to Box2D vehicle standards (5Hz).
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

  final double magneticStrength = 2.0; 

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
      // THE SUSPENSION FIX: 
      // Lowered to 5.0 (Box2D sweet spot for vehicles). 
      // Allows the wheels to absorb terrain without panicking the math solver.
      ..frequencyHz = 5.0  
      ..dampingRatio = 0.7  
      ..maxMotorTorque = 250.0); 
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
    double targetVelocity = (tilt * tilt.abs()) * 12.0; 
    double velocityError = targetVelocity - chassis.body.angularVelocity;
    
    // THE SLEDGEHAMMER FIX (Torque instead of Impulse):
    // Because applyTorque is scaled by time (dt), the multiplier must be much higher
    // to achieve the same strength, but the resulting force is perfectly smooth.
    double smoothTorque = velocityError * 6000.0; 
    
    // Using applyTorque stops the solver from tearing the joints apart
    chassis.body.applyTorque(smoothTorque.clamp(-20000.0, 20000.0));

    _applyMicroMagnet(frontW);
    _applyMicroMagnet(rearW);

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
    late Shape shape;
    
    if (isWheel) {
      shape = CircleShape()..radius = 0.5;
    } else {
      shape = PolygonShape()
        ..setAsBox(1.2, 0.3, Vector2(-0.5, -0.2), 0);
    }
    
    final bodyDef = BodyDef(type: BodyType.dynamic, position: pos);
    final double partDensity = isWheel ? 0.2 : 1.5; 
    
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