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
  static const buildLabel = 'physics v.90 - easy balancing';
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
  
  final List<String> tuningParamNames = [
    'Torque', 'Jump', 'Mass', 'CogDist', 'CogHeight', 'MagStr', 'FrontTorque', 
    'SuspStr', 'SuspDmp', 'SuspTrv'
  ];
  final List<double> tuningParamSteps = [
    10.0, 0.05, 1.0, 0.5, 0.5, 0.0005, 0.01, 
    50.0, 5.0, 0.5
  ];
  
  double crashTimer = 0.0;
  static const double _crashRestartDelay = 1.0;

  @override
  Future<void> onLoad() async {
    trackSegments = _buildTrack();
    player = Bike(_spawnPoint());
    player.trackSegments = trackSegments;
    
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
    
    // Increased sensitivity: dividing by 3.0 instead of 5.5 means reaching max tilt sooner
    final normalized = ((rawTilt - tiltZero) / 3.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.2 + normalized * 0.8;
    if (smoothedTilt.abs() < 0.05) smoothedTilt = 0.0;
    
    player.tilt = smoothedTilt;
    player.isGas = isGas;
    player.isBrake = isBrake;
    
    player.update(dt);
    
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
    player = Bike(_spawnPoint());
    player.trackSegments = trackSegments;
    crashTimer = 0.0;
    isGas = false;
    isBrake = false;
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
      }
      return; 
    }
    
    if (isTuningMode) {
      _adjustTuningParam(x < width * 0.5 ? -1 : 1);
    } else {
      isBrake = x < width / 2;
      isGas = !isBrake;
    }
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
      case 7: Bike.suspensionStrength += step; break;
      case 8: Bike.suspensionDamping += step; break;
      case 9: Bike.suspensionTravel += step; break;
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
    
    player.render(canvas);
    canvas.restore();
    
    _renderUIOverlay(canvas);
  }
  
  void _renderUIOverlay(Canvas canvas) {
    final width = size.x;
    final height = size.y;
    
    if (isTuningMode) {
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height * 0.25), Paint()..color = Colors.black.withOpacity(0.8));
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, width * 0.25, height * 0.25), Paint()..color = Colors.black.withOpacity(0.5));
    }

    void drawDebugText(String text, Offset pos, [Color color = Colors.white54]) {
      TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, pos);
    }

    if (!isTuningMode) {
      drawDebugText('[ TUNE ]', Offset(width * 0.05, height * 0.1), Colors.white);
      drawDebugText('< BRAKE', Offset(width * 0.05, height * 0.8));
      drawDebugText('GAS >', Offset(width * 0.85, height * 0.8));
    } else {
      drawDebugText('[ TUNE: ON ]', Offset(width * 0.05, height * 0.1), Colors.green);
      drawDebugText('[ NEXT ] >', Offset(width * 0.85, height * 0.1), Colors.white);
      drawDebugText('< DOWN (-)', Offset(width * 0.05, height * 0.5));
      drawDebugText('UP (+) >', Offset(width * 0.85, height * 0.5));
      
      double val = 0.0;
      switch (currentTuningParam) {
        case 0: val = Bike._playerTorqueStrength; break;
        case 1: val = Bike._airborneGravityFactor; break;
        case 2: val = Bike._bikeMass; break;
        case 3: val = Bike._cogDistanceFromRear; break;
        case 4: val = Bike._cogHeight; break;
        case 5: val = Bike._magnetStrength; break;
        case 6: val = Bike._frontGroundedTorqueScale; break;
        case 7: val = Bike.suspensionStrength; break;
        case 8: val = Bike.suspensionDamping; break;
        case 9: val = Bike.suspensionTravel; break;
      }
      
      TextPainter(
        text: TextSpan(
          text: '${tuningParamNames[currentTuningParam]}: ${val.toStringAsFixed(3)}', 
          style: const TextStyle(color: Colors.yellow, fontSize: 24, fontWeight: FontWeight.bold)
        ),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, Offset(width * 0.35, height * 0.1));
    }
  }

  Vector2 _spawnPoint() {
    const trackY = 38.0;
    return Vector2(-540.0, trackY - 100.0);
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
  const SurfaceHit({required this.point, required this.normal, required this.tangent, required this.distance});
}

