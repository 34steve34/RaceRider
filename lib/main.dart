/* ============================================================================
 * RACERIDER - v38 - BIGGER BIKE + ANTI-VIBRATION + MOTORCYCLE LOOK + FAST
 * Scaled 2.5x, strong tangent friction, smoothed correction, better visuals
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

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 2.8); // zoomed out a bit for bigger bike

  @override
  Future<void> onLoad() async {
    add(Background());
    trackSegments = _generateRandomTrack();
    player = Bike(Vector2(-80, -20.0)); // spawn a bit higher
    add(DebugOverlay());

    camera.viewfinder.zoom = 2.8;
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
    double y = 30.0;
    final rng = Random();

    segments.add(TrackSegment(x, y, x + 450, y));
    x += 450;

    for (int i = 0; i < 100; i++) {
      final dx = 55.0 + rng.nextDouble() * 65.0;
      final dy = -9.0 + rng.nextDouble() * 19.0;
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
    smoothedTilt = smoothedTilt * 0.48 + normalizedTilt * 0.52; // slightly faster smoothing

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

    // Thicker, nicer track
    final trackPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 9.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final seg in trackSegments) {
      canvas.drawLine(Offset(seg.xStart, seg.yStart), Offset(seg.xEnd, seg.yEnd), trackPaint);
    }

    // === Improved Motorcycle rendering ===
    canvas.save();
    canvas.translate(player.position.x, player.position.y);
    canvas.rotate(player.angle);

    final bodyPaint = Paint()..color = const Color(0xFFFF5500);
    final forkPaint = Paint()..color = Colors.grey[800]!..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final wheelPaint = Paint()..color = Colors.white;
    final rimPaint = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.8;

    // Chassis / frame
    canvas.drawRect(const Rect.fromLTWH(-5.5, -1.8, 11.0, 2.8), bodyPaint);

    // Seat
    final seatPaint = Paint()..color = const Color(0xFF222222);
    canvas.drawRect(const Rect.fromLTWH(-4.2, -3.4, 5.5, 1.6), seatPaint);

    // Rear fork / swingarm
    canvas.drawLine(const Offset(-5.0, 0.5), const Offset(-2.8, 2.2), forkPaint);
    // Front fork
    canvas.drawLine(const Offset(4.8, -0.8), const Offset(6.2, 2.1), forkPaint);

    // Handlebars
    canvas.drawLine(const Offset(4.5, -2.6), const Offset(7.0, -3.8), forkPaint);

    // Wheels
    canvas.drawCircle(const Offset(-4.2, 2.1), 1.65, wheelPaint);
    canvas.drawCircle(const Offset(5.1, 2.1), 1.65, wheelPaint);
    canvas.drawCircle(const Offset(-4.2, 2.1), 1.1, rimPaint);
    canvas.drawCircle(const Offset(5.1, 2.1), 1.1, rimPaint);

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

// ====================== BIKE v38 ======================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 195.0;
  final double leanDamping = 28.0;
  final double acceleration = 420.0;     // ~3.2x faster
  final double brakePower = 95.0;

  final double wheelbase = 10.8;         // scaled
  final double wheelRadius = 2.1;        // scaled
  final double magnetDistance = 3.2;
  final double magnetStrength = 620.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(16.0, 8.0);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double targetTilt, bool gas, bool brake, List<TrackSegment> segments) {
    velocity.y += gravity * dt;

    // Lean
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

    for (int pass = 0; pass < 3; pass++) {  // 3 passes for rock-solid stability
      // Rear wheel
      Vector2 rearPos = correctedPos + _rotate(rearLocal);
      final rearRes = getClosestPointOnTrack(rearPos, segments);
      double pen = wheelRadius - rearRes.distance;

      if (pen > 0.02) {
        Vector2 sep = (rearPos - rearRes.point).normalized();
        correctedPos -= sep * (pen * 0.85);           // softer correction
        double velDotN = velocity.dot(sep);
        if (velDotN < 0) velocity -= sep * velDotN * 1.65; // strong normal impulse

        // Tangent friction (kills sideways slide/vibration)
        Vector2 tangent = Vector2(sep.y, -sep.x);
        double velDotT = velocity.dot(tangent);
        velocity -= tangent * velDotT * 0.68;

        onGround = true;
        totalTorque += (rearPos.x - correctedPos.x) * pen * 2.8;
      } else if (rearRes.distance < magnetDistance + wheelRadius) {
        Vector2 pullDir = (rearRes.point - rearPos).normalized();
        double pull = (magnetDistance + wheelRadius - rearRes.distance) * magnetStrength * 0.55;
        velocity += pullDir * pull * dt;
      }

      // Front wheel (same but slightly softer)
      Vector2 frontPos = correctedPos + _rotate(frontLocal);
      final frontRes = getClosestPointOnTrack(frontPos, segments);
      double fPen = wheelRadius - frontRes.distance;

      if (fPen > 0.02) {
        Vector2 sep = (frontPos - frontRes.point).normalized();
        correctedPos -= sep * (fPen * 0.82);
        double velDotN = velocity.dot(sep);
        if (velDotN < 0) velocity -= sep * velDotN * 1.55;

        Vector2 tangent = Vector2(sep.y, -sep.x);
        double velDotT = velocity.dot(tangent);
        velocity -= tangent * velDotT * 0.65;

        onGround = true;
        totalTorque += (frontPos.x - correctedPos.x) * fPen * 2.1;
      } else if (frontRes.distance < magnetDistance + wheelRadius) {
        Vector2 pullDir = (frontRes.point - frontPos).normalized();
        double pull = (magnetDistance + wheelRadius - frontRes.distance) * magnetStrength * 0.48;
        velocity += pullDir * pull * dt;
      }
    }

    position = correctedPos;
    angularVelocity += totalTorque * 0.018 * dt;

    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.84;   // lower drag = feels faster
    } else {
      velocity.x *= 0.98;
    }
  }

  Vector2 _rotate(Vector2 local) {
    final c = cos(angle), s = sin(angle);
    return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
  }
}

// Background, TrackSegment, DebugOverlay (same as before)
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
        text: "v38 - BIG & FAST\n"
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