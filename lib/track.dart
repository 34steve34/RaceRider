import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class TrackComponent extends BodyComponent {

  // ── TRACK DESIGN TABLE ─────────────────────────────────────
  // Y-DOWN world (screen coordinates):
  //   y=0  = ground level
  //   y<0  = above ground (UP on screen)
  //   y>0  = below ground (DOWN on screen)
  // ──────────────────────────────────────────────────────────

  static const double loopRadius   = 8.0;    // inner radius
  static const double loopCenterX  = 120.0;  // horizontal center of loop
  static const double loopCenterY  = -8.0;   // center 8 units above ground
  static const int    loopPoints   = 48;     // smoothness
  static const double gapAngle     = 0.45;   // radians of gap on each side of bottom
                                              // 0.45 ≈ 26° — tune wider/narrower

  // ── LOOP POINT GENERATOR ───────────────────────────────────
  // Leaves a gap at the bottom for entry (left) and exit (right)
  // Counter-clockwise winding in Y-down = normals point inward
  static List<Vector2> _buildLoopPoints() {
    final points = <Vector2>[];

    // In Y-down, bottom of circle is at angle pi/2
    // We start just past bottom-left gap and end just before bottom-right gap
    // Going counter-clockwise (increasing angle in Y-down space)
    final startAngle = pi / 2 + gapAngle;           // entry side — left of bottom
    final endAngle   = pi / 2 - gapAngle + 2 * pi;  // exit side  — right of bottom

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

    // Loop entry point (bottom-left of gap) and exit point (bottom-right of gap)
    // These are loop.first and loop.last — ramps connect exactly here
    final entryPoint = loop.first; // left side of loop opening
    final exitPoint  = loop.last;  // right side of loop opening

    return [

      // ── STARTING STRAIGHT ──────────────────────────────────
      Vector2(-20,  0.0),
      Vector2(  0,  0.0),
      Vector2( 20,  0.0),
      Vector2( 40,  0.0),
      Vector2( 55,  0.0),

      // ── SMALL BUMP / JUMP ──────────────────────────────────
      Vector2( 60, -2.5),  // peak — negative Y = up on screen
      Vector2( 65,  0.0),  // back to ground

      // ── FLAT AFTER JUMP ────────────────────────────────────
      Vector2( 75,  0.0),
      Vector2( 85,  0.0),
      Vector2( 95,  0.0),

      // ── APPROACH RAMP ──────────────────────────────────────
      // Rises smoothly from ground up to loop entry point
      Vector2(100,  0.0),
      Vector2(105, -2.0),
      Vector2(108, -4.0),
      Vector2(110, -6.0),
      entryPoint,           // joins loop opening exactly

      // ── THE LOOP ───────────────────────────────────────────
      ...loop,

      // ── EXIT RAMP ──────────────────────────────────────────
      // Drops smoothly from loop exit point back to ground
      exitPoint,            // starts from loop opening exactly
      Vector2(exitPoint.x + 4,  -6.0),
      Vector2(exitPoint.x + 6,  -4.0),
      Vector2(exitPoint.x + 9,  -2.0),
      Vector2(exitPoint.x + 13,  0.0),

      // ── FINISH STRAIGHT ────────────────────────────────────
      Vector2(exitPoint.x + 25,  0.0),
      Vector2(exitPoint.x + 50,  0.0),

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
    final fixtureDef = FixtureDef(
      shape,
      friction: 0.6,
    );
    final body = world.createBody(bodyDef);
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

    // Brown track body — thick, gives illusion of solid ground
    canvas.drawPath(
      path,
      Paint()
        ..color       = Colors.brown.shade700
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Green surface line — thin, sits on top of brown
    canvas.drawPath(
      path,
      Paint()
        ..color       = Colors.greenAccent
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.15,
    );

  } // END render

} // END TrackComponent