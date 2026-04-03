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

  static const double loopRadius  = 8.0;   // inner radius
  static const double loopCenterX = 120.0; // horizontal position of loop
  static const double loopCenterY = -8.0;  // center is 8 units ABOVE ground
  static const int    loopPoints  = 48;    // smoothness of loop circle

  // ── LOOP POINT GENERATOR ───────────────────────────────────
  // Rides INSIDE the loop so points go COUNTER-clockwise in Y-down space
  // which makes collision normals point INWARD (toward center)
  static List<Vector2> _buildLoopPoints() {
    final points = <Vector2>[];
    // Start at bottom of loop, go counter-clockwise (in Y-down = left side first)
    for (int i = 0; i <= loopPoints; i++) {
      final angle = pi / 2 + (2 * pi * i / loopPoints);
      final x = loopCenterX + loopRadius * cos(angle);
      final y = loopCenterY + loopRadius * sin(angle);
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

      // ── SMALL BUMP / JUMP ──────────────────────────────────
      // Negative Y = rises UP on screen
      Vector2( 60, -2.5),  // bump peak
      Vector2( 65,  0.0),  // back to ground

      // ── FLAT AFTER JUMP ────────────────────────────────────
      Vector2( 75,  0.0),
      Vector2( 85,  0.0),
      Vector2( 95,  0.0),

      // ── APPROACH RAMP UP TO LOOP ENTRY ─────────────────────
      // Rises smoothly to meet bottom of loop at loopCenterY + loopRadius
      // Bottom of loop in Y-down = loopCenterY + loopRadius = -8 + 8 = 0
      // So the loop bottom sits exactly at ground level — perfect
      Vector2(105, -2.0),
      Vector2(110, -4.0),
      Vector2(112,  loopCenterY + loopRadius), // = 0.0, joins loop bottom-left

      // ── THE LOOP ───────────────────────────────────────────
      ...loop,

      // ── EXIT RAMP DOWN FROM LOOP ───────────────────────────
      Vector2(loopCenterX + loopRadius + 2,  loopCenterY + loopRadius),
      Vector2(loopCenterX + loopRadius + 6,  -4.0),
      Vector2(loopCenterX + loopRadius + 10, -2.0),
      Vector2(loopCenterX + loopRadius + 16,  0.0),

      // ── FINISH STRAIGHT ────────────────────────────────────
      Vector2(loopCenterX + loopRadius + 30, 0.0),
      Vector2(loopCenterX + loopRadius + 50, 0.0),

    ]; // END trackPoints list
  } // END get trackPoints

  @override
  Body createBody() {
    final points = trackPoints;
    final shape  = ChainShape()..createChain(points);
    final bodyDef = BodyDef(
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

    // ── Track body (thick, below surface) ──────────────────
    final trackPaint = Paint()
      ..color       = Colors.brown.shade700
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // ── Surface line (thin, on top) ─────────────────────────
    final surfacePaint = Paint()
      ..color       = Colors.greenAccent
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.15;

    final path = Path();
    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    } // END for

    canvas.drawPath(path, trackPaint);   // brown body first
    canvas.drawPath(path, surfacePaint); // green surface line on top

  } // END render

} // END TrackComponent