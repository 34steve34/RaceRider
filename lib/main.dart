import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
  ]);
  runApp(GameWidget(game: RaceRiderGame()));
}

Offset _off(Vector2 v) => Offset(v.x, v.y);

class RaceRiderGame extends FlameGame with TapCallbacks {
  static const buildLabel = 'physics v9 - 2026-04-25';
  late Bike player;
  late List<TrackSegment> trackSegments;
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  double tiltZero = 0.0;
  bool tiltCalibrated = false;
  bool isGas = false;
  bool isBrake = false;
  late StreamSubscription _accelSub;

  @override
  Future<void> onLoad() async {
    trackSegments = _buildTrack();
    player = Bike(_spawnPoint());
    player.settleOnTrack(trackSegments);
    add(Background());
    add(DebugOverlay());
    camera.viewfinder
      ..zoom = 2.1
      ..anchor = Anchor.center;
    _accelSub = accelerometerEvents.listen((e) => rawTilt = e.y);
  }

  @override
  void onRemove() {
    _accelSub.cancel();
    super.onRemove();
  }

  List<TrackSegment> _buildTrack() {
    final points = <Vector2>[
      Vector2(-700.0, 38.0),
      Vector2(-250.0, 38.0),
      Vector2(-120.0, 26.0),
      Vector2(20.0, 18.0),
      Vector2(170.0, 34.0),
      Vector2(310.0, 30.0),
      Vector2(430.0, 40.0),
      Vector2(510.0, 40.0),
      Vector2(560.0, 40.0),
      Vector2(604.0, 36.0),
      Vector2(642.0, 18.0),
      Vector2(672.0, 8.0),
    ];

    final segs = <TrackSegment>[];
    for (int i = 0; i < points.length - 1; i++) {
      segs.add(TrackSegment(points[i], points[i + 1]));
    }

    final landingRamp = <Vector2>[
      Vector2(928.0, 26.0),
      Vector2(1018.0, 112.0),
      Vector2(1090.0, 138.0),
      Vector2(1100.0, 130.0),
      Vector2(1240.0, 98.0),
      Vector2(1390.0, 114.0),
      Vector2(1540.0, 76.0),
      Vector2(1710.0, 124.0),
      Vector2(1910.0, 112.0),
      Vector2(2120.0, 112.0),
    ];
    for (int i = 0; i < landingRamp.length - 1; i++) {
      segs.add(TrackSegment(landingRamp[i], landingRamp[i + 1]));
    }

    final loopCenter = Vector2(840.0, -94.0);
    const loopRadius = 106.0;
    const loopSteps = 48;
    const startAngle = 2.34;
    const endAngle = 6.96;
    Vector2? prev;
    for (int i = 0; i <= loopSteps; i++) {
      final t = i / loopSteps;
      final a = startAngle + t * (endAngle - startAngle);
      final p = Vector2(
        loopCenter.x + cos(a) * loopRadius,
        loopCenter.y + sin(a) * loopRadius,
      );
      if (prev != null) {
        segs.add(TrackSegment(prev, p));
      }
      prev = p;
    }

    return segs;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!tiltCalibrated) {
      tiltZero = rawTilt;
      tiltCalibrated = true;
    }
    final normalized = (-(rawTilt - tiltZero) / 5.5).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.2 + normalized * 0.8;
    if (smoothedTilt.abs() < 0.05) {
      smoothedTilt = 0.0;
    }
    player.updateBike(dt, smoothedTilt, isGas, isBrake, trackSegments);
    if (!player.hasFiniteState) {
      player = Bike(_spawnPoint());
      player.settleOnTrack(trackSegments);
    }
    camera.viewfinder.position = player.position;
  }

  @override
  void onTapDown(TapDownEvent event) {
    isBrake = event.localPosition.x < size.x / 2;
    isGas = !isBrake;
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(camera.viewfinder.zoom);
    canvas.translate(-player.position.x, -player.position.y);

    final trackPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in trackSegments) {
      canvas.drawLine(_off(s.a), _off(s.b), trackPaint);
    }

    final markerPaint = Paint()
      ..color = const Color(0xFFFFFF44)
      ..strokeWidth = 1.5;
    final markerTextStyle = const TextStyle(
      color: Color(0xFFFFFF44),
      fontSize: 9,
    );
    for (int mx = -700; mx < 2600; mx += 300) {
      canvas.drawLine(
        Offset(mx.toDouble(), -120.0),
        Offset(mx.toDouble(), 50.0),
        markerPaint,
      );
      TextPainter(
        text: TextSpan(
          text: '${((mx + 700) ~/ 300)}s',
          style: markerTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout()
       ..paint(canvas, Offset(mx.toDouble() + 2.0, -130.0));
    }

    player.renderBike(canvas);
    canvas.restore();
  }

  Vector2 _spawnPoint() {
    const x = -540.0;
    const trackY = 38.0;
    return Vector2(x, trackY - Bike.spawnBodyYOffset);
  }
}

