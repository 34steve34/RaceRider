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
  
  // Smoothing variables
  double rawTilt = 0;
  double smoothedTilt = 0;
  bool isGas = false;

  RaceRiderGame() : super(gravity: Vector2(0, 20), zoom: 15);

  @override
  Future<void> onLoad() async {
    await add(Track());
    player = Bike(Vector2(0, 0));
    await add(player);
    
    // Read the landscape Y axis
    accelerometerEvents.listen((event) => rawTilt = -event.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Low-Pass Filter: Blends 85% of the old tilt with 15% of the new tilt
    // This completely removes hand-shake and makes the rotation buttery smooth
    smoothedTilt += (rawTilt - smoothedTilt) * 0.15;
    
    player.updateControl(smoothedTilt, isGas);
    
    // Camera follows the chassis with a slight offset so you can see ahead
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
      ..frequencyHz = 12 // Stiffer suspension
      ..dampingRatio = 0.8
      ..maxMotorTorque = 40); // Max torque for fast acceleration
  }

  void updateControl(double tilt, bool gas) {
    // 1. APPLY TORQUE INSTEAD OF VELOCITY
    // This allows natural wheelies on the ground and smooth flips in the air
    // We multiply by a large number because torque requires more force than velocity
    chassis.body.applyTorque(tilt * 250);

    // 2. RESPONSIVE MOTOR
    jointR.enableMotor(gas);
    // 60 is a fast max speed. It will accelerate hard but cap out.
    jointR.motorSpeed = gas ? 60 : 0; 
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
    
    return world.createBody(BodyDef(type: BodyType.dynamic, position: pos))
      ..createFixture(FixtureDef(shape, density: 1.5, friction: 0.9, restitution: 0.1));
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
  // Define the points as a class variable so both the physics and the renderer can use them perfectly
  final List<Vector2> pts = [
    Vector2(-50, 5), 
    Vector2(20, 5), 
    Vector2(35, -2), // Added a real hill to test torque/wheelies!
    Vector2(50, 5),
    Vector2(150, 5)
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
    // Loop through the exact physics points to draw the track
    final paint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 0.5 // Thicker line so you can actually see it
      ..style = PaintingStyle.stroke;
      
    for (var i = 0; i < pts.length - 1; i++) {
      canvas.drawLine(
        Offset(pts[i].x, pts[i].y), 
        Offset(pts[i+1].x, pts[i+1].y), 
        paint
      );
    }
  }
}