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

  // 🔴 MAGIC DEBUG MODE: Draws neon outlines around actual physics bodies
  @override
  bool get debugMode => true; 

  RaceRiderGame() : super(gravity: Vector2(0, 20), zoom: 15);

  @override
  Future<void> onLoad() async {
    await world.add(Track());
    player = Bike(Vector2(0, -2));
    await add(player); 
    
    accelerometerEvents.listen((event) => rawTilt = -event.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 1. NORMALIZE: Turn raw 9.8 gravity into a strict -1.0 to 1.0 limit
    double normalizedTilt = (rawTilt / 10).clamp(-1.0, 1.0);
    
    // 2. SMOOTH: Glide the rotation instead of jerking it
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.2;
    
    player.updateControl(smoothedTilt, isGas);
    
    // Camera follows slightly ahead of the bike
    camera.viewfinder.position = player.chassis.body.position + Vector2(5, 0);
  }

  @override
  void onTapDown(TapDownEvent event) => isGas = true;
  @override
  void onTapUp(TapUpEvent event) => isGas = false;
}

class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 pos;
  late Part chassis, frontW, rearW;
  late WheelJoint jointF, jointR;

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
      ..frequencyHz = 15 // Tighter springs to stop wheels from separating
      ..dampingRatio = 0.7
      ..maxMotorTorque = 25); // Lower torque to stop burnouts
  }

  void updateControl(double tilt, bool gas) {
    // Sane torque limit so the bike doesn't become a helicopter
    chassis.body.applyTorque(tilt * 20);

    jointR.enableMotor(gas);
    // Sane speed limit so you don't instantly fly off the track
    jointR.motorSpeed = gas ? 25 : 0; 
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
    
    // Air resistance so the bike stops spinning when you stop tilting
    if (!isWheel) bodyDef.angularDamping = 6.0; 
    
    return world.createBody(bodyDef)
      ..createFixture(FixtureDef(shape, density: 1.5, friction: 0.9, restitution: 0.1));
  }

  @override
  void render(Canvas canvas) {
    // We can leave this here, but debugMode will draw over it anyway
    final color = isWheel ? const Color(0xFFFFFFFF) : const Color(0xFFFF69B4);
    if (isWheel) {
      canvas.drawCircle(Offset.zero, 0.5, Paint()..color = color);
    } else {
      canvas.drawRect(const Rect.fromLTWH(-1.2, -0.3, 2.4, 0.6), Paint()..color = color);
    }
  }
}

class Track extends BodyComponent {
  // Made the track much longer so you have room to test
  final List<Vector2> pts = [
    Vector2(-50, 5), 
    Vector2(20, 5), 
    Vector2(35, -2), 
    Vector2(50, 5),
    Vector2(100, 5),
    Vector2(300, 5) // Huge runway
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