class TrackSegment {
  final Vector2 a;
  final Vector2 b;

  TrackSegment(this.a, this.b);

  Vector2 get delta => b - a;
  Vector2 get tangent => delta.normalized();
}

class SurfaceHit {
  final Vector2 point;
  final Vector2 normal;
  final Vector2 tangent;
  final double distance;

  const SurfaceHit({
    required this.point,
    required this.normal,
    required this.tangent,
    required this.distance,
  });
}

class WheelContact {
  final SurfaceHit hit;
  final double distance;
  final double compression;

  const WheelContact({
    required this.hit,
    required this.distance,
    required this.compression,
  });
}

enum BikeState { riding, crashed }

class Bike {
  static const _gravity = 125.0;
  static const _rearDrive = 420.0;
  static const _brakePerWheel = 430.0;
  static const _coastDrag = 0.9;
  static const _twoWheelTiltLift = 0.85;
  static const _freePitchAuthority = 1.05;
  static const _airDrag = 0.06;
  static const _maxSpeed = 250.0;
  static const _wheelRadius = 4.7;
  static const _headRadius = 2.4;
  static const _magnetRange = 0.04;
  static const _magnetStrength = 0.002;
  static const _groundStick = 0.002;
  static const _impactCrashSpeed = 280.0;
  static const _wheelSpinDamp = 0.985;
  static const _rearMass = 1.35;
  static const _frontMass = 1.0;
  static const _frameStiffness = 1.0;
  static const _suspensionTravel = 0.22;

  static final _rearLocal = Vector2(-7.0, 6.5);
  static final _frontLocal = Vector2(8.5, 6.5);
  static final _headLocal = Vector2(-3.5, -12.5);
  static double get spawnBodyYOffset => _rearLocal.y + _wheelRadius;

  late Vector2 rearPos;
  late Vector2 frontPos;
  late Vector2 headPos;
  late Vector2 rearVel;
  late Vector2 frontVel;
  late Vector2 headVel;

  BikeState state = BikeState.riding;
  bool rearOnGround = false;
  bool frontOnGround = false;
  double rearCompression = 0.0;
  double frontCompression = 0.0;
  double rearWheelAngle = 0.0;
  double frontWheelAngle = 0.0;
  double rearWheelAngVel = 0.0;
  double frontWheelAngVel = 0.0;
  SurfaceHit? _rearSurface;
  SurfaceHit? _frontSurface;

  late final double _wheelbase;
  late final Vector2 _headFromWheelCenter;

  Bike(Vector2 startPos) {
    rearPos = startPos + _rearLocal;
    frontPos = startPos + _frontLocal;
    headPos = startPos + _headLocal;
    rearVel = Vector2.zero();
    frontVel = Vector2.zero();
    headVel = Vector2.zero();
    _wheelbase = (_frontLocal - _rearLocal).length;
    _headFromWheelCenter = _headLocal - (_rearLocal + _frontLocal) / 2.0;
  }

  Vector2 get position => (rearPos * 1.8 + frontPos * 1.2 + headPos * 0.5) / 3.5;

  double get angle {
    final axis = frontPos - rearPos;
    return atan2(axis.y, axis.x);
  }

  double get speed => ((rearVel + frontVel + headVel) / 3.0).length;

  bool get crashed => state == BikeState.crashed;
  bool get hasFiniteState {
    final vectors = [rearPos, frontPos, headPos, rearVel, frontVel, headVel];
    for (final v in vectors) {
      if (!v.x.isFinite || !v.y.isFinite) {
        return false;
      }
    }
    return position.x.isFinite &&
        position.y.isFinite &&
        angle.isFinite &&
        speed.isFinite;
  }

