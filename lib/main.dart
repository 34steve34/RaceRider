/* ============================================================================
 * RACERIDER - v39 - BIGGER VISUALS + NO DOT + SUSTAINED GROUND + FAST DRIVE
 * Matched draw-to-physics scale, removed rim dot, zero micro-bounce, low drag
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

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 2.4);

  @override
  Future<void> onLoad() async {
    add(Background());
    trackSegments = _generateRandomTrack();
    player = Bike(Vector2(-90, -35.0));
    add(DebugOverlay());

    camera.viewfinder.zoom = 2.4;
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
    double y = 35.0;
    final rng = Random();

    segments.add(TrackSegment(x, y, x + 450, y));
    x += 450;

    for (int i = 0; i < 100; i++) {
      final dx = 58.0 + rng.nextDouble() * 68.0;
      final dy = -10.0 + rng.nextDouble() * 20.0;
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
    smoothedTilt = smoothedTilt * 0.45 + normalizedTilt * 0.55;

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
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final seg in trackSegments) {
      canvas.drawLine(Offset(seg.xStart, seg.yStart), Offset(seg.xEnd, seg.yEnd), trackPaint);
    }

    // === v39 Motorcycle - perfectly scaled to physics ===
    canvas.save();
    canvas.translate(player.position.x, player.position.y);
    canvas.rotate(player.angle);

    final bodyPaint = Paint()..color = const Color(0xFFFF5500);
    final forkPaint = Paint()..color = Colors.grey[800]!..strokeWidth = 3.5..style = PaintingStyle.stroke;
    final wheelPaint = Paint()..color = Colors.white;
    final rimPaint = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2.2;

    // Chassis / frame (longer, lower)
    canvas.drawRect(const Rect.fromLTWH(-8.2, -2.4, 16.5, 3.6), bodyPaint);

    // Seat
    final seatPaint = Paint()..color = const Color(0xFF222222);
    canvas.drawRect(const Rect.fromLTWH(-6.1, -4.1, 7.8, 2.0), seatPaint);

    // Rear swingarm
    canvas.drawLine(const Offset(-7.8, 0.8), const Offset(-4.1, 3.4), forkPaint);
    // Front fork (thicker, angled)
    canvas.drawLine(const Offset(6.8, -1.1), const Offset(9.1, 3.3), forkPaint);

    // Handlebars
    canvas.drawLine(const Offset(7.1, -3.4), const Offset(10.4, -4.6), forkPaint);

    // Wheels - EXACTLY match physics scale
    canvas.drawCircle(const Offset(-5.4, 3.15), 2.1, wheelPaint);   // rear
    canvas.drawCircle(const Offset(5.4, 3.15), 2.1, wheelPaint);    // front

    // Rims - no stray dot
    canvas.drawCircle(const Offset(-5.4, 3.15), 1.35, rimPaint);
    canvas.drawCircle(const Offset(5.4, 3.15), 1.35, rimPaint);

    canvas.restore();
    canvas.restore();
  }
}

// ====================== CLOSEST POINT (unchanged) ======================
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

// ====================== BIKE v39 ======================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 195.0;
  final double leanDamping = 28.0;
  final double acceleration = 480.0;     // even stronger
  final double brakePower = 110.0;

  final double wheelbase = 10.8;
  final double wheelRadius = 2.1;
  final double magnetDistance = 3.5;
  final double magnetStrength = 680.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(17.0, 9.0);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double targetTilt, bool gas, bool brake, List<TrackSegment> segments) {
    velocity.y += gravity * dt;

    double desiredAngle = targetTilt * 2.15;
    double angleError = desiredAngle - angle;
    double torque = angleError * leanStrength - angularVelocity * leanDamping;
    angularVelocity += torque * dt;
    if (onGround) angularVelocity *= 0.76;
    else angularVelocity *= 0.965;
    angle += angularVelocity * dt;

    Vector2 predictedPos = position + velocity * dt;
    Vector2 correctedPos = predictedPos.clone();

    onGround = false;
    double totalTorque = 0.0;

    final Vector2 rearLocal = Vector2(-wheelbase / 2, wheelRadius * 0.9);
    final Vector2 frontLocal = Vector2(wheelbase / 2, wheelRadius * 0.9);

    for (int pass = 0; pass < 3; pass++) {
      // Rear wheel
      Vector2 rearPos = correctedPos + _rotate(rearLocal);
      final rearRes = getClosestPointOnTrack(rearPos, segments);
      double pen = wheelRadius - rearRes.distance;

      if (pen > 0.015) {
        Vector2 sep = (rearPos - rearRes.point).normalized();
        correctedPos -= sep * (pen * 0.88);
        double velDotN = velocity.dot(sep);
        if (velDotN < 0) velocity -= sep * velDotN * 1.4;

        Vector2 tangent = Vector2(sep.y, -sep.x);
        double velDotT = velocity.dot(tangent);
        velocity -= tangent * velDotT * 0.62;

        onGround = true;
        totalTorque += (rearPos.x - correctedPos.x) * pen * 2.8;
      } else if (rearRes.distance < magnetDistance + wheelRadius) {
        Vector2 pullDir = (rearRes.point - rearPos).normalized();
        double pull = (magnetDistance + wheelRadius - rearRes.distance) * magnetStrength * 0.58;
        velocity += pullDir * pull * dt;
      }

      // Front wheel
      Vector2 frontPos = correctedPos + _rotate(frontLocal);
      final frontRes = getClosestPointOnTrack(frontPos, segments);
      double fPen = wheelRadius - frontRes.distance;

      if (fPen > 0.015) {
        Vector2 sep = (frontPos - frontRes.point).normalized();
        correctedPos -= sep * (fPen * 0.85);
        double velDotN = velocity.dot(sep);
        if (velDotN < 0) velocity -= sep * velDotN * 1.35;

        Vector2 tangent = Vector2(sep.y, -sep.x);
        double velDotT = velocity.dot(tangent);
        velocity -= tangent * velDotT * 0.59;

        onGround = true;
        totalTorque += (frontPos.x - correctedPos.x) * fPen * 2.1;
      } else if (frontRes.distance < magnetDistance + wheelRadius) {
        Vector2 pullDir = (frontRes.point - frontPos).normalized();
        double pull = (magnetDistance + wheelRadius - frontRes.distance) * magnetStrength * 0.5;
        velocity += pullDir * pull * dt;
      }
    }

    position = correctedPos;
    angularVelocity += totalTorque * 0.018 * dt;

    // === v39: Sustained drive + very low drag ===
    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.965;   // almost no drag → feels fast and responsive
    } else {
      velocity.x *= 0.98;
    }
  }

  Vector2 _rotate(Vector2 local) {
    final c = cos(angle), s = sin(angle);
    return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
  }
}

class Background extends Component {
  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(-5000, -5000, 15000, 15000), Paint()..color = const Color(0xFF112233));
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
        text: "v39 - BIG, FAST & STABLE\n"
            "Tilt: ${gameRef.smoothedTilt.toStringAsFixed(2)}\n"
            "Angle: ${gameRef.player.angle.toStringAsFixed(2)}\n"
            "OnGround: ${gameRef.player.onGround}",
        style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 20));
  }
}