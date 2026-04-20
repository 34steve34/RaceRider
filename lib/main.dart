/* ============================================================================
 * RACERIDER v43
 * Key changes from v42:
 *  - Torque tilt model (not target-angle seeking) → wheelie holds at neutral phone
 *  - Anti-stoppie ONLY when front wheel grounded → front-flick works freely in air
 *  - Single velocity impulse after all position passes → kills vibration
 *  - normalDamping was 2.1 (bouncy catapult) → fixed to restitution 0.10
 *  - tangentFriction applied 8×/frame → now applied once
 *  - Physics wheel positions now match canvas drawCircle exactly
 *  - Dropped Forge2DGame (no Box2D bodies were used) → plain FlameGame
 *  - Spawn inside flat section, not past it
 * ============================================================================ */

import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() => runApp(GameWidget(game: RaceRiderGame()));

// ══════════════════════════════════════════════════════════════════════════════
//  GAME
// ══════════════════════════════════════════════════════════════════════════════
class RaceRiderGame extends FlameGame with TapCallbacks {
  late Bike player;
  late List<TrackSegment> trackSegments;
  double rawTilt = 0.0;
  double smoothedTilt = 0.0;
  bool isGas = false, isBrake = false;
  late StreamSubscription _accelSub;

  @override
  Future<void> onLoad() async {
    trackSegments = _buildTrack();
    player = Bike(Vector2(-540, 20.0));   // inside the flat opening section
    add(Background());
    add(DebugOverlay());
    camera.viewfinder
      ..zoom = 2.1
      ..anchor = Anchor.center;
    _accelSub = accelerometerEvents.listen((e) => rawTilt = e.y);
  }

  @override
  void onRemove() { _accelSub.cancel(); super.onRemove(); }

  List<TrackSegment> _buildTrack() {
    final segs = <TrackSegment>[];
    double x = -700, y = 38.0;
    final rng = Random();
    segs.add(TrackSegment(x, y, x + 450, y));   // long flat opener
    x += 450;
    for (int i = 0; i < 120; i++) {
      final dx = 60 + rng.nextDouble() * 70;
      final dy = -12 + rng.nextDouble() * 24;
      segs.add(TrackSegment(x, y, x + dx, y + dy));
      x += dx; y += dy;
    }
    return segs;
  }

  @override
  void update(double dt) {
    super.update(dt);
    camera.viewfinder.position = player.position;
    final n = (rawTilt / 9.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.65 + n * 0.35;   // 0.65 = smoother than v42's 0.42
    player.updateBike(dt, smoothedTilt, isGas, isBrake, trackSegments);
  }

  @override
  void onTapDown(TapDownEvent e) {
    isBrake = e.localPosition.x < size.x / 2;
    isGas = !isBrake;
  }
  @override
  void onTapUp(TapUpEvent e) { isGas = isBrake = false; }

  @override
  void render(Canvas canvas) {
    super.render(canvas);   // draws Background + DebugOverlay components
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(camera.viewfinder.zoom);
    canvas.translate(-player.position.x, -player.position.y);

    // Track
    final tp = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in trackSegments) {
      canvas.drawLine(Offset(s.x1, s.y1), Offset(s.x2, s.y2), tp);
    }

    // Bike
    canvas.save();
    canvas.translate(player.position.x, player.position.y);
    canvas.rotate(player.angle);
    _drawBike(canvas);
    canvas.restore();
    canvas.restore();
  }

