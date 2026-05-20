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

class RaceRiderGame extends FlameGame with DragCallbacks, TapCallbacks {
  static const buildLabel = 'physics v.403 - Full Assembly';
  late Bike player;
  final List<TrackSegment> trackSegments = [];
  final SpatialGrid grid = SpatialGrid(cellSize: 80.0);
  
  AppState currentMode = AppState.design;
  DesignTool activeTool = DesignTool.draw;
  
  Vector2 startSpawnPoint = Vector2(-150.0, -30.0);
  Vector2 finishLinePoint = Vector2(150.0, -30.0);
  
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  double tiltZero = 0.0;
  bool tiltCalibrated = false;
  bool isGas = false;
  bool isBrake = false;
  
  StreamSubscription? _accelSub;
  Vector2? _lastDrawnPoint;
  static const double _drawingMinDistance = 14.0; 
  TrackSegment? _lastCreatedSegment;

  double _timeAccumulator = 0.0;
  static const double _fixedDt = 1.0 / 120.0; 
  static const double _panicMaxCap = 0.10;    

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

    if (currentMode == AppState.victory) {
      final centerX = size.x / 2;
      final centerY = size.y / 2;
      if (x >= centerX - 80 && x <= centerX + 80 && y >= centerY + 12 && y <= centerY + 48) {
        currentMode = AppState.ride;
        _restartBike();
        return;
      }
    }

    if (y < 60) {
      if (x < 125) {
        _clearCanvas();
        return;
      }
      if (x >= 135 && x < 245) {
        _undoLastSegment();
        return;
      }
      if (currentMode == AppState.design) {
        if (x >= 255 && x < 345) {
          camera.viewfinder.zoom = (camera.viewfinder.zoom + 0.15).clamp(0.4, 3.5);
          return;
        }
        if (x >= 355 && x < 445) {
          camera.viewfinder.zoom = (camera.viewfinder.zoom - 0.15).clamp(0.4, 3.5);
          return;
        }
      }
      if (x > size.x - 150) {
        _toggleMode();
        return;
      }
    }

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
    
    double cappedDt = dt.clamp(0.001, 0.033);
    
    if (!tiltCalibrated) {
      tiltZero = rawTilt;
      tiltCalibrated = true;
    }
    
    final normalized = ((rawTilt - tiltZero) / 8.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.15 + normalized * 0.85;
    if (smoothedTilt.abs() < 0.05) smoothedTilt = 0.0;
    
    player.tilt = smoothedTilt;
    player.isGas = (currentMode == AppState.victory) ? false : isGas;
    player.isBrake = (currentMode == AppState.victory) ? true : isBrake;
    
    if (currentMode == AppState.ride || currentMode == AppState.victory) {
      _timeAccumulator += cappedDt;
      if (_timeAccumulator > _panicMaxCap) {
        _timeAccumulator = _fixedDt;
      }
      while (_timeAccumulator >= _fixedDt) {
        player.stepPhysics(_fixedDt);
        _timeAccumulator -= _fixedDt;
      }
    }
    
    if (currentMode == AppState.ride) {
      double lowestTrackY = 200.0;
      for (final seg in trackSegments) {
        if (seg.a.y > lowestTrackY) lowestTrackY = seg.a.y;
        if (seg.b.y > lowestTrackY) lowestTrackY = seg.b.y;
      }
      if (player.position.y > lowestTrackY + 600.0) {
        _restartBike();
        return;
      }
    }

    if (player.state == BikeState.crashed && currentMode == AppState.ride) {
      _restartBike();
      return;
    }
    
    if (currentMode == AppState.ride) {
      double dx = player.headPos.x - finishLinePoint.x;
      double dy = player.headPos.y - finishLinePoint.y;
      if (dx >= 0 && dy <= 0 && dx < 28.0 && dy > -32.0) {
        currentMode = AppState.victory;
        isGas = isBrake = false;
      }
    }
    
    if (!player.hasFiniteState) {
      _restartBike();
      return;
    }

    if (currentMode == AppState.ride || currentMode == AppState.victory) {
      camera.viewfinder.zoom = 1.6; 
      double lerpRatio = (15.0 * cappedDt).clamp(0.0, 1.0);
      camera.viewfinder.position = camera.viewfinder.position + (player.position - camera.viewfinder.position) * lerpRatio;
    } else {
      if (_lastDrawnPoint == null && trackSegments.isEmpty) {
        double lerpRatio = (10.0 * cappedDt).clamp(0.0, 1.0);
        camera.viewfinder.position = camera.viewfinder.position + (startSpawnPoint - camera.viewfinder.position) * lerpRatio;
      }
    }
  }
  
