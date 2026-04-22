/* ============================================================================
 * RACERIDER v46
 * Key changes from v45:
 *  - gravity: 65 → 95  — bike still felt floaty; now properly planted
 *  - _accel: 1900 → 2600, _brake: 400 → 600 (scaled with heavier gravity)
 *  - _gravityTorque: 10 → 14 (scaled)
 *  - Tilt block broadened: was (bothWheels && tilt>0), now (frontOnGround && tilt>0)
 *    → nose-down tilt is blocked whenever front wheel is planted, even if rear is
 *      briefly airborne over a bump. Closes the gap that allowed forward lean.
 *  - Tilt dead zone added (|tilt| < 0.06 → 0): eliminates self-propulsion from
 *    phone resting at a slight angle. Small drift noise no longer rotates the bike.
 *  - Stoppie now IMMEDIATELY zeros forward angular velocity every substep.
 *    Old k=150 spring let angVel build for several frames first → visible rear lift.
 *    New: kill on entry + k=500 spring + hard cap at surfAngle+0.03 (≈1.7°).
 *    The rear wheel cannot visibly lift at all now — matches BR feel exactly.
 *  - Both-wheels nose-down spring: k=80 → k=120 (stiffer)
 *  - Debug overlay now shows velocity for diagnosing self-propulsion reports.
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
    smoothedTilt = smoothedTilt * 0.35 + n * 0.65;
    // Dead zone: phone resting at a slight angle should not rotate the bike.
    // Without this, sub-threshold accelerometer noise keeps angularVelocity
    // from ever settling to zero, which slowly shifts wheel contact geometry.
    if (smoothedTilt.abs() < 0.06) smoothedTilt = 0.0;
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

    // Track — thin line, not a road
    final tp = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in trackSegments) {
      canvas.drawLine(Offset(s.x1, s.y1), Offset(s.x2, s.y2), tp);
    }

    // 1-second markers — vertical posts every 300 world units.
    // At target cruising speed ~300 u/s these are ~1s apart.
    // Adjust spacing once you know your actual top speed.
    final mPaint = Paint()..color = const Color(0xFFFFFF44)..strokeWidth = 1.5;
    final mTextStyle = const TextStyle(color: Color(0xFFFFFF44), fontSize: 9);
    for (int mx = -700; mx < 8000; mx += 300) {
      canvas.drawLine(Offset(mx.toDouble(), 15), Offset(mx.toDouble(), 45), mPaint);
      TextPainter(
        text: TextSpan(text: '${((mx + 700) ~/ 300)}s', style: mTextStyle),
        textDirection: TextDirection.ltr,
      )..layout()..paint(canvas, Offset(mx.toDouble() + 2, 8));
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
    final wRim  = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 3.0;
    final body  = Paint()..color = const Color(0xFFFF4400);
    final frame = Paint()..color = const Color(0xFF333333)..strokeWidth = 3.0..style = PaintingStyle.stroke;
    final fork  = Paint()..color = const Color(0xFF888888)..strokeWidth = 3.5..style = PaintingStyle.stroke;
    final seat  = Paint()..color = const Color(0xFF111111);
    final rider = Paint()..color = const Color(0xFF2255BB);

    // Wheels — independent suspension per wheel
    final rs = player.rSuspOffset;  // rear compression
    final fs = player.fSuspOffset;  // front compression
    canvas.drawCircle(Offset(-7.0, 6.5 - rs), 4.7, wFill);
    canvas.drawCircle(Offset( 8.5, 6.5 - fs), 4.7, wFill);
    canvas.drawCircle(Offset(-7.0, 6.5 - rs), 3.1, wRim);
    canvas.drawCircle(Offset( 8.5, 6.5 - fs), 3.1, wRim);

    // Frame struts — each end follows its wheel's suspension
    canvas.drawLine(Offset(-7.0, 6.5 - rs), const Offset(-1.5, -2.5), frame);
    canvas.drawLine(const Offset(-1.5, -2.5), Offset(8.5, 6.5 - fs), frame);
    canvas.drawLine(Offset(8.5, 6.5 - fs), const Offset(8.5, -2.0), fork);
    canvas.drawLine(const Offset(7.5, -4.0), const Offset(13.0, -5.2), fork);

    // Body / tank
    canvas.drawRect(const Rect.fromLTWH(-9.5, -4.0, 19.5, 4.5), body);
    canvas.drawRect(const Rect.fromLTWH(-8.0, -6.2,  9.0, 2.4), seat);

    // Rider
    canvas.drawOval(const Rect.fromLTWH(-6.5, -11.0, 6.0, 5.0), rider);  // torso
    canvas.drawCircle(const Offset(-3.5, -12.5), 2.4, rider);             // helmet
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
  double  _coyoteTimer = 0.0;
  bool get canDrive => onGround || _coyoteTimer > 0.0;
  double  _surfAngle  = 0.0;
  double  rSuspOffset = 0.0, _rSuspVel = 0.0;  // rear suspension — visual only
  double  fSuspOffset = 0.0, _fSuspVel = 0.0;  // front suspension — visual only

  // ── Tuning knobs ── (all grouped, all named, go nuts) ──────────────────────
  static const _gravity   = 95.0;    // was 65 — still floaty; 95 gives BR's planted feel
  static const _accel     = 2600.0;  // was 1900 — scaled with heavier gravity
  static const _brake     = 600.0;   // was 400

  static const _wr        = 4.7;     // wheel radius — MUST match drawCircle radius

  static const _tiltTorque = 20.0;
  static const _airDamp    = 0.7;    // low = spins freely for tricks
  static const _gndDamp    = 4.0;

  static const _antiWheelie  = 40.0;  // safety net only — scaled up with gravity

  // cos(angle) gravity model for wheelie state. Scaled with gravity.
  static const _gravityTorque = 14.0;  // was 10

  static const _restitution = 0.0;
  // _friction removed: was 0.008 but (1-0.008)^(5*60) ≈ 0.09 → 90% speed loss/sec
  // "Rolls forever on flat" means tangential friction at contact must be ZERO.
  // Only force that slows the bike is gravity on uphills. Gas/brake do the rest.

  static const _coyoteTime = 0.08;

  // Wheel centres — MUST match drawCircle Offsets in _drawBike exactly
  static const _rearLx = -7.0,  _rearLy = 6.5;
  static const _frtLx  =  8.5,  _frtLy  = 6.5;
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

    // ── 2. Tilt torque ───────────────────────────────────────────────────────
    // Block nose-down (tilt > 0) whenever the front wheel is planted.
    // This covers BOTH the both-wheels-down case AND the stoppie case.
    // Previously only blocked when both wheels down — a brief front-only contact
    // (e.g. landing nose-first off a bump) still let tilt accumulate forward angVel.
    // In air (frontOnGround=false): full tilt applies for tricks.
    final effectiveTilt = (frontOnGround && tilt > 0) ? 0.0 : tilt;
    angularVelocity += effectiveTilt * _tiltTorque * dt;

    // ── 3. Gravity torque — state-aware ─────────────────────────────────────
    if (rearOnGround && frontOnGround) {
      // Both wheels planted: asymmetric spring around slope angle.
      // Nose-down (err > 0): very stiff — bike cannot visibly tip forward.
      // Nose-up (err < 0): gentle — tilt can initiate wheelie easily.
      final err = angle - _surfAngle;
      final k = err > 0 ? 120.0 : 5.0;   // was 80/5
      angularVelocity -= err * k * dt;

    } else if (rearOnGround && !frontOnGround) {
      // Wheelie: cos(angle) gravity around rear wheel pivot.
      // At 90° (COG above wheel) cos=0 → zero torque → neutral phone holds it.
      angularVelocity += cos(angle) * _gravityTorque * dt;

    } else if (frontOnGround && !rearOnGround) {
      // Stoppie — BR feel: the rear wheel CANNOT visibly lift at all.
      // The moment front is the sole contact, forward angVel is killed outright.
      // The k=500 spring then strongly resists any residual nose-down error.
      // You can tilt backward (nose-up) freely — that just brings the rear back down.
      if (angularVelocity > 0) angularVelocity = 0.0;   // kill forward spin immediately
      final err = angle - _surfAngle;
      if (err > 0) angularVelocity -= err * 500.0 * dt; // nose-down: lock it
      // nose-up: no torque — gravity + rear-wheel mass naturally brings rear down

    } else {
      // Air: NO automatic level-seeking — player controls spin freely for tricks.
      // Angular damping (_airDamp) handles gradual slowdown without fighting the spin.
    }

    // Safety net past 100° nose-up only — never fires during normal wheelies.
    // Gated on onGround: in air the bike must spin past this freely for backflips.
    if (onGround && angle < -1.75) {
      angularVelocity -= (angle + 1.75) * _antiWheelie * dt;
    }

    // ── 6. Angular damping ───────────────────────────────────────────────────
    final damp = onGround ? _gndDamp : _airDamp;
    angularVelocity *= (1.0 - damp * dt).clamp(0.0, 1.0);

    // ── 7. Integrate angle ───────────────────────────────────────────────────
    angle += angularVelocity * dt;

    if (onGround) {
      // On ground: normalise first (handles landings after multi-revolution air spins)
      // without this, a completed backflip lands at angle≈-6.28 and the spring
      // goes berserk with a huge err value.
      while (angle - _surfAngle >  pi) angle -= 2 * pi;
      while (angle - _surfAngle < -pi) angle += 2 * pi;

      // Hard cap on nose-down — much tighter in stoppie (front-only) than normal riding.
      // In stoppie: 0.03 rad ≈ 1.7° past slope. Rear wheel is visually locked.
      // In normal riding: 0.22 rad ≈ 12.5° past slope (safety net only).
      final maxNoseDown = (frontOnGround && !rearOnGround)
          ? _surfAngle + 0.03
          : _surfAngle + 0.22;
      if (angle > maxNoseDown) {
        angle = maxNoseDown;
        if (angularVelocity > 0) angularVelocity = 0.0;
      }
    }
    // In air: NO clamp at all → full 360° rotation enabled for tricks.

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
        pos = pos + rc.normal * rc.pen;
        rearOnGround = true;
        rearN = rc.normal;
      }

      final fw = pos + _rot(Vector2(_frtLx, _frtLy));
      final fc = _wheelContact(fw, segs, _wr);
      if (fc.pen > 0.005) {
        pos = pos + fc.normal * fc.pen;
        frontOnGround = true;
        frtN = fc.normal;
      }
    }

    position = pos;

    // ── Coyote timer + slope angle update ───────────────────────────────────
    if (onGround) {
      _coyoteTimer = _coyoteTime;
      // Slope angle = angle the bike frame should sit at for both wheels to contact.
      // atan2(n.x, -n.y): flat normal (0,-1) → 0.  Uphill-right normal → negative value.
      final n = (rearOnGround && frontOnGround)
          ? (rearN + frtN).normalized()
          : (rearOnGround ? rearN : frtN);
      _surfAngle = atan2(n.x, -n.y);
    } else {
      _coyoteTimer = (_coyoteTimer - dt).clamp(0.0, _coyoteTime);
      // Fade surface angle toward 0 while airborne so air-tricks feel neutral
      _surfAngle *= 0.92;
    }

    // ── 10. Single velocity impulse — after ALL position corrections ─────────
    if (rearOnGround || frontOnGround) {
      final avgN = (rearOnGround && frontOnGround)
          ? (rearN + frtN).normalized()
          : (rearOnGround ? rearN : frtN);

      // Kill incoming normal velocity (sticky landing, no bounce).
      final velN = velocity.dot(avgN);
      if (velN < 0) {
        velocity = velocity - avgN * (velN * (1.0 + _restitution));
      }
      // NO tangential friction — bike rolls forever on flat ground.
      // Gravity alone drives hill behaviour. Only gas/brake/gravity are forces.
    }

    // ── 11. Drive ────────────────────────────────────────────────────────────
    // Gas is rear-wheel-drive ONLY. During a stoppie (front only) gas does nothing —
    // the rear wheel is off the ground. This matches BR behaviour exactly.
    if (rearOnGround) {
      var surfDir = Vector2(-rearN.y, rearN.x);
      if (surfDir.x < 0) surfDir = -surfDir;

      if (gas) {
        velocity = velocity + surfDir * (_accel * dt);
      }
    }
    // Brake works on any ground contact (both-wheel braking like BR).
    if (onGround && brake) {
      final surfN   = rearOnGround ? rearN : frtN;
      var   surfDir = Vector2(-surfN.y, surfN.x);
      if (surfDir.x < 0) surfDir = -surfDir;
      final fwdSpeed = velocity.dot(surfDir);
      if (fwdSpeed > 0) {
        final brakeImpulse = (fwdSpeed / dt).clamp(0.0, _brake);
        velocity = velocity - surfDir * (brakeImpulse * dt);
      }
    }
    // No air drag, no rolling resistance — only gravity, gas, and brake are forces.

    // Soft top-speed cap via quadratic drag — only noticeable above ~280 u/s.
    final spd = velocity.length;
    if (spd > 0) velocity *= (1.0 - 0.000018 * spd * spd * dt).clamp(0.0, 1.0);

    // ── 12. Independent suspension springs ──────────────────────────────────
    const suspK = 140.0, suspD = 16.0, suspMax = 2.2;
    final rTarget = rearOnGround  ? 1.8 : 0.0;
    final fTarget = frontOnGround ? 1.8 : 0.0;
    _rSuspVel += (suspK * (rTarget - rSuspOffset) - suspD * _rSuspVel) * dt;
    rSuspOffset = (rSuspOffset + _rSuspVel * dt).clamp(0.0, suspMax);
    _fSuspVel += (suspK * (fTarget - fSuspOffset) - suspD * _fSuspVel) * dt;
    fSuspOffset = (fSuspOffset + _fSuspVel * dt).clamp(0.0, suspMax);
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
        text: 'v46'
            '\nTilt:   ${gameRef.smoothedTilt.toStringAsFixed(2)}'
            '\nAngle:  ${b.angle.toStringAsFixed(2)} rad'
            '\nAngVel: ${b.angularVelocity.toStringAsFixed(2)}'
            '\nVel:    ${b.velocity.x.toStringAsFixed(1)}, ${b.velocity.y.toStringAsFixed(1)}'
            '\nGnd  R:${b.rearOnGround}  F:${b.frontOnGround}',
        style: const TextStyle(
            color: Colors.yellow, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    )..layout()..paint(canvas, const Offset(16, 16));
  }
}
