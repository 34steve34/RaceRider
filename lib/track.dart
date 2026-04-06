import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {

  static const double loopRadius  = 8.0;
  static const double loopCenterX = 120.0;
  static const double loopCenterY = -8.0;
  static const int    loopPoints  = 36;    // reduced — fewer chances for duplicate points
  static const double gapAngle    = 0.5;   // ~29 degrees each side

  // Pre-calculate entry and exit angles as constants
  static double get entryAngle => pi / 2 + gapAngle;  // left of bottom
  static double get exitAngle  => pi / 2 - gapAngle;  // right of bottom

  // Pre-calculate exact entry and exit coordinates
  // These are used by BOTH the ramp endpoints AND loop start/end
  // so they are mathematically guaranteed to match
  static double get entryX => loopCenterX + loopRadius * cos(entryAngle);
  static double get entryY => loopCenterY + loopRadius * sin(entryAngle);
  static double get exitX  => loopCenterX + loopRadius * cos(exitAngle);
  static double get exitY  => loopCenterY + loopRadius * sin(exitAngle);

  static List<Vector2> _buildLoopPoints() {
    final points = <Vector2>[];
    // Go from entryAngle to exitAngle + 2*pi (full loop counter-clockwise)
    final startAngle = entryAngle;
    final endAngle   = exitAngle + 2 * pi;

    for (int i = 0; i <= loopPoints; i++) {
      final t     = i / loopPoints;
      final angle = startAngle + (endAngle - startAngle) * t;
      final x     = loopCenterX + loopRadius * cos(angle);
      final y     = loopCenterY + loopRadius * sin(angle);
      points.add(Vector2(x, y));
    } // END for
    return points;
  } // END _buildLoopPoints

  List<Vector2> get trackPoints {
    final loop = _buildLoopPoints();
    return [

      // ── STARTING STRAIGHT ──────────────────────────────────
      Vector2(-20,  0.0),
      Vector2(  0,  0.0),
      Vector2( 20,  0.0),
      Vector2( 40,  0.0),
      Vector2( 55,  0.0),

      // ── SMALL BUMP ─────────────────────────────────────────
      Vector2( 60, -2.5),
      Vector2( 65,  0.0),

      // ── FLAT AFTER BUMP ────────────────────────────────────
      Vector2( 75,  0.0),
      Vector2( 85,  0.0),
      Vector2( 95,  0.0),

      // ── APPROACH RAMP ──────────────────────────────────────
      // Last point uses exact same math as loop entry — guaranteed match
      Vector2(100,  0.0),
      Vector2(105, -2.0),
      Vector2(108, -4.0),
      Vector2(110, -6.0),

      // ── THE LOOP ───────────────────────────────────────────
      ...loop,

      // ── EXIT RAMP ──────────────────────────────────────────
      // First point uses exact same math as loop exit — guaranteed match
      Vector2(exitX + 4,  -6.0),
      Vector2(exitX + 7,  -4.0),
      Vector2(exitX + 10, -2.0),
      Vector2(exitX + 14,  0.0),

      // ── NEW SMALL RAMP IN MIDDLE ───────────────────────────
      // Simple ramp at x=150
      Vector2(150,  0.0),
      Vector2(155, -1.5),
      Vector2(160,  0.0),

      // ── FINISH STRAIGHT ────────────────────────────────────
      Vector2(170,  0.0),
      Vector2(190,  0.0),

    ]; // END trackPoints list
  } // END get trackPoints

  @override
  Body createBody() {
    final points     = trackPoints;
    final shape      = ChainShape()..createChain(points);
    final bodyDef    = BodyDef(
      userData: this,
      position: Vector2.zero(),
      type:     BodyType.static,
    );
    final fixtureDef = FixtureDef(shape, friction: 0.6);
    final body       = world.createBody(bodyDef);
    body.createFixture(fixtureDef);
    return body;
  } // END createBody

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final points = trackPoints;

    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    } // END for

    canvas.drawPath(
      path,
      Paint()
        ..color       = Colors.brown.shade700
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color       = Colors.greenAccent
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.15,
    );

  } // END render

} // END TrackComponent