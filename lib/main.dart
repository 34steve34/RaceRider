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

// --- SPATIAL PARTITIONING GRID ---
// Divides the 2D game world into manageable cells to optimize collision scanning.
class SpatialGrid {
  final double cellSize;
  final Map<String, List<TrackSegment>> _buckets = {};

  SpatialGrid({this.cellSize = 60.0});

  String _getKey(int cx, int cy) => '$cx,$cy';

  void clear() => _buckets.clear();

  // Registers a segment into every grid cell its bounding box overlaps
  void insert(TrackSegment seg) {
    int minX = (min(seg.a.x, seg.b.x) / cellSize).floor();
    int maxX = (max(seg.a.x, seg.b.x) / cellSize).floor();
    int minY = (min(seg.a.y, seg.b.y) / cellSize).floor();
    int maxY = (max(seg.a.y, seg.b.y) / cellSize).floor();

    for (int cx = minX; cx <= maxX; cx++) {
      for (int cy = minY; cy <= maxY; cy++) {
        final key = _getKey(cx, cy);
        _buckets.putIfAbsent(key, () => []).add(seg);
      }
    }
  }

  // Retrieves all distinct segments nearby a specific world position radius
  List<TrackSegment> getNearby(Vector2 pos, double radius) {
    final Set<TrackSegment> nearby = {};
    int minX = ((pos.x - radius) / cellSize).floor();
    int maxX = ((pos.x + radius) / cellSize).floor();
    int minY = ((pos.y - radius) / cellSize).floor();
    int maxY = ((pos.y + radius) / cellSize).floor();

    for (int cx = minX; cx <= maxX; cx++) {
      for (int cy = minY; cy <= maxY; cy++) {
        final key = _getKey(cx, cy);
        final cellSegs = _buckets[key];
        if (cellSegs != null) nearby.addAll(cellSegs);
      }
    }
    return nearby.toList();
  }
}