class RaycastHit {
  final Vector2 point;
  final Vector2 normal;
  final Vector2 tangent;
  final double distance;
  const RaycastHit({required this.point, required this.normal, required this.tangent, required this.distance});
}

enum BikeState { riding, crashed }

class Bike {
  static const _gravity = 250.0;
  static const _rearDrive = 380.0;
  static const _brakePerWheel = 500.0;
  static const _airDrag = 0.05;
  static const _maxSpeed = 300.0;
  static const _wheelRadius = 5.0;
  static const _headRadius = 2.5;
  static const _impactCrashLimit = 400.0; 
  
  static double suspensionTravel = 4.5; 
  static double suspensionStrength = 1200.0; 
  static double suspensionDamping = 25.0; 

  static double _playerTorqueStrength = 305.0;
  static double _cogDistanceFromRear = 9.0;
  static double _cogHeight = 5.0;
  static double _frontGroundedTorqueScale = 0.12;
  static double _magnetStrength = 0.012;
  static double _wheelbase = 18.0;
  static double _bikeMass = 10.0;
  static double _airborneGravityFactor = 0.85;
  static double _maxRotationVelocity = 3.0 * pi; // 3 complete rotations in 2 seconds

  static final _rearLocal = Vector2(-9.5, 6.5);
  static final _frontLocal = Vector2(8.5, 6.5);
  static final _headLocal = Vector2(-4.0, -7.0);
  static final _collisionHeadLocal = Vector2(-3.5, -13.0);

  double _timeAccumulator = 0.0;
  static const double _fixedDt = 1.0 / 120.0; 

  final Vector2 _diff = Vector2.zero();
  final Vector2 _center = Vector2.zero();
  final Vector2 _fwd = Vector2.zero();
  final Vector2 _up = Vector2.zero();
  final Vector2 _rotCache = Vector2.zero(); 
  
  final Vector2 _oldRear = Vector2.zero();
  final Vector2 _oldFront = Vector2.zero();

  late List<TrackSegment> trackSegments;
  double tilt = 0.0;
  bool isGas = false;
  bool isBrake = false;

  late Vector2 rearPos, frontPos, headPos, collisionHeadPos;
  late Vector2 rearVel, frontVel;

  final Vector2 rearWheelPos = Vector2.zero();
  final Vector2 frontWheelPos = Vector2.zero();

  BikeState state = BikeState.riding;
  bool rearOnGround = false;
  bool frontOnGround = false;
  double rearCompression = 0.0;
  double frontCompression = 0.0;
  SurfaceHit? _rearSurface;
  SurfaceHit? _frontSurface;

  late final Vector2 _headFromWheelCenter;

  Bike(Vector2 startPos) {
    rearPos = startPos + _rearLocal;
    frontPos = startPos + _frontLocal;
    headPos = startPos + _headLocal;
    collisionHeadPos = startPos + _collisionHeadLocal;
    
    rearVel = Vector2.zero();
    frontVel = Vector2.zero();

    _headFromWheelCenter = _headLocal - (_rearLocal + _frontLocal) / 2.0;
  }

  Vector2 get position => (rearPos + frontPos) / 2.0;
  double get angle => atan2(frontPos.y - rearPos.y, frontPos.x - rearPos.x);
  double get speed => ((rearVel + frontVel) / 2.0).length;
  bool get hasFiniteState => rearPos.x.isFinite && frontPos.x.isFinite;

