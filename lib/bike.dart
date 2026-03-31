import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// 1. The Wheels
class Wheel extends BodyComponent {
  final Vector2 initialPosition;
  Wheel(this.initialPosition);

  @override
  Body createBody() {
    final shape = CircleShape()..radius = 0.75;
    final fixtureDef = FixtureDef(
      shape,
      density: 0.5,
      friction: 0.9,     // Grippy rubber tires
      restitution: 0.1,  // Not too bouncy on their own
    );
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.2;
    
    // Draw the tire
    canvas.drawCircle(Offset.zero, 0.75, paint);
    // Draw a spoke line so we can actually see it spinning!
    canvas.drawLine(Offset.zero, const Offset(0.75, 0), paint);
  }
}

// 2. The Chassis (The Blue Box)
class Chassis extends BodyComponent {
  final Vector2 initialPosition;
  Chassis(this.initialPosition);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(2.0, 0.5);
    final fixtureDef = FixtureDef(
      shape,
      density: 1.0, // Chassis is heavier than the wheels
      friction: 0.3,
      restitution: 0.2,
    );
    final bodyDef = BodyDef(
      userData: this,
      position: initialPosition,
      type: BodyType.dynamic,
    );
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()..color = Colors.blueAccent;
    canvas.drawRect(const Rect.fromLTRB(-2, -0.5, 2, 0.5), paint);
  }
}

// 3. The Assembler (Bolts it all together)
class Bike extends Component with HasWorldReference<Forge2DWorld> {
  final Vector2 initialPosition;
  Bike({required this.initialPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Spawn the individual parts
    final chassis = Chassis(initialPosition);
    final rearWheel = Wheel(initialPosition + Vector2(-1.5, 1.0));
    final frontWheel = Wheel(initialPosition + Vector2(1.5, 1.0));

    // Add them to the world and wait for the physics engine to register them
    await world.addAll([chassis, rearWheel, frontWheel]);

    // --- INDEPENDENT SUSPENSION TUNING ---
    
    // Rear Shock Settings (Softer/Springier)
    double rearStiffness = 4.0; 
    double rearDamping = 0.4;   // Lower = More bounce/spring-back
    
    // Front Fork Settings (Stiffer for landings)
    double frontStiffness = 5.0; 
    double frontDamping = 0.5;

    // Rear Joint
    final rearAxis = Vector2(-0.2, 1.0)..normalize();
    final rearJointDef = WheelJointDef()
      ..initialize(chassis.body, rearWheel.body, rearWheel.body.position, rearAxis)
      ..dampingRatio = rearDamping
      ..frequencyHz = rearStiffness;
    
    // Front Joint
    final frontAxis = Vector2(0.4, 1.0)..normalize();
    final frontJointDef = WheelJointDef()
      ..initialize(chassis.body, frontWheel.body, frontWheel.body.position, frontAxis)
      ..dampingRatio = frontDamping
      ..frequencyHz = frontStiffness;

    // Bolt them on
    world.physicsWorld.createJoint(WheelJoint(rearJointDef));
    world.physicsWorld.createJoint(WheelJoint(frontJointDef));
  }
}
