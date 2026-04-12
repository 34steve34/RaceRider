/* ============================================================================
 * RACERIDER: GAME DESIGN MANIFESTO & AI CONTEXT
 * ============================================================================
 * Target Feel: 2D Arcade Physics Motorcycle Game (Clone of "Bike Race")
 * Engine: Flutter + Flame + Forge2D (Box2D)
 * * CORE ARCADE MECHANICS (SINGLE-LOGIC PHYSICS MODEL):
 * 1. Offset COG (The "Heavy Tail"): The chassis mass is shifted physically backward 
 * and low. This makes backflips naturally resist gravity and front-wheel stoppies 
 * require momentum, perfectly replicating the original game's balance struggle.
 * 2. Absolute Air Control (Soft-Clamp): The bike's rotation targets the phone's tilt 
 * using an S-Curve impulse. This applies constant authority, allowing the player 
 * to fight the physics engine smoothly without ghosting through walls.
 * 3. Constant Authority Control: No state switching. The arcade controller applies 
 * torque 100% of the time, allowing seamless transitions from ground to air.
 * 4. Micro-Magnetic Wheels: A localized normal force pulls the wheel axle into the 
 * track ONLY when contact is actively occurring. This allows for ceiling rides 
 * and loops without creating a universal gravity well during jumps.
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

  // Bumped gravity slightly to make the bike feel "snappier" on landings
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
    
    // Normalize and smooth the accelerometer input
    double normalizedTilt = (rawTilt / 10).clamp(-1.0, 1.0);
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.2; 
    
    player.updateControl(smoothedTilt, isGas, isBrake);
    
    // Follow camera
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

  // Reduced magnet strength since it's pulling against higher gravity now
  final double magneticStrength = 20.0; 

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
      ..frequencyHz = 15 
      ..dampingRatio = 0.7
      ..maxMotorTorque = 45); // Capped to prevent instant flips on acceleration
  }

  void _applyMicroMagnet(Part wheel) {
    if (!wheel.isMounted) return;
    
    for (final contact in wheel.body.contacts) {
      if (contact.isTouching()) {
        final manifold = WorldManifold();
        contact.getWorldManifold(manifold); 
        Vector2 surfaceNormal = manifold.normal;
        
        // Ensure the normal vector always points from the surface into the wheel
        if (contact.fixtureB.body == wheel.body) {
           surfaceNormal = -surfaceNormal;
        }
        
        // Pull the wheel center directly into the surface to stick to loops
        wheel.body.applyForce(surfaceNormal * -magneticStrength); 
        break; // Only apply once per frame per wheel
      }
    }
  }

  void updateControl(double tilt, bool gas, bool brake) {
    // 1. Unified Rotation (The Arcade Controller)
    // S-Curve input for deadzone in the middle, fast rotation at the edges
    double targetAngle = (tilt * tilt.abs()) * 3.0; 
    double angleError = targetAngle - chassis.body.angle;
    
    // Apply constant impulse. The offset COG will naturally resist this 
    // when trying to backflip or stoppie, providing the "weight" feel.
    chassis.body.applyAngularImpulse(angleError * 15.0);

    // 2. Micro-Magnetics (Only triggers on active physical contact)
    _applyMicroMagnet(frontW);
    _applyMicroMagnet(rearW);

    // 3. Drive Train & Friction
    double friction = (gas || brake) ? 0.9 : 0.1;
    frontW.setFriction(friction);
    rearW.setFriction(friction);

    jointR.enableMotor(gas || brake);
    
    if (brake) {
      // Lock both wheels for a snappy stop
      jointR.motorSpeed = 0;
      jointF.enableMotor(true); 
      jointF.motorSpeed = 0;
    } else {
      // Power to the rear wheel only
      jointF.enableMotor(false);
      jointR.motorSpeed = gas ? 60 : 0; // High speed for arcade zip
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
      // THE OFFSET COG ("Heavy Tail")
      // Shift mass 0.5 forward and 0.2 down relative to the joints.
      // This puts the actual pivot center closer to the rear wheel.
      shape = PolygonShape()
        ..setAsBox(1.2, 0.3, Vector2(0.5, 0.2), 0);
    }
    
    final bodyDef = BodyDef(type: BodyType.dynamic, position: pos);
    if (!isWheel) bodyDef.angularDamping = 3.0; // Keeps it from spinning wildly
    
    final double partDensity = isWheel ? 0.75 : 1.5;
    
    return world.createBody(bodyDef)
      ..createFixture(FixtureDef(shape, density: partDensity, friction: 0.9, restitution: 0.1));
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
      // Visual representation is kept centered despite the physical COG shift
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