/* ============================================================================
 * RACERIDER v47  — clean COG rewrite
 * Physics core rebuilt from scratch. All patches removed.
 * The Bike class is now ~110 lines. The tuning block is self-documenting.
 *
 * Removed entirely:
 *   _surfAngle, coyote timer, effectiveTilt block, angle normalisation,
 *   hard nose-down cap, stoppie kill, cos(angle) torque, _antiWheelie spring,
 *   all gravity-torque special cases, _restitution, _friction constant
 *
 * New:
 *   COG-based gravity torque — single formula, no branches, handles all states:
 *     both wheels → stable; rear only → wheelie with 90° balance;
 *     front only → stoppie instantly corrected; air → free 360° spin
 *   Substeps: 5 → 8 (prevents tunneling at higher speeds)
 *   _cogLx / _cogLy / _gravityTorque — tunable, documented in-code
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
    // smoothedTilt = smoothedTilt * 0.35 + n * 0.65;
	smoothedTilt = n
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
  Vector2 velocity        = Vector2.zero();
  double  angle           = 0.0;
  double  angularVelocity = 0.0;
  bool    rearOnGround    = false;
  bool    frontOnGround   = false;
  bool get onGround => rearOnGround || frontOnGround;
  double  rSuspOffset = 0.0, _rSuspVel = 0.0;   // visual-only suspension
  double  fSuspOffset = 0.0, _fSuspVel = 0.0;

  // ════════════════════════════════════════════════════════════════════════════
  //  TUNING — every physics knob in one place, explained
  // ════════════════════════════════════════════════════════════════════════════

  // ── World ────────────────────────────────────────────────────────────────
  // Downward acceleration (units/s²).
  // Raise → heavier feel, harder to climb hills, falls faster off jumps.
  // Lower → floatier, easier hills, longer air time.
  static const _gravity = 90.0;

  // ── Drive ─────────────────────────────────────────────────────────────────
  // Rear-wheel acceleration (units/s²). BR felt almost instant — raise freely.
  static const _accel    = 2600.0;
  // Max braking deceleration (units/s²). Only slows, never reverses.
  static const _brake    = 600.0;
  // Quadratic drag coefficient for top-speed cap.
  // Equilibrium speed where gas = drag: v = cbrt(accel / topSpeedK) ≈ 525 u/s.
  // Raise topSpeedK to lower top speed, lower it to raise top speed.
  static const _topSpeedK = 0.000018;

  // ── Rotation feel ─────────────────────────────────────────────────────────
  // Angular impulse per second at full tilt (radians/s per second).
  // Raise → snappier, quicker tricks and wheelies.
  // Lower → heavier, lazier rotation.
  static const _tiltTorque = 14.0;

  // Angular damping — friction that slows rotation.
  // Equilibrium spin rate = tiltTorque / damp (e.g. 14/4 = 5 rad/s on ground).
  // Ground damp is high so the bike settles quickly.
  // Air: how quickly rotation bleeds off when you stop tilting.
  // Higher = more responsive/obedient. Lower = drifty/hard to control.
  static const _gndDamp = 4.0;
  static const _airDamp = 2.5;

  // ── COG gravity torque ────────────────────────────────────────────────────
  // The "virtual centre of gravity" in bike-local space.
  // This is the heart of the wheelie/stoppie physics — no special cases needed.
  //
  // HOW IT WORKS:
  //   torque = (cogWorldX - contactWheelWorldX) × _gravityTorque
  //   Positive lever (COG right of contact) → nose-down torque.
  //   Negative lever (COG left of contact)  → nose-up torque.
  //   No contact (airborne) → no torque. Free 360° spin.
  //
  // _cogLx  — horizontal position in local space. Controls rear/front bias.
  //   Midpoint of wheels = (_rearLx + _frtLx) / 2 = 0.75 → symmetric
  //   < 0.75  → rear-biased COG → wheelie easier, stoppie harder  (BR feel)
  //   > 0.75  → front-biased  → stoppie easier (not recommended)
  //
  // _cogLy  — vertical position in local space. Controls wheelie balance angle.
  //   = _rearLy (6.5)  → wheelie balances at exactly 90° (recommended)
  //   > _rearLy        → balance angle < 90° (falls sooner, harder to hold)
  //   < _rearLy        → balance angle > 90° (past vertical before falling)
  //
  // _gravityTorque — scales the lever-arm effect.
  //   Raise → gravity corrects wheelie faster (harder to hold).
  //   Lower → gravity corrects wheelie slower (easier to hold, more floaty).
  static const _cogLx         = -1.0;   // range: -2.0 (very rear) to 1.5 (slight fwd)
  static const _cogLy         = 6.5;   // keep = _rearLy unless experimenting
  static const _gravityTorque = 2.0;   // range: 1.0 (easy wheelie) to 5.0 (hard)

  // ── Geometry ──────────────────────────────────────────────────────────────
  // Wheel radius and centres MUST match _drawBike drawCircle calls exactly.
  static const _wr     = 4.7;
  static const _rearLx = -7.0,  _rearLy = 6.5;
  static const _frtLx  =  8.5,  _frtLy  = 6.5;
  // ════════════════════════════════════════════════════════════════════════════

  Bike(Vector2 startPos) : position = startPos.clone();

  void updateBike(double dt, double tilt, bool gas, bool brake,
      List<TrackSegment> segs) {
    // 8 substeps: at 60 fps each substep = ~2 ms.
    // At 500 u/s that's 1 unit/substep vs wheel radius 4.7 — cannot tunnel.
    const substeps = 8;
    final sdt = dt / substeps;
    for (int i = 0; i < substeps; i++) {
      _step(sdt, tilt, gas, brake, segs);
    }
  }

  void _step(double dt, double tilt, bool gas, bool brake,
      List<TrackSegment> segs) {

    // ── 1. Linear gravity ────────────────────────────────────────────────────
    velocity.y += _gravity * dt;

    // ── 2. Tilt torque ───────────────────────────────────────────────────────
    // Same formula always — no special cases.
    // The COG placement (step 3) creates asymmetry naturally.
    angularVelocity += tilt * _tiltTorque * dt;

    // ── 3. COG gravity torque ────────────────────────────────────────────────
    // Rotate the virtual COG into world space and compute the lever arm to
    // each grounded wheel. The horizontal offset drives the angular impulse.
    //
    // Behaviours that emerge with no extra code:
    //   Both wheels down → COG between wheels → near-zero net torque → stable
    //   Rear only (wheelie) → COG right of rear wheel → nose-down pull;
    //       at 90° the COG is directly above the wheel → zero torque → holds
    //   Front only (stoppie) → COG far left of front wheel → strong nose-up →
    //       rear slams back; almost impossible to hold (correct BR feel)
    //   Air → no contact → zero torque → free 360° rotation
    final cogW = position + _rot(Vector2(_cogLx, _cogLy));
    if (rearOnGround) {
      final rw = position + _rot(Vector2(_rearLx, _rearLy));
      angularVelocity += (cogW.x - rw.x) * _gravityTorque * dt;
    }
    if (frontOnGround) {
      final fw = position + _rot(Vector2(_frtLx, _frtLy));
      angularVelocity += (cogW.x - fw.x) * _gravityTorque * dt;
    }

    // ── 4. Angular damping ───────────────────────────────────────────────────
    final damp = onGround ? _gndDamp : _airDamp;
    angularVelocity *= (1.0 - damp * dt).clamp(0.0, 1.0);

    // ── 5. Integrate angle — NO clamping, NO normalisation ───────────────────
    // Full 360° always. No patches. Angle accumulates freely.
    angle += angularVelocity * dt;

    // ── 6. Predict position ──────────────────────────────────────────────────
    var pos = position + velocity * dt;

    // ── 7. Contact detection + position correction ───────────────────────────
    // Three passes push wheels out of the ground. Velocity is not touched here
    // (that's step 8) — separating these eliminates the vibration from older
    // versions that applied impulses inside the correction loop.
    rearOnGround  = false;
    frontOnGround = false;
    var rearN = Vector2(0.0, -1.0);
    var frtN  = Vector2(0.0, -1.0);

    for (int pass = 0; pass < 3; pass++) {
      final rw = pos + _rot(Vector2(_rearLx, _rearLy));
      final rc = _wheelContact(rw, segs, _wr);
      if (rc.pen > 0.005) {
        pos         += rc.normal * rc.pen;
        rearOnGround = true;
        rearN        = rc.normal;
      }
      final fw = pos + _rot(Vector2(_frtLx, _frtLy));
      final fc = _wheelContact(fw, segs, _wr);
      if (fc.pen > 0.005) {
        pos          += fc.normal * fc.pen;
        frontOnGround = true;
        frtN          = fc.normal;
      }
    }

    position = pos;

    // ── 8. Velocity impulse on contact ───────────────────────────────────────
    // Kill the velocity component going INTO the surface (sticky landing).
    // Tangential component is untouched — rolls forever on flat ground.
    // Only gravity, gas, and brake are forces. No friction. No drag.
    if (onGround) {
      final avgN = (rearOnGround && frontOnGround)
          ? (rearN + frtN).normalized()
          : (rearOnGround ? rearN : frtN);
      final velN = velocity.dot(avgN);
      if (velN < 0) velocity -= avgN * velN;   // perfectly sticky (restitution = 0)
    }

    // ── 9. Drive ─────────────────────────────────────────────────────────────
    // Gas: rear-wheel drive only. If rear is airborne (stoppie), no gas.
    // Brake: any contact, both-wheel style like BR.
    if (rearOnGround) {
      var dir = Vector2(-rearN.y, rearN.x);
      if (dir.x < 0) dir = -dir;                          // ensure forward = positive
      if (gas) velocity += dir * (_accel * dt);
    }
    if (onGround && brake) {
      final n   = rearOnGround ? rearN : frtN;
      var   dir = Vector2(-n.y, n.x);
      if (dir.x < 0) dir = -dir;
      final fwd = velocity.dot(dir);
      if (fwd > 0) velocity -= dir * (fwd / dt).clamp(0.0, _brake) * dt;
    }

    // Soft top-speed cap — quadratic drag that only bites above ~400 u/s.
    final spd = velocity.length;
    if (spd > 0) velocity *= (1.0 - _topSpeedK * spd * spd * dt).clamp(0.0, 1.0);

    // ── 10. Visual suspension springs ────────────────────────────────────────
    // Physics contact points are fixed. These only move the drawn wheel positions.
    const suspK = 140.0, suspD = 16.0, suspMax = 2.2;
    _rSuspVel += (suspK * ((rearOnGround  ? 1.8 : 0.0) - rSuspOffset) - suspD * _rSuspVel) * dt;
    rSuspOffset = (rSuspOffset + _rSuspVel * dt).clamp(0.0, suspMax);
    _fSuspVel += (suspK * ((frontOnGround ? 1.8 : 0.0) - fSuspOffset) - suspD * _fSuspVel) * dt;
    fSuspOffset = (fSuspOffset + _fSuspVel * dt).clamp(0.0, suspMax);
  }

  // Rotate a local-space vector by the current bike angle.
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
        text: 'v49'
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
