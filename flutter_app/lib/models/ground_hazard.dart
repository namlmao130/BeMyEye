/// ground_hazard.dart
/// Model dữ liệu hiểm họa mặt đất (Bậc tam cấp, lề đường, hố sụt)

import 'detection_result.dart';

enum GroundHazardType { stepUp, stepDown }

class GroundHazard {
  final GroundHazardType type;
  final String vietnameseName;
  final double normalizedY; // 0.0 (đỉnh) đến 1.0 (sát chân)
  final double confidence;
  final DistanceLevel distanceLevel;
  final String distanceMeters;
  final bool
      isNegativeObstacle; // Bậc bước xuống / lề đường tụt dốc (vật cản âm)

  GroundHazard({
    required this.type,
    required this.vietnameseName,
    required this.normalizedY,
    required this.confidence,
    required this.distanceLevel,
    required this.distanceMeters,
    required this.isNegativeObstacle,
  });
}
