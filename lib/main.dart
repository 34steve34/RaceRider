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
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

enum AppState { design, ride, victory }
enum DesignTool { draw, startFlag, finishFlag, pan }

class RaceRiderGame extends FlameGame with DragCallbacks, TapCallbacks, ScaleDetector {
  static const buildLabel = 'physics v.370 - Start/Finish Gate Matrix';
  late Bike player;
  final List<TrackSegment> trackSegments = [];
  final SpatialGrid grid = SpatialGrid(cellSize: 80.0);
  
  AppState currentMode = AppState.design;
  DesignTool activeTool = DesignTool.draw;
  
  // Dedicated Gate Coordinates
  Vector2 startSpawnPoint = Vector2(-150.0, -30.0);
  Vector2 finishLinePoint = Vector2(150.0, -30.0);
  
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  double tiltZero = 0.0;
  bool tiltCalibrated = false;
  bool isGas = false;
  bool isBrake = false;
  
  double dt = 0.0;
  StreamSubscription? _accelSub;
  
  double crashTimer = 0.0;
  double victoryTimer = 0.0;
  static const double _restartDelay = 1.2;
  static const double _victoryDelay = 2.5;

  Vector2? _lastDrawnPoint;
  static const double _drawingMinDistance = 14.0; 
  TrackSegment? _lastCreatedSegment;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _clearCanvas();
    _accelSub = accelerometerEvents.listen((e) => rawTilt = e.y);
  }

  @override
  void onRemove() {
    _accelSub?.cancel();
    super.onRemove();
  }

  Vector2 _screenToWorld(Vector2 localPosition) {
    return camera.viewfinder.position + 
        (localPosition - size / 2) / camera.viewfinder.zoom;
  }

  @override
  void onTapDown(TapDownEvent event) {
    final x = event.localPosition.x;
    final y = event.localPosition.y;

    // TOP BAR MENU NAVIGATION INTERCEPTS
    if (y < 60) {
      if (x < 130) {
        _clearCanvas();
        return;
      }
      if (x >= 142 && x < 252) {
        _undoLastSegment();
        return;
      }
      if (x > size.x - 150) {
        _toggleMode();
        return;
      }
    }

    // BOTTOM TOOLBAR INTERCEPTS (Only in Design Mode)
    if (currentMode == AppState.design && y > size.y - 65) {
      double barWidth = 520;
      double startX = (size.x / 2) - (barWidth / 2);
      
      if (x >= startX && x < startX + 115) {
        activeTool = DesignTool.draw;
        return;
      }
      if (x >= startX + 130 && x < startX + 245) {
        activeTool = DesignTool.startFlag;
        return;
      }
      if (x >= startX + 260 && x < startX + 375) {
        activeTool = DesignTool.finishFlag;
        return;
      }
      if (x >= startX + 390 && x < startX + 505) {
        activeTool = DesignTool.pan;
        return;
      }
    }

    // WORLD SPACE INPUT ROUTING
    if (currentMode == AppState.design) {
      final worldPos = _screenToWorld(event.localPosition);
      if (activeTool == DesignTool.draw) {
        _lastDrawnPoint = worldPos;
        _lastCreatedSegment = null;
      } else if (activeTool == DesignTool.startFlag) {
        startSpawnPoint = worldPos;
      } else if (activeTool == DesignTool.finishFlag) {
        finishLinePoint = worldPos;
      }
    } else if (currentMode == AppState.ride) {
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
    if (currentMode != AppState.design) return;

    if (activeTool == DesignTool.pan) {
      camera.viewfinder.position -= event.localDelta / camera.viewfinder.zoom;
      return;
    }

    if (activeTool != DesignTool.draw) return;

    final worldPos = _screenToWorld(event.localEndPosition);
    if (_lastDrawnPoint != null) {
      double dist = (worldPos - _lastDrawnPoint!).length;
      
      if (dist >= _drawingMinDistance) {
        if ((worldPos.x - _lastDrawnPoint!.x).abs() < 1.0 && (worldPos.y - _lastDrawnPoint!.y).abs() < 1.0) {
          return;
        }

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
    if (currentMode != AppState.design) return;
    double scaleDelta = info.scale.global.x; 
    if (scaleDelta != 0 && scaleDelta != 1.0) {
      camera.viewfinder.zoom = (camera.viewfinder.zoom * (scaleDelta > 1 ? 1.05 : 0.95)).clamp(0.3, 4.0);
    }
  }

  void _undoLastSegment() {
    if (trackSegments.isEmpty) return;
    trackSegments.removeLast();
    grid.clear();
    for (final seg in trackSegments) {
      grid.insert(seg);
    }
    _lastDrawnPoint = null;
    _lastCreatedSegment = null;
  }

  void _toggleMode() {
    _lastDrawnPoint = null;
    _lastCreatedSegment = null;

    if (currentMode == AppState.ride || currentMode == AppState.victory) {
      currentMode = AppState.design;
      isGas = isBrake = false;
    } else {
      currentMode = AppState.ride;
      _restartBike(); 
    }
  }

  void _clearCanvas() {
    grid.clear();
    trackSegments.clear();
    startSpawnPoint = Vector2(-150.0, -30.0);
    finishLinePoint = Vector2(150.0, -30.0);
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
    
    if (currentMode == AppState.ride || currentMode == AppState.victory) {
      player.update(dt);
    }
    
    // Check for Crash Loop Reset
    if (player.state == BikeState.crashed && currentMode == AppState.ride) {
      crashTimer += dt;
      if (crashTimer >= _restartDelay) _restartBike();
    } else {
      crashTimer = 0.0;
    }
    
    // Check for Victory Finish Gate Collisions
    if (currentMode == AppState.ride) {
      double distToFinish = (player.position - finishLinePoint).length;
      if (distToFinish < 22.0) {
        currentMode = AppState.victory;
        isGas = isBrake = false;
      }
    }

    if (currentMode == AppState.victory) {
      victoryTimer += dt;
      if (victoryTimer >= _victoryDelay) {
        currentMode = AppState.ride;
        _restartBike();
      }
    } else {
      victoryTimer = 0.0;
    }
    
    if (!player.hasFiniteState) _restartBike();

    if (currentMode == AppState.ride || currentMode == AppState.victory) {
      camera.viewfinder.zoom = 1.6; 
      camera.viewfinder.position = camera.viewfinder.position * 0.85 + player.position * 0.15;
    } else {
      if (_lastDrawnPoint == null && trackSegments.isEmpty) {
        camera.viewfinder.position = camera.viewfinder.position * 0.9 + startSpawnPoint * 0.1;
      }
    }
  }
  
  void _restartBike() {
    player = Bike(startSpawnPoint.clone(), grid);
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

    // Render Track Layout Geometry
    final trackPaint = Paint()..color = const Color(0xFF00FF88)..strokeWidth = 2.5..style = PaintingStyle.stroke;
    for (final s in trackSegments) canvas.drawLine(_off(s.a), _off(s.b), trackPaint);
    
    // Render flags across both modes so you see targets while driving
    _drawStartFlag(canvas, startSpawnPoint);
    _drawCheckeredFlag(canvas, finishLinePoint);
    
    player.render(canvas);
    canvas.restore();
    _renderUIOverlay(canvas);
  }

  void _drawStartFlag(Canvas canvas, Vector2 point) {
    final flagPaint = Paint()..color = Colors.greenAccent[400]!..strokeWidth = 2.0;
    canvas.drawLine(Offset(point.x, point.y - 25), Offset(point.x, point.y), flagPaint);
    
    final path = Path()
      ..moveTo(point.x, point.y - 25)
      ..lineTo(point.x + 14, point.y - 17)
      ..lineTo(point.x, point.y - 9)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.green[600]!..style = PaintingStyle.fill);
  }

  void _drawCheckeredFlag(Canvas canvas, Vector2 point) {
    final flagPaint = Paint()..color = Colors.white!..strokeWidth = 2.0;
    canvas.drawLine(Offset(point.x, point.y - 25), Offset(point.x, point.y), flagPaint);
    
    // Draw an authentic tiny checkered box block banner
    final rectPaintBlack = Paint()..color = Colors.black;
    final rectPaintWhite = Paint()..color = Colors.white;
    
    double topY = point.y - 25;
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 4; col++) {
        final p = ((row + col) % 2 == 0) ? rectPaintBlack : rectPaintWhite;
        canvas.drawRect(Rect.fromLTWH(point.x + (col * 4), topY + (row * 4), 4, 4), p);
      }
    }
  }
  
  void _renderUIOverlay(Canvas canvas) {
    // --- TOP MENU ELEMENT: CLEAR ---
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(12, 12, 115, 36), const Radius.circular(6)), Paint()..color = Colors.redAccent.withOpacity(0.85));
    TextPainter(text: const TextSpan(text: '[ CLEAR ALL ]', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, const Offset(24, 22));

    // --- TOP MENU ELEMENT: UNDO ---
    final undoOpacity = trackSegments.isNotEmpty ? 0.85 : 0.3;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(139, 12, 110, 36), const Radius.circular(6)), Paint()..color = Colors.blueGrey[700]!.withOpacity(undoOpacity));
    TextPainter(text: const TextSpan(text: '[ UNDO LINE ]', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, const Offset(153, 22));

    // --- TOP MENU ELEMENT: MODE SWAP ---
    final isRiding = currentMode == AppState.ride || currentMode == AppState.victory;
    final toggleBg = isRiding ? Colors.green[600]! : Colors.orange[700]!;
    final toggleLabel = isRiding ? 'GO TO DESIGN' : 'START RIDING';

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.x - 152, 12, 140, 36), const Radius.circular(6)), Paint()..color = toggleBg.withOpacity(0.9));
    TextPainter(text: TextSpan(text: toggleLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, Offset(size.x - 138, 22));

    // --- VICTORY CONGRATULATORY CARD ---
    if (currentMode == AppState.victory) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), Paint()..color = Colors.black.withOpacity(0.4));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((size.x / 2) - 160, (size.y / 2) - 40, 320, 80), const Radius.circular(12)), Paint()..color = Colors.green[700]!);
      TextPainter(text: const TextSpan(text: '🏁 VICTORY! 🏁\nTRACK CLEARED!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.3), textAlign: TextAlign.center), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, Offset((size.x / 2) - 76, (size.y / 2) - 24));
    }

    // --- BOTTOM TOOLBAR CONTROLS (Design Mode Only) ---
    if (currentMode == AppState.design) {
      final centerX = size.x / 2;
      final bottomY = size.y - 50;
      double barWidth = 520;
      double startX = centerX - (barWidth / 2);

      // Tool A: PEN
      final penSelected = activeTool == DesignTool.draw;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = penSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '✏️ PEN DRAW', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, Offset(startX + 20, bottomY + 11));

      // Tool B: START FLAG
      final sFlagSelected = activeTool == DesignTool.startFlag;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX + 130, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = sFlagSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '🟢 START LINE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, Offset(startX + 148, bottomY + 11));

      // Tool C: FINISH FLAG
      final fFlagSelected = activeTool == DesignTool.finishFlag;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX + 260, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = fFlagSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '🏁 FINISH GATE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, Offset(startX + 274, bottomY + 11));

      // Tool D: HAND PAN
      final panSelected = activeTool == DesignTool.pan;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX + 390, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = panSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '✋ HAND PAN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, Offset(startX + 412, bottomY + 11));
    }
  }
}

