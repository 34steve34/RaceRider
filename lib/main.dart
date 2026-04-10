import 'dart:async';
import 'package:flutter/material.dart' hide Column;
// Hide Flame's vectors and world to prevent the clash
import 'package:flame/game.dart' hide Vector2, World;
import 'package:flame/components.dart' hide Vector2, World;
import 'package:flame/events.dart';
// Let Forge2D provide the correct 32-bit Vector2 and World automatically
import 'package:flame_forge2d/flame_forge2d.dart'; 
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with TapCallbacks {
  late Bike player;
  double tiltX = 0;
  bool isGas = false;

  RaceRiderGame() : super(gravity: Vector2(0, 20), zoom: 15);

  @override
  Future<void> onLoad() async {
    await add(Track());
    player = Bike(Vector2(0, 0));
    await add(player);
    
    accelerometerEvents.listen((event) => tiltX = event.x);
  }

  @override
  void update(double dt) {
    super.update(dt);
    player.updateControl(-tiltX / 5, isGas);
    camera.viewfinder.position = player.chassis.body.position;
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
      ..frequencyHz = 10
      ..dampingRatio = 0.7
      ..maxMotorTorque = 20);
  }

  void updateControl(double tilt, bool gas) {
    chassis.body.angularVelocity = tilt * 5;
    jointR.enableMotor(gas);
    jointR.motorSpeed = gas ? 40 : 0;
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
      ..createFixture(FixtureDef(shape, density: 1, friction: 0.8));
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
  @override
  Body createBody() {
    final body = world.createBody(BodyDef(type: BodyType.static));
    final List<Vector2> pts = [
      Vector2(-50, 5), 
      Vector2(20, 5), 
      Vector2(40, 2), 
      Vector2(100, 5)
    ];
    for (var i = 0; i < pts.length - 1; i++) {
      body.createFixture(FixtureDef(EdgeShape()..set(pts[i], pts[i+1]), friction: 0.6));
    }
    return body;
  }
  
  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFF00FF99)..strokeWidth = 0.2;
    canvas.drawLine(const Offset(-50, 5), const Offset(20, 5), paint);
    canvas.drawLine(const Offset(20, 5), const Offset(40, 2), paint);
    canvas.drawLine(const Offset(40, 2), const Offset(100, 5), paint);
  }
}