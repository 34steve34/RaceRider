/* ============================================================================
 * RACERIDER - v26 - TRACK POSITION FIX (no bike color change)
 * Goal: Green line in the middle of the screen, bike clearly visible above it
 * ============================================================================ */

import 'dart:math';
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
  late Track track;
  late DebugOverlay debug;

  double rawTilt = 0.0;
  double smoothedTilt = 0.0;

  bool isGas = false;
  bool isBrake = false;

  RaceRiderGame() : super(gravity: Vector2(0, 0), zoom: 5.0);

  @override
  Future<void> onLoad() async {
    add(Background());
    track = Track();
    add(track);

    player = Bike(Vector2(0, 6));        // clearly above the track
    // Don't add player to the scene - we'll render it manually
    // add(player);

    debug = DebugOverlay();
    add(debug);

    // Set up camera properly
    camera.viewfinder.zoom = 5.5;
    camera.viewfinder.anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Update camera position to follow bike
    camera.viewfinder.position = player.position;

    double normalizedTilt = (rawTilt / 8.0).clamp(-1.0, 1.0);
    smoothedTilt = smoothedTilt * 0.4 + normalizedTilt * 0.6;

    player.updateBike(dt, smoothedTilt, isGas, isBrake);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final isLeftSide = event.localPosition.x < size.x / 2;
    if (isLeftSide) isBrake = true;
    else isGas = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    isGas = false;
    isBrake = false;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Apply camera transform manually
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);  // Center of screen
    canvas.scale(camera.viewfinder.zoom);
    canvas.translate(-player.position.x, -player.position.y);  // Follow bike
    
    // Draw track with bumps
    final trackPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    // Main track line
    canvas.drawLine(const Offset(-100, 12), const Offset(300, 12), trackPaint);
    
    // Bumps on the track
    final bumpPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    
    // Bump 1 at x=-20
    canvas.drawLine(const Offset(-20, 12), const Offset(-15, 10), bumpPaint);
    canvas.drawLine(const Offset(-15, 10), const Offset(-10, 12), bumpPaint);
    
    // Bump 2 at x=30
    canvas.drawLine(const Offset(30, 12), const Offset(35, 9), bumpPaint);
    canvas.drawLine(const Offset(35, 9), const Offset(40, 12), bumpPaint);
    
    // Bump 3 at x=80
    canvas.drawLine(const Offset(80, 12), const Offset(85, 10.5), bumpPaint);
    canvas.drawLine(const Offset(85, 10.5), const Offset(90, 12), bumpPaint);
    
    // Draw bike
    canvas.save();
    canvas.translate(player.position.x, player.position.y);
    canvas.rotate(player.angle);
    
    final chassisPaint = Paint()..color = const Color(0xFFFF8800);
    canvas.drawRect(const Rect.fromLTWH(-3.25, -0.8, 6.5, 1.6), chassisPaint);
    
    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-2.1, 0.95), 0.85, wheelPaint);
    canvas.drawCircle(const Offset(2.1, 0.95), 0.85, wheelPaint);
    
    canvas.restore();
    canvas.restore();
  }
}

// Background
class Background extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    // Draw background - will be affected by camera but that's okay
    canvas.drawRect(Rect.fromLTWH(-1000, -1000, 3000, 3000), 
      Paint()..color = const Color(0xFF112233));
  }
}

// Debug Text
class DebugOverlay extends Component with HasGameRef<RaceRiderGame> {
  @override
  void render(Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
        text: "v26 - TRACK FIX\n"
            "Green line should now be in the middle\n"
            "Left=Brake | Right=Gas\n"
            "Bike pos: ${gameRef.player.position}\n"
            "Camera pos: ${gameRef.camera.viewfinder.position}\n"
            "Camera zoom: ${gameRef.camera.viewfinder.zoom}",
        style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(20, 30));
  }
}

// Bike (unchanged color)
class Bike extends PositionComponent {
  Vector2 velocity = Vector2.zero();
  double angle = 0.0;
  double angularVelocity = 0.0;