  void settleOnTrack(List<TrackSegment> segs) {
    final rearHit = _nearestSurface(rearPos, segs);
    final frontHit = _nearestSurface(frontPos, segs);
    if (rearHit == null || frontHit == null) {
      return;
    }

    rearPos = rearHit.point + rearHit.normal * _wheelRadius;
    frontPos = frontHit.point + frontHit.normal * _wheelRadius;
    _alignHeadToFrame();

    rearVel.setZero();
    frontVel.setZero();
    headVel.setZero();
    rearOnGround = true;
    frontOnGround = true;
    rearCompression = 0.0;
    frontCompression = 0.0;
    _rearSurface = rearHit;
    _frontSurface = frontHit;
  }

  void updateBike(
    double dt,
    double tilt,
    bool gas,
    bool brake,
    List<TrackSegment> segs,
  ) {
    const substeps = 10;
    final stepDt = dt / substeps;
    for (int i = 0; i < substeps; i++) {
      _step(stepDt, tilt, gas, brake, segs);
    }
  }

  void _step(
    double dt,
    double tilt,
    bool gas,
    bool brake,
    List<TrackSegment> segs,
  ) {
    if (state == BikeState.crashed) {
      rearVel *= 0.99;
      frontVel *= 0.99;
      headVel *= 0.99;
      rearPos += rearVel * dt;
      frontPos += frontVel * dt;
      headPos += headVel * dt;
      _updateWheelRotation(dt, brake);
      return;
    }

    rearVel.y += _gravity * dt;
    frontVel.y += _gravity * dt;
    headVel.y += _gravity * dt;

    final twoWheelGrounded = rearOnGround && frontOnGround;
    _applyTiltImpulse(
      tilt,
      tilt * _freePitchAuthority * dt,
      twoWheelGrounded: twoWheelGrounded,
    );

    final oldRear = rearPos.clone();
    final oldFront = frontPos.clone();
    rearPos += rearVel * dt;
    frontPos += frontVel * dt;
    headPos += headVel * dt;

    final wasAirborne = !(rearOnGround || frontOnGround);
    rearOnGround = false;
    frontOnGround = false;
    rearCompression = 0.0;
    frontCompression = 0.0;
    SurfaceHit? rearSurface;
    SurfaceHit? frontSurface;

    for (int i = 0; i < 12; i++) {
      _solveBoundedDistance(
        rearPos,
        frontPos,
        _wheelbase,
        _wheelbase,
        _frameStiffness,
        _rearMass,
        _frontMass,
      );
      _alignHeadToFrame();

      final rearContact = _solveWheelContact(
        rearPos,
        rearVel,
        segs,
        allowAssist: wasAirborne,
      );
      if (rearContact != null) {
        rearOnGround = true;
        rearSurface = rearContact.hit;
        rearCompression = rearContact.compression;
      }

      final frontContact = _solveWheelContact(
        frontPos,
        frontVel,
        segs,
        allowAssist: wasAirborne,
      );
      if (frontContact != null) {
        frontOnGround = true;
        frontSurface = frontContact.hit;
        frontCompression = frontContact.compression;
      }

      if (_headHitsTrack(segs)) {
        _crash();
        break;
      }
    }

    if (state == BikeState.crashed) {
      rearVel = (rearPos - oldRear) / dt;
      frontVel = (frontPos - oldFront) / dt;
      headVel = (rearVel + frontVel) * 0.5;
      _updateWheelRotation(dt, brake);
      return;
    }

    rearVel = (rearPos - oldRear) / dt;
    frontVel = (frontPos - oldFront) / dt;
    _alignHeadToFrame();
    headVel = (rearVel + frontVel) * 0.5;

    if (!rearOnGround && !frontOnGround) {
      final avg = (rearVel + frontVel + headVel) / 3.0;
      const spinRetention = 0.87;
      rearVel = avg + (rearVel - avg) * spinRetention;
      frontVel = avg + (frontVel - avg) * spinRetention;
      headVel = avg + (headVel - avg) * spinRetention;
    }

    _rearSurface = rearSurface;
    _frontSurface = frontSurface;
    _applyDriveAndBrake(dt, gas, brake);

    final damp = max(0.0, 1.0 - _airDrag * dt);
    rearVel *= damp;
    frontVel *= damp;
    headVel *= damp;
    _capSpeed();

    _updateWheelRotation(dt, brake);
  }