class RaceRiderGame extends FlameGame with TapCallbacks {
  static const buildLabel = 'physics v.300 - Spatial Hash Grid Restructure';
  late Bike player;
  late List<TrackSegment> trackSegments;
  final SpatialGrid grid = SpatialGrid(cellSize: 80.0);
  
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
    'SuspStr', 'SuspDmp', 'SuspTrv', 'CrashLim', 'LandDamp', 'WhlDamp', 'AirDamp', 'BrakeStr'
  ];
  final List<double> tuningParamSteps = [
    5000.0, 0.05, 1.0, 0.5, 0.5, 0.0005, 0.01, 
    50.0, 5.0, 0.5, 50.0, 10.0, 5.0, 5.0, 50.0
  ];
  
  double crashTimer = 0.0;
  static const double _crashRestartDelay = 1.2;

  @override
  Future<void> onLoad() async {
    _loadTrackData();
    player = Bike(_spawnPoint(), grid);
    
    add(Background());
    add(DebugOverlay());
    
    camera.viewfinder
      ..zoom = 2.1
      ..anchor = Anchor.center;
      
    _accelSub = accelerometerEvents.listen((e) => rawTilt = e.y);
  }

  void _loadTrackData() {
    grid.clear();
    trackSegments = _buildTrack();
    for (final seg in trackSegments) {
      grid.insert(seg);
    }
  }

  @override
  void onRemove() {
    _accelSub.cancel();
    super.onRemove();
  }

  // FACTORY METHOD: Stitches continuous paths together seamlessly
  List<TrackSegment> _stitchPath(List<Vector2> points) {
    final pathSegs = <TrackSegment>[];
    for (int i = 0; i < points.length - 1; i++) {
      final seg = TrackSegment(points[i], points[i + 1]);
      if (pathSegs.isNotEmpty) {
        pathSegs.last.next = seg;
        seg.prev = pathSegs.last;
      }
      pathSegs.add(seg);
    }
    return pathSegs;
  }

  List<TrackSegment> _buildTrack() {
    final allSegs = <TrackSegment>[];
    
    // 1. Initial Flat & Ramp & Cliff Face Sequence (Stitched)
    final initialPoints = [
      Vector2(-600.0, 38.0),
      Vector2(-400.0, 38.0),
      Vector2(-310.0, -34.0), // Ramp Top
      Vector2(-310.0, 38.0),  // Vertical Drop
      Vector2(-200.0, 38.0),  // Landing Flat
    ];
    allSegs.addAll(_stitchPath(initialPoints));
    
    // 2. Smooth Launch Arc/Curve (Procedurally Stitched)
    final curveCenter = Vector2(-200.0, 38.0 - 72.0); 
    const curveRadius = 72.0;
    const curveSteps = 24;
    const curveStartAngle = 1.5708;  
    const curveEndAngle = 0.0;       
    
    final curvePoints = <Vector2>[];
    for (int i = 0; i <= curveSteps; i++) {
      final t = i / curveSteps;
      final a = curveStartAngle + t * (curveEndAngle - curveStartAngle);
      curvePoints.add(Vector2(curveCenter.x + cos(a) * curveRadius, curveCenter.y + sin(a) * curveRadius));
    }
    final curveSegs = _stitchPath(curvePoints);
    if (allSegs.isNotEmpty && curveSegs.isNotEmpty) {
      allSegs.last.next = curveSegs.first;
      curveSegs.first.prev = allSegs.last;
    }
    allSegs.addAll(curveSegs);
    
    // 3. Vertical Wall attached to curve endpoint
    final wallBottom = Vector2(curvePoints.last.x, curvePoints.last.y - 250.0);
    final wallSeg = TrackSegment(curvePoints.last, wallBottom);
    allSegs.last.next = wallSeg;
    wallSeg.prev = allSegs.last;
    allSegs.add(wallSeg);
	
    // 4. Isolated/Disjoint Loops & Landing Platform Ramps
    final loopCenter = Vector2(840.0, -94.0);
    const loopRadius = 106.0;
    const loopSteps = 48;
    const startAngle = 2.62;
    const endAngle = 6.68;
    
    final loopPoints = <Vector2>[];
    for (int i = 0; i <= loopSteps; i++) {
      final t = i / loopSteps;
      final a = startAngle + t * (endAngle - startAngle);
      loopPoints.add(Vector2(loopCenter.x + cos(a) * loopRadius, loopCenter.y + sin(a) * loopRadius));
    }
    allSegs.addAll(_stitchPath(loopPoints));

    final landingRampPoints = <Vector2>[
      Vector2(928.0, 26.0), Vector2(1018.0, 112.0), Vector2(1090.0, 138.0),
      Vector2(1100.0, 130.0), Vector2(1240.0, 98.0), Vector2(1390.0, 114.0),
      Vector2(1540.0, 76.0), Vector2(1710.0, 124.0), Vector2(1910.0, 112.0),
      Vector2(2120.0, 112.0),
    ];
    allSegs.addAll(_stitchPath(landingRampPoints));

    return allSegs;
  }

  @override
  void update(double dt) {
    super.update(dt);
    this.dt = dt; 
    
    if (!tiltCalibrated) {
      tiltZero = rawTilt;
      tiltCalibrated = true;
    }
    
    final normalized = ((rawTilt - tiltZero) / 8.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.15 + normalized * 0.85;
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
    player = Bike(_spawnPoint(), grid);
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
  void onTapUp(TapUpEvent event) => isGas = isBrake = false;

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
      case 10: Bike._impactCrashLimit += step; break;
      case 11: Bike._landingRotationDamping += step; break;
      case 12: Bike._wheelieRotationDamping += step; break;
      case 13: Bike._airborneRotationDamping += step; break;
      case 14: Bike._brakeStrength += step; break;
    }
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(camera.viewfinder.zoom);
    canvas.translate(-player.position.x, -player.position.y);

    final trackPaint = Paint()..color = const Color(0xFF00FF88)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    for (final s in trackSegments) canvas.drawLine(_off(s.a), _off(s.b), trackPaint);
    
    player.render(canvas);
    canvas.restore();
    _renderUIOverlay(canvas);
  }
  
  void _renderUIOverlay(Canvas canvas) {
    final width = size.x;
    final height = size.y;
    
    if (isTuningMode) {
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height * 0.25), Paint()..color = Colors.black.withOpacity(0.8));
    }

    void drawDebugText(String text, Offset pos, [Color color = Colors.white54]) {
      TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, pos);
    }

    if (!isTuningMode) {
      drawDebugText('[ TUNE ]', Offset(width * 0.05, height * 0.05), Colors.white);
    } else {
      drawDebugText('[ TUNE: ON ]', Offset(width * 0.05, height * 0.05), Colors.green);
      drawDebugText('[ NEXT ] >', Offset(width * 0.85, height * 0.05), Colors.white);
      
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
        case 10: val = Bike._impactCrashLimit; break;
        case 11: val = Bike._landingRotationDamping; break;
        case 12: val = Bike._wheelieRotationDamping; break;
        case 13: val = Bike._airborneRotationDamping; break;
        case 14: val = Bike._brakeStrength; break;
      }
      
      drawDebugText('${tuningParamNames[currentTuningParam]}: ${val.toStringAsFixed(2)}', Offset(width * 0.35, height * 0.05), Colors.yellow);
    }
  }

  Vector2 _spawnPoint() => Vector2(-550.0, -50.0);
}

