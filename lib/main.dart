/* ============================================================================
 * RACERIDER - v31 - THIN TRACK + NO FALL THROUGH + TILT FIXED + NO WILD SPIN
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

  double rawTilt = 0.0;
  double smoothedTilt = 0.0;

  bool isGas = false;
  bool isBrake = false;

  late StreamSubscription<AccelerometerEvent> _accelSubscription;

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 5.3);

  @override
  Future<void> onLoad() async {
    add(Background());

    trackSegments = _generateRandomTrack();

    player = Bike(Vector2(-30, 9.0));   // safely above track
    add(DebugOverlay());

    camera.viewfinder.zoom = 5.3;
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = player.position;

    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      rawTilt = event.y;   // ← Flipped sign for your desired control
    });
  }

  @override
  void onRemove() {
    _accelSubscription.cancel();
    super.onRemove();
  }

  List<TrackSegment> _generateRandomTrack() {
    final segments = <TrackSegment>[];
    double x = -700.0;
    double y = 12.0;
    final rng = Random();

    segments.add(TrackSegment(x, y, x + 450, y));
    x += 450;

    for (int i = 0; i < 100; i++) {
      final dx = 48.0 + rng.nextDouble() * 55.0;
      final dy = -8.0 + rng.nextDouble() * 17.0;
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

    double normalizedTilt = (rawTilt / 9.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.5 + normalizedTilt * 0.5;

    player.updateBike(dt, smoothedTilt, isGas, isBrake, trackSegments);
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

    // Thin green track - exactly like original feel
    final trackPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 4.0      // ← Much thinner now
      ..style = PaintingStyle.stroke;

    for (final seg in trackSegments) {
      canvas.drawLine(
        Offset(seg.xStart, seg.yStart),
        Offset(seg.xEnd, seg.yEnd),
        trackPaint,
      );
    }

    // Bike
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

// Background
class Background extends Component {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(-5000, -5000, 12000, 12000), 
      Paint()..color = const Color(0xFF112233));
  }
}

class TrackSegment {
  final double xStart, yStart, xEnd, yEnd;
  TrackSegment(this.xStart, this.yStart, this.xEnd, this.yEnd);
}

// Debug
class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
        text: "v31\n"
            "Tilt: ${gameRef.smoothedTilt.toStringAsFixed(2)}\n"
            "Angle: ${gameRef.player.angle.toStringAsFixed(2)}\n"
            "OnGround: ${gameRef.player.onGround}\n"
            "Bike Y: ${gameRef.player.position.y.toStringAsFixed(1)}",
        style: const TextStyle(color: Colors.yellow, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 20));
  }
}

// Bike
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  final double gravity = 38.0;
  final double leanStrength = 58.0;
  final double acceleration = 130.0;
  final double brakePower = 35.0;

  final double wheelbase = 4.3;
  final double wheelYOffset = 0.95;
  final double wheelRadius = 0.85;
  final double suspensionStiffness = 1450.0;
  final double suspensionDamping = 110.0;
  final double magnetDistance = 2.8;
  final double magnetStrength = 820.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(6.5, 3.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake, List<TrackSegment> trackSegments) {
    velocity.y += gravity * dt;

    double torque = tilt * leanStrength;
    angularVelocity += torque * dt;

    if (onGround) {
      angularVelocity *= 0.72;     // strong damping = almost no wild spin
    } else {
      angularVelocity *= 0.96;
    }
    angle += angularVelocity * dt;

    position += velocity * dt;

    onGround = false;
    double totalFy = 0.0;
    double totalTorque = 0.0;

    Vector2 rotateOffset(Vector2 local, double a) {
      final c = cos(a), s = sin(a);
      return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
    }

    // Rear wheel
    final rearOffset = rotateOffset(Vector2(-wheelbase / 2, wheelYOffset), angle);
    final rearX = position.x + rearOffset.x;
    final rearY = position.y + rearOffset.y;
    final trackY = _getTrackHeightAt(rearX, trackSegments);
    final desiredY = trackY - wheelRadius;
    double comp = rearY - desiredY;

    if (comp > 0) {
      totalFy -= (comp * suspensionStiffness - velocity.y * suspensionDamping);
      totalTorque += rearOffset.x * comp * 1.5;
      onGround = true;
    } else if (comp > -magnetDistance) {
      totalFy += (comp + magnetDistance) * magnetStrength;
    }

    // Front wheel
    final frontOffset = rotateOffset(Vector2(wheelbase / 2, wheelYOffset), angle);
    final frontX = position.x + frontOffset.x;
    final frontY = position.y + frontOffset.y;
    final fTrackY = _getTrackHeightAt(frontX, trackSegments);
    final fDesiredY = fTrackY - wheelRadius;
    double fComp = frontY - fDesiredY;

    if (fComp > 0) {
      totalFy -= (fComp * suspensionStiffness * 0.92 - velocity.y * suspensionDamping);
      totalTorque += frontOffset.x * fComp * 1.3;
      onGround = true;
    } else if (fComp > -magnetDistance) {
      totalFy += (fComp + magnetDistance) * magnetStrength * 0.9;
    }

    velocity.y += totalFy * dt;
    angularVelocity += totalTorque * 0.016 * dt;

    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.88;
    }
  }

  double _getTrackHeightAt(double x, List<TrackSegment> segments) {
    for (final seg in segments) {
      if (x >= min(seg.xStart, seg.xEnd) && x <= max(seg.xStart, seg.xEnd)) {
        final t = (x - seg.xStart) / (seg.xEnd - seg.xStart);
        return seg.yStart + t * (seg.yEnd - seg.yStart);
      }
    }
    return segments.last.yEnd;
  }
}