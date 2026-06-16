import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 3D attitude math for the 3D view.
///
/// FC body frame: X forward, Y right, Z down (NED body).
/// Scene frame: X right, Y up, Z depth — level ground is the XZ plane (Y = 0).
class Attitude3DMath {
  Attitude3DMath._();

  static const axisLength = 0.85;
  static const levelToleranceDeg = 2.0;

  /// Body point → visual world (FC NED attitude, then Y-up scene).
  static Vec3 bodyToWorld(
    Vec3 local, {
    required double rollDeg,
    required double pitchDeg,
    required double yawDeg,
  }) {
    final r = rollDeg * math.pi / 180;
    final p = pitchDeg * math.pi / 180;
    final y = yawDeg * math.pi / 180;
    final ned = rotateZ(rotateY(rotateX(local, r), p), y);
    return nedToVisual(ned);
  }

  /// NED earth (Z down) → Y-up visualization (ground = XZ).
  static Vec3 nedToVisual(Vec3 ned) => rotateX(ned, math.pi / 2);

  static bool isNearLevel(double rollDeg, double pitchDeg) =>
      rollDeg.abs() <= levelToleranceDeg && pitchDeg.abs() <= levelToleranceDeg;

  /// Body basis in world frame: unit vectors for body X/Y/Z.
  static List<Vec3> bodyAxesWorld({
    required double rollDeg,
    required double pitchDeg,
    required double yawDeg,
  }) {
    return [
      bodyToWorld(const Vec3(1, 0, 0), rollDeg: rollDeg, pitchDeg: pitchDeg, yawDeg: yawDeg),
      bodyToWorld(const Vec3(0, 1, 0), rollDeg: rollDeg, pitchDeg: pitchDeg, yawDeg: yawDeg),
      bodyToWorld(const Vec3(0, 0, 1), rollDeg: rollDeg, pitchDeg: pitchDeg, yawDeg: yawDeg),
    ];
  }

  /// + quad in body frame: X forward (nose), Y right, Z down.
  static List<({Vec3 from, Vec3 to})> quadArms({double arm = 0.62}) {
    return [
      (from: Vec3.zero, to: Vec3(arm, arm, 0)),
      (from: Vec3.zero, to: Vec3(arm, -arm, 0)),
      (from: Vec3.zero, to: Vec3(-arm, arm, 0)),
      (from: Vec3.zero, to: Vec3(-arm, -arm, 0)),
    ];
  }

  static List<Vec3> motorTips({double arm = 0.62}) =>
      quadArms(arm: arm).map((a) => a.to).toList();

  /// Filled deck polygon (motor tips, body XY plane).
  static List<Vec3> quadDeck({double arm = 0.62}) => motorTips(arm: arm);

  /// Level horizon ring in the fixed ground plane.
  static List<Vec3> levelHorizonRing({double radius = 0.95, int segments = 56}) {
    return List.generate(segments, (i) {
      final a = 2 * math.pi * i / segments;
      return Vec3(radius * math.cos(a), 0, radius * math.sin(a));
    });
  }

  /// Nose triangle on +X.
  static List<Vec3> noseMarker({double len = 0.22, double half = 0.1}) => [
        Vec3(armHint + len, 0, 0),
        Vec3(armHint, half, 0),
        Vec3(armHint, -half, 0),
      ];

  static const armHint = 0.62;

  static Vec3 rotateX(Vec3 v, double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
  }

  static Vec3 rotateY(Vec3 v, double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
  }

  static Vec3 rotateZ(Vec3 v, double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
  }

  /// Isometric projection (fixed camera) → screen offset from center.
  static Offset project(Vec3 p, double scale) {
    const cos30 = 0.8660254;
    const sin30 = 0.5;
    final sx = (p.x - p.z) * cos30 * scale;
    final sy = (-p.y + (p.x + p.z) * sin30) * scale;
    return Offset(sx, sy);
  }
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const zero = Vec3(0, 0, 0);

  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
}
