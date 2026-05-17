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
class SpatialGrid {
  final double cellSize;
  final Map<String, List<TrackSegment>> _buckets = {};

  SpatialGrid({this.cellSize = 80.0});

  String _getKey(int cx, int cy) => '$cx,$cy';

  void clear() => _buckets.clear();

  void insert(TrackSegment seg) {
    int minX = (min(seg.a.x, seg.b.x) / cellSize).floor();
    int maxX = (max(seg.a.x, seg.b.x) / cellSize).floor();
    int minY = (min(seg.a.y, seg.b.y) / cellSize).floor();
    int maxY = (max(seg.a.y, seg.b.y) / cellSize).floor();

    for (int cx = minX; cx <= maxX; cx++) {
      for (int cy = minY; cy <= maxY; cy++) {
        _buckets.putIfAbsent(_getKey(cx, cy), () => []).add(seg);
      }
    }
  }

  List<TrackSegment> getNearby(Vector2 pos, double radius) {
    final Set<TrackSegment> nearby = {};
    int minX = ((pos.x - radius) / cellSize).floor();
    int maxX = ((pos.x + radius) / cellSize).floor();
    int minY = ((pos.y - radius) / cellSize).floor();
    int maxY = ((pos.y + radius) / cellSize).floor();

    for (int cx = minX; cx <= maxX; cx++) {
      for (int cy = minY; cy <= maxY; cy++) {
        final cellSegs = _buckets[_getKey(cx, cy)];
        if (cellSegs != null) nearby.addAll(cellSegs);
      }
    }
    return nearby.toList();
  }
}

// Global Enum to govern app behavior states
enum AppState { design, ride }

class RaceRiderGame extends FlameGame with DragCallbacks, TapCallbacks, ScaleDetector {
  static const buildLabel = 'physics v.340 - Stage 2 Mode UI Toggle Matrix';
  late Bike player;
  final List<TrackSegment> trackSegments = [];
  final SpatialGrid grid = SpatialGrid(cellSize: 80.0);
  
  // App State configuration
  AppState currentMode = AppState.design;
  
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  double tiltZero = 0.0;
  bool tiltCalibrated = false;
  bool isGas = false;
  bool isBrake = false;
  
  double dt = 0.0;
  late StreamSubscription _accelSub;
  
  double crashTimer = 0.0;
  static const double _crashRestartDelay = 1.2;

  Vector2? _lastDrawnPoint;
  static const double _drawingMinDistance = 12.0; 
  TrackSegment? _lastCreatedSegment;

  @override
  Future<void> onLoad() async {
    _loadStarterTrack();
    player = Bike(_spawnPoint(), grid);
    
    add(Background());
    add(DebugOverlay());
    
    camera.viewfinder
      ..zoom = 1.5
      ..anchor = Anchor.center
      ..position = player.position;
      
    _accelSub = accelerometerEvents.listen((e) => rawTilt = e.y);
  }

  void _loadStarterTrack() {
    grid.clear();
    trackSegments.clear();
    
    final points = [
      Vector2(-700.0, 100.0),
      Vector2(-200.0, 100.0),
    ];
    
    for (int i = 0; i < points.length - 1; i++) {
      final seg = TrackSegment(points[i], points[i + 1]);
      trackSegments.add(seg);
      grid.insert(seg);
    }
  }

  @override
  void onRemove() {
    _accelSub.cancel();
    super.onRemove();
  }

  Vector2 _screenToWorld(Vector2 localPosition) {
    return camera.viewfinder.position + 
        (localPosition - size / 2) / camera.viewfinder.zoom;
  }

