/* ============================================================================
 * RACERIDER - Custom Arcade Physics (Bike Race style)
 * Engine: Flutter + Flame (No Forge2D)
 * ============================================================================ */

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(GameWidget(game: RaceRiderGame()));
}

class RaceRiderGame extends FlameGame with TapCallbacks {
  late Bike player;
  late Track track;

  double rawTilt = 0;
  double smoothedTilt = 0;

  bool isGas = false;
  bool isBrake = false;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    const double visibleWorldWidth = 40.0;
    final double aspectRatio = size.x / size.y;
    camera.viewfinder.visibleGameSize = Vector2(
      visibleWorldWidth,
      visibleWorldWidth / aspectRatio,
    );
  }

  @override
  Future<void> onLoad() async {
    track = Track();
    world.add(track);

    player = Bike(Vector2(0, -8), track.points);
    world.add(player);

    camera.follow(player);

    accelerometerEvents.listen((event) {
      rawTilt = event.y;
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    double normalizedTilt = (rawTilt / 10).clamp(-1.0, 1.0);
    smoothedTilt += (normalizedTilt - smoothedTilt) * 0.75;
    player.updateBike(dt, smoothedTilt, isGas, isBrake);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.x > size.x / 2) {
      isGas = true;
    } else {
      isBrake = true;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }
}

// ===================================================================
// TRACK INFO HELPER
// ===================================================================
class TrackInfo {
  final double y;
  final double angle;
  TrackInfo(this.y, this.angle);
}

// ===================================================================
// BIKE
// ===================================================================
class Bike extends PositionComponent {
  final List<Vector2> trackPoints;

  // Body velocity (world space)
  Vector2 velocity = Vector2.zero();

  // Body rotation
  double bodyAngle = 0.0;
  double angularVelocity = 0.0;

  // ── Suspension constants ─────────────────────────────────────────
  static const double wheelRadius    = 0.55;
  static const double suspRest       = 0.65;  // natural extension
  static const double suspMaxTravel  = 0.70;  // max extension beyond rest
  static const double suspMinTravel  = 0.10;  // max compression
  static const double suspSpringK    = 220.0;
  static const double suspDamperC    = 22.0;

  // Attachment offset from body center (local space, unrotated)
  static const double attachX        = 1.45;
  static const double attachY        = 0.30; // slightly below body center

  // Per-wheel suspension extension + extension velocity
  double rearExt   = suspRest;
  double frontExt  = suspRest;
  double rearExtV  = 0.0;
  double frontExtV = 0.0;

  bool   rearOnGround     = false;
  bool   frontOnGround    = false;
  double rearGroundAngle  = 0.0;
  double frontGroundAngle = 0.0;

  // ── Physics tuning ───────────────────────────────────────────────
  static const double gravity        = 38.0;
  static const double leanStrength   = 19.5;
  static const double groundLeanMult = 2.4;
  static const double airControl     = 0.78;
  static const double acceleration   = 130.0;
  static const double brakePower     = 160.0;
  static const double maxSpeed       = 150.0;
  static const double groundFriction = 0.94;  // base for pow(f, dt*60)
  static const double airDrag        = 0.999;
  static const double restitution    = 0.08;

  bool get onGround => rearOnGround || frontOnGround;
  double get groundAngle {
    if (rearOnGround && frontOnGround) {
      return (rearGroundAngle + frontGroundAngle) / 2;
    }
    return rearOnGround ? rearGroundAngle : frontGroundAngle;
  }

  Bike(Vector2 startPos, this.trackPoints) {
    position = startPos;
    size = Vector2(3.8, 1.8);
    anchor = Anchor.center;
  }

  // ── Main update ──────────────────────────────────────────────────
  void updateBike(double dt, double tilt, bool gas, bool brake) {

    // 1. Gravity on body
    velocity.y += gravity * dt;

    // 2. Suspension for each wheel — also applies reaction force to body
    _updateWheel(dt, isRear: true,  localAttachX: -attachX);
    _updateWheel(dt, isRear: false, localAttachX:  attachX);

    // 3. Lean / angular control
    double torque = tilt * leanStrength;
    if (onGround) {
      torque *= groundLeanMult;
      // Smoothly blend body angle toward ground slope
      bodyAngle += (groundAngle - bodyAngle) * (1.0 - pow(0.30, dt * 60));
      angularVelocity *= pow(0.40, dt * 60).toDouble();
    } else {
      torque *= airControl;
      angularVelocity *= pow(0.98, dt * 60).toDouble();
    }
    angularVelocity += torque * dt;
    bodyAngle += angularVelocity * dt;

    // 4. Throttle / Brake
    if (onGround) {
      final slopeX = cos(groundAngle);
      final slopeY = sin(groundAngle);

      if (gas) {
        velocity.x += acceleration * slopeX * dt;
        velocity.y += acceleration * slopeY * dt;
      }

      // Brakes oppose forward motion only — never reverse
      if (brake && velocity.x > 0.3) {
        final brakeForce = brakePower * dt;
        velocity.x = (velocity.x - brakeForce).clamp(0.0, maxSpeed);
      }

      // Frame-rate-independent friction
      velocity.x *= pow(groundFriction, dt * 60).toDouble();
      velocity.y *= pow(0.88,           dt * 60).toDouble();

      velocity.x = velocity.x.clamp(-maxSpeed, maxSpeed);
    } else {
      velocity.x *= pow(airDrag, dt * 60).toDouble();
    }

    // 5. Integrate body position
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
  }

  // ── Single-wheel suspension + collision ─────────────────────────
  // The suspension extension coordinate lives entirely in the body's
  // LOCAL space — it is the distance the wheel hangs below the
  // attachment point along the body's local Y axis.
  // Body forces are always applied in WORLD space.
  void _updateWheel(double dt, {required bool isRear, required double localAttachX}) {
    final cosA = cos(bodyAngle);
    final sinA = sin(bodyAngle);

    // Attachment point in world space
    final attachWorldX = position.x + localAttachX * cosA - attachY * sinA;
    final attachWorldY = position.y + localAttachX * sinA + attachY * cosA;

    double ext  = isRear ? rearExt  : frontExt;
    double extV = isRear ? rearExtV : frontExtV;

    // Spring force: positive = extending (pushing wheel down, body up)
    // Negative displacement from rest = compressed = pushes extension open
    final displacement = ext - suspRest;
    final springForce  = -suspSpringK * displacement;
    final damperForce  = -suspDamperC * extV;
    final totalForce   =  springForce + damperForce;

    // Integrate extension (massless wheel assumption: extension reacts instantly)
    // Gravity acts to extend the suspension (pulls wheel down)
    extV += (gravity + totalForce) * dt;
    ext  += extV * dt;

    // Apply equal-and-opposite reaction force to the body (upward in world Y)
    // This is what makes the body feel the bumps
    velocity.y -= totalForce * dt;

    // Wheel world Y position
    // Suspension extends along body local Y axis rotated to world space
    final suspDirX = -sinA; // local Y axis in world space
    final suspDirY =  cosA;
    final wheelWorldX = attachWorldX + suspDirX * ext;
    final wheelWorldY = attachWorldY + suspDirY * ext;

    // Ground collision
    final trackInfo = _getTrackInfoAtX(wheelWorldX);
    final groundY   = trackInfo.y - wheelRadius;

    bool touching = wheelWorldY >= groundY;

    if (touching) {
      // How far the wheel penetrated into the ground
      final penetration = wheelWorldY - groundY;
      // Convert penetration back to extension space (along susp axis)
      ext -= penetration;
      if (extV > 0) extV = -extV * restitution;
      // Also push body up by the penetration to prevent sinking
      velocity.y -= penetration * 80.0 * dt; // strong corrective impulse
    }

    // Clamp suspension travel
    final minE = suspRest - suspMinTravel;
    final maxE = suspRest + suspMaxTravel;
    if (ext < minE) { ext = minE; if (extV < 0) extV = 0; }
    if (ext > maxE) { ext = maxE; if (extV > 0) extV = 0; }

    if (isRear) {
      rearExt         = ext;
      rearExtV        = extV;
      rearOnGround    = touching;
      rearGroundAngle = trackInfo.angle;
    } else {
      frontExt         = ext;
      frontExtV        = extV;
      frontOnGround    = touching;
      frontGroundAngle = trackInfo.angle;
    }
  }

  // ── Track raycast ────────────────────────────────────────────────
  TrackInfo _getTrackInfoAtX(double x) {
    if (x <= trackPoints.first.x) return TrackInfo(trackPoints.first.y, 0);
    if (x >= trackPoints.last.x)  return TrackInfo(trackPoints.last.y,  0);

    for (int i = 0; i < trackPoints.length - 1; i++) {
      final p1 = trackPoints[i];
      final p2 = trackPoints[i + 1];
      if (x >= p1.x && x < p2.x) {
        final t = (x - p1.x) / (p2.x - p1.x);
        return TrackInfo(
          p1.y + t * (p2.y - p1.y),
          atan2(p2.y - p1.y, p2.x - p1.x),
        );
      }
    }
    return TrackInfo(0, 0);
  }

  // ── Render ───────────────────────────────────────────────────────
  // PositionComponent already translates canvas to `position`.
  // We rotate once for the body, then draw EVERYTHING in that same
  // rotated local space so wheels and chassis are always coherent.
  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.rotate(bodyAngle);

    // Wheel centers in local space (attachment + extension along local Y)
    final rearWheelOffset  = Offset(-attachX, attachY + rearExt);
    final frontWheelOffset = Offset( attachX, attachY + frontExt);

    // Suspension struts
    final strutPaint = Paint()
      ..color = const Color(0xFF999999)
      ..strokeWidth = 0.14
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(-attachX, attachY), rearWheelOffset,  strutPaint);
    canvas.drawLine(Offset( attachX, attachY), frontWheelOffset, strutPaint);

    // Chassis
    final chassisPaint = Paint()..color = const Color(0xFF0000FF);
    canvas.drawRect(const Rect.fromLTWH(-1.9, -0.45, 3.8, 0.9), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFFFFAA00);
    canvas.drawRect(const Rect.fromLTWH(-0.6, -1.2, 1.2, 1.0), riderPaint);

    // Wheels
    final wheelFill = Paint()..color = Colors.white;
    final wheelRim  = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;

    canvas.drawCircle(rearWheelOffset,  wheelRadius, wheelFill);
    canvas.drawCircle(frontWheelOffset, wheelRadius, wheelFill);
    canvas.drawCircle(rearWheelOffset,  wheelRadius, wheelRim);
    canvas.drawCircle(frontWheelOffset, wheelRadius, wheelRim);

    canvas.restore();
  }
}

// ===================================================================
// TRACK
// ===================================================================
class Track extends Component {
  final List<Vector2> points = [
    Vector2(-80,  5),
    Vector2( 20,  5),
    Vector2( 35, -1),
    Vector2( 52,  5),
    Vector2( 70, -4),
    Vector2( 88, -4),
    Vector2(105,  5),
    Vector2(300,  5),
  ];

  @override
  void render(Canvas canvas) {
    // Filled ground below the line for visual depth
    final groundPaint = Paint()
      ..color = const Color(0xFF004422)
      ..style = PaintingStyle.fill;

    final groundPath = Path();
    groundPath.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      groundPath.lineTo(points[i].x, points[i].y);
    }
    groundPath.lineTo(points.last.x,  points.last.y  + 50);
    groundPath.lineTo(points.first.x, points.first.y + 50);
    groundPath.close();
    canvas.drawPath(groundPath, groundPaint);

    // Track surface line
    final trackPaint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final trackPath = Path();
    trackPath.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      trackPath.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(trackPath, trackPaint);
  }
}
