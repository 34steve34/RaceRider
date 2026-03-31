import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(shape, density: 0.5, friction: 0.9, restitution: 0.1);
    final bodyDef = BodyDef(userData: this, position: initialPosition, type: BodyType.dynamic);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 0.2;
    canvas.drawCircle(Offset.zero, 0.75, paint);
    canvas.drawLine(Offset.zero, const Offset(0.75, 0), paint);
  }
}

class Chassis extends BodyComponent {
  final Vector2 initialPosition;
  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(2.0, 0.5);
    final fixtureDef = FixtureDef(shape, density: 1.0, friction: 0.3, restitution: 0.2);
    final bodyDef = BodyDef(userData: this, position: initialPosition, type: BodyType.dynamic);
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()..color = Colors.blueAccent;
    canvas.drawRect(const Rect.fromLTRB(-2, -0.5, 2, 0.5), paint);
  }
}

class Bike extends Component with HasWorldReference<Forge2DWorld> {
  final Vector2 initialPosition;
  late Chassis _chassisRef; 

  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _chassisRef = Chassis(initialPosition);
    final rearWheel = Wheel(initialPosition + Vector2(-1.5, 1.0));
    final frontWheel = Wheel(initialPosition + Vector2(1.5, 1.0));

    await world.addAll([_chassisRef, rearWheel, frontWheel]);

    // Suspension Tuning
    final rearJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, rearWheel.body, rearWheel.body.position, (Vector2(-0.2, 1.0)..normalize()))
      ..dampingRatio = 0.4
      ..frequencyHz = 4.0;
    
    final frontJointDef = WheelJointDef()
      ..initialize(_chassisRef.body, frontWheel.body, frontWheel.body.position, (Vector2(0.4, 1.0)..normalize()))
      ..dampingRatio = 0.5
      ..frequencyHz = 5.0;

    world.physicsWorld.createJoint(WheelJoint(rearJointDef));
    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }

  Vector2 getChassisPosition() => _chassisRef.isLoaded ? _chassisRef.body.position : initialPosition;
}