  void _applyDriveAndBrake(double dt, bool gas, bool brake) {
    if (rearOnGround && _rearSurface != null && gas) {
      final tangent = _forwardTangent(_rearSurface!.tangent);
      rearVel += tangent * (_rearDrive * dt);
      frontVel += tangent * (_rearDrive * dt * 0.18);
    }

    if (brake) {
      if (rearOnGround && _rearSurface != null) {
        _applyBrakeAtWheel(rearVel, _rearSurface!.tangent, dt);
      }
      if (frontOnGround && _frontSurface != null) {
        _applyBrakeAtWheel(frontVel, _frontSurface!.tangent, dt);
      }
    } else {
      if (rearOnGround && _rearSurface != null) {
        _applyCoastDrag(rearVel, _rearSurface!.tangent, dt);
      }
      if (frontOnGround && _frontSurface != null) {
        _applyCoastDrag(frontVel, _frontSurface!.tangent, dt);
      }
    }
  }

  void _applyBrakeAtWheel(Vector2 velocity, Vector2 tangent, double dt) {
    final forward = _forwardTangent(tangent);
    final speedAlong = velocity.dot(forward);
    if (speedAlong.abs() < 0.001) {
      return;
    }
    final delta = _brakePerWheel * dt;
    final next = speedAlong > 0
        ? max(0.0, speedAlong - delta)
        : min(0.0, speedAlong + delta);
    velocity.add(forward * (next - speedAlong));
  }

  void _applyCoastDrag(Vector2 velocity, Vector2 tangent, double dt) {
    final forward = _forwardTangent(tangent);
    final speedAlong = velocity.dot(forward);
    if (speedAlong.abs() < 0.001) {
      return;
    }
    final next = speedAlong > 0
        ? max(0.0, speedAlong - _coastDrag * dt)
        : min(0.0, speedAlong + _coastDrag * dt);
    velocity.add(forward * (next - speedAlong));
  }

  void _applyTiltImpulse(double tilt, double impulse, {required bool twoWheelGrounded}) {
    final frame = frontPos - rearPos;
    if (frame.length2 <= 0.0001) {
      return;
    }

    final frameDir = frame.normalized();
    final up = Vector2(frameDir.y, -frameDir.x);

    if (twoWheelGrounded) {
      // Two-wheel grounded mode: smooth front-wheel unloading with only a mild
      // pitch bias, so wheelies begin early without turning into an on/off
      // threshold. Nose-down never yanks the rear wheel upward.
      final backTilt = max(0.0, tilt);
      final noseTilt = max(0.0, -tilt);

      final wheelieBlend = ((backTilt - 0.05) / 0.12).clamp(0.0, 1.0);
      final loadShift =
          up * (backTilt * (_twoWheelTiltLift + 1.65 * wheelieBlend));
      frontVel.add(loadShift);
      rearVel.sub(loadShift * (0.55 + 0.15 * wheelieBlend));

      final pitchBias = up * (backTilt * wheelieBlend * 0.8);
      frontVel.add(pitchBias);
      rearVel.sub(pitchBias);

      final settle = up * (-noseTilt * 0.75);
      frontVel.add(settle);
      rearVel.add(settle * 0.12);
      return;
    }

    // Free-pitch mode: same authority whether the bike is on the rear wheel
    // only or fully airborne.
    final pitch = up * (tilt * 1.0);
    frontVel.add(pitch);
    rearVel.sub(pitch);
  }

  WheelContact? _solveWheelContact(
    Vector2 pos,
    Vector2 vel,
    List<TrackSegment> segs,
    {required bool allowAssist}
  ) {
    final hit = _nearestSurface(pos, segs);
    if (hit == null) {
      return null;
    }

    final targetDistance = _wheelRadius;
    final magnetDistance = targetDistance + _magnetRange;
    final incoming = -vel.dot(hit.normal);

    if (hit.distance < targetDistance && incoming > _impactCrashSpeed) {
      _crash();
      return null;
    }

    if (hit.distance < targetDistance) {
      pos.add(hit.normal * (targetDistance - hit.distance));
      final normalSpeed = vel.dot(hit.normal);
      if (normalSpeed < 0.0) {
        vel.sub(hit.normal * normalSpeed);
      }
    } else if (allowAssist && hit.distance < magnetDistance && vel.dot(hit.normal) < 4.0) {
      final pull = (magnetDistance - hit.distance) / _magnetRange;
      pos.add(
        hit.normal * (targetDistance - hit.distance) * (_magnetStrength * pull),
      );
      final normalSpeed = vel.dot(hit.normal);
      vel.sub(hit.normal * (normalSpeed * _groundStick * pull));
    } else {
      return null;
    }

    return WheelContact(
      hit: hit,
      distance: hit.distance,
      compression: (magnetDistance - hit.distance).clamp(0.0, _suspensionTravel),
    );
  }

