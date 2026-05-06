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
  static const buildLabel = 'physics v.72 - Drop Test & UI Fix';
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
  
  // Added the 3 new suspension variables to the tuning system
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
    
    // Bike is NO LONGER added as a component. It is manually rendered below.
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
    
    final normalized = ((rawTilt - tiltZero) / 5.5).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.2 + normalized * 0.8;
    if (smoothedTilt.abs() < 0.05) smoothedTilt = 0.0;
    
    player.tilt = smoothedTilt;
    player.isGas = isGas;
    player.isBrake = isBrake;
    
    // Manually updating the Bike
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
  }

  @override
  void onTapDown(TapDownEvent event) {
    final x = event.localPosition.x;
    final y = event.localPosition.y;
    final width = size.x;
    final height = size.y;
    
    // Top 25% of screen reserved for UI toggles
    if (y < height * 0.25) {
      if (x < width * 0.3) {
        isTuningMode = !isTuningMode;
      } else if (x > width * 0.7 && isTuningMode) {
        currentTuningParam = (currentTuningParam + 1) % tuningParamNames.length;
      }
      return; 
    }
    
    // Bottom 75% handles gameplay/tuning adjustments based on Left/Right
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
    
    // Draw Camera/World Space
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
    
    // Render the bike manually within the translated canvas
    player.render(canvas);
    canvas.restore();
    
    // Draw UI Overlay (Screen Space)
    _renderUIOverlay(canvas);
  }
  
  void _renderUIOverlay(Canvas canvas) {
    final width = size.x;
    final height = size.y;
    
    // Draw Top Bar Background if Tuning
    if (isTuningMode) {
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height * 0.25), Paint()..color = Colors.black.withOpacity(0.8));
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, width * 0.25, height * 0.25), Paint()..color = Colors.black.withOpacity(0.5));
    }

    // Helper function for drawing overlay text
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
      
      // Draw Current Value
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
    // 100 units drop is roughly 5.5 bike lengths given an 18-unit wheelbase
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

enum BikeState { riding, crashed }

// Reverted from `extends Component` to a standard class to fix camera clipping
class Bike {
  static const _gravity = 250.0;
  static const _rearDrive = 380.0;
  static const _brakePerWheel = 500.0;
  static const _airDrag = 0.05;
  static const _maxSpeed = 300.0;
  static const _wheelRadius = 5.0;
  static const _headRadius = 2.5;
  static const _impactCrashLimit = 320.0;
  
  // Tunable Suspension Constants (Converted to Static vars)
  static double suspensionTravel = 4.5; 
  static double suspensionStrength = 1200.0; 
  static double suspensionDamping = 65.0; 

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

  // Fixed Timestep Architecture
  double _timeAccumulator = 0.0;
  static const double _fixedDt = 1.0 / 120.0; 

  // Object Pooling for Constraint Math
  final Vector2 _diff = Vector2.zero();
  final Vector2 _center = Vector2.zero();