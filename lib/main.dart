import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:forge2d/forge2d.dart' as f2d;
import 'package:flutter/material.dart';

// --- ADDED STARTING POINT ---
void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with TapDetector {
  late final Bike player;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Add the bike to the world
    player = Bike(initialPosition: Vector2(0, 5));
    add(player);
    
    // Add a simple ground so the bike doesn't fall forever
    add(Ground());
  }

  @override
  void onTapDown(TapDownInfo info) {
    // Example: Trigger gas on tap
    player.updateControl(0, true, false);
  }

  @override
  void onTapUp(TapUpInfo info) {
    player.updateControl(0, false, false);
  }
}

class Ground extends BodyComponent {
  @override
  Body createBody() {
    final shape = EdgeShape()..set(Vector2(-100, 10), Vector2(100, 10));
    final bodyDef = BodyDef()..type = BodyType.static;
    return world.createBody(bodyDef)..createFixture(FixtureDef(shape, friction: 0.8));
  }
}
// --- END OF ADDED CLASSES ---

class _Part extends BodyComponent {
  final Vector2 pos;
  final bool isWheel;
  _Part({required this.pos, this.isWheel = false});

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..position = pos
      ..type = BodyType.dynamic;
    if (!isWheel) {
      bodyDef.angularDamping = 1.8;
    }

    final body = world.createBody(bodyDef);
    final shape = CircleShape()..radius = isWheel ? Bike.wheelRadius : 0.4;

    body.createFixture(FixtureDef(shape)
      ..density = 1.0
      ..friction = isWheel ? 0.9 : 0.5
      ..restitution = 0.1);

    return body;
  }
}

class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 initialPosition;
  late final _Part _chassisComp;
  late final _Part _frontWheelComp;
  late final _Part _rearWheelComp;

  late f2d.WheelJoint rearJoint;
  late f2d.WheelJoint frontJoint;

  static const double wheelBase = 2.8;
  static const double wheelRadius = 0.5;
  static const double hz = 18.0; 
  static const double damping = 0.8;

  Bike({required this.initialPosition});

  Body get chassisBody => _chassisComp.body;

  @override
  Future<void> onLoad() async {
    final frontPos = initialPosition + Vector2(wheelBase / 2, 0.8);
    final rearPos = initialPosition + Vector2(-wheelBase / 2, 0.8);

    _chassisComp = _Part(pos: initialPosition);
    _frontWheelComp = _Part(pos: frontPos, isWheel: true);
    _rearWheelComp = _Part(pos: rearPos, isWheel: true);

    await add(_chassisComp);
    await add(_frontWheelComp);
    await add(_rearWheelComp);

    // Wait for bodies to be created before making joints
    final physicsWorld = gameRef.world.physicsWorld;
    frontJoint = _makeJoint(physicsWorld, _chassisComp.body, _frontWheelComp.body, frontPos);
    rearJoint = _makeJoint(physicsWorld, _chassisComp.body, _rearWheelComp.body, rearPos);
  }

  f2d.WheelJoint _makeJoint(f2d.World world, Body bodyA, Body bodyB, Vector2 anchor) {
    final def = f2d.WheelJointDef()
      ..initialize(bodyA, bodyB, anchor, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping
      ..maxMotorTorque = 20.0
      ..enableMotor = false;
    
    final joint = f2d.WheelJoint(def);
    world.createJoint(joint);
    return joint;
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    chassisBody.angularVelocity = tilt * 7.0;

    if (isGas) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = 55.0; 
      rearJoint.setMaxMotorTorque(25.0); 
    } else {
      rearJoint.enableMotor(false); 
    }

    if (isBrake) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = 0;
      rearJoint.setMaxMotorTorque(150.0);
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFFFF69B4)
      ..strokeWidth = 0.15
      ..style = PaintingStyle.stroke;

    final chassisPos = _chassisComp.body.position;
    final fPos = _frontWheelComp.body.position;
    final rPos = _rearWheelComp.body.position;

    final fLocal = Offset(fPos.x - chassisPos.x, fPos.y - chassisPos.y);
    final rLocal = Offset(rPos.x - chassisPos.x, rPos.y - chassisPos.y);

    canvas.drawLine(Offset.zero, fLocal, paint);
    canvas.drawLine(Offset.zero, rLocal, paint);
    canvas.drawLine(fLocal, rLocal, paint);

    canvas.drawCircle(Offset.zero, 0.4, Paint()..color = Colors.white);
  }
}