  bool _headHitsTrack(List<TrackSegment> segs) {
    final hit = _nearestSurface(headPos, segs);
    return hit != null && hit.distance < _headRadius;
  }

  SurfaceHit? _nearestSurface(Vector2 point, List<TrackSegment> segs) {
    SurfaceHit? best;
    var bestDist = double.infinity;

    for (final seg in segs) {
      final delta = seg.delta;
      final len2 = delta.length2;
      if (len2 == 0.0) {
        continue;
      }
      final t = ((point - seg.a).dot(delta) / len2).clamp(0.0, 1.0);
      final closest = seg.a + delta * t;
      final diff = point - closest;
      final dist = diff.length;
      if (dist >= bestDist) {
        continue;
      }
      final tangent = delta.normalized();
      final normal = dist > 0.0001
          ? diff / dist
          : Vector2(-tangent.y, tangent.x);
      bestDist = dist;
      best = SurfaceHit(
        point: closest,
        normal: normal,
        tangent: tangent,
        distance: dist,
      );
    }
    return best;
  }

  void _solveBoundedDistance(
    Vector2 a,
    Vector2 b,
    double minDist,
    double maxDist,
    double stiffness,
    double massA,
    double massB,
  ) {
    final delta = b - a;
    final dist = delta.length;
    if (dist < 0.0001) {
      return;
    }

    double error = 0.0;
    if (dist < minDist) {
      error = dist - minDist;
    } else if (dist > maxDist) {
      error = dist - maxDist;
    } else {
      return;
    }

    final correction = delta / dist * (error * stiffness);
    final invA = 1.0 / massA;
    final invB = 1.0 / massB;
    final sum = invA + invB;
    a.add(correction * (invA / sum));
    b.sub(correction * (invB / sum));
  }

  Vector2 _forwardTangent(Vector2 tangent) {
    var dir = tangent.normalized();
    if (dir.x < 0.0) {
      dir = -dir;
    }
    return dir;
  }

  void _updateWheelRotation(double dt, bool brake) {
    if (rearOnGround && _rearSurface != null) {
      rearWheelAngVel = rearVel.dot(_forwardTangent(_rearSurface!.tangent)) / _wheelRadius;
      rearWheelAngle += rearWheelAngVel * dt;
    } else {
      if (brake) {
        rearWheelAngVel = 0.0;
      } else {
        rearWheelAngVel *= _wheelSpinDamp;
      }
      rearWheelAngle += rearWheelAngVel * dt;
    }

    if (frontOnGround && _frontSurface != null) {
      frontWheelAngVel = frontVel.dot(_forwardTangent(_frontSurface!.tangent)) / _wheelRadius;
      frontWheelAngle += frontWheelAngVel * dt;
    } else {
      if (brake) {
        frontWheelAngVel = 0.0;
      } else {
        frontWheelAngVel *= _wheelSpinDamp;
      }
      frontWheelAngle += frontWheelAngVel * dt;
    }
  }

  void _capSpeed() {
    final avgVelocity = (rearVel + frontVel + headVel) / 3.0;
    final speed = avgVelocity.length;
    if (speed <= _maxSpeed || speed == 0.0) {
      return;
    }

    final scale = _maxSpeed / speed;
    rearVel.scale(scale);
    frontVel.scale(scale);
    headVel.scale(scale);
  }

  void _alignHeadToFrame() {
    final axis = frontPos - rearPos;
    if (axis.length2 <= 0.0001) {
      return;
    }
    final frameDir = axis.normalized();
    final down = Vector2(-frameDir.y, frameDir.x);
    final frameCenter = (rearPos + frontPos) / 2.0;
    headPos =
        frameCenter +
        frameDir * _headFromWheelCenter.x +
        down * _headFromWheelCenter.y;
  }

  void _crash() {
    state = BikeState.crashed;
  }