  // --- RECONCILED INTERACTION CONTROLLER ---
  @override
  void onTapDown(TapDownEvent event) {
    final x = event.localPosition.x;
    final y = event.localPosition.y;

    // MENU SYSTEM GATING BOUNDS
    if (y < 60) {
      if (x < 150) {
        _clearCanvas();
        return;
      }
      if (x > size.x - 150) {
        _toggleMode();
        return;
      }
    }

    // SPLIT SYSTEM OPERATION
    if (currentMode == AppState.design) {
      final worldPos = _screenToWorld(event.localPosition);
      _lastDrawnPoint = worldPos;
      _lastCreatedSegment = null;
    } else {
      // Pure Ride Input mapping
      isBrake = x < size.x / 2;
      isGas = !isBrake;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (currentMode == AppState.ride) {
      isGas = isBrake = false;
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    // Only process drawing lines if explicitly sitting in Design Mode
    if (currentMode != AppState.design) return;

    final worldPos = _screenToWorld(event.localEndPosition);
    if (_lastDrawnPoint != null) {
      double dist = (worldPos - _lastDrawnPoint!).length;
      if (dist >= _drawingMinDistance) {
        final newSeg = TrackSegment(_lastDrawnPoint!.clone(), worldPos.clone());
        if (_lastCreatedSegment != null) {
          _lastCreatedSegment!.next = newSeg;
          newSeg.prev = _lastCreatedSegment;
        }
        trackSegments.add(newSeg);
        grid.insert(newSeg);

        _lastCreatedSegment = newSeg;
        _lastDrawnPoint = worldPos;
      }
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    _lastDrawnPoint = null;
    _lastCreatedSegment = null;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    // Scale and zoom configurations are dedicated exclusively to Design view spaces
    if (currentMode != AppState.design) return;

    double scaleDelta = info.scale.global.x; 
    if (scaleDelta != 0 && scaleDelta != 1.0) {
      camera.viewfinder.zoom = (camera.viewfinder.zoom * (scaleDelta > 1 ? 1.03 : 0.97)).clamp(0.4, 4.0);
    }
    
    final delta = info.delta.global;
    if (delta.length2 > 0 && scaleDelta == 1.0) {
      camera.viewfinder.position -= delta / camera.viewfinder.zoom;
    }
  }

  void _toggleMode() {
    if (currentMode == AppState.design) {
      currentMode = AppState.ride;
      _restartBike(); // Drop fresh bike down on spawn whenever entering ride mode
    } else {
      currentMode = AppState.design;
      isGas = isBrake = false;
    }
  }

  void _clearCanvas() {
    grid.clear();
    trackSegments.clear();
    _lastDrawnPoint = null;
    _lastCreatedSegment = null;
    currentMode = AppState.design;
    _restartBike();
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
    
    // Physics execution runs full loop cycle
    player.update(dt);
    
    if (player.state == BikeState.crashed) {
      crashTimer += dt;
      if (crashTimer >= _crashRestartDelay) _restartBike();
    } else {
      crashTimer = 0.0;
    }
    
    if (!player.hasFiniteState) _restartBike();

    // CAMERA LOGIC SPLIT: Dynamic target tracking vs Manual Workspace Panning
    if (currentMode == AppState.ride) {
      camera.viewfinder.zoom = 1.6; // Standard comfort racing zoom
      camera.viewfinder.position = camera.viewfinder.position * 0.85 + player.position * 0.15;
    } else {
      // In Design mode, if not dragging canvas, softly look near spawn target base
      if (_lastDrawnPoint == null && trackSegments.isEmpty) {
        camera.viewfinder.position = camera.viewfinder.position * 0.9 + _spawnPoint() * 0.1;
      }
    }
  }
  
  void _restartBike() {
    player = Bike(_spawnPoint(), grid);
    crashTimer = 0.0;
    if (currentMode == AppState.design) {
      isGas = isBrake = false;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(camera.viewfinder.zoom);
    canvas.translate(-camera.viewfinder.position.x, -camera.viewfinder.position.y);

    final trackPaint = Paint()..color = const Color(0xFF00FF88)..strokeWidth = 2.5..style = PaintingStyle.stroke;
    for (final s in trackSegments) canvas.drawLine(_off(s.a), _off(s.b), trackPaint);
    
    player.render(canvas);
    canvas.restore();
    _renderUIOverlay(canvas);
  }
  
  void _renderUIOverlay(Canvas canvas) {
    // Left System Element: CLEAR
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(12, 12, 130, 36), const Radius.circular(6)), Paint()..color = Colors.redAccent.withOpacity(0.85));
    TextPainter(text: const TextSpan(text: '[ CLEAR ALL ]', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, const Offset(26, 22));

    // Right System Element: MODE SWAP SWITCHER
    final isRiding = currentMode == AppState.ride;
    final toggleBg = isRiding ? Colors.green[600]! : Colors.orange[700]!;
    final toggleLabel = isRiding ? 'GO TO DESIGN' : 'START RIDING';

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.x - 152, 12, 140, 36), const Radius.circular(6)), Paint()..color = toggleBg.withOpacity(0.9));
    TextPainter(text: TextSpan(text: toggleLabel, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, Offset(size.x - 138, 22));
  }

  Vector2 _spawnPoint() => Vector2(-650.0, 20.0);
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
  static double suspensionStrength = 1500.0; 
  static double suspensionDamping = 30.0; 
  static double _magnetStrength = 0.005;
  static double _playerTorqueStrength = 300000.0; 
  static double _cogDistanceFromRear = 8.5;
  static double _cogHeight = 3.5;
  static double _frontGroundedTorqueScale = 0.15;
  static double _wheelbase = 18.0;
  static double _bikeMass = 10.0;
  static double _airborneGravityFactor = 1.0; 
  static double _landingRotationDamping = 140.0;  
  static double _wheelieRotationDamping = 65.0;   
  static double _airborneRotationDamping = 85.0;  
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
        if (vNorm < -_impactCrashLimit) _crash();
      }
    }

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

  SurfaceHit? _nearestSurface(Vector2 pt) {
    SurfaceHit? best; 
    double bDist = double.infinity;
    
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

        if (rawT < -0.001 && s.prev != null) continue; 
        if (rawT > 1.001 && s.next != null) continue;

        if (dist < bDist) {
          bDist = dist;
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
  void render(Canvas canvas) => canvas.drawRect(const Rect.fromLTWH(-10000, -10000, 30000, 30000), Paint()..color = const Color(0xFF112233));
}

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final modeStr = gameRef.currentMode == AppState.ride ? 'RIDING MODE' : 'DESIGN MODE';
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(
      text: 'RaceRider ${RaceRiderGame.buildLabel}\nState: $modeStr\nLines Active: ${gameRef.trackSegments.length}\nZoom: ${gameRef.camera.viewfinder.zoom.toStringAsFixed(2)}', 
      style: const TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold)
    ))..layout()..paint(canvas, const Offset(16, 60));
  }
}