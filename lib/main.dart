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

  RaceRiderGame() : super(gravity: Vector2(0, 20), zoom: 15);

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
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.2;
    
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

  final double maxRotationSpeed = 8.0; 

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
      ..maxMotorTorque = 100); 
  }

  void updateControl(double tilt, bool gas, bool brake) {
    // 1. ARCADE S-CURVE ROTATION
    double smoothedS = tilt * tilt.abs(); 
    double targetAngle = smoothedS * 3.0; 
    
    double angleError = targetAngle - chassis.body.angle;
    double desiredSpeed = angleError * 12.0;
    
    chassis.body.angularVelocity = desiredSpeed.clamp(-maxRotationSpeed, maxRotationSpeed);

    // 2. DYNAMIC FRICTION PIVOT (Repaired)
    if (gas || brake) {
      // Sticky rubber when driving or stopping
      frontW.setFriction(0.9);
      rearW.setFriction(0.9);
    } else {
      // Low friction when coasting. Allows sliding on hills and smooth wheelie pivots.
      frontW.setFriction(0.1);
      rearW.setFriction(0.1);
    }

    // 3. MOTOR LOGIC
    if (brake) {
      jointR.enableMotor(true);
      jointR.motorSpeed = 0;
      jointF.enableMotor(true);
      jointF.motorSpeed = 0;
    } else {
      jointF.enableMotor(false); 
      jointR.enableMotor(gas);
      jointR.motorSpeed = gas ? 50 : 0; 
    }
  }
}

class Part extends BodyComponent {
  final Vector2 pos;
  final bool isWheel;
  Part(this.pos, {this.isWheel = false});

  @override
  Body createBody() {
    final shape = isWheel 
        ? (CircleShape()..radius = 0.5) 
        : (PolygonShape()..setAsBox(1.2, 0.3, Vector2.zero(), 0));
    
    final bodyDef = BodyDef(type: BodyType.dynamic, position: pos);
    if (!isWheel) bodyDef.angularDamping = 2.0; 
    
    final double partDensity = isWheel ? 0.75 : 1.5;
    
    return world.createBody(bodyDef)
      ..createFixture(FixtureDef(shape, density: partDensity, friction: 0.9, restitution: 0.1));
  }

  // REPAIRED: Helper method to dynamically change friction on the fly
  void setFriction(double newFriction) {
    if (!isMounted || body.fixtures.isEmpty) return;
    
    final fixture = body.fixtures.first;
    // Only update if it actually changed to save CPU
    if (fixture.friction == newFriction) return; 

    fixture.friction = newFriction;
    
    // CRITICAL FIX: Tell the physics engine to clear the contact cache and recalculate!
    for (var edge = body.contacts; edge != null; edge = edge.next) {
      edge.contact.resetFriction();
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