  void update(double dt) {
    _timeAccumulator += dt;
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

    _applyTilt(dt);

    final gVal = (rearOnGround || frontOnGround) ? _gravity : _gravity * _airborneGravityFactor;
    rearVel.y += gVal * dt;
    frontVel.y += gVal * dt;

    _applySuspension(dt);

    if (rearOnGround && _rearSurface != null && isGas) {
      rearVel.addScaled(_forwardTangent(_rearSurface!.tangent), _rearDrive * dt);
    }
    if (isBrake) {
      if (rearOnGround) _applyBrake(rearVel, _rearSurface!.tangent, dt);
      if (frontOnGround) _applyBrake(frontVel, _frontSurface!.tangent, dt);
    }

    _oldRear.setFrom(rearPos);
    _oldFront.setFrom(frontPos);

    rearPos.addScaled(rearVel, dt);
    frontPos.addScaled(frontVel, dt);

    for (int i = 0; i < 8; i++) {
      _solveDist(rearPos, frontPos, _wheelbase, 1.0, 1.0);
      _solveGround(rearPos, _oldRear);
      _solveGround(frontPos, _oldFront);
    }

    rearVel.setFrom(rearPos);
    rearVel.sub(_oldRear);
    rearVel.scale(1.0 / dt);

    frontVel.setFrom(frontPos);
    frontVel.sub(_oldFront);
    frontVel.scale(1.0 / dt);

    _checkGroundAndCrash();
    _syncFrameAndCollision(angle);

    final dragFactor = 1.0 - (_airDrag * dt);
    rearVel.scale(dragFactor);
    frontVel.scale(dragFactor);
    _capSpeed();
  }

  double _cross(Vector2 v, Vector2 w) => v.x * w.y - v.y * w.x;

  RaycastHit? _raycast(Vector2 origin, Vector2 dir, List<TrackSegment> segs) {
    RaycastHit? best;
    double minDist = double.infinity;
    for (final s in segs) {
      final e = s.b - s.a;
      final rhs = s.a - origin;
      final det = _cross(dir, e);
      if (det.abs() < 1e-6) continue; 
      
      final t = _cross(rhs, e) / det;
      final u = _cross(rhs, dir) / det;
      
      if (t >= 0 && u >= 0 && u <= 1) {
        if (t < minDist) {
          minDist = t;
          final geomNormal = Vector2(s.tangent.y, -s.tangent.x);
          best = RaycastHit(point: origin + dir * t, normal: geomNormal, tangent: s.tangent, distance: t);
        }
      }
    }
    return best;
  }

  void _applySuspension(double dt) {
    _fwd.setFrom(frontPos);
    _fwd.sub(rearPos);
    _fwd.normalize();
    
    final rearForkDir = Vector2(-_fwd.y, _fwd.x); 
    final frontForkDir = Vector2(-_fwd.y, _fwd.x)..rotate(-0.25); 
    
    final rHit = _raycast(rearPos, rearForkDir, trackSegments);
    final fHit = _raycast(frontPos, frontForkDir, trackSegments);

    rearCompression = _processWheelSuspension(rearPos, rearVel, rHit, rearForkDir, dt);
    frontCompression = _processWheelSuspension(frontPos, frontVel, fHit, frontForkDir, dt);

    rearWheelPos.setFrom(rearPos);
    rearWheelPos.addScaled(rearForkDir, suspensionTravel - rearCompression);

    frontWheelPos.setFrom(frontPos);
    frontWheelPos.addScaled(frontForkDir, suspensionTravel - frontCompression);
  }

  double _processWheelSuspension(Vector2 pos, Vector2 vel, RaycastHit? hit, Vector2 forkDir, double dt) {
    if (hit == null) return 0.0;
    
    double distToGround = hit.distance;
    double restingDist = _wheelRadius + suspensionTravel;
    
    if (distToGround < restingDist) {
      double compression = (restingDist - distToGround).clamp(0.0, suspensionTravel);
      double springF = compression * suspensionStrength;
      
      double compressionVelocity = -vel.dot(hit.normal); 
      
      // Dampen both compression AND rebound to prevent the pogo-stick effect
      double dampF = compressionVelocity * suspensionDamping;
      
      double totalF = (springF + dampF).clamp(-2000.0, 10000.0);
      
      vel.addScaled(hit.normal, totalF * dt);

      if (compressionVelocity > Bike._impactCrashLimit) _crash();
      
      return compression;
    }
    return 0.0;
  }

