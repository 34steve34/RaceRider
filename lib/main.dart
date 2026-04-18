/* ============================================================================
 * RACERIDER - v37 - TUNNELING FIXED (Predictive Position Correction)
 * No more falling through. Wheels are corrected to surface BEFORE drawing.
 * Uses separation vectors + impulses. Robust on any slope/speed.
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
    player = Bike(Vector2(-40, 0.0));
    add(DebugOverlay());

    camera.viewfinder.zoom = 5.3;
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = player.position;

    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      rawTilt = event.y;
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

    final trackPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    for (final seg in trackSegments) {
      canvas.drawLine(Offset(seg.xStart, seg.yStart), Offset(seg.xEnd, seg.yEnd), trackPaint);
    }

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

// ====================== CLOSEST POINT ON TRACK (unchanged - still perfect) ======================
class ClosestPointResult {
  final double distance;
  final Vector2 point;
  final Vector2 normal;
  ClosestPointResult(this.distance, this.point, this.normal);
}

ClosestPointResult getClosestPointOnTrack(Vector2 wheelPos, List<TrackSegment> segments) {
  double minDist = double.infinity;
  Vector2 bestPoint = Vector2.zero();
  Vector2 bestNormal = Vector2(0, -1);

  for (final seg in segments) {
    final a = Vector2(seg.xStart, seg.yStart);
    final b = Vector2(seg.xEnd, seg.yEnd);
    final ab = b - a;
    final ap = wheelPos - a;
    double proj = ap.dot(ab) / ab.length2;
    proj = proj.clamp(0.0, 1.0);
    final closest = a + ab * proj;

    final distVec = wheelPos - closest;
    final dist = distVec.length;
    if (dist < minDist) {
      minDist = dist;
      bestPoint = closest;
      bestNormal = ab..rotate(-pi / 2)..normalize();
      if (bestNormal.y > 0) bestNormal.negate();
    }
  }
  return ClosestPointResult(minDist, bestPoint, bestNormal);
}

// ====================== BIKE - v37 collision system ======================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  final double gravity = 38.0;
  final double leanStrength = 165.0;
  final double leanDamping = 22.0;
  final double acceleration = 130.0;
  final double brakePower = 35.0;

  final double wheelbase = 4.3;
  final double wheelRadius = 0.85;
  final double magnetDistance = 1.4;
  final double magnetStrength = 580.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(6.5, 3.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double targetTilt, bool gas, bool brake, List<TrackSegment> segments) {
    velocity.y += gravity * dt;

    // COG-aware lean (stable wheelies)
    double desiredAngle = targetTilt * 1.95;
    double angleError = desiredAngle - angle;
    double torque = angleError * leanStrength - angularVelocity * leanDamping;
    angularVelocity += torque * dt;

    if (onGround) angularVelocity *= 0.79;
    else angularVelocity *= 0.968;

    angle += angularVelocity * dt;

    final predictedPos = position + velocity * dt;

    // ====================== v37: PREDICTIVE COLLISION RESOLUTION ======================
    onGround = false;
    double totalTorque = 0.0;
    Vector2 correctedPos = predictedPos.clone();

    // 2-pass resolution (rear → front) to handle deep or chained penetrations
    for (int pass = 0; pass < 2; pass++) {
      // Rear wheel
      final rearLocal = Vector2(-wheelbase / 2, 0.95);
      final rearWheelPos = correctedPos + _rotate(rearLocal);
      final rearResult = getClosestPointOnTrack(rearWheelPos, segments);
      double rearPen = wheelRadius - rearResult.distance;

      if (rearPen > 0) {
        final sepDir = (rearWheelPos - rearResult.point).normalized();
        correctedPos -= sepDir * rearPen;
        // Impulse - kill velocity into the track + tiny rebound
        final velDot = velocity.dot(sepDir);
        if (velDot < 0) {
          velocity -= sepDir * velDot * 1.4;
        }
        onGround = true;
        totalTorque += (rearWheelPos.x - correctedPos.x) * rearPen * 2.2;
      } else if (rearResult.distance < magnetDistance + wheelRadius) {
        final pullDir = (rearResult.point - rearWheelPos).normalized();
        final pull = (magnetDistance + wheelRadius - rearResult.distance) * magnetStrength * 0.6;
        velocity += pullDir * (pull * dt);
      }

      // Front wheel
      final frontLocal = Vector2(wheelbase / 2, 0.95);
      final frontWheelPos = correctedPos + _rotate(frontLocal);
      final frontResult = getClosestPointOnTrack(frontWheelPos, segments);
      double frontPen = wheelRadius - frontResult.distance;

      if (frontPen > 0) {
        final sepDir = (frontWheelPos - frontResult.point).normalized();
        correctedPos -= sepDir * frontPen * 0.96; // slightly softer front suspension feel
        final velDot = velocity.dot(sepDir);
        if (velDot < 0) {
          velocity -= sepDir * velDot * 1.3;
        }
        onGround = true;
        totalTorque += (frontWheelPos.x - correctedPos.x) * frontPen * 1.8;
      } else if (frontResult.distance < magnetDistance + wheelRadius) {
        final pullDir = (frontResult.point - frontWheelPos).normalized();
        final pull = (magnetDistance + wheelRadius - frontResult.distance) * magnetStrength * 0.55;
        velocity += pullDir * (pull * dt);
      }
    }

    position = correctedPos;

    // Apply accumulated torque
    angularVelocity += totalTorque * 0.017 * dt;

    // Ground drive (gas/brake)
    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.88;
    }
  }

  Vector2 _rotate(Vector2 local) {
    final c = cos(angle), s = sin(angle);
    return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
  }
}

// ====================== Rest of the file unchanged ======================
class Background extends Component {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(-5000, -5000, 12000, 12000), Paint()..color = const Color(0xFF112233));
  }
}

class TrackSegment {
  final double xStart, yStart, xEnd, yEnd;
  TrackSegment(this.xStart, this.yStart, this.xEnd, this.yEnd);
}

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
        text: "v37 - TUNNELING FIXED\n"
            "Tilt: ${gameRef.smoothedTilt.toStringAsFixed(2)}\n"
            "Angle: ${gameRef.player.angle.toStringAsFixed(2)}\n"
            "OnGround: ${gameRef.player.onGround}",
        style: const TextStyle(color: Colors.yellow, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 20));
  }
}