class TrackSegment {
  final Vector2 a, b;
  TrackSegment? prev;
  TrackSegment? next;

  TrackSegment(this.a, this.b);
  Vector2 get delta => b - a;
  Vector2 get tangent => delta.normalized();
}

class SurfaceHit {
  final Vector2 point, normal, tangent;
  final double distance;
  const SurfaceHit({required this.point, required this.normal, required this.tangent, required this.distance});
}

enum BikeState { riding, crashed }

class Bike {
  static const _gravity = 300.0;
  static const _rearDrive = 420.0;
  static double _brakeStrength = 700.0; 
  static const _wheelRadius = 5.0;
  static const _headRadius = 3.0;
  
  static double _impactCrashLimit = 950.0; 
  static double suspensionTravel = 4.5; 
  
  static double suspensionStrength = 1300.0; 
  static double suspensionDamping = 40.0; 
  static double _magnetStrength = 0.005;

  static double _playerTorqueStrength = 200000.0; 
  static double _cogDistanceFromRear = 8.5;
  static double _cogHeight = 5.0;
  static double _frontGroundedTorqueScale = 0.15;
  static double _wheelbase = 18.0;
  static double _bikeMass = 10.0;
  static double _airborneGravityFactor = 1.0; 
  
  static double _landingRotationDamping = 140.0;  
  static double _wheelieRotationDamping = 65.0;   
  static double _airborneRotationDamping = 45.0;  

  // Tightened optimization gating radius to fit the spatial hash setup
  static const double _maxSurfaceDist = 12.0;

  final SpatialGrid spatialGrid;
  double tilt = 0.0;
  bool isGas = false;
  bool isBrake = false;

  late Vector2 rearPos, frontPos;
  late Vector2 rearOldPos, frontOldPos;
  late Vector2 frameTopPos, headPos, collisionHeadPos;

  BikeState state = BikeState.riding;
  bool rearOnGround = false;
  bool frontOnGround = false;
  
  SurfaceHit? _rearSurface, _frontSurface;

  double get _massRear => (_wheelbase - _cogDistanceFromRear) / _wheelbase;
  double get _massFront => _cogDistanceFromRear / _wheelbase;

  Bike(Vector2 startPos, this.spatialGrid) {
    rearPos = startPos + Vector2(-9.5, 6.5);
    frontPos = startPos + Vector2(8.5, 6.5);
    rearOldPos = rearPos.clone();
    frontOldPos = frontPos.clone();
    
    frameTopPos = startPos.clone();
    headPos = startPos.clone();
    collisionHeadPos = startPos.clone();
    
    _syncFrameAndCollision(0.0);
  }

  Vector2 get position => (rearPos + frontPos) / 2.0;
  double get speed => ((rearPos - rearOldPos).length + (frontPos - frontOldPos).length) / (2.0 * (1/120));
  bool get hasFiniteState => rearPos.x.isFinite && frontPos.x.isFinite;

