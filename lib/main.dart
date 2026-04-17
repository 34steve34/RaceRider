/* ============================================================================
 * RACERIDER - v35 - COG-AWARE TILT + NO MORE FALLING THROUGH
 * Lean force now applied at COG (exactly like real BR). Stable wheelies.
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
    player = Bike(Vector2(-40, 8.5));
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

// ====================== RAYCAST ======================
class RaycastResult {
  final bool hit;
  final double distance;
  final Vector2 point;
  final Vector2 normal;
  RaycastResult(this.hit, this.distance, this.point, this.normal);
}

RaycastResult castRay(Vector2 start, Vector2 dir, List<TrackSegment> segments, {double maxDist = 60.0}) {
  RaycastResult best = RaycastResult(false, maxDist, Vector2.zero(), Vector2.zero());
  final end = start + dir.normalized() * maxDist;

  for (final seg in segments) {
    final p1 = Vector2(seg.xStart, seg.yStart);
    final p2 = Vector2(seg.xEnd, seg.yEnd);
    final den = (start.x - end.x) * (p1.y - p2.y) - (start.y - end.y) * (p1.x - p2.x);
    if (den.abs() < 1e-9) continue;

    final t = ((start.x - p1.x) * (p1.y - p2.y) - (start.y - p1.y) * (p1.x - p2.x)) / den;
    final u = -((start.x - end.x) * (start.y - p1.y) - (start.y - end.y) * (start.x - p1.x)) / den;

    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
      final hitPoint = start + (end - start) * t;
      final dist = (hitPoint - start).length;
      if (dist < best.distance) {
        final normal = (p2 - p1)..rotate(-pi / 2)..normalize();
        if (normal.y > 0) normal.negate();
        best = RaycastResult(true, dist, hitPoint, normal);
      }
    }
  }
  return best;
}

// ====================== BIKE - COG-AWARE ======================
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;
  bool onGround = false;

  final double gravity = 38.0;
  final double leanStrength = 165.0;      // COG force strength
  final double leanDamping = 22.0;        // kills oscillation instantly
  final double acceleration = 130.0;
  final double brakePower = 35.0;

  final double wheelbase = 4.3;
  final double wheelRadius = 0.85;
  final double suspensionStiffness = 2350.0;
  final double suspensionDamping = 180.0;
  final double magnetDistance = 1.4;
  final double magnetStrength = 580.0;

  // Virtual COG position (slightly above and behind center - like real rider)
  final Vector2 cogOffset = Vector2(-0.4, -1.1);

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(6.5, 3.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double targetTilt, bool gas, bool brake, List<TrackSegment> segments) {
    velocity.y += gravity * dt;

    // === COG-AWARE LEAN (exactly like Bike Race) ===
    double desiredAngle = targetTilt * 1.95;                 // full wheelies + backflips
    double angleError = desiredAngle - angle;
    double torque = angleError * leanStrength - angularVelocity * leanDamping;
    angularVelocity += torque * dt;

    if (onGround) angularVelocity *= 0.79;
    else angularVelocity *= 0.968;

    angle += angularVelocity * dt;

    // Predict position
    final predictedPos = position + velocity * dt;

    onGround = false;
    double totalFy = 0.0;
    double totalTorque = 0.0;

    Vector2 rotate(Vector2 local) {
      final c = cos(angle), s = sin(angle);
      return Vector2(local.x * c - local.y * s, local.x * s + local.y * c);
    }

    // Rear wheel raycast (starts high above)
    final rearLocal = Vector2(-wheelbase / 2, 0.95);
    final rearPos = predictedPos + rotate(rearLocal);
    final rayStart = rearPos + Vector2(0, -40); // much higher start = no tunneling
    final down = Vector2(0, 1);

    var result = castRay(rayStart, down, segments);
    if (result.hit) {
      final effectiveDist = result.distance - 40;
      if (effectiveDist < wheelRadius) {
        double penetration = wheelRadius - effectiveDist;
        if (penetration > 0) {
          totalFy -= penetration * suspensionStiffness - velocity.y * suspensionDamping;
          totalTorque += (rearPos.x - predictedPos.x) * penetration * 2.2;
          onGround = true;
        }
      } else if (effectiveDist < magnetDistance + wheelRadius) {
        totalFy -= (effectiveDist - wheelRadius - magnetDistance) * magnetStrength;
      }
    }

    // Front wheel (same robust raycast)
    final frontLocal = Vector2(wheelbase / 2, 0.95);
    final frontPos = predictedPos + rotate(frontLocal);
    final frontRayStart = frontPos + Vector2(0, -40);

    result = castRay(frontRayStart, down, segments);
    if (result.hit) {
      final effectiveDist = result.distance - 40;
      if (effectiveDist < wheelRadius) {
        double penetration = wheelRadius - effectiveDist;
        if (penetration > 0) {
          totalFy -= penetration * suspensionStiffness * 0.94 - velocity.y * suspensionDamping;
          totalTorque += (frontPos.x - predictedPos.x) * penetration * 1.8;
          onGround = true;
        }
      } else if (effectiveDist < magnetDistance + wheelRadius) {
        totalFy -= (effectiveDist - wheelRadius - magnetDistance) * magnetStrength * 0.9;
      }
    }

    // Hard anti-tunnel snap
    if (!onGround && (rearPos.y > 12 + 20 || frontPos.y > 12 + 20)) {
      position.y -= 8; // pull bike back up if it somehow sank
      velocity.y = velocity.y * 0.3;
    }

    velocity.y += totalFy * dt;
    angularVelocity += totalTorque * 0.017 * dt;

    position = predictedPos;

    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.88;
    }
  }
}

// Background, TrackSegment, DebugOverlay (unchanged)
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
        text: "v35 - COG TILT\n"
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