  bool onGround = false;

  final double gravity = 42.0;
  final double leanStrength = 45.0;
  final double acceleration = 116.0;  // Doubled from 58.0
  final double brakePower = 22.0;
  
  // Suspension parameters
  final double suspensionRestLength = 1.5;
  final double suspensionStiffness = 800.0;
  final double suspensionDamping = 50.0;

  Bike(Vector2 startPos) {
    position = startPos;
    size = Vector2(6.5, 3.2);
    anchor = Anchor.center;
  }

  void updateBike(double dt, double tilt, bool gas, bool brake) {
    velocity.y += gravity * dt;

    double torque = tilt * leanStrength;
    if (!onGround) angularVelocity *= 0.96;

    angularVelocity += torque * dt;
    angle += angularVelocity * dt;

    if (onGround) {
      double drive = gas ? acceleration : (brake ? -brakePower : 0);
      velocity.x += drive * cos(angle) * dt;
      velocity.y += drive * sin(angle) * dt;
      velocity.x *= 0.82;
    }

    position += velocity * dt;

    // Check collision with track - raycast downward from bike
    double trackHeightAtBike = getTrackHeightAt(position.x);
    double bikeBottomY = position.y + 0.95;  // Wheel radius
    
    if (bikeBottomY >= trackHeightAtBike) {
      // Bike is on or below track
      onGround = true;
      
      // Apply suspension force
      double compression = bikeBottomY - trackHeightAtBike;
      if (compression > 0) {
        double springForce = compression * suspensionStiffness;
        double dampingForce = velocity.y * suspensionDamping;
        double totalForce = springForce - dampingForce;
        velocity.y -= totalForce * dt;
      }
      
      // Clamp to track surface
      position.y = trackHeightAtBike - 0.95;
      angularVelocity *= 0.55;
    } else {
      onGround = false;
    }
  }
  
  // Get track height at a given x position
  double getTrackHeightAt(double x) {
    const double baseTrackY = 12.0;
    
    // Bump 1 at x=-20 to -10
    if (x >= -20 && x <= -10) {
      if (x < -15) {
        return baseTrackY - 2.0 * (x + 20) / 5;  // Going up
      } else {
        return baseTrackY - 2.0 * (-10 - x) / 5;  // Going down
      }
    }
    
    // Bump 2 at x=30 to 40
    if (x >= 30 && x <= 40) {
      if (x < 35) {
        return baseTrackY - 3.0 * (x - 30) / 5;  // Going up
      } else {
        return baseTrackY - 3.0 * (40 - x) / 5;  // Going down
      }
    }
    
    // Bump 3 at x=80 to 90
    if (x >= 80 && x <= 90) {
      if (x < 85) {
        return baseTrackY - 1.5 * (x - 80) / 5;  // Going up
      } else {
        return baseTrackY - 1.5 * (90 - x) / 5;  // Going down
      }
    }
    
    return baseTrackY;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(angle);

    final chassisPaint = Paint()..color = const Color(0xFFFF8800);
    canvas.drawRect(const Rect.fromLTWH(-3.25, -0.8, 6.5, 1.6), chassisPaint);

    final riderPaint = Paint()..color = const Color(0xFF00FFFF);
    canvas.drawRect(const Rect.fromLTWH(-1.0, -2.1, 2.0, 1.8), riderPaint);

    final wheelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-2.1, 0.95), 0.85, wheelPaint);
    canvas.drawCircle(const Offset(2.1, 0.95), 0.85, wheelPaint);

    canvas.restore();
  }
}

// Track - moved way down
class Track extends BodyComponent {
  @override
  Body createBody() {
    final body = world.createBody(BodyDef()..type = BodyType.static);
    final points = [Vector2(-100, 12), Vector2(300, 12)];   // lowered significantly
    body.createFixture(FixtureDef(EdgeShape()..set(points[0], points[1]))..friction = 0.9);
    return body;
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 16.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-100, 12), const Offset(300, 12), paint);
  }
}