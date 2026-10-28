/// detection_result.dart
/// Model dữ liệu đối tượng phát hiện từ mô hình thị giác AI và phân tích không gian

enum DistanceLevel { far, near, critical }

enum DirectionZone { left, center, right }

class DetectionResult {
  final String id;
  final String label;
  final String vietnameseLabel;
  final String category; // 'vehicle', 'pedestrian', 'obstacle'
  final double score;
  final List<double> bbox; // [x, y, width, height]

  // Tọa độ chuẩn hóa (0.0 - 1.0)
  final double centerX;
  final double bottomY;
  final double areaRatio;

  // Thuộc tính không gian & hành lang
  final DirectionZone direction;
  final double panValue; // -1.0 (Trái cực đại) đến +1.0 (Phải cực đại)
  final DistanceLevel distanceLevel;
  final String approximateDistanceMeters;

  // Thuộc tính hiểm họa đặc biệt
  final bool isApproaching; // Đang lao tới nhanh
  final double growthRate; // Tốc độ nở bounding box
  final bool isHeadLevelHazard; // Vật cản tầm đầu/ngực (bạt che)

  DetectionResult({
    required this.id,
    required this.label,
    required this.vietnameseLabel,
    required this.category,
    required this.score,
    required this.bbox,
    required this.centerX,
    required this.bottomY,
    required this.areaRatio,
    required this.direction,
    required this.panValue,
    required this.distanceLevel,
    required this.approximateDistanceMeters,
    this.isApproaching = false,
    this.growthRate = 0.0,
    this.isHeadLevelHazard = false,
  });
}
