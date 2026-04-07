import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:forge2d/forge2d.dart' as f2d;

/// Chassis body — rendered by [BodyComponent] like the track.
class _ChassisPart extends BodyComponent {
  _ChassisPart({required this.initialPosition});

  final Vector2 initialPosition;

  @override
  Body createBody() {
    final body = world.createBody(BodyDef()
      ..position = initialPosition
      ..type = BodyType.dynamic
      ..angularDamping = 1.8);
    final head = body.createFixture(FixtureDef(
      CircleShape()..radius = 0.4,
      density: 1.0,
    ));
    head.userData = 'head';
    return body;
  }
}

class _WheelPart extends BodyComponent {
  _WheelPart({required this.position});

  final Vector2 position;

  @override
  Body createBody() {
    final shape = CircleShape()..radius = Bike.wheelRadius;
    return world.createBody(BodyDef()
      ..position = position
      ..type = BodyType.dynamic)
      ..createFixture(FixtureDef(shape)..friction = 0.9..density = 1.2);
  }
}

class Bike extends Component with HasGameRef<Forge2DGame> {
  final Vector2 initialPosition;
  late final _ChassisPart _chassis;
  late final _WheelPart _frontWheelComp;
  late final _WheelPart _rearWheelComp;

  late WheelJoint rearJoint;
  late WheelJoint frontJoint;

  static const double wheelBase = 2.8;
  static const double wheelRadius = 0.5;
  static const double hz = 18.0;
  static const double damping = 0.8;

  Bike({required this.initialPosition});

  Body get chassis => _chassis.body;
  Body get frontWheel => _frontWheelComp.body;
  Body get rearWheel => _rearWheelComp.body;

  @override
  Future<void> onLoad() async {
    final frontPos = initialPosition + Vector2(wheelBase / 2, 0.8);
    final rearPos = initialPosition + Vector2(-wheelBase / 2, 0.8);
    _chassis = _ChassisPart(initialPosition: initialPosition);
    _frontWheelComp = _WheelPart(position: frontPos);
    _rearWheelComp = _WheelPart(position: rearPos);

    await add(_chassis);
    await add(_frontWheelComp);
    await add(_rearWheelComp);

    final pw = gameRef.world.physicsWorld;
    final frontAnchor = initialPosition + Vector2(wheelBase / 2, 0.8);
    final rearAnchor = initialPosition + Vector2(-wheelBase / 2, 0.8);
    frontJoint = _makeJoint(pw, _chassis.body, _frontWheelComp.body, frontAnchor);
    rearJoint = _makeJoint(pw, _chassis.body, _rearWheelComp.body, rearAnchor);
  }

  WheelJoint _makeJoint(f2d.World world, Body bodyA, Body bodyB, Vector2 anchorWorld) {
    final def = WheelJointDef()
      ..initialize(bodyA, bodyB, anchorWorld, Vector2(0, 1))
      ..frequencyHz = hz
      ..dampingRatio = damping
      ..maxMotorTorque = 25.0
      ..enableMotor = false;
    final joint = f2d.WheelJoint(def);
    world.createJoint(joint);
    return joint;
  }

  void updateControl(double tilt, bool isGas, bool isBrake) {
    chassis.angularVelocity = tilt * 6.5;

    if (isGas) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = -55.0;
      rearJoint.setMaxMotorTorque(25.0);
    } else {
      rearJoint.enableMotor(false);
    }

    if (isBrake) {
      rearJoint.enableMotor(true);
      rearJoint.motorSpeed = 0;
      rearJoint.setMaxMotorTorque(125.0);
    }
  }
}