  void update(double dt) {
    double timeAcc = dt;
    const fixedDt = 1.0 / 120.0;
    while (timeAcc >= fixedDt) {
      _stepPhysics(fixedDt);
      timeAcc -= fixedDt;
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
    
    rVel *= 0.999; 
    fVel *= 0.999;

    Vector2 rAccel = Vector2(0, _gravity), fAccel = Vector2(0, _gravity);

    Vector2 fwd = (frontPos - rearPos).normalized();
    Vector2 localDown = Vector2(-fwd.y, fwd.x); 
    Vector2 rForkDir = localDown.clone()..rotate(0.2); 
    Vector2 fForkDir = localDown.clone()..rotate(-0.5); 

    Vector2 rTarget = rearPos + rForkDir * suspensionTravel;
    Vector2 fTarget = frontPos + fForkDir * suspensionTravel;

    // QUERY THE GRID INSTEAD OF SCROLLING ALL MAP SEGMENTS GLOBAL-WIDE
    _rearSurface = _nearestSurface(rTarget);
    _frontSurface = _nearestSurface(fTarget);
    rearOnGround = frontOnGround = false;

    if (_rearSurface != null && _rearSurface!.distance < _maxSurfaceDist) {
      double sd = (rTarget - _rearSurface!.point).dot(_rearSurface!.normal);
      if (sd < _wheelRadius) {
        rearOnGround = true;
        double penetration = _wheelRadius - sd;
        double vNorm = rVel.dot(_rearSurface!.normal);
        rAccel += _rearSurface!.normal * max(0.0, penetration * suspensionStrength - vNorm * suspensionDamping);
        
        if (isGas) rAccel += _forwardTangent(_rearSurface!.tangent) * _rearDrive;
        if (isBrake) {
          double vTan = rVel.dot(_rearSurface!.tangent);
          rAccel -= _rearSurface!.tangent * (vTan.sign * _brakeStrength);
        }
        if (vNorm < -_impactCrashLimit) _crash();
      } 
      else if (sd < _wheelRadius + 5.0 && sd > 0) {
        rAccel -= _rearSurface!.normal * (_gravity * _magnetStrength * 100.0);
      }
    }

    if (_frontSurface != null && _frontSurface!.distance < _maxSurfaceDist) {
      double sd = (fTarget - _frontSurface!.point).dot(_frontSurface!.normal);
      if (sd < _wheelRadius) {
        frontOnGround = true;
        double penetration = _wheelRadius - sd;
        double vNorm = fVel.dot(_frontSurface!.normal);
        fAccel += _frontSurface!.normal * max(0.0, penetration * suspensionStrength - vNorm * suspensionDamping);
        
        if (isBrake) {
          double vTan = fVel.dot(_frontSurface!.tangent);
          fAccel -= _frontSurface!.tangent * (vTan.sign * _brakeStrength);
        }
        if (vNorm < -_impactCrashLimit) _crash();
      }
    }

    // --- COG AND TORQUE FIXES ---
    Vector2 axle = frontPos - rearPos;
    Vector2 tangent = Vector2(-axle.y, axle.x)..normalize();
    double angle = atan2(axle.y, axle.x);

    double playerTorque = -tilt * _playerTorqueStrength;
    if (playerTorque < 0 && frontOnGround) playerTorque *= _frontGroundedTorqueScale;

    double gravTorqueAccel = 0.0;
    if (rearOnGround && !frontOnGround) {
      double cosA = cos(angle);
      double sinA = sin(angle);
      double cogHorizontalOffset = (cosA * _cogDistanceFromRear) - (sinA * _cogHeight);
      gravTorqueAccel = (-_gravity * cogHorizontalOffset) / _wheelbase;
    }

    double damping;
    if (!rearOnGround && !frontOnGround) {
      damping = _airborneRotationDamping;
    } else if ((rearOnGround && !frontOnGround) || (!rearOnGround && frontOnGround)) {
      damping = _wheelieRotationDamping;
    } else {
      damping = _landingRotationDamping;
    }

    Vector2 relVel = fVel - rVel;
    double rotVel = relVel.dot(tangent) / _wheelbase;
    double linearTorqueAccel = (playerTorque / (_wheelbase * _bikeMass))
                             + gravTorqueAccel
                             + (rotVel * damping);

    rAccel += tangent * linearTorqueAccel;
    fAccel -= tangent * linearTorqueAccel;

    Vector2 rNext = rearPos + rVel * dt + rAccel * (dt * dt);
    Vector2 fNext = frontPos + fVel * dt + fAccel * (dt * dt);

    rearOldPos.setFrom(rearPos); frontOldPos.setFrom(frontPos);
    rearPos.setFrom(rNext); frontPos.setFrom(fNext);

    for (int i = 0; i < 8; i++) {
      final diff = frontPos - rearPos;
      final dist = diff.length;
      if (dist < 0.0001) continue;
      final err = (dist - _wheelbase) / dist;
      rearPos.add(diff * (err * _massFront));
      frontPos.sub(diff * (err * _massRear));
    }
    
    _syncFrameAndCollision(atan2(frontPos.y - rearPos.y, frontPos.x - rearPos.x));
    SurfaceHit? hHit = _nearestSurface(collisionHeadPos);
    if (hHit != null && hHit.distance < _headRadius) _crash();
  }

  void _syncFrameAndCollision(double currAngle) {
    Vector2 center = (rearPos + frontPos) / 2.0;
    Vector2 fwd = (frontPos - rearPos).normalized();
    Vector2 localDown = Vector2(-fwd.y, fwd.x); 
    
    frameTopPos = center + localDown * -14.0;
    collisionHeadPos = frameTopPos;
    headPos = center + localDown * -7.0; 
  }

  // REWRITTEN NEAREST SURFACE PROJECTION FILTER
  SurfaceHit? _nearestSurface(Vector2 pt) {
    SurfaceHit? best; 
    double bDist = double.infinity;
    
    // Retrieve only segments overlapping locally near this spatial vector cluster
    final localSegs = spatialGrid.getNearby(pt, _maxSurfaceDist + 10.0);

    for (final s in localSegs) {
      final l2 = s.delta.length2; 
      if (l2 == 0) continue;
      
      final double rawT = (pt - s.a).dot(s.delta) / l2;
      final t = rawT.clamp(0.0, 1.0);
      final close = s.a + s.delta * t;
      final dist = (pt - close).length;
      
      if (dist < bDist) {
        Vector2 geomNormal = Vector2(s.tangent.y, -s.tangent.x);
        Vector2 geomTangent = s.tangent;

        // Continuity check: smooth out joint transitions if vertices match
        double effectiveDist = dist;
        if (rawT < -0.001 && s.prev != null) continue; 
        if (rawT > 1.001 && s.next != null) continue;

        if (effectiveDist < bDist) {
          bDist = effectiveDist;
          Vector2 toPt = pt - close;
          if ((t <= 0.001 || t >= 0.999) && toPt.length2 > 0) {
            if (geomNormal.dot(toPt) < 0) {
              geomNormal = toPt.normalized();
              geomTangent = Vector2(-geomNormal.y, geomNormal.x);
            }
          }
          best = SurfaceHit(point: close, normal: geomNormal, tangent: geomTangent, distance: dist);
        }
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
    Vector2 rForkDir = localDown.clone()..rotate(0.2); 
    Vector2 fForkDir = localDown.clone()..rotate(-0.5); 

    Vector2 rWheelVis = rearPos + rForkDir * suspensionTravel;
    if (_rearSurface != null && _rearSurface!.distance < _maxSurfaceDist) {
      Vector2 targetWheel = rearPos + rForkDir * suspensionTravel;
      double sd = (targetWheel - _rearSurface!.point).dot(_rearSurface!.normal);
      if (sd < _wheelRadius) {
        double normalComp = _wheelRadius - sd;
        double forkAlign = rForkDir.dot(-_rearSurface!.normal).clamp(0.1, 1.0);
        double forkComp = (normalComp / forkAlign).clamp(0.0, suspensionTravel);
        rWheelVis = rearPos + rForkDir * (suspensionTravel - forkComp);
      }
    }

    Vector2 fWheelVis = frontPos + fForkDir * suspensionTravel;
    if (_frontSurface != null && _frontSurface!.distance < _maxSurfaceDist) {
      Vector2 targetWheel = frontPos + fForkDir * suspensionTravel;
      double sd = (targetWheel - _frontSurface!.point).dot(_frontSurface!.normal);
      if (sd < _wheelRadius) {
        double normalComp = _wheelRadius - sd;
        double forkAlign = fForkDir.dot(-_frontSurface!.normal).clamp(0.1, 1.0);
        double forkComp = (normalComp / forkAlign).clamp(0.0, suspensionTravel);
        fWheelVis = frontPos + fForkDir * (suspensionTravel - forkComp);
      }
    }

    canvas.drawCircle(_off(rWheelVis), _wheelRadius, wheelP);
    canvas.drawCircle(_off(fWheelVis), _wheelRadius, wheelP);
    
    canvas.drawLine(_off(rearPos), _off(frontPos), frameP);
    canvas.drawLine(_off(rearPos), _off(frameTopPos), frameP);
    canvas.drawLine(_off(frontPos), _off(frameTopPos), frameP);
    
    final shockP = Paint()..color = Colors.grey[400]!..strokeWidth = 2;
    canvas.drawLine(_off(rearPos), _off(rWheelVis), shockP);
    canvas.drawLine(_off(frontPos), _off(fWheelVis), shockP);
    
    canvas.drawCircle(_off(headPos), _headRadius, riderP);
  }
}

class Background extends Component {
  @override
  void render(Canvas canvas) => canvas.drawRect(const Rect.fromLTWH(-5000, -5000, 16000, 16000), Paint()..color = const Color(0xFF112233));
}

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(
      text: 'RaceRider ${RaceRiderGame.buildLabel}\nSpeed: ${gameRef.player.speed.toStringAsFixed(1)}', 
      style: const TextStyle(color: Colors.yellow, fontSize: 12)
    ))..layout()..paint(canvas, const Offset(16, 60));
  }
}