// --- ALL REMAINING PHYSICS AND SCENERY ENGINE OBJECTS REMAIN UNCHANGED ---
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

    final Vector2 rVel = (rearPos - rearOldPos) / dt;
    final Vector2 fVel = (frontPos - frontOldPos) / dt;
    
    final Vector2 rAccel = Vector2(0, _gravity);
    final Vector2 fAccel = Vector2(0, _gravity);

    final Vector2 fwd = (frontPos - rearPos).normalized();
    final Vector2 localDown = Vector2(-fwd.y, fwd.x); 
    final Vector2 rForkDir = localDown.clone()..rotate(0.2); 
    final Vector2 fForkDir = localDown.clone()..rotate(-0.5); 

    final Vector2 rTarget = rearPos + rForkDir * suspensionTravel;
    final Vector2 fTarget = frontPos + fForkDir * suspensionTravel;

    _rearSurface = _nearestSurface(rTarget);
    _frontSurface = _nearestSurface(fTarget);
    rearOnGround = frontOnGround = false;

    if (_rearSurface != null && _rearSurface!.distance < _maxSurfaceDist) {
      double sd = (rTarget - _rearSurface!.point).dot(_rearSurface!.normal);
      if (sd < _wheelRadius) {
        rearOnGround = true;
        double penetration = _wheelRadius - sd;
        double vNorm = rVel.dot(_rearSurface!.normal);
        rAccel.add(_rearSurface!.normal * max(0.0, penetration * suspensionStrength - vNorm * suspensionDamping));
        
        if (isGas) rAccel.add(_forwardTangent(_rearSurface!.tangent) * _rearDrive);
        if (isBrake) {
          double vTan = rVel.dot(_rearSurface!.tangent);
          rAccel.sub(_rearSurface!.tangent * (vTan.sign * _brakeStrength));
        }
        if (vNorm < -_impactCrashLimit) _crash();
      }
    }

    if (_frontSurface != null && _frontSurface!.distance < _maxSurfaceDist) {
      double sd = (fTarget - _frontSurface!.point).dot(_frontSurface!.normal);
      if (sd < _wheelRadius) {
        frontOnGround = true;
        double penetration = _wheelRadius - sd;
        double vNorm = fVel.dot(_frontSurface!.normal);
        fAccel.add(_frontSurface!.normal * max(0.0, penetration * suspensionStrength - vNorm * suspensionDamping));
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

    rAccel.add(tangent * linearTorqueAccel);
    fAccel.sub(tangent * linearTorqueAccel);

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
    final modeStr = gameRef.currentMode == AppState.ride ? 'RIDING MODE' : gameRef.currentMode == AppState.victory ? 'VICTORY CELEBRATION' : 'DESIGN MODE';
    TextPainter(textDirection: TextDirection.ltr, text: TextSpan(
      text: 'RaceRider ${RaceRiderGame.buildLabel}\nState: $modeStr\nLines Active: ${gameRef.trackSegments.length}\nZoom: ${gameRef.camera.viewfinder.zoom.toStringAsFixed(2)}', 
      style: const TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold)
    ))..layout()..paint(canvas, const Offset(16, 60));
  }
}