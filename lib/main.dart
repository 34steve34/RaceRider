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
  static const buildLabel = 'v.202gemini04 ZERO SPIN PATCH';
  late Bike player;
  late List<TrackSegment> trackSegments;
  
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  double tiltZero = 0.0;
  bool tiltCalibrated = false;
  bool isGas = false;
  bool isBrake = false;
  
  double dt = 0.0;
  late StreamSubscription _accelSub;
  
  bool isTuningMode = false;
  int currentTuningParam = 0;
  
  final List<String> tuningParamNames = [
    'Torque', 'Jump', 'Mass', 'CogDist', 'CogHeight', 'MagStr', 'FrontTorque', 
    'SuspStr', 'SuspDmp', 'SuspTrv', 'MaxRotVel', 'LandDamp', 'AirDamp'
  ];
  final List<double> tuningParamSteps = [
    1000.0, 0.05, 1.0, 0.5, 0.5, 0.0005, 0.01, 
    50.0, 5.0, 0.5, 0.1, 10.0, 5.0
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
    final segs = <TrackSegment>[];
    
    segs.add(TrackSegment(Vector2(-400.0, 38.0), Vector2(-200.0, 38.0)));
    
    final curveCenter = Vector2(-200.0, 38.0 - 72.0); 
    const curveRadius = 72.0;
    const curveSteps = 24;
    const curveStartAngle = 1.5708;  
    const curveEndAngle = 0.0;       
    
    Vector2? curvePrev;
    for (int i = 0; i <= curveSteps; i++) {
      final t = i / curveSteps;
      final a = curveStartAngle + t * (curveEndAngle - curveStartAngle);
      final p = Vector2(
        curveCenter.x + cos(a) * curveRadius,
        curveCenter.y + sin(a) * curveRadius,
      );
      if (curvePrev != null) {
        segs.add(TrackSegment(curvePrev, p));
      }
      curvePrev = p;
    }
    
    final wallTop = curvePrev!;
    final wallBottom = Vector2(wallTop.x, wallTop.y - 150.0);
    segs.add(TrackSegment(wallTop, wallBottom));
	
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
    this.dt = dt; 
    
    if (!tiltCalibrated) {
      tiltZero = rawTilt;
      tiltCalibrated = true;
    }
    
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
      case 10: Bike._maxRotationVelocity += step; break;
      case 11: Bike._landingRotationDamping += step; break;
      case 12: Bike._airborneRotationDamping += step; break;
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
        case 10: val = Bike._maxRotationVelocity; break;
        case 11: val = Bike._landingRotationDamping; break;
        case 12: val = Bike._airborneRotationDamping; break;
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
    return Vector2(-350.0, trackY - 100.0);
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

enum BikeState { riding, crashed }

class Bike {
  static const _gravity = 250.0;
  static const _rearDrive = 380.0;
  static const _brakePerWheel = 500.0;
  static const _airDrag = 0.05;
  static const _maxSpeed = 300.0;
  static const _wheelRadius = 5.0;
  static const _headRadius = 2.5;
  
  // Raised impact limit so proper landings don't explode
  static const _impactCrashLimit = 850.0; 
  
  static double suspensionTravel = 4.5; 
  // Heavily increased strength and damping to stop bounciness
  static double suspensionStrength = 500.0; 
  static double suspensionDamping = 35.0; 

  static double _playerTorqueStrength = 55000.0; 
  static double _cogDistanceFromRear = 8.0;
  static double _cogHeight = 5.0;
  static double _frontGroundedTorqueScale = 0.12;
  static double _magnetStrength = 0.012;
  static double _wheelbase = 18.0;
  static double _bikeMass = 10.0;
  static double _airborneGravityFactor = 0.85; 
  static double _maxRotationVelocity = 0.8 * pi; 
  
  static double _landingRotationDamping = 120.0;  
  static double _airborneRotationDamping = 40.0; 

  static double debugCurrentGravityTorque = 0.0;
  static double debugCurrentPlayerTorque = 0.0;
  static double debugCurrentTotalTorque = 0.0;
  static double debugWheelieTorqueNeeded = 0.0;
  static bool debugFrontGrounded = false;
  static double debugFrontGroundDistance = 0.0;

  static final _rearLocal = Vector2(-9.5, 6.5);
  static final _frontLocal = Vector2(8.5, 6.5);
  static final _headLocal = Vector2(-4.0, -7.0);

  double _timeAccumulator = 0.0;
  static const double _fixedDt = 1.0 / 120.0; 

  late List<TrackSegment> trackSegments;
  double tilt = 0.0;
  bool isGas = false;
  bool isBrake = false;

  late Vector2 rearPos, frontPos;
  late Vector2 rearOldPos, frontOldPos;
  late Vector2 headPos, collisionHeadPos;

  BikeState state = BikeState.riding;
  bool rearOnGround = false;
  bool frontOnGround = false;
  
  SurfaceHit? _rearSurface;
  SurfaceHit? _frontSurface;

  late final Vector2 _headFromWheelCenter;

  // Mass distribution logic for natural Center of Gravity rotation
  double get _massRear => (_wheelbase - _cogDistanceFromRear) / _wheelbase;
  double get _massFront => _cogDistanceFromRear / _wheelbase;

  Bike(Vector2 startPos) {
    rearPos = startPos + _rearLocal;
    frontPos = startPos + _frontLocal;
    rearOldPos = rearPos.clone();
    frontOldPos = frontPos.clone();
    
    headPos = startPos + _headLocal;
    collisionHeadPos = startPos + Vector2(-3.5, -13.0);
    _headFromWheelCenter = _headLocal - (_rearLocal + _frontLocal) / 2.0;
  }

  Vector2 get position => (rearPos + frontPos) / 2.0;
  double get speed => ((rearPos - rearOldPos).length + (frontPos - frontOldPos).length) / (2.0 * _fixedDt);
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
      rearPos.add((rearPos - rearOldPos) * 0.98);
      frontPos.add((frontPos - frontOldPos) * 0.98);
      return;
    }

    Vector2 rVel = (rearPos - rearOldPos) / dt;
    Vector2 fVel = (frontPos - frontOldPos) / dt;

    Vector2 rAccel = Vector2(0, _gravity);
    Vector2 fAccel = Vector2(0, _gravity);

    _rearSurface = _nearestSurface(rearPos, trackSegments);
    _frontSurface = _nearestSurface(frontPos, trackSegments);

    rearOnGround = false; 
    frontOnGround = false;
    double restingDist = _wheelRadius + suspensionTravel;

    if (_rearSurface != null) {
      double sd = (rearPos - _rearSurface!.point).dot(_rearSurface!.normal);
      if (sd < restingDist) {
        rearOnGround = true;
        double penetration = restingDist - sd;
        double vNorm = rVel.dot(_rearSurface!.normal);
        
        double rNormAccel = max(0.0, penetration * suspensionStrength - vNorm * suspensionDamping);
        rAccel += _rearSurface!.normal * rNormAccel;
        
        if (isGas) {
          Vector2 driveDir = _forwardTangent(_rearSurface!.tangent);
          rAccel += driveDir * _rearDrive;
        }
        if (isBrake) {
          double vTan = rVel.dot(_rearSurface!.tangent);
          double bForce = -vTan * suspensionDamping * 0.5;
          double maxFric = rNormAccel * 1.5; 
          rAccel += _rearSurface!.tangent * bForce.clamp(-maxFric, maxFric);
        }
        
        if (vNorm < -_impactCrashLimit) _crash();
      } else if (sd < restingDist + 10.0 && sd > 0) {
        rAccel -= _rearSurface!.normal * (_gravity * _magnetStrength * 100.0);
      }
    }

    if (_frontSurface != null) {
      double sd = (frontPos - _frontSurface!.point).dot(_frontSurface!.normal);
      debugFrontGroundDistance = sd;
      
      if (sd < restingDist) {
        frontOnGround = true;
        double penetration = restingDist - sd;
        double vNorm = fVel.dot(_frontSurface!.normal);
        
        double fNormAccel = max(0.0, penetration * suspensionStrength - vNorm * suspensionDamping);
        fAccel += _frontSurface!.normal * fNormAccel;
        
        if (isBrake) {
          double vTan = fVel.dot(_frontSurface!.tangent);
          double bForce = -vTan * suspensionDamping * 0.5;
          double maxFric = fNormAccel * 1.5;
          fAccel += _frontSurface!.tangent * bForce.clamp(-maxFric, maxFric);
        }
        
        if (vNorm < -_impactCrashLimit) _crash();
      }
    }

    debugFrontGrounded = frontOnGround;

    // --- TILT & TORQUE ---
    Vector2 axle = frontPos - rearPos;
    Vector2 tangent = Vector2(-axle.y, axle.x)..normalize(); 
    
    double playerTorque = -tilt * _playerTorqueStrength; 
    
    if (playerTorque < 0 && frontOnGround) {
      playerTorque *= _frontGroundedTorqueScale; 
    }

    // Removed the fake Airborne Gravity Torque motor. Player Torque is the only applied rotational force.
    double totalTorque = playerTorque; 

    double angle = atan2(axle.y, axle.x);
    
    // Debug info updated for pure mathematical observation
    debugCurrentGravityTorque = _cogDistanceFromRear * _bikeMass * _gravity * cos(angle);
    debugCurrentPlayerTorque = playerTorque;
    debugCurrentTotalTorque = totalTorque;
    debugWheelieTorqueNeeded = debugCurrentGravityTorque;

    Vector2 relVel = fVel - rVel;
    double rotVel = relVel.dot(tangent) / _wheelbase;
    double dampForce = rotVel * (rearOnGround || frontOnGround ? _landingRotationDamping : _airborneRotationDamping);
    
    double linearTorqueAccel = (totalTorque / (_wheelbase * _bikeMass)) - dampForce;
    rAccel += tangent * linearTorqueAccel;
    fAccel -= tangent * linearTorqueAccel;

    double drag = 1.0 - (_airDrag * dt);
    Vector2 rNext = rearPos + rVel * drag * dt + rAccel * (dt * dt);
    Vector2 fNext = frontPos + fVel * drag * dt + fAccel * (dt * dt);

    rearOldPos.setFrom(rearPos);
    frontOldPos.setFrom(frontPos);
    rearPos.setFrom(rNext);
    frontPos.setFrom(fNext);

    for (int i = 0; i < 8; i++) {
      _solveDist(rearPos, frontPos, _wheelbase);
    }

    _syncFrameAndCollision(atan2(frontPos.y - rearPos.y, frontPos.x - rearPos.x));
    
    SurfaceHit? hHit = _nearestSurface(collisionHeadPos, trackSegments);
    if (hHit != null && hHit.distance < _headRadius) {
      _crash();
    }
  }

  void _solveDist(Vector2 a, Vector2 b, double target) {
    final diff = b - a;
    final dist = diff.length;
    if (dist < 0.0001) return;
    final err = (dist - target) / dist;
    
    // Proper mass distribution solves the COG naturally.
    // Heavier wheel moves less. Lighter wheel drops more.
    a.add(diff * (err * _massFront));
    b.sub(diff * (err * _massRear));
  }

  void _syncFrameAndCollision(double currAngle) {
    Vector2 center = (rearPos + frontPos) / 2.0;
    collisionHeadPos = center + (Vector2(-3.5, -13.0)..rotate(currAngle));
    
    Vector2 fwd = (frontPos - rearPos).normalized();
    Vector2 up = Vector2(-fwd.y, fwd.x);
    headPos = center + fwd * _headFromWheelCenter.x + up * _headFromWheelCenter.y;
  }

  SurfaceHit? _nearestSurface(Vector2 pt, List<TrackSegment> segs) {
    SurfaceHit? best; 
    double bDist = double.infinity;
    for (final s in segs) {
      final d = s.delta; final l2 = d.length2; if (l2 == 0) continue;
      final t = ((pt - s.a).dot(d) / l2).clamp(0.0, 1.0);
      final close = s.a + d * t;
      final dist = (pt - close).length;
      if (dist < bDist) {
        bDist = dist;
        final geomNormal = Vector2(s.tangent.y, -s.tangent.x);
        best = SurfaceHit(point: close, normal: geomNormal, tangent: s.tangent, distance: dist);
      }
    }
    return best;
  }

  Vector2 _forwardTangent(Vector2 t) => t.x < 0 ? -t : t;

  void _crash() => state = BikeState.crashed;

  void render(Canvas canvas) {
    final frameP = Paint()..color = Colors.grey[800]!..strokeWidth = 3..style = PaintingStyle.stroke;
    final wheelP = Paint()..color = Colors.black87..strokeWidth = 3..style = PaintingStyle.stroke;
    final riderP = Paint()..color = const Color(0xFF2255BB);

    Vector2 fwd = (frontPos - rearPos).normalized();
    Vector2 localDown = Vector2(-fwd.y, fwd.x);

    Vector2 rWheelVis = rearPos + localDown * suspensionTravel;
    if (_rearSurface != null) {
      double sd = (rearPos - _rearSurface!.point).dot(_rearSurface!.normal);
      if (sd < _wheelRadius + suspensionTravel) {
        rWheelVis = _rearSurface!.point + _rearSurface!.normal * _wheelRadius;
      }
    }

    Vector2 fWheelVis = frontPos + localDown * suspensionTravel;
    if (_frontSurface != null) {
      double sd = (frontPos - _frontSurface!.point).dot(_frontSurface!.normal);
      if (sd < _wheelRadius + suspensionTravel) {
        fWheelVis = _frontSurface!.point + _frontSurface!.normal * _wheelRadius;
      }
    }

    canvas.drawCircle(_off(rWheelVis), _wheelRadius, wheelP);
    canvas.drawCircle(_off(fWheelVis), _wheelRadius, wheelP);

    canvas.drawLine(_off(rearPos), _off(frontPos), frameP);
    canvas.drawLine(_off(rearPos), _off(headPos), frameP);
    canvas.drawLine(_off(frontPos), _off(headPos), frameP);
    canvas.drawCircle(_off(headPos), _headRadius, riderP);

    final shockP = Paint()..color = Colors.grey[400]!..strokeWidth = 2;
    canvas.drawLine(_off(rearPos), _off(rWheelVis), shockP);
    canvas.drawLine(_off(frontPos), _off(fWheelVis), shockP);

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
  double _debugUpdateTimer = 0.0;
  static const double _debugUpdateInterval = 0.33; 
  
  String _cachedDebugText = '';
  Color _cachedWheelieColor = Colors.red;
  
  @override
  void render(Canvas canvas) {
    final b = gameRef.player;
    
    _debugUpdateTimer += gameRef.dt;
    if (_debugUpdateTimer >= _debugUpdateInterval) {
      _debugUpdateTimer = 0.0;
      
      _cachedDebugText = 'RaceRider\n${RaceRiderGame.buildLabel}\nSpeed: ${b.speed.toStringAsFixed(1)}\n';
      _cachedDebugText += '─' * 20 + '\n';
      _cachedDebugText += 'TORQUE DEBUG:\n';
      _cachedDebugText += 'Gravity Needed to Wheelie: ${Bike.debugCurrentGravityTorque.toStringAsFixed(1)}\n';
      _cachedDebugText += 'Player Applied:  ${Bike.debugCurrentPlayerTorque.toStringAsFixed(1)}\n';
      _cachedDebugText += 'Front Grounded: ${Bike.debugFrontGrounded ? "YES" : "NO"}\n';
      _cachedDebugText += 'Front Distance: ${Bike.debugFrontGroundDistance.toStringAsFixed(1)}\n';
      
      if (Bike.debugCurrentPlayerTorque > Bike.debugWheelieTorqueNeeded) {
        _cachedWheelieColor = Colors.green;
        _cachedDebugText += 'Wheelie Status: LIFTING!';
      } else if (Bike.debugCurrentPlayerTorque > 0) {
        _cachedWheelieColor = Colors.yellow;
        _cachedDebugText += 'Wheelie Status: Trying...';
      } else {
        _cachedWheelieColor = Colors.red;
        _cachedDebugText += 'Wheelie Status: Not lifting';
      }
    }
    
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(
      text: _cachedDebugText, 
      style: const TextStyle(color: Colors.yellow, fontSize: 14)
    ))..layout()..paint(canvas, const Offset(16, 16));
    
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(
      text: '▲ WHEELIE', 
      style: TextStyle(color: _cachedWheelieColor, fontSize: 16, fontWeight: FontWeight.bold)
    ))..layout()..paint(canvas, const Offset(16, 200));
  }
}