  void renderBike(Canvas canvas) {
    final frame = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final fork = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 3.3
      ..style = PaintingStyle.stroke;
    final body = Paint()..color = const Color(0xFFFF4400);
    final seat = Paint()..color = const Color(0xFF111111);
    final rider = Paint()..color = const Color(0xFF2255BB);
    final wheelFill = Paint()..color = Colors.white;
    final wheelRim = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final spoke = Paint()
      ..color = const Color(0xFFFFFF44)
      ..strokeWidth = 1.5;

    _drawWheel(canvas, rearPos, rearWheelAngle, wheelFill, wheelRim, spoke);
    _drawWheel(canvas, frontPos, frontWheelAngle, wheelFill, wheelRim, spoke);

    final bodyTop = (rearPos + headPos) / 2.0;
    final seatPoint = headPos + Vector2(-1.2, 1.4);
    final tankPoint = (frontPos + headPos) / 2.0;

    canvas.drawLine(_off(rearPos), _off(bodyTop), frame);
    canvas.drawLine(_off(bodyTop), _off(frontPos), frame);
    canvas.drawLine(_off(frontPos), _off(headPos), fork);
    canvas.drawLine(_off(rearPos), _off(headPos), frame);
    canvas.drawLine(_off(seatPoint), _off(seatPoint + Vector2(5.0, -0.8)), fork);

    final bodyPath = Path()
      ..moveTo(bodyTop.x - 4.0, bodyTop.y + 1.4)
      ..lineTo(tankPoint.x + 1.0, tankPoint.y + 1.0)
      ..lineTo(tankPoint.x + 2.5, tankPoint.y - 3.0)
      ..lineTo(bodyTop.x - 3.0, bodyTop.y - 3.3)
      ..close();
    canvas.drawPath(bodyPath, body);
    canvas.drawRect(
      Rect.fromCenter(
        center: _off(seatPoint),
        width: 9.0,
        height: 2.4,
      ),
      seat,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: _off((headPos + bodyTop) / 2.0),
        width: 6.0,
        height: 5.0,
      ),
      rider,
    );
    canvas.drawCircle(_off(headPos), _headRadius, rider);

    if (state == BikeState.crashed) {
      final crashText = TextPainter(
        textDirection: TextDirection.ltr,
        text: const TextSpan(
          text: 'CRASHED',
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      )..layout();
      crashText.paint(canvas, _off(headPos + Vector2(-14.0, -16.0)));
    }
  }

  void _drawWheel(
    Canvas canvas,
    Vector2 center,
    double wheelAngle,
    Paint fill,
    Paint rim,
    Paint spokePaint,
  ) {
    canvas.drawCircle(_off(center), _wheelRadius, fill);
    canvas.drawCircle(_off(center), 3.1, rim);
    const numSpokes = 3;
    const spokeLength = 3.1;
    for (int i = 0; i < numSpokes; i++) {
      final angle = wheelAngle + (i * 2 * pi / numSpokes);
      final spokeEnd = Vector2(
        center.x + cos(angle) * spokeLength,
        center.y + sin(angle) * spokeLength,
      );
      canvas.drawLine(_off(center), _off(spokeEnd), spokePaint);
    }
  }
}

class Background extends Component {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(-5000.0, -5000.0, 16000.0, 16000.0),
      Paint()..color = const Color(0xFF112233),
    );
  }
}

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final bike = gameRef.player;
    TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: '3-point prototype'
            '\n${RaceRiderGame.buildLabel}'
            '\nState:  ${bike.state.name}'
            '\nCtrl:   ${bike.rearOnGround && bike.frontOnGround ? '2-wheel' : 'free-pitch'}'
            '\nTilt:   ${gameRef.smoothedTilt.toStringAsFixed(2)}'
            '\nFinite: ${bike.hasFiniteState}'
            '\nSpeed:  ${bike.speed.toStringAsFixed(1)}'
            '\nAngle:  ${bike.angle.toStringAsFixed(2)} rad'
            '\nPos:    ${bike.position.x.toStringAsFixed(1)}, ${bike.position.y.toStringAsFixed(1)}'
            '\nRear:   ${bike.rearOnGround}  comp ${bike.rearCompression.toStringAsFixed(2)}'
            '\nFront:  ${bike.frontOnGround}  comp ${bike.frontCompression.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    )..layout()
     ..paint(canvas, const Offset(16.0, 16.0));
  }
}