  void _drawBike(Canvas canvas) {
    final wFill = Paint()..color = Colors.white;
    final wRim  = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final body  = Paint()..color = const Color(0xFFFF4400);
    final frame = Paint()..color = const Color(0xFF333333)..strokeWidth = 3.5..style = PaintingStyle.stroke;
    final fork  = Paint()..color = const Color(0xFF888888)..strokeWidth = 4.0..style = PaintingStyle.stroke;
    final seat  = Paint()..color = const Color(0xFF111111);
    final rider = Paint()..color = const Color(0xFF2255BB);

    // Wheels — centres at (-6.8, 4.8) and (7.8, 4.8), radius 2.35
    // These MUST match Bike._rearLocal and Bike._frontLocal exactly
    canvas.drawCircle(const Offset(-6.8, 4.8), 2.35, wFill);
    canvas.drawCircle(const Offset( 7.8, 4.8), 2.35, wFill);
    canvas.drawCircle(const Offset(-6.8, 4.8), 1.6,  wRim);
    canvas.drawCircle(const Offset( 7.8, 4.8), 1.6,  wRim);

    // Frame struts connecting to wheel centres
    canvas.drawLine(const Offset(-6.8, 4.8), const Offset(-2.0, -3.0), frame);  // rear strut
    canvas.drawLine(const Offset(-2.0, -3.0), const Offset( 7.8, 4.8), frame);  // main spar
    canvas.drawLine(const Offset( 7.8, -1.5), const Offset( 7.8,  4.8), fork);  // front fork
    canvas.drawLine(const Offset( 7.0, -3.8), const Offset(12.0, -4.8), fork);  // handlebars

    // Body / tank
    canvas.drawRect(const Rect.fromLTWH(-9.0, -3.5, 18.0, 4.0), body);
    canvas.drawRect(const Rect.fromLTWH(-7.5, -5.5,  8.0, 2.2), seat);

    // Rider (torso + head — simple shapes, but clearly a person)
    canvas.drawOval(const Rect.fromLTWH(-6.0, -9.8, 5.5, 4.5), rider);  // torso
    canvas.drawCircle(const Offset(-3.2, -11.2), 2.1, rider);            // helmet
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRACK
// ══════════════════════════════════════════════════════════════════════════════
class TrackSegment {
  final double x1, y1, x2, y2;
  const TrackSegment(this.x1, this.y1, this.x2, this.y2);
}

class _Contact {
  final double pen;      // positive = penetrating, negative = above track
  final Vector2 normal;  // points away from track surface (toward wheel)
  const _Contact(this.pen, this.normal);
}

_Contact _wheelContact(Vector2 wPos, List<TrackSegment> segs, double r) {
  double minDist = double.infinity;
  var bestNormal = Vector2(0.0, -1.0);

  for (final s in segs) {
    final a = Vector2(s.x1, s.y1), b = Vector2(s.x2, s.y2);
    final ab = b - a;
    final t = ((wPos - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
    final dist = (wPos - (a + ab * t)).length;
    if (dist < minDist) {
      minDist = dist;
      final sd = ab.normalized();
      bestNormal = Vector2(-sd.y, sd.x);           // 90° CCW from segment
      if (bestNormal.y > 0) bestNormal = -bestNormal; // ensure pointing up (neg y in y-down coords)
    }
  }
  return _Contact(r - minDist, bestNormal);
}

// ══════════════════════════════════════════════════════════════════════════════
//  BIKE  — plain class, no PositionComponent overhead
// ══════════════════════════════════════════════════════════════════════════════
class Bike {
  Vector2 position;
  Vector2 velocity  = Vector2.zero();
  double  angle     = 0.0;
  double  angularVelocity = 0.0;
  bool    rearOnGround  = false;
  bool    frontOnGround = false;
  bool get onGround => rearOnGround || frontOnGround;

  // ── Tuning knobs ── (all grouped, all named, go nuts) ──────────────────────
  static const _gravity   = 42.0;
  static const _accel     = 560.0;    // gas force
  static const _brake     = 130.0;    // brake force

  static const _wr        = 2.35;     // wheel radius — MUST match drawCircle radius

  // Tilt: torque model, NOT target-angle model
  // Equilibrium spin rate in air  = _tiltTorque / _airDamp  (rad/s at full tilt)
  // Equilibrium spin rate on gnd  = _tiltTorque / _gndDamp
  static const _tiltTorque = 3.6;     // angular impulse per tilt unit per second
  static const _airDamp    = 1.2;     // angular damping in air  (lower = spins more freely)
  static const _gndDamp    = 4.6;     // angular damping on ground (higher = snappier settle)

  // Anti-stoppie: ONLY fires when front wheel is grounded.
  // Zero when front is in air → front-flick is completely free.
  static const _antiStoppie  = 90.0;  // restoring torque coefficient for nose-down

  // Anti-extreme-wheelie: kicks in past ~85° nose-up. Always active.
  static const _antiWheelie = 18.0;

  // Gas nose-up torque: rear-wheel-drive feel
  static const _gasTorque  = 1.7;

  // Landing: velocity resolved ONCE after all position passes
  static const _restitution = 0.10;   // 0=perfectly sticky  0.3=noticeable bounce
  static const _friction    = 0.06;   // tangential friction (applied once per contact frame)

  // Magnet: gentle pull toward track when close but not penetrating
  static const _magnetDist =  3.2;
  static const _magnetStr  = 140.0;

  // Wheel local positions — keep these identical to drawCircle Offsets above
  static const _rearLx = -6.8,  _rearLy = 4.8;
  static const _frtLx  =  7.8,  _frtLy  = 4.8;
  // ───────────────────────────────────────────────────────────────────────────

  Bike(Vector2 startPos) : position = startPos.clone();

  // Public entry point — splits dt into substeps to prevent tunneling.
  // At 60fps and substeps=5: max movement per step ≈ 0.003s × speed.
  // At speed 200 that's 0.6 units/step vs wheelRadius 2.35 → cannot tunnel.
  void updateBike(double dt, double tilt, bool gas, bool brake, List<TrackSegment> segs) {
    const substeps = 5;
    final sdt = dt / substeps;
    for (int i = 0; i < substeps; i++) {
      _step(sdt, tilt, gas, brake, segs);
    }
  }

  void _step(double dt, double tilt, bool gas, bool brake, List<TrackSegment> segs) {

    // ── 1. Gravity ──────────────────────────────────────────────────────────
    velocity.y += _gravity * dt;

    // ── 2. Tilt torque — always, no ground/air restriction ──────────────────
    angularVelocity += tilt * _tiltTorque * dt;

    // ── 3. Anti-stoppie — ONLY when front wheel is grounded ─────────────────
    //    When front is in air this block is skipped → front-flick is free
    if (frontOnGround && angle > 0.03) {
      angularVelocity -= angle * _antiStoppie * dt;
    }

    // ── 4. Anti-extreme-wheelie (past ~85° nose-up) — always ────────────────
    if (angle < -1.48) {
      angularVelocity -= angle * _antiWheelie * dt;
    }

    // ── 5. Rear-wheel-drive nose-up torque ──────────────────────────────────
    if (gas && onGround) {
      angularVelocity -= _gasTorque * dt;
    }

    // ── 6. Angular damping ───────────────────────────────────────────────────
    final damp = onGround ? _gndDamp : _airDamp;
    angularVelocity *= (1.0 - damp * dt).clamp(0.0, 1.0);

    // ── 7. Integrate angle ───────────────────────────────────────────────────
    angle += angularVelocity * dt;
    angle = angle.clamp(-pi * 0.72, pi * 0.55);

    // ── 8. Predict position ─────────────────────────────────────────────────
    var pos = position + velocity * dt;

    // ── 9. Position-only correction passes ──────────────────────────────────
    //    Velocity untouched here — no multi-pass vibration.
    //    Full correction (1.0) per pass — no residual penetration drift.
    rearOnGround  = false;
    frontOnGround = false;
    var rearN = Vector2(0.0, -1.0);
    var frtN  = Vector2(0.0, -1.0);

    for (int pass = 0; pass < 3; pass++) {
      final rw = pos + _rot(Vector2(_rearLx, _rearLy));
      final rc = _wheelContact(rw, segs, _wr);
      if (rc.pen > 0.005) {
        pos = pos - rc.normal * rc.pen;          // full correction, no multiplier
        rearOnGround = true;
        rearN = rc.normal;
      } else if (rc.pen > -_magnetDist) {
        velocity = velocity - rc.normal * ((_magnetDist + rc.pen) * _magnetStr * dt);
      }

      final fw = pos + _rot(Vector2(_frtLx, _frtLy));
      final fc = _wheelContact(fw, segs, _wr);
      if (fc.pen > 0.005) {
        pos = pos - fc.normal * fc.pen;          // full correction
        frontOnGround = true;
        frtN = fc.normal;
      } else if (fc.pen > -_magnetDist) {
        velocity = velocity - fc.normal * ((_magnetDist + fc.pen) * _magnetStr * dt);
      }
    }

    position = pos;

    // ── 10. Single velocity impulse — after ALL position corrections ─────────
    if (rearOnGround || frontOnGround) {
      final avgN = (rearOnGround && frontOnGround)
          ? (rearN + frtN).normalized()
          : (rearOnGround ? rearN : frtN);

      final velN = velocity.dot(avgN);
      if (velN < 0) {
        velocity = velocity - avgN * (velN * (1.0 + _restitution));
      }

      final tan = Vector2(-avgN.y, avgN.x);
      velocity = velocity - tan * (velocity.dot(tan) * _friction);
    }

    // ── 11. Drive — along surface tangent ───────────────────────────────────
    if (onGround) {
      final surfN   = rearOnGround ? rearN : frtN;
      var   surfDir = Vector2(-surfN.y, surfN.x);
      if (surfDir.x < 0) surfDir = -surfDir;
      final drive = gas ? _accel : (brake ? -_brake : 0.0);
      velocity = velocity + surfDir * (drive * dt);
      velocity.x *= pow(0.974, 1 / 5.0).toDouble();  // scale rolling resistance per substep
    } else {
      velocity.x *= pow(0.993, 1 / 5.0).toDouble();  // scale air drag per substep
    }
  }

  // Rotate a local-space vector by bike angle
  Vector2 _rot(Vector2 v) {
    final c = cos(angle), s = sin(angle);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SUPPORT COMPONENTS
// ══════════════════════════════════════════════════════════════════════════════
class Background extends Component {
  @override
  void render(Canvas canvas) => canvas.drawRect(
      const Rect.fromLTWH(-5000, -5000, 16000, 16000),
      Paint()..color = const Color(0xFF112233));
}

class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final b = gameRef.player;
    TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: 'v43'
            '\nTilt:   ${gameRef.smoothedTilt.toStringAsFixed(2)}'
            '\nAngle:  ${b.angle.toStringAsFixed(2)} rad'
            '\nAngVel: ${b.angularVelocity.toStringAsFixed(2)}'
            '\nGnd  R:${b.rearOnGround}  F:${b.frontOnGround}',
        style: const TextStyle(
            color: Colors.yellow, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    )..layout()..paint(canvas, const Offset(16, 16));
  }
}
