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
  static const buildLabel = 'physics v14 - Decoupled Master/Slave';
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
    const startAngle = 2.62;
    const endAngle = 6.68;
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
    // Fixed logic: Removing negative sign for 'phone right side up = wheelie'
    final normalized = ((rawTilt - tiltZero) / 5.5).clamp(-1.0, 1.0);
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
  static const _gravity = 800.0;
  static const _rearDrive = 420.0;
  static const _brakePerWheel = 430.0;
  static const _coastDrag = 0.9;
  static const _airDrag = 0.08;
  static const _maxSpeed = 250.0;
  static const _wheelRadius = 4.7;
  static const _headRadius = 2.4;
  static const _magnetRange = 0.04;
  static const _magnetStrength = 0.002;
  static const _groundStick = 0.002;
  static const _impactCrashSpeed = 280.0;
  static const _wheelSpinDamp = 0.985;
  static const _frameStiffness = 1.0;
  static const _suspensionTravel = 0.22;

  static final _rearLocal = Vector2(-7.0, 6.5);
  static final _frontLocal = Vector2(8.5, 6.5);
  static final _headLocal = Vector2(-3.5, -12.5);
  static final _cogLocal = Vector2(-5.0, -3.0);
  static double get spawnBodyYOffset => _rearLocal.y + _wheelRadius;

  late Vector2 rearPos;
  late Vector2 frontPos;
  late Vector2 headPos;
  late Vector2 cogPos;
  late Vector2 rearVel;
  late Vector2 frontVel;
  late Vector2 headVel;
  late Vector2 cogVel;

  BikeState state = BikeState.riding;
  bool rearOnGround = false;
  bool frontOnGround = false;
  double rearCompression = 0.0;
  double frontCompression = 0.0;
  double rearWheelAngle = 0.0;
  double frontWheelAngle = 0.0;
  double rearWheelAngVel = 0.0;
  double frontWheelAngVel = 0.0;
  double freePitchBlend = 0.0;
  SurfaceHit? _rearSurface;
  SurfaceHit? _frontSurface;

  late final double _wheelbase;
  late final double _distRH;
  late final double _distFH;
  late final Vector2 _headFromWheelCenter;

  Bike(Vector2 startPos) {
    rearPos = startPos + _rearLocal;
    frontPos = startPos + _frontLocal;
    headPos = startPos + _headLocal;
    cogPos = startPos + _cogLocal;
    rearVel = Vector2.zero();
    frontVel = Vector2.zero();
    headVel = Vector2.zero();
    cogVel = Vector2.zero();
    _wheelbase = (_frontLocal - _rearLocal).length;
    _distRH = (_headLocal - _rearLocal).length;
    _distFH = (_headLocal - _frontLocal).length;
    _headFromWheelCenter = _headLocal - (_rearLocal + _frontLocal) / 2.0;
  }

  Vector2 get position => (rearPos * 1.8 + frontPos * 1.2 + headPos * 0.5) / 3.5;

  double get angle {
    final axis = frontPos - rearPos;
    return atan2(axis.y, axis.x);
  }

  double get speed => ((rearVel + frontVel + headVel) / 3.0).length;

  bool get hasFiniteState {
    final vectors = [rearPos, frontPos, headPos, cogPos, rearVel, frontVel, headVel, cogVel];
    for (final v in vectors) {
      if (!v.x.isFinite || !v.y.isFinite) return false;
    }
    return true;
  }

  void settleOnTrack(List<TrackSegment> segs) {
    final rearHit = _nearestSurface(rearPos, segs);
    final frontHit = _nearestSurface(frontPos, segs);
    if (rearHit == null || frontHit == null) return;

    rearPos = rearHit.point + rearHit.normal * _wheelRadius;
    frontPos = frontHit.point + frontHit.normal * _wheelRadius;
    _alignHeadToFrame();
    cogPos = (rearPos + frontPos + headPos) / 3.0;

    rearVel.setZero();
    frontVel.setZero();
    headVel.setZero();
    cogVel.setZero();
    rearOnGround = true;
    frontOnGround = true;
    _rearSurface = rearHit;
    _frontSurface = frontHit;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake, List<TrackSegment> segs) {
    const substeps = 10;
    final stepDt = dt / substeps;
    for (int i = 0; i < substeps; i++) {
      _step(stepDt, tilt, gas, brake, segs);
    }
  }

  void _step(double dt, double tilt, bool gas, bool brake, List<TrackSegment> segs) {
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

    // 1. Apply Gravity (Linear Force)
    final grav = Vector2(0, _gravity * dt);
    rearVel.add(grav);
    frontVel.add(grav);
    headVel.add(grav);

    // 2. Ground Detection & Interaction
    _updateGroundedStatus(segs);

    // 3. Drive Forces (Gas/Brake)
    _applyDriveAndBrake(dt, gas, brake);

    // 4. THE DECOUPLER: Capture Master Linear Velocity
    // This is the trajectory the bike wants to follow based on forces.
    cogVel = (rearVel + frontVel + headVel) / 3.0;

    // 5. Apply Rotation (Slave points pivot around the Master)
    _applyTiltImpulse(tilt);

    // 6. Integrate Positions
    rearPos.add(rearVel * dt);
    frontPos.add(frontVel * dt);
    headPos.add(headVel * dt);

    // 7. Solve Hard Constraints
    for (int i = 0; i < 5; i++) {
      _solveBoundedDistance(rearPos, frontPos, _wheelbase, _wheelbase, 1.0, 1.35, 1.0);
      _solveBoundedDistance(rearPos, headPos, _distRH, _distRH, 1.0, 1.35, 0.5);
      _solveBoundedDistance(frontPos, headPos, _distFH, _distFH, 1.0, 1.0, 0.5);
    }

    // 8. Friction and Speed Cap
    final damp = max(0.0, 1.0 - _airDrag * dt);
    rearVel *= damp;
    frontVel *= damp;
    headVel *= damp;
    _capSpeed();

    // 9. Visuals
    _updateWheelRotation(dt, brake);
  }

  void _updateGroundedStatus(List<TrackSegment> segs) {
    final wasAirborne = !(rearOnGround || frontOnGround);
    rearOnGround = false;
    frontOnGround = false;
    
    final rearContact = _solveWheelContact(rearPos, rearVel, segs, allowAssist: wasAirborne);
    if (rearContact != null) {
      rearOnGround = true;
      _rearSurface = rearContact.hit;
      rearCompression = rearContact.compression;
    }
    
    final frontContact = _solveWheelContact(frontPos, frontVel, segs, allowAssist: wasAirborne);
    if (frontContact != null) {
      frontOnGround = true;
      _frontSurface = frontContact.hit;
      frontCompression = frontContact.compression;
    }

    if (_headHitsTrack(segs)) _crash();
  }

  void _applyDriveAndBrake(double dt, bool gas, bool brake) {
    if (rearOnGround && _rearSurface != null && gas) {
      rearVel += _forwardTangent(_rearSurface!.tangent) * (_rearDrive * dt);
    }
    if (brake) {
      if (rearOnGround && _rearSurface != null) _applyBrakeAtWheel(rearVel, _rearSurface!.tangent, dt);
      if (frontOnGround && _frontSurface != null) _applyBrakeAtWheel(frontVel, _frontSurface!.tangent, dt);
    } else if (rearOnGround && _rearSurface != null) {
      _applyCoastDrag(rearVel, _rearSurface!.tangent, dt);
    }
  }

  void _applyBrakeAtWheel(Vector2 velocity, Vector2 tangent, double dt) {
    final forward = _forwardTangent(tangent);
    final speedAlong = velocity.dot(forward);
    if (speedAlong.abs() < 0.001) return;
    final delta = _brakePerWheel * dt;
    final next = speedAlong > 0 ? max(0.0, speedAlong - delta) : min(0.0, speedAlong + delta);
    velocity.add(forward * (next - speedAlong));
  }

  void _applyCoastDrag(Vector2 velocity, Vector2 tangent, double dt) {
    final forward = _forwardTangent(tangent);
    final speedAlong = velocity.dot(forward);
    if (speedAlong.abs() < 0.001) return;
    final next = speedAlong > 0 ? max(0.0, speedAlong - _coastDrag * dt) : min(0.0, speedAlong + _coastDrag * dt);
    velocity.add(forward * (next - speedAlong));
  }

  void _applyTiltImpulse(double tilt) {
    const maxOmega = 6.0; 
    double omega = tilt * maxOmega; 

    // Ground Authority
    if (rearOnGround && frontOnGround) {
      omega *= 0.45; 
    } else if (rearOnGround || frontOnGround) {
      omega *= 0.90; 
    }

    final masterVel = cogVel.clone();

    // TRUE DECOUPLING: We must rotate around the exact center of the 3 points.
    // Because masterVel is the average of the 3 points, rotating around this
    // specific point guarantees the rotation adds exactly 0.0 to the master speed.
    final trueCenterLocal = (_rearLocal + _frontLocal + _headLocal) / 3.0;

    void updatePoint(Vector2 localOffset, Vector2 currentVel, bool isGrounded, Vector2? normal) {
      final currentAngle = angle;
      
      // Radius from the TRUE geometric center, not the custom COG
      final worldRadius = (localOffset - trueCenterLocal)..rotate(currentAngle);
      
      // Counter-Clockwise rotation for positive omega
      final rotVel = Vector2(worldRadius.y, -worldRadius.x) * omega;

      // Safe Ground Collision (doesn't push bike into dirt)
      if (isGrounded && normal != null) {
        double intoGround = rotVel.dot(normal);
        if (intoGround < 0) rotVel.sub(normal * intoGround);
      }

      // No subtraction hacks. Pure Master + Slave logic.
      currentVel.setFrom(masterVel + rotVel);
    }

    // Pass in the base local offsets directly
    updatePoint(_rearLocal, rearVel, rearOnGround, _rearSurface?.normal);
    updatePoint(_frontLocal, frontVel, frontOnGround, _frontSurface?.normal);
    updatePoint(_headLocal, headVel, false, null);
  }

    applySafely(rearVel, pureRRot, rearOnGround, _rearSurface?.normal);
    applySafely(frontVel, pureFRot, frontOnGround, _frontSurface?.normal);
    applySafely(headVel, pureHRot, false, null);

    // 6. Resync the Master Velocity so the physics loop stays stable
    cogVel = (rearVel + frontVel + headVel) / 3.0;
  }

    void updatePoint(Vector2 localOffset, Vector2 currentPos, Vector2 currentVel, bool isGrounded, Vector2? surfaceNormal) {
      final currentAngle = angle;
      final worldRadius = localOffset.clone()..rotate(currentAngle);
      
      // Rotational velocity: Perpendicular to radius
      // Vector2(y, -x) for Counter-Clockwise (Front-up) if omega is positive
      final rotVel = Vector2(worldRadius.y, -worldRadius.x) * omega;

      // ANTI-JUMP: Ground Normal Clipping
      if (isGrounded && surfaceNormal != null) {
        double intoGround = rotVel.dot(surfaceNormal);
        if (intoGround < 0) rotVel.sub(surfaceNormal * intoGround);
      }

      currentVel.setFrom(masterVel + rotVel);
    }

    updatePoint(_rearLocal - _cogLocal, rearPos, rearVel, rearOnGround, _rearSurface?.normal);
    updatePoint(_frontLocal - _cogLocal, frontPos, frontVel, frontOnGround, _frontSurface?.normal);
    updatePoint(_headLocal - _cogLocal, headPos, headVel, false, null);
  }

  WheelContact? _solveWheelContact(Vector2 pos, Vector2 vel, List<TrackSegment> segs, {required bool allowAssist}) {
    final hit = _nearestSurface(pos, segs);
    if (hit == null) return null;

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
      if (normalSpeed < 0.0) vel.sub(hit.normal * normalSpeed * 0.82);
    } else if (allowAssist && hit.distance < magnetDistance && vel.dot(hit.normal) < 4.0) {
      final pull = (magnetDistance - hit.distance) / _magnetRange;
      pos.add(hit.normal * (targetDistance - hit.distance) * (_magnetStrength * pull));
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
      if (len2 == 0.0) continue;
      final t = ((point - seg.a).dot(delta) / len2).clamp(0.0, 1.0);
      final closest = seg.a + delta * t;
      final diff = point - closest;
      final dist = diff.length;
      if (dist >= bestDist) continue;
      final tangent = delta.normalized();
      bestDist = dist;
      best = SurfaceHit(
        point: closest,
        normal: dist > 0.0001 ? diff / dist : Vector2(-tangent.y, tangent.x),
        tangent: tangent,
        distance: dist,
      );
    }
    return best;
  }

  void _solveBoundedDistance(Vector2 a, Vector2 b, double minDist, double maxDist, double stiffness, double massA, double massB) {
    final delta = b - a;
    final dist = delta.length;
    if (dist < 0.0001) return;
    double error = 0.0;
    if (dist < minDist) error = dist - minDist;
    else if (dist > maxDist) error = dist - maxDist;
    else return;
    final correction = delta / dist * (error * stiffness);
    final sum = (1.0 / massA) + (1.0 / massB);
    a.add(correction * ((1.0 / massA) / sum));
    b.sub(correction * ((1.0 / massB) / sum));
  }

  Vector2 _forwardTangent(Vector2 tangent) {
    var dir = tangent.normalized();
    if (dir.x < 0.0) dir = -dir;
    return dir;
  }

  void _updateWheelRotation(double dt, bool brake) {
    if (rearOnGround && _rearSurface != null) {
      rearWheelAngVel = rearVel.dot(_forwardTangent(_rearSurface!.tangent)) / _wheelRadius;
    } else {
      rearWheelAngVel = brake ? 0.0 : rearWheelAngVel * _wheelSpinDamp;
    }
    rearWheelAngle += rearWheelAngVel * dt;

    if (frontOnGround && _frontSurface != null) {
      frontWheelAngVel = frontVel.dot(_forwardTangent(_frontSurface!.tangent)) / _wheelRadius;
    } else {
      frontWheelAngVel = brake ? 0.0 : frontWheelAngVel * _wheelSpinDamp;
    }
    frontWheelAngle += frontWheelAngVel * dt;
  }

  void _capSpeed() {
    final speed = cogVel.length;
    if (speed <= _maxSpeed) return;
    final scale = _maxSpeed / speed;
    rearVel.scale(scale);
    frontVel.scale(scale);
    headVel.scale(scale);
    cogVel.scale(scale);
  }

  void _alignHeadToFrame() {
    final axis = frontPos - rearPos;
    if (axis.length2 <= 0.0001) return;
    final frameDir = axis.normalized();
    final down = Vector2(-frameDir.y, frameDir.x);
    final frameCenter = (rearPos + frontPos) / 2.0;
    headPos = frameCenter + frameDir * _headFromWheelCenter.x + down * _headFromWheelCenter.y;
  }

  void _crash() => state = BikeState.crashed;

  void renderBike(Canvas canvas) {
    final frame = Paint()..color = const Color(0xFF333333)..strokeWidth = 3.0..style = PaintingStyle.stroke;
    final rider = Paint()..color = const Color(0xFF2255BB);
    final wheelRim = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 3.0;

    canvas.drawCircle(_off(rearPos), _wheelRadius, wheelRim);
    canvas.drawCircle(_off(frontPos), _wheelRadius, wheelRim);
    canvas.drawLine(_off(rearPos), _off(frontPos), frame);
    canvas.drawLine(_off(rearPos), _off(headPos), frame);
    canvas.drawLine(_off(frontPos), _off(headPos), frame);
    canvas.drawCircle(_off(headPos), _headRadius, rider);

    if (state == BikeState.crashed) {
      TextPainter(textDirection: TextDirection.ltr, text: const TextSpan(text: 'CRASHED', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)))..layout()..paint(canvas, _off(headPos + Vector2(-14, -16)));
    }
  }
}

class Background extends Component {
  @override
  void render(Canvas canvas) => canvas.drawRect(const Rect.fromLTWH(-5000, -5000, 16000, 16000), Paint()..color = const Color(0xFF112233));
}

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final bike = gameRef.player;
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(text: 'RaceRider Prototype\n${RaceRiderGame.buildLabel}\nState: ${bike.state.name}\nSpeed: ${bike.speed.toStringAsFixed(1)}\nAngle: ${bike.angle.toStringAsFixed(2)} rad', style: const TextStyle(color: Colors.yellow, fontSize: 14, fontWeight: FontWeight.bold)))..layout()..paint(canvas, const Offset(16, 16));
  }
}