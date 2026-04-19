/* ============================================================================
 * RACERIDER - v42 - TUNABLE ANTI-VIBRATION SECTION
 * All key parameters grouped at the top for easy experimenting
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

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 2.1);

  @override
  Future<void> onLoad() async {
    add(Background());
    trackSegments = _generateRandomTrack();
    player = Bike(Vector2(-90, -45.0));
    add(DebugOverlay());

    camera.viewfinder.zoom = 2.1;
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
    double y = 38.0;
    final rng = Random();

    segments.add(TrackSegment(x, y, x + 450, y));
    x += 450;

    for (int i = 0; i < 100; i++) {
      final dx = 62.0 + rng.nextDouble() * 72.0;
      final dy = -11.0 + rng.nextDouble() * 22.0;
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
    smoothedTilt = smoothedTilt * 0.42 + normalizedTilt * 0.58;

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
      ..strokeWidth = 11.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final seg in trackSegments) {
      canvas.drawLine(Offset(seg.xStart, seg.yStart), Offset(seg.xEnd, seg.yEnd), trackPaint);
    }

    canvas.save();
    canvas.translate(player.position.x, player.position.y);
    canvas.rotate(player.angle);

    final bodyPaint = Paint()..color = const Color(0xFFFF4400);
    final framePaint = Paint()..color = Colors.black..strokeWidth = 4.0..style = PaintingStyle.stroke;
    final forkPaint = Paint()..color = Colors.grey[700]!..strokeWidth = 4.5..style = PaintingStyle.stroke;
    final wheelPaint = Paint()..color = Colors.white;
    final rimPaint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.5;

    canvas.drawRect(const Rect.fromLTWH(-9.5, -3.2, 19.5, 4.2), bodyPaint);
    final seatPaint = Paint()..color = const Color(0xFF111111);
    canvas.drawRect(const Rect.fromLTWH(-7.2, -5.1, 8.5, 2.1), seatPaint);

    canvas.drawLine(const Offset(-9.2, 1.2), const Offset(-4.8, 4.8), framePaint);
    canvas.drawLine(const Offset(7.8, -2.1), const Offset(11.2, 4.6), forkPaint);
    canvas.drawLine(const Offset(8.5, -4.2), const Offset(12.8, -5.6), forkPaint);

    canvas.drawCircle(const Offset(-6.8, 4.8), 2.35, wheelPaint);
    canvas.drawCircle(const Offset(7.8, 4.8), 2.35, wheelPaint);
    canvas.drawCircle(const Offset(-6.8, 4.8), 1.55, rimPaint);
    canvas.drawCircle(const Offset(7.8, 4.8), 1.55, rimPaint);

    canvas.restore();
    canvas.restore();
  }
}

// ====================== CLOSEST POINT ======================
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

// ====================== BIKE v42 - TUNING SECTION ======================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  // ==================== TUNABLE PARAMETERS ====================
  final double gravity = 42.0;

  final double leanStrength = 210.0;
  final double leanDamping = 32.0;

  final double acceleration = 620.0;
  final double brakePower = 140.0;

  final double wheelbase = 13.6;
  final double wheelRadius = 2.35;

  final double magnetDistance = 2.8;        // how early it starts pulling down
  final double magnetStrength = 550.0;

  final double penetrationCorrectionFactor = 0.65;   // lower = softer landing (try 0.6~0.85)
  final double normalDamping = 2.1;                 // how strongly it kills downward speed (1.6 ~ 2.2)
  final double tangentFriction = 0.72;               // how sticky the wheels are (0.5 ~ 0.85)
  final double minPenetrationThreshold = 0.008;      // smaller = more sensitive

  final double torqueMultiplier = 2.6;               // wheel torque for rotation
  // ===========================================================

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(21.0, 11.0);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double targetTilt, bool gas, bool brake, List<TrackSegment> segments) {
    velocity.y += gravity * dt;

    double desiredAngle = targetTilt * 2.2;
    double angleError = desiredAngle - angle;
    double torque = angleError * leanStrength - angularVelocity * leanDamping;
    angularVelocity += torque * dt;

    if (onGround) angularVelocity *= 0.74;
    else angularVelocity *= 0.96;

    angle += angularVelocity * dt;

    Vector2 predictedPos = position + velocity * dt;
    Vector2 correctedPos = predictedPos.clone();

    onGround = false;
    double totalTorque = 0.0;

    final Vector2 rearLocal = Vector2(-wheelbase / 2, wheelRadius * 0.85);
    final Vector2 frontLocal = Vector2(wheelbase / 2, wheelRadius * 0.85);

    for (int pass = 0; pass < 4; pass++) {
      // Rear wheel
      Vector2 rearPos = correctedPos + _rotate(rearLocal);
      final rearRes = getClosestPointOnTrack(rearPos, segments);
      double pen = wheelRadius - rearRes.distance;

      if (pen > minPenetrationThreshold) {
        Vector2 sep = (rearPos - rearRes.point).normalized();
        correctedPos -= sep * (pen * penetrationCorrectionFactor);
        
        double velDotN = velocity.dot(sep);
        if (velDotN < 0) velocity -= sep * velDotN * normalDamping;

        Vector2 tangent = Vector2(sep.y, -sep.x);
        velocity -= tangent * (velocity.dot(tangent) * tangentFriction);

        onGround = true;
        totalTorque += (rearPos.x - correctedPos.x) * pen * torqueMultiplier;
      } 
      else if (rearRes.distance < magnetDistance + wheelRadius) {
        Vector2 pullDir = (rearRes.point - rearPos).normalized();
        velocity += pullDir * ((magnetDistance + wheelRadius - rearRes.distance) * magnetStrength * 0.62 * dt);
      }

      // Front wheel
      Vector2 frontPos = correctedPos + _rotate(frontLocal);
      final frontRes = getClosestPointOnTrack(frontPos, segments);
      double fPen = wheelRadius - frontRes.distance;

      if (fPen > minPenetrationThreshold) {
        Vector2 sep = (frontPos - frontRes.point).normalized();
        correctedPos -= sep * (fPen * penetrationCorrectionFactor * 0.96);
        
        double velDotN = velocity.dot(sep);
        if (velDotN < 0) velocity -= sep * velDotN * (normalDamping * 0.94);

        Vector2 tangent = Vector2(sep.y, -sep.x);
        velocity -= tangent * (velocity.dot(tangent) * (tangentFriction * 0.94));

        onGround = true;
        totalTorque += (frontPos.x - correctedPos.x) * fPen * (torqueMultiplier * 0.8);
      } 
      else if (frontRes.distance < magnetDistance + wheelRadius) {
        Vector2 pullDir = (frontRes.point - frontPos).normalized();
        velocity += pullDir * ((magnetDistance + wheelRadius - frontRes.distance) * magnetStrength * 0.55 * dt);
      }
    }

    position = correctedPos;
    angularVelocity += totalTorque * 0.019 * dt;

    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.972;
    } else {
      velocity.x *= 0.98;
    }
  }

  Vector2 _rotate(Vector2 local) {
    final c = cos(angle), s = sin(angle);
    return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
  }
}

// Rest of the file (Background, TrackSegment, DebugOverlay) unchanged
class Background extends Component {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(-5000, -5000, 16000, 16000), Paint()..color = const Color(0xFF112233));
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
      text: TextSpan(text: "v42 - TUNABLE\nTilt: ${gameRef.smoothedTilt.toStringAsFixed(2)}\nAngle: ${gameRef.player.angle.toStringAsFixed(2)}\nOnGround: ${gameRef.player.onGround}",
          style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 20));
  }
}