  void _restartBike() {
    _timeAccumulator = 0.0;
    player = Bike(startSpawnPoint.clone(), grid);
    if (currentMode == AppState.design) isGas = isBrake = false;
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
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(12, 12, 115, 36), const Radius.circular(6)), Paint()..color = Colors.redAccent.withOpacity(0.85));
    TextPainter(text: const TextSpan(text: '[ CLEAR ALL ]', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, const Offset(24, 22));

    final undoOpacity = trackSegments.isNotEmpty ? 0.85 : 0.3;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(139, 12, 110, 36), const Radius.circular(6)), Paint()..color = Colors.blueGrey[700]!.withOpacity(undoOpacity));
    TextPainter(text: const TextSpan(text: '[ UNDO LINE ]', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, const Offset(153, 22));

    if (currentMode == AppState.design) {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(260, 12, 85, 36), const Radius.circular(6)), Paint()..color = Colors.purple[700]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '[ ZOOM + ]', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, const Offset(275, 23));

      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(355, 12, 85, 36), const Radius.circular(6)), Paint()..color = Colors.purple[700]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '[ ZOOM - ]', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
        ..layout()..paint(canvas, const Offset(370, 23));
    }

    final isRiding = currentMode == AppState.ride || currentMode == AppState.victory;
    final toggleBg = isRiding ? Colors.green[600]! : Colors.orange[700]!;
    final toggleLabel = isRiding ? 'GO TO DESIGN' : 'START RIDING';

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.x - 152, 12, 140, 36), const Radius.circular(6)), Paint()..color = toggleBg.withOpacity(0.9));
    TextPainter(text: TextSpan(text: toggleLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)
      ..layout()..paint(canvas, Offset(size.x - 138, 22));

    if (currentMode == AppState.victory) {
      final centerX = size.x / 2;
      final centerY = size.y / 2;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), Paint()..color = Colors.black.withOpacity(0.5));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(centerX - 160, centerY - 70, 320, 130), const Radius.circular(14)), Paint()..color = Colors.green[800]!);
      TextPainter(text: const TextSpan(text: '🏁 VICTORY! 🏁\nTRACK CLEARED', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, height: 1.25)), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(minWidth: 320, maxWidth: 320)..paint(canvas, Offset(centerX - 160, centerY - 52));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(centerX - 80, centerY + 12, 160, 36), const Radius.circular(8)), Paint()..color = Colors.orange[700]!);
      TextPainter(text: const TextSpan(text: 'RESTART RUN', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(minWidth: 160, maxWidth: 160)..paint(canvas, Offset(centerX - 80, centerY + 23));
    }

    if (currentMode == AppState.design) {
      final centerX = size.x / 2;
      final bottomY = size.y - 50;
      double barWidth = 520;
      double startX = centerX - (barWidth / 2);

      final penSelected = activeTool == DesignTool.draw;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = penSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '✏️ PEN DRAW', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(startX + 20, bottomY + 11));

      final sFlagSelected = activeTool == DesignTool.startFlag;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX + 130, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = sFlagSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '🟢 START LINE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(startX + 148, bottomY + 11));

      final fFlagSelected = activeTool == DesignTool.finishFlag;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX + 260, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = fFlagSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '🏁 FINISH GATE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(startX + 274, bottomY + 11));

      final panSelected = activeTool == DesignTool.pan;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(startX + 390, bottomY, 115, 38), const Radius.circular(20)), Paint()..color = panSelected ? Colors.orange[600]! : Colors.grey[800]!.withOpacity(0.9));
      TextPainter(text: const TextSpan(text: '✋ HAND PAN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(startX + 412, bottomY + 11));
    }
  }
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
  static const _rearDrive = 440.0;
  static double _brakeStrength = 750.0; 
  static const _wheelRadius = 5.0;
  static const _headRadius = 3.0;
  
  static double _microMagnetPull = 150.0; 
  static double _impactCrashLimit = 1600.0;       
  static double suspensionTravel = 4.5; 
  static double suspensionStrength = 1650.0;     
  static double suspensionDamping = 34.0; 
  
  static double _playerTorqueStrength = 212750.0;  
  static double _cogDistanceFromRear = 9.2;       
  static double _cogHeight = 3.8;
  static double _frontGroundedTorqueScale = 0.12;
  static double _wheelbase = 19.5;                
  static double _bikeMass = 14.0;                 

  static double _landingRotationDamping = 185.0;  
  static double _wheelieRotationDamping = 110.0;   
  static double _airborneRotationDamping = 125.0;  
  static const double _maxSurfaceDist = 12.0;

  final SpatialGrid spatialGrid;
  double tilt = 0.0;
  bool isGas = false;
  bool isBrake = false;

  late Vector2 rearPos, frontPos;
  late Vector2 rearOldPos, frontOldPos;
  late Vector2 frameTopPos, headPos, collisionHeadPos;

  BikeState state = BikeState.crashed;
  bool rearOnGround = false;
  bool frontOnGround = false;
  SurfaceHit? _rearSurface, _frontSurface;

  double get _massRear => (_wheelbase - _cogDistanceFromRear) / _wheelbase;
  double get _massFront => _cogDistanceFromRear / _wheelbase;

  Bike(Vector2 startPos, this.spatialGrid) {
    rearPos = startPos + Vector2(-10.2, 6.5);
    frontPos = startPos + Vector2(9.3, 6.5);
    rearOldPos = rearPos.clone();
    frontOldPos = frontPos.clone();
    frameTopPos = startPos.clone();
    headPos = startPos.clone();
    collisionHeadPos = startPos.clone();
    state = BikeState.riding;
    _syncFrameAndCollision();
  }

  Vector2 get position => (rearPos + frontPos) / 2.0;
  bool get hasFiniteState => rearPos.x.isFinite && frontPos.x.isFinite;

  void stepPhysics(double dt) {
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
        rAccel.add(_rearSurface!.normal * (penetration * suspensionStrength - (vNorm * suspensionDamping) + _microMagnetPull));
        
        if (isGas) {
          rAccel.add(_forwardTangent(_rearSurface!.tangent) * _rearDrive);
        } else {
          double vTan = rVel.dot(_rearSurface!.tangent);
          rAccel.sub(_rearSurface!.tangent * (vTan * 0.8));
        }
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
        fAccel.add(_frontSurface!.normal * (penetration * suspensionStrength - (vNorm * suspensionDamping) + _microMagnetPull));
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
      double balanceAngle = atan2(_cogHeight, _cogDistanceFromRear); 
      double angularOffset = angle - balanceAngle;
      gravTorqueAccel = (_gravity * sin(angularOffset) * _cogDistanceFromRear) / _wheelbase;
    }

    double damping = (!rearOnGround && !frontOnGround) ? _airborneRotationDamping : ((rearOnGround && !frontOnGround) || (!rearOnGround && frontOnGround)) ? _wheelieRotationDamping : _landingRotationDamping;
    double rotVel = (fVel - rVel).dot(tangent) / _wheelbase;
    double linearTorqueAccel = (playerTorque / (_wheelbase * _bikeMass)) + gravTorqueAccel + (rotVel * damping);

    rAccel.add(tangent * linearTorqueAccel);
    fAccel.sub(tangent * linearTorqueAccel);

    Vector2 rNext = rearPos + rVel * dt + rAccel * (dt * dt);
    Vector2 fNext = frontPos + fVel * dt + fAccel * (dt * dt);

    rearOldPos.setFrom(rearPos); frontOldPos.setFrom(frontPos);
    rearPos.setFrom(rNext); frontPos.setFrom(fNext);

    for (int i = 0; i < 8; i++) {
      final diff = frontPos - rearPos;
      final dist = diff.length;
      if (dist < 0.001) continue;
      final err = (dist - _wheelbase) / dist;
      rearPos.add(diff * (err * _massFront));
      frontPos.sub(diff * (err * _massRear));
    }
    _syncFrameAndCollision();
    SurfaceHit? hHit = _nearestSurface(collisionHeadPos);
    if (hHit != null && hHit.distance < _headRadius) _crash();
  }

  void _syncFrameAndCollision() {
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
        if (rawT < -0.001 && s.prev != null) continue; 
        if (rawT > 1.001 && s.next != null) continue;

        bDist = dist;
        Vector2 geomNormal = Vector2(s.tangent.y, -s.tangent.x);
        Vector2 geomTangent = s.tangent;
        Vector2 toPt = pt - close;
        
        if (toPt.length2 > 0.0001) {
          if (geomNormal.dot(toPt) < 0) {
            geomNormal = -geomNormal;
            geomTangent = -geomTangent;
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
      double sd = (rWheelVis - _rearSurface!.point).dot(_rearSurface!.normal);
      if (sd < _wheelRadius) {
        rWheelVis = rearPos + rForkDir * (suspensionTravel - ((_wheelRadius - sd) / rForkDir.dot(-_rearSurface!.normal).clamp(0.1, 1.0)).clamp(0.0, suspensionTravel));
      }
    }

    Vector2 fWheelVis = frontPos + fForkDir * suspensionTravel;
    if (_frontSurface != null && _frontSurface!.distance < _maxSurfaceDist) {
      double sd = (fWheelVis - _frontSurface!.point).dot(_frontSurface!.normal);
      if (sd < _wheelRadius) {
        fWheelVis = frontPos + fForkDir * (suspensionTravel - ((_wheelRadius - sd) / fForkDir.dot(-_frontSurface!.normal).clamp(0.1, 1.0)).clamp(0.0, suspensionTravel));
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