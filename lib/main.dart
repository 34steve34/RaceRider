/* ============================================================================
 * RACERIDER - v27 - PER-WHEEL RAYCASTING + 3-UNIT BIKE
 * Goal: Exact 2012 Bike Race feel on arbitrary tracks
 * ============================================================================ */

import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends Forge2DGame with TapCallbacks {
  late Bike player;
  late List<TrackSegment> trackSegments;
  late TrackRenderer trackRenderer;
  late DebugOverlay debug;

  double rawTilt = 0.0;
  double smoothedTilt = 0.0;

  bool isGas = false;
  bool isBrake = false;

  late StreamSubscription<AccelerometerEvent> _accelSubscription;

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 5.0);

  @override
  Future<void> onLoad() async {
    add(Background());

    trackSegments = _generateRandomTrack();
    trackRenderer = TrackRenderer();
    add(trackRenderer);

    player = Bike(Vector2(0, 6));
    debug = DebugOverlay();
    add(debug);

    camera.viewfinder.zoom = 5.5;
    camera.viewfinder.anchor = Anchor.center;

    // Accelerometer (portrait mode)
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      rawTilt = -event.x; // negative = natural lean direction on most phones
    });
  }

  @override
  void onRemove() {
    _accelSubscription.cancel();
    super.onRemove();
  }

  List<TrackSegment> _generateRandomTrack() {
    final segments = <TrackSegment>[];
    double x = -300.0;
    double y = 12.0;
    final rng = Random();

    // Starting flat
    segments.add(TrackSegment(x, y, x + 200, y));
    x += 200;

    for (int i = 0; i < 80; i++) {
      final dx = 40.0 + rng.nextDouble() * 60.0;
      final dy = -8.0 + rng.nextDouble() * 16.0; // big hills possible
      segments.add(TrackSegment(x, y, x + dx, y + dy));
      x += dx;
      y += dy;
    }
    return segments;
  }

  @override
  void update(double dt) {
    super.update(dt);

    camera.viewfinder.position = player.position;

    double normalizedTilt = (rawTilt / 8.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.4 + normalizedTilt * 0.6;

    player.updateBike(dt, smoothedTilt, isGas, isBrake, trackSegments);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final isLeftSide = event.localPosition.x < size.x / 2;
    if (isLeftSide) isBrake = true;
    else isGas = true;
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

    // Bike (manual draw - wheels now sit exactly on the raycast track)
    canvas.save();
    canvas.translate(player.position.x, player.position.y);
    canvas.rotate(player.angle);

    final chassisPaint = Paint()..color = const Color(0xFFFF8800);
    canvas.drawRect(const Rect.fromLTWH(-3.25, -0.8, 6.5, 1.6), chassisPaint);

    final riderPaint = Paint()..color = const Color(0xFF00FFFF);
    canvas.drawRect(const Rect.fromLTWH(-1.0, -2.1, 2.0, 1.8), riderPaint);

    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-2.1, 0.95), 0.85, wheelPaint);
    canvas.drawCircle(const Offset(2.1, 0.95), 0.85, wheelPaint);

    canvas.restore();
    canvas.restore();
  }
}

// ====================== TRACK ======================

class TrackSegment {
  final double xStart, yStart, xEnd, yEnd;
  TrackSegment(this.xStart, this.yStart, this.xEnd, this.yEnd);
}

class TrackRenderer extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 16.0
      ..style = PaintingStyle.stroke;

    for (final seg in gameRef.trackSegments) {
      canvas.drawLine(
        Offset(seg.xStart, seg.yStart),
        Offset(seg.xEnd, seg.yEnd),
        paint,
      );
    }
  }
}

// ====================== DEBUG ======================

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
        text: "v27 - RAYCAST 3-UNIT BIKE\n"
            "Left=Brake | Right=Gas\n"
            "Bike pos: ${gameRef.player.position}\n"
            "Angle: ${gameRef.player.angle.toStringAsFixed(2)}\n"
            "Camera zoom: ${gameRef.camera.viewfinder.zoom}",
        style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 30));
  }
}

// ====================== BIKE (raycasting version) ======================

class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 45.0;
  final double acceleration = 116.0;
  final double brakePower = 22.0;

  // 3-unit bike parameters
  final double wheelbase = 4.2;
  final double wheelYOffset = 0.95;   // local y offset of wheel centers
  final double wheelRadius = 0.85;
  final double suspensionStiffness = 800.0;
  final double suspensionDamping = 50.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(6.5, 3.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake, List<TrackSegment> trackSegments) {
    velocity.y += gravity * dt;

    // Lean torque (exactly like original)
    double torque = tilt * leanStrength;
    if (!onGround) angularVelocity *= 0.96;
    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    // Integrate position
    position += velocity * dt;

    // === PER-WHEEL RAYCAST SUSPENSION ===
    onGround = false;
    double totalFy = 0.0;      // upward force accumulator
    double totalTorque = 0.0;  // torque from differential suspension

    Vector2 rotateOffset(Vector2 local, double a) {
      final c = cos(a);
      final s = sin(a);
      return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
    }

    // Rear wheel raycast
    final localRear = Vector2(-wheelbase / 2, wheelYOffset);
    final rearOffset = rotateOffset(localRear, angle);
    final rearWheelX = position.x + rearOffset.x;
    final rearWheelY = position.y + rearOffset.y;
    final rearTrackY = _getTrackHeightAt(rearWheelX, trackSegments);
    final rearDesiredY = rearTrackY - wheelRadius;

    double rearCompression = rearWheelY - rearDesiredY;
    if (rearCompression > 0) {
      double spring = rearCompression * suspensionStiffness;
      double damp = velocity.y * suspensionDamping;
      double forceUp = spring - damp;
      totalFy -= forceUp;           // push chassis up (y-down coordinate)
      totalTorque += rearOffset.x * forceUp;
      onGround = true;
    }

    // Front wheel raycast
    final localFront = Vector2(wheelbase / 2, wheelYOffset);
    final frontOffset = rotateOffset(localFront, angle);
    final frontWheelX = position.x + frontOffset.x;
    final frontWheelY = position.y + frontOffset.y;
    final frontTrackY = _getTrackHeightAt(frontWheelX, trackSegments);
    final frontDesiredY = frontTrackY - wheelRadius;

    double frontCompression = frontWheelY - frontDesiredY;
    if (frontCompression > 0) {
      double spring = frontCompression * suspensionStiffness;
      double damp = velocity.y * suspensionDamping;
      double forceUp = spring - damp;
      totalFy -= forceUp;
      totalTorque += frontOffset.x * forceUp;
      onGround = true;
    }

    // Apply suspension forces
    velocity.y += totalFy * dt;
    angularVelocity += totalTorque * 0.012 * dt; // tuned inertia factor

    // Drive / brake (only when at least one wheel on ground)
    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.82; // ground friction
    }
  }

  double _getTrackHeightAt(double x, List<TrackSegment> segments) {
    for (final seg in segments) {
      final minX = min(seg.xStart, seg.xEnd);
      final maxX = max(seg.xStart, seg.xEnd);
      if (x >= minX && x <= maxX) {
        final t = (x - seg.xStart) / (seg.xEnd - seg.xStart);
        return seg.yStart + t * (seg.yEnd - seg.yStart);
      }
    }
    return segments.isNotEmpty ? segments.last.yEnd : 12.0;
  }

  @override
  void render(Canvas canvas) {
    // (bike is drawn manually in RaceRiderGame.render)
  }
}