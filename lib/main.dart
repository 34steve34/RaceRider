/* ============================================================================
 * RACERIDER - Custom Arcade Physics (Bike Race style)
 * Engine: Flutter + Flame (No Forge2D)
 *
 * FIXES APPLIED:
 *  1. Render double-transform bug fixed — removed manual canvas.translate
 *     from Bike.render() since PositionComponent already applies it.
 *  2. Frame-rate independent friction using pow(friction, dt * 60).
 *  3. Two-wheel spring-damper suspension model added.
 *  4. Wheel physics separated from body: each wheel has its own Y position
 *     and velocity, with a spring connecting it to the chassis.
 *  5. Throttle/brake force now acts along the ground slope, not bike angle.
 *  6. Restitution bounce coefficient on landing (instead of hard velocity=0).
 *  7. Angular damping tuned for snappier feel on ground.
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

  RaceRiderGame();

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
// HELPER CLASS FOR TRACK COLLISIONS
// ===================================================================
class TrackInfo {
  final double y;
  final double angle;
  TrackInfo(this.y, this.angle);
}

// ===================================================================
// WHEEL — holds its own vertical suspension state
// ===================================================================
class Wheel {
  // Position of the wheel center in world space
  double worldX = 0;
  double worldY = 0;

  // The vertical velocity of the wheel mass (used for damping)
  double velY = 0;

  // Whether this wheel is touching the track
  bool onGround = false;
  double groundAngle = 0;

  // ---- Suspension tuning ----
  static const double restLength = 0.55;   // natural spring extension (world units)
  static const double springK    = 180.0;  // spring stiffness
  static const double damperC    = 18.0;   // damping coefficient
  static const double wheelRadius = 0.55;

  // Attachment offset from bike body center (local space, unrotated)
  final Vector2 localAttach;

  Wheel(this.localAttach);

  // Compute world-space attachment point given body position + angle
  Vector2 worldAttach(Vector2 bodyPos, double bodyAngle) {
    final rotated = Vector2(localAttach.x, localAttach.y)..rotate(bodyAngle);
    return bodyPos + rotated;
  }
}

// ===================================================================
// CUSTOM BIKE PHYSICS
// ===================================================================
class Bike extends PositionComponent {
  final List<Vector2> trackPoints;

  // Body (chassis) velocity
  Vector2 velocity = Vector2.zero();
  double bodyAngle = 0.0;
  double angularVelocity = 0.0;

  // ==================== TUNING ====================
  static const double gravity          = 38.0;
  static const double airDamping       = 0.995; // per-frame multiplier in air (use pow for dt)
  static const double groundFrictionX  = 0.78;  // base ground friction (frame-rate independent base)
  static const double leanStrength     = 19.5;
  static const double groundLeanMult   = 2.4;
  static const double airControl       = 0.78;
  static const double acceleration     = 52.0;  // increased for snappier feel
  static const double brakePower       = 60.0;
  static const double maxSpeed         = 52.0;
  static const double restitution      = 0.12;  // bounce on landing (0 = dead stop, 1 = full bounce)
  static const double bodyMass         = 1.0;

  // Suspension wheels — rear and front
  // localAttach = offset from body center in local (unrotated) space
  // Y of 0.0 = body center; wheels hang downward (+Y in Flame = down)
  final Wheel rearWheel  = Wheel(Vector2(-1.45, 0.30));
  final Wheel frontWheel = Wheel(Vector2( 1.45, 0.30));

  // Combined ground-contact flag for driving logic
  bool get onGround => rearWheel.onGround || frontWheel.onGround;
  double get groundAngle {
    if (rearWheel.onGround && frontWheel.onGround) {
      return (rearWheel.groundAngle + frontWheel.groundAngle) / 2;
    } else if (rearWheel.onGround) {
      return rearWheel.groundAngle;
    } else {
      return frontWheel.groundAngle;
    }
  }

  Bike(Vector2 startPos, this.trackPoints) {
    position = startPos;
    size = Vector2(3.8, 1.8);
    anchor = Anchor.center;
    bodyAngle = 0;

    // Initialize wheel world positions
    _initWheels();
  }

  void _initWheels() {
    for (final w in [rearWheel, frontWheel]) {
      final attach = w.worldAttach(position, bodyAngle);
      w.worldX = attach.x;
      w.worldY = attach.y + Wheel.restLength;
      w.velY = 0;
    }
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    // ----------------------------------------------------------------
    // 1. GRAVITY on body
    // ----------------------------------------------------------------
    velocity.y += gravity * dt;

    // ----------------------------------------------------------------
    // 2. SUSPENSION — spring-damper for each wheel
    // ----------------------------------------------------------------
    double totalSuspForceY = 0;
    double totalSuspTorque = 0;

    for (final w in [rearWheel, frontWheel]) {
      // Update wheel X to follow the attachment point (wheels can't slide sideways)
      final attach = w.worldAttach(position, bodyAngle);
      w.worldX = attach.x;

      // Track height under this wheel
      final trackInfo = _getTrackInfoAtX(w.worldX);
      final groundY = trackInfo.y - Wheel.wheelRadius;

      // Extension = how far the wheel is below the attachment point
      double extension = w.worldY - attach.y;
      double extensionVel = w.velY - velocity.y; // relative velocity

      // Spring + damper force (pushes wheel down to rest, pushes body up)
      double springForce = Wheel.springK * (extension - Wheel.restLength);
      double damperForce = Wheel.damperC * extensionVel;
      double suspForce   = springForce + damperForce;

      // Apply to wheel
      w.velY += (gravity - suspForce / bodyMass) * dt;

      // --- Ground collision for the wheel ---
      w.worldY += w.velY * dt;

      if (w.worldY >= groundY) {
        w.worldY = groundY;
        if (w.velY > 0) {
          // Bounce with restitution, damped heavily for arcade feel
          w.velY = -w.velY * restitution;
        }
        w.onGround   = true;
        w.groundAngle = trackInfo.angle;
      } else {
        w.onGround = false;
        w.groundAngle = 0;
      }

      // Clamp wheel travel (max compression / extension)
      final minExt = 0.10;
      final maxExt = Wheel.restLength + 0.80;
      final curExt = w.worldY - attach.y;
      if (curExt < minExt) {
        w.worldY = attach.y + minExt;
        if (w.velY < 0) w.velY = 0;
      }
      if (curExt > maxExt) {
        w.worldY = attach.y + maxExt;
        if (w.velY > 0) w.velY = 0;
      }

      // Force the wheel exerts on the body (reaction force, upward)
      final curExtension = w.worldY - attach.y;
      double reactionForce = Wheel.springK * (curExtension - Wheel.restLength)
                           + Wheel.damperC * (w.velY - velocity.y);

      totalSuspForceY += reactionForce;

      // Torque on body from this wheel's suspension (offset from center)
      // Using local X offset * force magnitude for a plausible torque
      final localX = w.localAttach.x;
      totalSuspTorque += localX * reactionForce * 0.012;
    }

    // Apply suspension forces to body
    velocity.y += (totalSuspForceY / bodyMass) * dt;
    angularVelocity += totalSuspTorque * dt;

    // ----------------------------------------------------------------
    // 3. LEAN CONTROL (tilt input)
    // ----------------------------------------------------------------
    double torque = tilt * leanStrength;

    if (onGround) {
      torque *= groundLeanMult;
      // Blend body angle toward ground slope for visual grounding
      bodyAngle = bodyAngle * 0.70 + groundAngle * 0.30;
      angularVelocity *= pow(0.55, dt * 60).toDouble();
    } else {
      torque *= airControl;
      angularVelocity *= pow(airDamping, dt * 60).toDouble();
    }

    angularVelocity += torque * dt;
    bodyAngle += angularVelocity * dt;

    // ----------------------------------------------------------------
    // 4. THROTTLE / BRAKE — only on ground, along the slope
    // ----------------------------------------------------------------
    if (onGround) {
      double driveForce = 0.0;
      if (gas)   driveForce =  acceleration;
      if (brake) driveForce = -brakePower;

      // Drive force acts along the track slope, not bike angle,
      // so you don't launch upward when tilted
      final slopeX = cos(groundAngle);
      final slopeY = sin(groundAngle);

      velocity.x += driveForce * slopeX * dt;
      velocity.y += driveForce * slopeY * dt;

      // Frame-rate independent friction
      final frictionFactor = pow(groundFrictionX, dt * 60).toDouble();
      velocity.x *= frictionFactor;
      // Vertical is kept more free so suspension can do its job
      velocity.y *= pow(0.92, dt * 60).toDouble();

      velocity.x = velocity.x.clamp(-maxSpeed, maxSpeed);
    } else {
      // Very light air resistance
      velocity.x *= pow(0.998, dt * 60).toDouble();
    }

    // ----------------------------------------------------------------
    // 5. INTEGRATE BODY POSITION
    // ----------------------------------------------------------------
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
  }

  // Raycasts straight down to find track Y and slope under a given X
  TrackInfo _getTrackInfoAtX(double x) {
    if (x <= trackPoints.first.x) return TrackInfo(trackPoints.first.y, 0);
    if (x >= trackPoints.last.x)  return TrackInfo(trackPoints.last.y, 0);

    for (int i = 0; i < trackPoints.length - 1; i++) {
      final p1 = trackPoints[i];
      final p2 = trackPoints[i + 1];
      if (x >= p1.x && x < p2.x) {
        double t = (x - p1.x) / (p2.x - p1.x);
        double trackY    = p1.y + t * (p2.y - p1.y);
        double slopeAngle = atan2(p2.y - p1.y, p2.x - p1.x);
        return TrackInfo(trackY, slopeAngle);
      }
    }
    return TrackInfo(0, 0);
  }

  // ----------------------------------------------------------------
  // RENDER
  // FIX: PositionComponent.renderTree() already translates the canvas
  // to `position` before calling render(). Do NOT translate again.
  // We only need to rotate around the body center (which is now at 0,0).
  // ----------------------------------------------------------------
  @override
  void render(Canvas canvas) {
    // --- Draw suspension struts (from body attach to wheel center) ---
    final strutPaint = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 0.12
      ..style = PaintingStyle.stroke;

    for (final w in [rearWheel, frontWheel]) {
      // Attach in LOCAL space (unrotated offset, since canvas is not yet rotated here)
      final attachLocal = w.localAttach;
      // Wheel center in world space, converted to local body space
      final wheelWorldPos = Vector2(w.worldX, w.worldY);
      final bodyWorldPos  = position;
      final wheelLocal    = worldToLocal(wheelWorldPos, bodyWorldPos, bodyAngle);

      canvas.drawLine(
        Offset(attachLocal.x, attachLocal.y),
        Offset(wheelLocal.x,  wheelLocal.y),
        strutPaint,
      );
    }

    // --- Rotate canvas for body drawing ---
    canvas.save();
    canvas.rotate(bodyAngle);

    // Chassis
    final chassisPaint = Paint()..color = const Color(0xFF0000FF);
    canvas.drawRect(const Rect.fromLTWH(-1.9, -0.45, 3.8, 0.9), chassisPaint);

    // Rider
    final riderPaint = Paint()..color = const Color(0xFFFFAA00);
    canvas.drawRect(const Rect.fromLTWH(-0.6, -1.2, 1.2, 1.0), riderPaint);

    canvas.restore();

    // --- Draw wheels at their actual (suspension-displaced) world positions ---
    // These are drawn in LOCAL BODY SPACE (no rotation applied) so they float
    // correctly at their physical location regardless of body tilt.
    final wheelPaint = Paint()..color = Colors.white;
    final wheelOutline = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;

    for (final w in [rearWheel, frontWheel]) {
      final wheelWorldPos = Vector2(w.worldX, w.worldY);
      final local = worldToLocal(wheelWorldPos, position, bodyAngle);
      canvas.drawCircle(Offset(local.x, local.y), Wheel.wheelRadius, wheelPaint);
      canvas.drawCircle(Offset(local.x, local.y), Wheel.wheelRadius, wheelOutline);
    }
  }

  // Convert a world-space point into local body space
  // (inverse of: world = bodyPos + rotate(local, bodyAngle))
  Vector2 worldToLocal(Vector2 world, Vector2 bodyPos, double angle) {
    final dx = world.x - bodyPos.x;
    final dy = world.y - bodyPos.y;
    final cosA = cos(-angle);
    final sinA = sin(-angle);
    return Vector2(dx * cosA - dy * sinA, dx * sinA + dy * cosA);
  }
}

// ===================================================================
// TRACK
// ===================================================================
class Track extends Component {
  final List<Vector2> points = [
    Vector2(-80, 5),
    Vector2(20,  5),
    Vector2(35, -1),
    Vector2(52,  5),
    Vector2(70, -4),
    Vector2(88, -4),
    Vector2(105, 5),
    Vector2(300, 5),
  ];

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF99)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(path, paint);

    // Draw a filled ground below the track line so there's visual depth
    final groundPaint = Paint()
      ..color = const Color(0xFF004422)
      ..style = PaintingStyle.fill;

    final groundPath = Path();
    groundPath.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      groundPath.lineTo(points[i].x, points[i].y);
    }
    groundPath.lineTo(points.last.x,  points.last.y  + 30);
    groundPath.lineTo(points.first.x, points.first.y + 30);
    groundPath.close();
    canvas.drawPath(groundPath, groundPaint);
  }
}