  void _checkGroundAndCrash() {
    final rHit = _nearestSurface(rearPos, trackSegments);
    final fHit = _nearestSurface(frontPos, trackSegments);
    
    rearOnGround = rHit != null && rHit.distance <= (_wheelRadius + suspensionTravel + 0.5);
    frontOnGround = fHit != null && fHit.distance <= (_wheelRadius + suspensionTravel + 0.5);
    _rearSurface = rHit; 
    _frontSurface = fHit;

    final headHit = _nearestSurface(collisionHeadPos, trackSegments);
    if (headHit != null && headHit.distance < _headRadius) _crash();
  }

   void _applyTilt(double dt) {
    if (tilt.abs() < 0.03) return;

    _fwd.setFrom(frontPos);
    _fwd.sub(rearPos);
    _fwd.normalize();
    final tangent = Vector2(-_fwd.y, _fwd.x);

    // === Natural Gravity Torque (much simpler and more stable) ===
    double angle = atan2(_fwd.y, _fwd.x);                    // bike angle
    double cogOffset = (_cogDistanceFromRear - _wheelbase / 2); 
    double gravityTorque = sin(angle) * cogOffset * _gravity * _bikeMass * 0.30;

    // === Player Input ===
    double playerTorque = tilt * _playerTorqueStrength;

    if (playerTorque > 0 && frontOnGround) {
      playerTorque *= _frontGroundedTorqueScale;
    }

    double totalTorque = gravityTorque + playerTorque;

    // === Very Strong Damping ===
    Vector2 relVel = frontVel - rearVel;
    double currentRotVel = relVel.dot(tangent) / _wheelbase;

    double damping = 15.0; // Equal damping for grounded and airborne to match BIKE RACE
    totalTorque -= currentRotVel * damping * 1.8;   // extra multiplier

    // === Apply ===
    double force = totalTorque * (_wheelbase / 2.0) / _bikeMass;
    
    // Calculate potential new rotation velocity and clamp if needed
    double potentialRotVel = currentRotVel + (force * 2.0 / _wheelbase) * dt;
    if (potentialRotVel.abs() > _maxRotationVelocity) {
      // Limit force to stay within max rotation velocity
      double maxRotVelChange = (_maxRotationVelocity - currentRotVel.abs()) * currentRotVel.sign;
      force = maxRotVelChange * _wheelbase / (2.0 * dt);
    }

    rearVel.addScaled(tangent, -force * dt);
    frontVel.addScaled(tangent, force * dt);
  }

  void _applyBrake(Vector2 vel, Vector2 tangent, double dt) {
    final fwd = _forwardTangent(tangent);
    double currentSpeed = vel.dot(fwd);
    double decel = _brakePerWheel * dt;
    double newSpeed = currentSpeed > 0 ? max(0, currentSpeed - decel) : min(0, currentSpeed + decel);
    vel.addScaled(fwd, newSpeed - currentSpeed);
  }

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

  // Passing oldPos kills the springboard bounce caused by positional snapping
  void _solveGround(Vector2 pos, Vector2 oldPos) {
    final hit = _nearestSurface(pos, trackSegments);
    if (hit != null && hit.distance < _wheelRadius) {
      Vector2 correction = hit.normal * (_wheelRadius - hit.distance);
      pos.add(correction);
      oldPos.add(correction); 
    }
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
        final geomNormal = Vector2(s.tangent.y, -s.tangent.x);
        best = SurfaceHit(
          point: close, 
          normal: geomNormal, 
          tangent: s.tangent, 
          distance: dist
        );
      }
    }
    return best;
  }

  Vector2 _forwardTangent(Vector2 t) => t.x < 0 ? -t : t;

  void _capSpeed() {
    final currentSpeed = speed;
    if (currentSpeed > _maxSpeed) {
      double s = _maxSpeed / currentSpeed;
      rearVel.scale(s); frontVel.scale(s);
    }
  }

  void _crash() => state = BikeState.crashed;

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