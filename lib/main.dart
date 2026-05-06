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
  static const buildLabel = 'physics v.70 - PRO Architecture';
  late Bike player;
  late List<TrackSegment> trackSegments;
  
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  double tiltZero = 0.0;
  bool tiltCalibrated = false;
  bool isGas = false;
  bool isBrake = false;
  late StreamSubscription _accelSub;
  
  bool isTuningMode = false;
  int currentTuningParam = 0;
  final List<String> tuningParamNames = ['Torque', 'Jump', 'Mass', 'CogDist', 'CogHeight', 'MagStr', 'FrontTorque'];
  final List<double> tuningParamSteps = [10.0, 0.05, 1.0, 0.5, 0.5, 0.0005, 0.01];
  
  double crashTimer = 0.0;
  static const double _crashRestartDelay = 1.0;

  @override
  Future<void> onLoad() async {
    trackSegments = _buildTrack();
    player = Bike(_spawnPoint());
    player.trackSegments = trackSegments;
    player.settleOnTrack();
    
    add(Background());
    add(player);
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
      Vector2(-700.0, 38.0), Vector2(-250.0, 38.0), Vector2(-120.0, 26.0),
      Vector2(20.0, 18.0), Vector2(170.0, 34.0), Vector2(310.0, 30.0),
      Vector2(430.0, 40.0), Vector2(510.0, 40.0), Vector2(560.0, 40.0),
      Vector2(604.0, 36.0), Vector2(642.0, 18.0), Vector2(672.0, 8.0),
    ];

    final segs = <TrackSegment>[];
    for (int i = 0; i < points.length - 1; i++) {
      segs.add(TrackSegment(points[i], points[i + 1]));
    }

    final landingRamp = <Vector2>[
      Vector2(928.0, 26.0), Vector2(1018.0, 112.0), Vector2(1090.0, 138.0),
      Vector2(1100.0, 130.0), Vector2(1240.0, 98.0), Vector2(1390.0, 114.0),
      Vector2(1540.0, 76.0), Vector2(1710.0, 124.0), Vector2(1910.0, 112.0),
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
      if (prev != null) segs.add(TrackSegment(prev, p));
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
    
    final normalized = ((rawTilt - tiltZero) / 5.5).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.2 + normalized * 0.8;
    if (smoothedTilt.abs() < 0.05) smoothedTilt = 0.0;
    
    player.tilt = smoothedTilt;
    player.isGas = isGas;
    player.isBrake = isBrake;
    
    if (player.state == BikeState.crashed) {
      crashTimer += dt;
      if (crashTimer >= _crashRestartDelay) _restartBike();
    } else {
      crashTimer = 0.0;
    }
    
    if (!player.hasFiniteState) _restartBike();
    camera.viewfinder.position = player.position;
  }
  
  void _restartBike() {
    remove(player);
    player = Bike(_spawnPoint());
    player.trackSegments = trackSegments;
    player.settleOnTrack();
    add(player);
    crashTimer = 0.0;
  }

  @override
  void onTapDown(TapDownEvent event) {
    final x = event.localPosition.x;
    final y = event.localPosition.y;
    final width = size.x;
    final height = size.y;
    
    if (y < height * 0.25) {
      if (x < width * 0.3) {
        isTuningMode = !isTuningMode;
      } else if (x > width * 0.7 && isTuningMode) {
        currentTuningParam = (currentTuningParam + 1) % tuningParamNames.length;
      } else if (isTuningMode) {
        _adjustTuningParam(x < width * 0.5 ? -1 : 1);
      }
      return;
    }
    
    isBrake = x < width / 2;
    isGas = !isBrake;
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }

  void _adjustTuningParam(double direction) {
    final step = tuningParamSteps[currentTuningParam] * direction;
    switch (currentTuningParam) {
      case 0: Bike._playerTorqueStrength += step; break;
      case 1: Bike._airborneGravityFactor += step; break;
      case 2: Bike._bikeMass += step; break;
      case 3: Bike._cogDistanceFromRear += step; break;
      case 4: Bike._cogHeight += step; break;
      case 5: Bike._magnetStrength += step; break;
      case 6: Bike._frontGroundedTorqueScale += step; break;
    }
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
    canvas.restore();
    _renderTuningUI(canvas);
  }
  
  void _renderTuningUI(Canvas canvas) {
    final width = size.x;
    final height = size.y;
    
    if (!isTuningMode) {
      final hintRect = Rect.fromLTWH(0, 0, width * 0.3, height * 0.25);
      canvas.drawRect(hintRect, Paint()..color = Colors.black.withOpacity(0.5));
      TextPainter(
        text: const TextSpan(text: 'TUNE', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, Offset(width * 0.1, height * 0.1));
      return;
    }
    
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height * 0.25), Paint()..color = Colors.black.withOpacity(0.8));
    
    double val = 0.0;
    switch (currentTuningParam) {
      case 0: val = Bike._playerTorqueStrength; break;
      case 1: val = Bike._airborneGravityFactor; break;
      case 2: val = Bike._bikeMass; break;
      case 3: val = Bike._cogDistanceFromRear; break;
      case 4: val = Bike._cogHeight; break;
      case 5: val = Bike._magnetStrength; break;
      case 6: val = Bike._frontGroundedTorqueScale; break;
    }
    
    TextPainter(
      text: TextSpan(text: '${tuningParamNames[currentTuningParam]}: ${val.toStringAsFixed(3)}', style: const TextStyle(color: Colors.yellow, fontSize: 18, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout()..paint(canvas, Offset(width * 0.35, height * 0.05));
  }

  Vector2 _spawnPoint() => Vector2(-540.0, 38.0 - Bike.spawnBodyYOffset);
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
  const SurfaceHit({required this.point, required this.normal, required this.tangent, required this.distance});
}

enum BikeState { riding, crashed }

class Bike extends Component {
  // --- Physics Tuning Constants ---
  static const _gravity = 250.0;
  static const _rearDrive = 380.0;
  static const _brakePerWheel = 500.0;
  static const _airDrag = 0.05;
  static const _maxSpeed = 300.0;
  static const _wheelRadius = 5.0;
  static const _headRadius = 2.5;
  
  static const _suspensionTravel = 4.5; 
  static const _suspensionStrength = 1200.0; 
  static const _suspensionDamping = 65.0; 
  static const _impactCrashLimit = 320.0;

  static double _magnetStrength = 0.04;
  static double _frontGroundedTorqueScale = 0.05;
  static double _wheelbase = 18.0;
  static double _cogDistanceFromRear = 9.0;
  static double _cogHeight = 6.0;
  static double _bikeMass = 10.0;
  static double _playerTorqueStrength = 550.0;
  static double _airborneGravityFactor = 0.75;

  static final _rearLocal = Vector2(-9.5, 6.5);
  static final _frontLocal = Vector2(8.5, 6.5);
  static final _headLocal = Vector2(-4.0, -7.0);
  static final _collisionHeadLocal = Vector2(-3.5, -13.0);
  static double get spawnBodyYOffset => _rearLocal.y + _wheelRadius;

  // --- Fixed Timestep Architecture ---
  double _timeAccumulator = 0.0;
  static const double _fixedDt = 1.0 / 120.0; // 120Hz Physics Loop

  // Object Pooling for Constraint Math (Zero Allocation)
  final Vector2 _diff = Vector2.zero();
  final Vector2 _center = Vector2.zero();
  final Vector2 _fwd = Vector2.zero();
  final Vector2 _up = Vector2.zero();

  // Component State
  late List<TrackSegment> trackSegments;
  double tilt = 0.0;
  bool isGas = false;
  bool isBrake = false;

  // Sprung Mass (Frame)
  late Vector2 rearPos, frontPos, headPos, collisionHeadPos;
  late Vector2 rearVel, frontVel, headVel;

  // Unsprung Mass (Wheels - Render Only)
  final Vector2 rearWheelPos = Vector2.zero();
  final Vector2 frontWheelPos = Vector2.zero();

  BikeState state = BikeState.riding;
  bool rearOnGround = false;
  bool frontOnGround = false;
  double rearCompression = 0.0;
  double frontCompression = 0.0;
  SurfaceHit? _rearSurface;
  SurfaceHit? _frontSurface;

  late final double _distRH, _distFH;
  late final Vector2 _headFromWheelCenter;

  Bike(Vector2 startPos) {
    rearPos = startPos + _rearLocal;
    frontPos = startPos + _frontLocal;
    headPos = startPos + _headLocal;
    collisionHeadPos = startPos + _collisionHeadLocal;
    
    rearVel = Vector2.zero();
    frontVel = Vector2.zero();
    headVel = Vector2.zero();

    _distRH = (_headLocal - _rearLocal).length;
    _distFH = (_headLocal - _frontLocal).length;
    _headFromWheelCenter = _headLocal - (_rearLocal + _frontLocal) / 2.0;
  }

  Vector2 get position => (rearPos + frontPos + headPos) / 3.0;
  double get angle => atan2(frontPos.y - rearPos.y, frontPos.x - rearPos.x);
  double get speed => ((rearVel + frontVel + headVel) / 3.0).length;
  bool get hasFiniteState => rearPos.x.isFinite && frontPos.x.isFinite && headPos.x.isFinite;

  void settleOnTrack() {
    final rHit = _nearestSurface(rearPos, trackSegments);
    final fHit = _nearestSurface(frontPos, trackSegments);
    if (rHit == null || fHit == null) return;
    
    rearPos.setFrom(rHit.point);
    rearPos.addScaled(rHit.normal, _wheelRadius + 1.0);
    
    frontPos.setFrom(fHit.point);
    frontPos.addScaled(fHit.normal, _wheelRadius + 1.0);
    
    _syncFrameAndCollision(angle);
  }

  @override
  void update(double dt) {
    _timeAccumulator += dt;
    // Run physics exactly at 120Hz. If framerate drops, this catches up mechanically.
    while (_timeAccumulator >= _fixedDt) {
      _stepPhysics(_fixedDt);
      _timeAccumulator -= _fixedDt;
    }
  }

  void _stepPhysics(double dt) {
    if (state == BikeState.crashed) {
      _applyCrashedPhysics(dt);
      return;
    }

    // 1. Gravity (In-Place Mutation)
    final gVal = (rearOnGround || frontOnGround) ? _gravity : _gravity * _airborneGravityFactor;
    rearVel.y += gVal * dt;
    frontVel.y += gVal * dt;
    headVel.y += gVal * dt;

    // 2. Suspension Physics
    _applySuspension(dt);

    // 3. Drive & Brake
    if (rearOnGround && _rearSurface != null && isGas) {
      rearVel.addScaled(_forwardTangent(_rearSurface!.tangent), _rearDrive * dt);
    }
    if (isBrake) {
      if (rearOnGround) _applyBrake(rearVel, _rearSurface!.tangent, dt);
      if (frontOnGround) _applyBrake(frontVel, _frontSurface!.tangent, dt);
    }

    // 4. Input Torque
    _applyTilt(dt);

    // 5. Integrate Velocities (In-Place)
    rearPos.addScaled(rearVel, dt);
    frontPos.addScaled(frontVel, dt);
    headPos.addScaled(headVel, dt);

    // 6. Kinematic Distance Constraints (Iterative Solver)
    for (int i = 0; i < 8; i++) {
      _solveDist(rearPos, frontPos, _wheelbase, 1.0, 1.0);
      _solveDist(rearPos, headPos, _distRH, 1.0, 0.5);
      _solveDist(frontPos, headPos, _distFH, 1.0, 0.5);
    }

    // 7. Ground/Crash Verification
    _checkGroundAndCrash();
    _syncFrameAndCollision(angle);

    // Air Drag and Speed Cap
    final dragFactor = 1.0 - (_airDrag * dt);
    rearVel.scale(dragFactor);
    frontVel.scale(dragFactor);
    _capSpeed();
  }

  void _applySuspension(double dt) {
    final rHit = _nearestSurface(rearPos, trackSegments);
    final fHit = _nearestSurface(frontPos, trackSegments);

    rearCompression = _processWheelSuspension(rearPos, rearVel, rHit, dt);
    frontCompression = _processWheelSuspension(frontPos, frontVel, fHit, dt);

    // Calculate Rear Unsprung Mass Visual Position
    if (rHit != null) {
      rearWheelPos.setFrom(rearPos);
      rearWheelPos.addScaled(rHit.normal, -(_suspensionTravel - rearCompression));
      if (rHit.distance < _wheelRadius) { // Hard limit clamp
        rearWheelPos.setFrom(rHit.point);
        rearWheelPos.addScaled(rHit.normal, _wheelRadius);
      }
    } else {
      rearWheelPos.setValues(rearPos.x, rearPos.y + _suspensionTravel);
    }

    // Calculate Front Unsprung Mass Visual Position (Bug Fixed)
    if (fHit != null) {
      frontWheelPos.setFrom(frontPos);
      frontWheelPos.addScaled(fHit.normal, -(_suspensionTravel - frontCompression));
      if (fHit.distance < _wheelRadius) { // Hard limit clamp on fHit
        frontWheelPos.setFrom(fHit.point);
        frontWheelPos.addScaled(fHit.normal, _wheelRadius);
      }
    } else {
      frontWheelPos.setValues(frontPos.x, frontPos.y + _suspensionTravel);
    }
  }

  double _processWheelSuspension(Vector2 pos, Vector2 vel, SurfaceHit? hit, double dt) {
    if (hit == null) return 0.0;
    
    double distToGround = hit.distance;
    double restingDist = _wheelRadius + _suspensionTravel;
    
    if (distToGround < restingDist) {
      double compression = (restingDist - distToGround).clamp(0.0, _suspensionTravel);
      
      // Spring force based on compression ratio
      double springF = compression * _suspensionStrength;
      
      // Damper force counteracting velocity along normal
      double dampF = -vel.dot(hit.normal) * _suspensionDamping;
      
      double totalF = (springF + dampF).clamp(0.0, 5000.0);
      vel.addScaled(hit.normal, totalF * dt);

      if (-vel.dot(hit.normal) > _impactCrashLimit) _crash();
      return compression;
    }
    return 0.0;
  }

  void _checkGroundAndCrash() {
    final rHit = _nearestSurface(rearPos, trackSegments);
    final fHit = _nearestSurface(frontPos, trackSegments);
    
    rearOnGround = rHit != null && rHit.distance <= (_wheelRadius + _suspensionTravel + 0.5);
    frontOnGround = fHit != null && fHit.distance <= (_wheelRadius + _suspensionTravel + 0.5);
    _rearSurface = rHit; 
    _frontSurface = fHit;

    final headHit = _nearestSurface(collisionHeadPos, trackSegments);
    if (headHit != null && headHit.distance < _headRadius) _crash();
  }

  void _applyTilt(double dt) {
    double torque = -tilt * _playerTorqueStrength;
    if (tilt > 0 && frontOnGround) torque *= _frontGroundedTorqueScale;

    _center.setFrom(rearPos);
    _center.add(frontPos);
    _center.scale(0.5);

    // Rotate frame nodes around center of mass
    final rotRear = (rearPos - _center)..rotate(torque * 0.0001);
    final rotFront = (frontPos - _center)..rotate(torque * 0.0001);
    
    rearPos.setFrom(_center); rearPos.add(rotRear);
    frontPos.setFrom(_center); frontPos.add(rotFront);
  }

  void _applyBrake(Vector2 vel, Vector2 tangent, double dt) {
    final fwd = _forwardTangent(tangent);
    double currentSpeed = vel.dot(fwd);
    double decel = _brakePerWheel * dt;
    double newSpeed = currentSpeed > 0 ? max(0, currentSpeed - decel) : min(0, currentSpeed + decel);
    vel.addScaled(fwd, newSpeed - currentSpeed);
  }

  // Zero-Allocation Constraint Solver
  void _solveDist(Vector2 a, Vector2 b, double target, double massA, double massB) {
    _diff.setFrom(b);
    _diff.sub(a);
    final dist = _diff.length;
    if (dist < 0.001) return;
    
    final err = (dist - target) / dist;
    final totalM = massA + massB;
    
    a.addScaled(_diff, err * (massB / totalM));
    b.addScaled(_diff, -err * (massA / totalM));
  }

  void _syncFrameAndCollision(double currAngle) {
    _center.setFrom(rearPos);
    _center.add(frontPos);
    _center.scale(0.5);
    
    collisionHeadPos.setFrom(_center);
    collisionHeadPos.add(Vector2(-3.5, -13.0)..rotate(currAngle));
    
    _fwd.setFrom(frontPos);
    _fwd.sub(rearPos);
    _fwd.normalize();
    
    _up.setValues(-_fwd.y, _fwd.x);
    
    headPos.setFrom(_center);
    headPos.addScaled(_fwd, _headFromWheelCenter.x);
    headPos.addScaled(_up, _headFromWheelCenter.y);
  }

  void _applyCrashedPhysics(double dt) {
    rearVel.scale(0.98); 
    frontVel.scale(0.98);
    rearPos.addScaled(rearVel, dt); 
    frontPos.addScaled(frontVel, dt);
    collisionHeadPos.addScaled(rearVel, dt);
  }

  SurfaceHit? _nearestSurface(Vector2 pt, List<TrackSegment> segs) {
    SurfaceHit? best; 
    double bDist = double.infinity;
    for (final s in segs) {
      final d = s.delta; final l2 = d.length2; if (l2 == 0) continue;
      final t = ((pt - s.a).dot(d) / l2).clamp(0.0, 1.0);
      final close = s.a + d * t;
      final diff = pt - close; 
      final dist = diff.length;
      if (dist < bDist) {
        bDist = dist;
        best = SurfaceHit(point: close, normal: dist > 0.1 ? diff / dist : Vector2(-s.tangent.y, s.tangent.x), tangent: s.tangent, distance: dist);
      }
    }
    return best;
  }

  Vector2 _forwardTangent(Vector2 t) => t.x < 0 ? -t : t;

  void _capSpeed() {
    final currentSpeed = speed;
    if (currentSpeed > _maxSpeed) {
      double s = _maxSpeed / currentSpeed;
      rearVel.scale(s); frontVel.scale(s); headVel.scale(s);
    }
  }

  void _crash() => state = BikeState.crashed;

  @override
  void render(Canvas canvas) {
    final frameP = Paint()..color = Colors.grey[800]!..strokeWidth = 3..style = PaintingStyle.stroke;
    final wheelP = Paint()..color = Colors.black87..strokeWidth = 3..style = PaintingStyle.stroke;
    final riderP = Paint()..color = const Color(0xFF2255BB);

    canvas.drawCircle(_off(rearWheelPos), _wheelRadius, wheelP);
    canvas.drawCircle(_off(frontWheelPos), _wheelRadius, wheelP);

    canvas.drawLine(_off(rearPos), _off(frontPos), frameP);
    canvas.drawLine(_off(rearPos), _off(headPos), frameP);
    canvas.drawLine(_off(frontPos), _off(headPos), frameP);
    canvas.drawCircle(_off(headPos), _headRadius, riderP);

    final shockP = Paint()..color = Colors.grey[400]!..strokeWidth = 2;
    canvas.drawLine(_off(rearPos), _off(rearWheelPos), shockP);
    canvas.drawLine(_off(frontPos), _off(frontWheelPos), shockP);

    if (state == BikeState.crashed) {
      TextPainter(textDirection: TextDirection.ltr, text: const TextSpan(text: 'CRASHED', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)))..layout()..paint(canvas, _off(collisionHeadPos + Vector2(-15, -20)));
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
    final b = gameRef.player;
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(text: 'RaceRider\n${RaceRiderGame.buildLabel}\nSpeed: ${b.speed.toStringAsFixed(1)}', style: const TextStyle(color: Colors.yellow, fontSize: 14)))..layout()..paint(canvas, const Offset(16, 16));
  }
}